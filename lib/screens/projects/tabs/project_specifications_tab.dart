/// Specifications tab for a project.
///
/// FAB "New specifications sheet" opens a budget-item multi-select dialog and
/// produces a PDF (description + qty + unit; no pricing). The PDF is uploaded
/// to Supabase Storage as a `file_attachment`, recorded in `spec_sheets`, and
/// listed on this tab so it can be opened, emailed or shared in a project
/// conversation.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/budget_item.dart';
import '../../../models/conversation.dart';
import '../../../models/file_attachment.dart';
import '../../../models/project.dart';
import '../../../models/spec_sheet.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/confirm_dialog.dart';
import '../../../utils/project_terminology.dart';
import '../../../utils/user_facing_error.dart';
import '../specifications/specs_pdf_builder.dart';

class ProjectSpecificationsTab extends StatefulWidget {
  final Project project;
  const ProjectSpecificationsTab({super.key, required this.project});

  @override
  State<ProjectSpecificationsTab> createState() =>
      _ProjectSpecificationsTabState();
}

class _ProjectSpecificationsTabState extends State<ProjectSpecificationsTab> {
  late final Stream<List<SpecSheet>> _stream =
      ServiceLocator.specificationService.watchSheets(widget.project.id);
  final _dateFmt = DateFormat.yMMMd();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _createSpecSheet,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('New specifications sheet'),
      ),
      body: StreamBuilder<List<SpecSheet>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(UserFacingError.uiMessage(snap.error,
                  action: 'load specifications sheets')),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sheets = snap.data!;
          if (sheets.isEmpty) {
            return _empty();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: sheets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _sheetCard(sheets[i]),
          );
        },
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.picture_as_pdf_outlined,
              size: 48, color: Colors.black38),
          const SizedBox(height: 12),
          const Text('No specifications sheets yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Text(
              'Pick budget items to include and generate a printable PDF. '
              'Saved sheets can be downloaded, emailed or sent in a message.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _createSpecSheet,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('New specifications sheet'),
          ),
        ],
      ),
    );
  }

  Widget _sheetCard(SpecSheet sheet) {
    final hasUrl = (sheet.fileUrl ?? '').isNotEmpty;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: hasUrl ? () => _openSheet(sheet) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.red.shade50,
                child: Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.red.shade700),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sheet.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      '${sheet.itemCount} item${sheet.itemCount == 1 ? "" : "s"}'
                      ' • Created ${_dateFmt.format(sheet.createdAt)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (v) => _handleAction(v, sheet),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: Row(children: [
                      Icon(Icons.open_in_new, size: 18),
                      SizedBox(width: 10),
                      Text('Open / Download'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'email',
                    child: Row(children: [
                      Icon(Icons.mail_outline, size: 18),
                      SizedBox(width: 10),
                      Text('Email'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'message',
                    child: Row(children: [
                      Icon(Icons.chat_bubble_outline, size: 18),
                      SizedBox(width: 10),
                      Text('Send in message'),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text('Delete',
                          style: TextStyle(color: Colors.redAccent)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleAction(String action, SpecSheet sheet) async {
    switch (action) {
      case 'open':
        await _openSheet(sheet);
        break;
      case 'email':
        await _emailSheet(sheet);
        break;
      case 'message':
        await _sendInMessage(sheet);
        break;
      case 'delete':
        await _deleteSheet(sheet);
        break;
    }
  }

  Future<void> _openSheet(SpecSheet sheet) async {
    final url = sheet.fileUrl;
    if (url == null || url.isEmpty) {
      _toast('PDF is unavailable.');
      return;
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open the PDF.');
  }

  Future<void> _deleteSheet(SpecSheet sheet) async {
    final confirm = await confirmDestructive(
      context,
      title: 'Delete this sheet?',
      message: 'This will permanently remove "${sheet.title}" and its PDF.',
    );
    if (!confirm) return;
    try {
      await ServiceLocator.specificationService.deleteSheet(sheet.id);
    } catch (e) {
      if (!mounted) return;
      _toast(UserFacingError.uiMessage(e, action: 'delete sheet'));
    }
  }

  Future<void> _emailSheet(SpecSheet sheet) async {
    final result = await showDialog<_EmailResult>(
      context: context,
      builder: (_) => _EmailSheetDialog(defaultSubject: sheet.title),
    );
    if (result == null) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'send-spec-sheet-email',
        body: {
          'specSheetId': sheet.id,
          'recipientEmail': result.email,
          if (result.subject.isNotEmpty) 'subject': result.subject,
          if (result.message.isNotEmpty) 'message': result.message,
        },
      );
      if (!mounted) return;
      _toast('Email sent to ${result.email}.');
    } catch (e) {
      if (!mounted) return;
      _toast(UserFacingError.uiMessage(e, action: 'send email'));
    }
  }

  Future<void> _sendInMessage(SpecSheet sheet) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.appUser;
    final workspaceId = user?.currentWorkspaceId;
    if (user == null || workspaceId == null) {
      _toast('You must be signed in to send a message.');
      return;
    }

    // Pull a snapshot of project-scoped conversations the user participates
    // in. Picker dialog handles the "no conversations" state.
    final convos = await ServiceLocator.messageService
        .getConversationsByScope(
          workspaceId: workspaceId,
          userId: user.id,
          scope: 'project',
          scopeReferenceId: widget.project.id,
        )
        .first as List<Conversation>;

    if (!mounted) return;
    final picked = await showDialog<Conversation>(
      context: context,
      builder: (_) => _ConversationPickerDialog(conversations: convos),
    );
    if (picked == null) return;

    try {
      // Re-use the same file_attachment; build a MessageAttachment payload
      // pointing at the stored PDF.
      final fileRow = await Supabase.instance.client
          .from('file_attachments')
          .select(
              'id, file_name, file_url, file_size, mime_type, thumbnail_url')
          .eq('id', sheet.fileAttachmentId)
          .single();
      final attachmentJson = {
        'id': fileRow['id'],
        'fileName': fileRow['file_name'],
        'fileUrl': fileRow['file_url'],
        'fileSize': fileRow['file_size'],
        'mimeType': fileRow['mime_type'],
        'thumbnailUrl': fileRow['thumbnail_url'],
      };
      await ServiceLocator.messageService.sendMessage(
        conversationId: picked.id,
        workspaceId: workspaceId,
        senderId: user.id,
        senderName: user.displayName ?? 'Unknown',
        content: 'Specifications sheet: ${sheet.title}',
        attachments: [attachmentJson],
      );
      if (!mounted) return;
      _toast('Sent to ${picked.subject ?? "conversation"}.');
    } catch (e) {
      if (!mounted) return;
      _toast(UserFacingError.uiMessage(e, action: 'send message'));
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------------
  // Create flow
  // ---------------------------------------------------------------------------

  Future<void> _createSpecSheet() async {
    List<BudgetItem> items;
    try {
      items = await ServiceLocator.budgetService
          .getBudgetItems(widget.project.id,
              workspaceId: widget.project.workspaceId)
          .first;
    } catch (e) {
      if (!mounted) return;
      _toast(UserFacingError.uiMessage(e, action: 'load budget items'));
      return;
    }

    if (!mounted) return;
    final leafCount =
        items.where((b) => b.itemType == BudgetItemType.item).length;
    if (leafCount == 0) {
      _toast('This project has no budget items yet. Add budget items first, '
          'then generate a specifications sheet.');
      return;
    }

    final result = await showDialog<_PickerResult>(
      context: context,
      builder: (_) => _BudgetItemPickerDialog(
        allItems: items,
        defaultTitle:
            'Specifications — ${widget.project.name} — '
            '${DateFormat.yMMMd().format(DateTime.now())}',
      ),
    );
    if (result == null || result.selectedIds.isEmpty) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await buildSpecsPdf(
        project: widget.project,
        allItems: items,
        selectedIds: result.selectedIds,
      );

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.appUser;
      if (user == null) throw Exception('Not signed in');

      final safeName = result.title
          .replaceAll(RegExp(r'[\\/\r\n]+'), ' ')
          .trim();
      final fileName = '$safeName.pdf';

      final FileAttachment uploaded = await ServiceLocator.storageService
          .uploadFileBytes(
        bytes: bytes,
        fileName: fileName,
        workspaceId: widget.project.workspaceId,
        projectId: widget.project.id,
        uploadedBy: user.id,
      );

      await ServiceLocator.specificationService.createSheet(
        workspaceId: widget.project.workspaceId,
        projectId: widget.project.id,
        title: result.title,
        fileAttachmentId: uploaded.id,
        itemIds: result.selectedIds.toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Specifications sheet saved.'),
        action: SnackBarAction(
          label: 'Preview',
          onPressed: () async {
            try {
              await Printing.layoutPdf(
                name: result.title,
                onLayout: (_) async => bytes,
              );
            } catch (_) {/* user cancelled */}
          },
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      _toast(UserFacingError.uiMessage(e,
          action: 'generate specifications PDF'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// =============================================================================
// Email dialog
// =============================================================================

class _EmailResult {
  final String email;
  final String subject;
  final String message;
  _EmailResult(this.email, this.subject, this.message);
}

class _EmailSheetDialog extends StatefulWidget {
  final String defaultSubject;
  const _EmailSheetDialog({required this.defaultSubject});

  @override
  State<_EmailSheetDialog> createState() => _EmailSheetDialogState();
}

class _EmailSheetDialogState extends State<_EmailSheetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  late final TextEditingController _subjectCtrl =
      TextEditingController(text: 'Specifications: ${widget.defaultSubject}');
  final _messageCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Email specifications sheet'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailCtrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Recipient email *',
                    border: OutlineInputBorder()),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                    labelText: 'Subject', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Message (optional)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Send'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _EmailResult(
                _emailCtrl.text.trim(),
                _subjectCtrl.text.trim(),
                _messageCtrl.text.trim(),
              ),
            );
          },
        ),
      ],
    );
  }
}

// =============================================================================
// Conversation picker (project-scoped)
// =============================================================================

class _ConversationPickerDialog extends StatelessWidget {
  final List<Conversation> conversations;
  const _ConversationPickerDialog({required this.conversations});

  @override
  Widget build(BuildContext context) {
    final projectTermLower = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();
    return AlertDialog(
      title: Text('Send to $projectTermLower conversation'),
      content: SizedBox(
        width: 480,
        height: 360,
        child: conversations.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Text(
                    'No $projectTermLower conversations yet.\n'
                    'Start one from the Messages tab, then try again.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              )
            : ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = conversations[i];
                  final title = c.displayTitle.isNotEmpty
                      ? c.displayTitle
                      : (c.subject ?? 'Conversation');
                  return ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(title),
                    subtitle: c.lastMessage != null
                        ? Text(c.lastMessage!,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// =============================================================================
// Budget item picker dialog (with title input)
// =============================================================================

class _PickerResult {
  final Set<String> selectedIds;
  final String title;
  _PickerResult(this.selectedIds, this.title);
}

class _BudgetItemPickerDialog extends StatefulWidget {
  final List<BudgetItem> allItems;
  final String defaultTitle;
  const _BudgetItemPickerDialog({
    required this.allItems,
    required this.defaultTitle,
  });

  @override
  State<_BudgetItemPickerDialog> createState() =>
      _BudgetItemPickerDialogState();
}

class _BudgetItemPickerDialogState extends State<_BudgetItemPickerDialog> {
  final Set<String> _selected = {};
  String _query = '';
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.defaultTitle);

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  List<BudgetItem> get _orderedItems {
    final byParent = <String?, List<BudgetItem>>{};
    for (final b in widget.allItems) {
      byParent.putIfAbsent(b.parentId, () => []).add(b);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    final result = <BudgetItem>[];
    void walk(BudgetItem n) {
      result.add(n);
      for (final c in byParent[n.id] ?? const <BudgetItem>[]) {
        walk(c);
      }
    }
    for (final r in byParent[null] ?? const <BudgetItem>[]) {
      walk(r);
    }
    return result;
  }

  bool _matches(BudgetItem item) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return item.name.toLowerCase().contains(q) ||
        (item.description?.toLowerCase().contains(q) ?? false);
  }

  void _selectAllVisible(List<BudgetItem> visibleLeaves) {
    setState(() {
      _selected.addAll(visibleLeaves.map((e) => e.id));
    });
  }

  void _clearAll() {
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _orderedItems;
    Set<String> includedGroupIds = {};
    if (_query.isNotEmpty) {
      final byId = {for (final b in widget.allItems) b.id: b};
      for (final b in ordered) {
        if (b.itemType == BudgetItemType.item && _matches(b)) {
          var cur = b.parentId == null ? null : byId[b.parentId!];
          while (cur != null) {
            includedGroupIds.add(cur.id);
            cur = cur.parentId == null ? null : byId[cur.parentId!];
          }
        }
      }
    }

    final rows = <Widget>[];
    final visibleLeaves = <BudgetItem>[];
    for (final item in ordered) {
      if (item.itemType == BudgetItemType.group) {
        if (_query.isNotEmpty && !includedGroupIds.contains(item.id)) continue;
        rows.add(_groupHeader(item));
      } else {
        if (!_matches(item)) continue;
        visibleLeaves.add(item);
        rows.add(_itemTile(item));
      }
    }

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      title: Row(
        children: [
          const Expanded(child: Text('New specifications sheet')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sheet title',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search items or descriptions...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.md),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: visibleLeaves.isEmpty
                        ? null
                        : () => _selectAllVisible(visibleLeaves),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty ? null : _clearAll,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          'No matching budget items.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  : ListView(children: rows),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Generate & save'),
          onPressed: _selected.isEmpty || _titleCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _PickerResult(
                      Set<String>.from(_selected),
                      _titleCtrl.text.trim(),
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _groupHeader(BudgetItem g) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20 + g.hierarchyLevel * 14.0, 10, 16, 4),
      child: Text(
        g.name,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _itemTile(BudgetItem item) {
    final isSelected = _selected.contains(item.id);
    final qty = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(2);
    final qtyLabel = item.unit != null && item.unit!.isNotEmpty
        ? '$qty ${item.unit}'
        : qty;
    return CheckboxListTile(
      value: isSelected,
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _selected.add(item.id);
          } else {
            _selected.remove(item.id);
          }
        });
      },
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.only(
          left: 12 + item.hierarchyLevel * 14.0, right: 16),
      title: Text(
        item.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: (item.description?.isNotEmpty == true)
          ? Text(
              item.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            )
          : null,
      secondary: Text(
        qtyLabel,
        style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
