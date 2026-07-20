import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/field_form_submission.dart';
import '../../models/field_form_template.dart';
import '../../models/form_field_definition.dart';
import '../../models/form_field_type.dart';
import '../../models/task.dart';
import '../../models/workspace.dart';
import '../../providers/auth_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/service_locator.dart';
import '../../widgets/common/status_chip.dart';
import '../../widgets/forms/signature_dialog.dart';
import '../../widgets/forms/stacked_field.dart';
import '../../theme/theme.dart';

class FieldFormSubmissionDetailScreen extends StatefulWidget {
  const FieldFormSubmissionDetailScreen({
    super.key,
    required this.submissionId,
  });

  final String submissionId;

  @override
  State<FieldFormSubmissionDetailScreen> createState() =>
      _FieldFormSubmissionDetailScreenState();
}

class _FieldFormSubmissionDetailScreenState
    extends State<FieldFormSubmissionDetailScreen> {
  FieldFormSubmission? _submission;
  FieldFormTemplate? _template;
  Task? _linkedTask;
  Workspace? _workspace;
  bool _isLoading = true;
  bool _isActing = false;
  bool _isExportingPdf = false;

  dynamic get _service => ServiceLocator.fieldFormService;
  dynamic get _taskService => ServiceLocator.taskService;
  dynamic get _workspaceService => ServiceLocator.workspaceService;
  final PDFService _pdfService = PDFService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sub = await _service.getSubmission(widget.submissionId);
      FieldFormTemplate? template;
      Task? task;
      Workspace? workspace;
      if (sub != null) {
        template = await _service.getTemplate(sub.templateId);
        if (sub.taskId != null) {
          try {
            task = await _taskService.getTask(sub.taskId);
          } catch (_) {}
        }
        try {
          final wsData =
              await _workspaceService.getWorkspace(sub.workspaceId).first;
          if (wsData != null) {
            workspace = Workspace.fromJson(wsData, sub.workspaceId);
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _submission = sub;
          _template = template;
          _linkedTask = task;
          _workspace = workspace;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =========================================================
  // Actions
  // =========================================================

  Future<void> _signAsSupervisor() async {
    final sub = _submission;
    if (sub == null) return;
    final auth = context.read<AuthProvider>();
    final workspaceId = auth.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    setState(() => _isActing = true);
    try {
      final signed = await SignatureDialog.show(
        context,
        title: 'Sign as Supervisor',
        disclaimer:
            'By signing you confirm you have reviewed this form.',
        initialName: auth.appUser?.displayName ?? '',
        initialEmail: auth.appUser?.email ?? '',
        onSign: (name, email, bytes) async {
          await _service.signAsSupervisor(
            submissionId: sub.id,
            workspaceId: workspaceId,
            signatureBytes: bytes,
            name: name,
            email: email,
          );
        },
      );
      if (signed) await _load();
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _approve() async {
    final sub = _submission;
    if (sub == null) return;
    setState(() => _isActing = true);
    try {
      await _service.approveSubmission(sub.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Form approved')));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _reject() async {
    final sub = _submission;
    if (sub == null) return;
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Form'),
        content: SizedBox(
          width: 400,
          child: StackedField(
            label: 'Reason (optional)',
            child: TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Explain why this form is being rejected…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isActing = true);
    try {
      await _service.rejectSubmission(sub.id,
          reason: reasonController.text.trim().isEmpty
              ? null
              : reasonController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Form rejected')));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _requestCustomerSignature() async {
    final sub = _submission;
    if (sub == null) return;
    final auth = context.read<AuthProvider>();
    final workspaceId = auth.appUser?.currentWorkspaceId;
    final userId = auth.appUser?.id;
    if (workspaceId == null || userId == null) return;

    final emailController = TextEditingController(
        text: sub.customerSignature.signedByEmail ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request Customer Signature'),
        content: SizedBox(
          width: 400,
          child: StackedField(
            label: "Customer's Email",
            child: TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'customer@example.com',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send Link')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isActing = true);
    try {
      final token = await _service.createCustomerSignLink(
        submissionId: sub.id,
        workspaceId: workspaceId,
        recipientEmail: emailController.text.trim().isEmpty
            ? null
            : emailController.text.trim(),
        createdBy: userId,
      );
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: token));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Customer sign link copied to clipboard'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Customer Sign Link'),
                    content: SelectableText(token),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // =========================================================
  // Build
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_submission?.templateName ?? 'Form Submission'),
        actions: _buildAppBarActions(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _submission == null
              ? const Center(child: Text('Submission not found'))
              : _buildBody(context),
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  List<Widget> _buildAppBarActions() {
    final sub = _submission;
    if (sub == null) return [];
    final actions = <Widget>[];
    if (sub.status == FieldFormStatus.draft) {
      actions.add(TextButton(
        onPressed: () => context.push(
            '/field-forms/${sub.templateId}/fill?submissionId=${sub.id}'),
        child: const Text('Edit'),
      ));
    }
    actions.add(IconButton(
      tooltip: 'Download PDF',
      icon: _isExportingPdf
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined),
      onPressed: _isExportingPdf ? null : _exportPdf,
    ));
    return actions;
  }

  Widget _buildBody(BuildContext context) {
    final sub = _submission!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        _buildHeader(context, sub),
        const SizedBox(height: 16),
        if (_template != null && _template!.fields.isNotEmpty) ...[
          _buildFieldValues(context, sub, _template!.fields),
          const SizedBox(height: 16),
        ],
        _buildSignatures(context, sub),
        if (sub.notes != null && sub.notes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildNotes(context, sub.notes!),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, FieldFormSubmission sub) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(sub.status),
                const Spacer(),
                Text(
                  sub.formattedCreatedAt,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.person_outline, 'Filled by',
                sub.filledByName ?? '—'),
            if (sub.submittedAt != null)
              _buildInfoRow(
                Icons.check_circle_outline,
                'Submitted',
                DateFormat('MM/dd/yyyy hh:mm a').format(sub.submittedAt!),
              ),
            if (sub.taskId != null)
              _buildTaskRow(context, sub.taskId!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldValues(BuildContext context, FieldFormSubmission sub,
      List<FormFieldDefinition> fields) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Responses',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ...fields.map((field) {
              // Section headers
              if (field.type == FormFieldType.section) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      const SizedBox(height: 4),
                      Text(field.label,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      if (field.description != null &&
                          field.description!.isNotEmpty)
                        Text(field.description!,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }

              // Table fields
              if (field.type == FormFieldType.table) {
                final rows = (sub.data[field.id] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    [];
                final cols = field.columns ?? [];
                if (rows.isEmpty || cols.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(field.label,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          headingRowHeight: 32,
                          dataRowMinHeight: 28,
                          dataRowMaxHeight: 28,
                          columns: cols
                              .map((c) => DataColumn(
                                  label: Text(c.label,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.w600))))
                              .toList(),
                          rows: rows
                              .map((row) => DataRow(
                                    cells: cols
                                        .map((c) => DataCell(Text(
                                            row[c.key]?.toString() ??
                                                '',
                                            style: const TextStyle(
                                                fontSize: 12))))
                                        .toList(),
                                  ))
                              .toList(),
                        ),
                      ),
                      const Divider(height: 16),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    _buildFieldValueWidget(field, sub.data[field.id]),
                    const Divider(height: 16),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatFieldValue(FormFieldDefinition field, dynamic value) {
    if (value == null) return '';
    switch (field.type) {
      case FormFieldType.checkbox:
        return (value as bool? ?? false) ? 'Yes' : 'No';
      case FormFieldType.multiSelect:
        final list = (value as List?)?.cast<String>() ?? [];
        return list.join(', ');
      case FormFieldType.inspectionItem:
        switch (value as String?) {
          case 'pass':
            return '✓ Pass';
          case 'fail':
            return '✗ Fail';
          case 'na':
            return 'N/A';
          default:
            return '—';
        }
      case FormFieldType.rating:
        final r = (value as num?)?.toInt() ?? 0;
        return '${'★' * r}${'☆' * (5 - r)} ($r/5)';
      case FormFieldType.file:
      case FormFieldType.photo:
        if (value is Map) {
          return (value['fileName'] as String?) ?? 'File';
        }
        return value.toString();
      default:
        return value.toString();
    }
  }

  Widget _buildFieldValueWidget(FormFieldDefinition field, dynamic value) {
    if (value == null) {
      return const Text('—', style: TextStyle(fontSize: 14));
    }
    if ((field.type == FormFieldType.photo ||
            field.type == FormFieldType.file) &&
        value is Map) {
      final url = value['fileUrl'] as String?;
      final mimeType = (value['mimeType'] as String?) ?? '';
      final fileName = (value['fileName'] as String?) ?? 'File';
      final isImage = mimeType.startsWith('image/') ||
          _looksLikeImage(fileName) ||
          field.type == FormFieldType.photo;
      if (url != null && url.isNotEmpty && isImage) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            height: 220,
            width: double.infinity,
            placeholder: (_, __) => Container(
              height: 220,
              color: AppColors.background,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
            errorWidget: (_, __, ___) => Row(
              children: [
                const Icon(Icons.broken_image_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(fileName)),
              ],
            ),
          ),
        );
      }
      // Non-image file: show filename with a download link if url present.
      return Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(fileName, style: const TextStyle(fontSize: 14))),
        ],
      );
    }

    final str = _formatFieldValue(field, value);
    return Text(str.isEmpty ? '—' : str, style: const TextStyle(fontSize: 14));
  }

  bool _looksLikeImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp') ||
        n.endsWith('.heic');
  }

  Widget _buildTaskRow(BuildContext context, String taskId) {
    final title = _linkedTask?.title ?? taskId;
    final navPath = _linkedTask != null
        ? '/projects/${_linkedTask!.projectId}/tasks/${_linkedTask!.id}'
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.task_outlined,
              size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          const Text('Task: ',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Expanded(
            child: navPath == null
                ? Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))
                : InkWell(
                    onTap: () => context.push(navPath),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    final sub = _submission;
    final template = _template;
    final workspace = _workspace;
    if (sub == null || template == null || workspace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submission not ready for export')),
      );
      return;
    }

    setState(() => _isExportingPdf = true);
    try {
      // Fetch logo
      Uint8List? logoBytes;
      if (workspace.avatarUrl != null && workspace.avatarUrl!.isNotEmpty) {
        logoBytes = await PDFService.fetchImageBytes(workspace.avatarUrl!);
      }

      // Fetch image bytes for photo/file fields whose value points at an image.
      final imageBytes = <String, Uint8List>{};
      for (final field in template.fields) {
        if (field.type != FormFieldType.photo &&
            field.type != FormFieldType.file) {
          continue;
        }
        final v = sub.data[field.id];
        if (v is! Map) continue;
        final url = v['fileUrl'] as String?;
        final mime = (v['mimeType'] as String?) ?? '';
        final name = (v['fileName'] as String?) ?? '';
        final isImage = mime.startsWith('image/') ||
            _looksLikeImage(name) ||
            field.type == FormFieldType.photo;
        if (url == null || url.isEmpty || !isImage) continue;
        final bytes = await PDFService.fetchImageBytes(url);
        if (bytes != null) imageBytes[field.id] = bytes;
      }

      // Signatures
      Future<Uint8List?> fetchSig(FormSignatureSlot s) async {
        if (!s.isSigned || s.signatureUrl == null) return null;
        return PDFService.fetchImageBytes(s.signatureUrl!);
      }

      final techBytes = await fetchSig(sub.techSignature);
      final supBytes = await fetchSig(sub.supervisorSignature);
      final custBytes = await fetchSig(sub.customerSignature);

      final pdfBytes = await _pdfService.generateFieldFormSubmissionPDF(
        submission: sub,
        template: template,
        workspace: workspace,
        taskTitle: _linkedTask?.title,
        logoBytes: logoBytes,
        imageBytesByFieldId: imageBytes,
        techSignatureBytes: techBytes,
        supervisorSignatureBytes: supBytes,
        customerSignatureBytes: custBytes,
      );

      final safeName = template.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final datePart =
          DateFormat('yyyy-MM-dd').format(sub.submittedAt ?? sub.createdAt);
      final filename = '${safeName}_$datePart.pdf';
      await _pdfService.sharePDF(pdfBytes, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Widget _buildSignatures(
      BuildContext context, FieldFormSubmission sub) {
    final t = _template;
    // Only show signature slots the template requires, or ones already signed.
    final slots = <Widget>[];
    if (t?.requiresTechSignature == true || sub.techSignature.isSigned) {
      slots.add(_SignatureSlotTile(
        role: 'Technician',
        icon: Icons.construction_outlined,
        slot: sub.techSignature,
      ));
    }
    if (t?.requiresSupervisorSignature == true ||
        sub.supervisorSignature.isSigned) {
      slots.add(_SignatureSlotTile(
        role: 'Supervisor',
        icon: Icons.manage_accounts_outlined,
        slot: sub.supervisorSignature,
      ));
    }
    if (t?.requiresCustomerSignature == true ||
        sub.customerSignature.isSigned) {
      slots.add(_SignatureSlotTile(
        role: 'Customer',
        icon: Icons.person_outline,
        slot: sub.customerSignature,
      ));
    }
    if (slots.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signatures',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            for (var i = 0; i < slots.length; i++) ...[
              slots[i],
              if (i < slots.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotes(BuildContext context, String notes) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(notes),
          ],
        ),
      ),
    );
  }

  Widget? _buildActionBar(BuildContext context) {
    final sub = _submission;
    if (sub == null || sub.status.isTerminal) return null;

    final actions = <Widget>[];

    if (sub.status == FieldFormStatus.submitted) {
      if (_template?.requiresSupervisorSignature == true &&
          !sub.supervisorSignature.isSigned) {
        actions.add(OutlinedButton.icon(
          onPressed: _isActing ? null : _signAsSupervisor,
          icon: const Icon(Icons.draw_outlined, size: 18),
          label: const Text('Sign as Supervisor'),
        ));
      }
      if (_template?.requiresCustomerSignature == true &&
          !sub.customerSignature.isSigned) {
        actions.add(OutlinedButton.icon(
          onPressed: _isActing ? null : _requestCustomerSignature,
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Request Customer Sig'),
        ));
      }
      actions.add(ElevatedButton.icon(
        onPressed: _isActing ? null : _approve,
        icon: _isActing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check, size: 18),
        label: const Text('Approve'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white),
      ));
      actions.add(OutlinedButton.icon(
        onPressed: _isActing ? null : _reject,
        icon: const Icon(Icons.close, size: 18),
        label: const Text('Reject'),
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
      ));
    }

    if (actions.isEmpty) return null;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(
              top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: actions,
        ),
      ),
    );
  }
}

// ───────────────���──────────────────────────────────────���──────
// Sub-widgets
// ─────────────────────────────────────────────���───────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final FieldFormStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusChip(label: status.displayName, color: status.color);
  }
}

class _SignatureSlotTile extends StatelessWidget {
  const _SignatureSlotTile({
    required this.role,
    required this.icon,
    required this.slot,
  });

  final String role;
  final IconData icon;
  final FormSignatureSlot slot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: slot.isSigned
            ? AppColors.success.withOpacity(0.06)
            : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: slot.isSigned
              ? AppColors.success.withOpacity(0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: slot.isSigned
                  ? AppColors.success
                  : AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                if (slot.isSigned)
                  Text(
                    '${slot.signedByName ?? ''} · ${slot.formattedSignedAt}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  )
                else
                  Text('Not yet signed',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Icon(
            slot.isSigned ? Icons.verified_outlined : Icons.pending_outlined,
            size: 16,
            color: slot.isSigned
                ? AppColors.success
                : AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
