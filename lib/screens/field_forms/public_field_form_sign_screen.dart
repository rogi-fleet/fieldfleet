import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import '../../config/supabase_config.dart';
import '../../models/form_field_definition.dart';
import '../../models/form_field_type.dart';
import '../../widgets/forms/stacked_field.dart';
import '../../theme/theme.dart';

/// Public screen for customer signing of a field form submission.
/// Reached via /sign-form/:token — no authentication required.
class PublicFieldFormSignScreen extends StatefulWidget {
  const PublicFieldFormSignScreen({super.key, required this.token});

  final String token;

  @override
  State<PublicFieldFormSignScreen> createState() =>
      _PublicFieldFormSignScreenState();
}

class _PublicFieldFormSignScreenState
    extends State<PublicFieldFormSignScreen> {
  bool _isLoading = true;
  bool _isSigning = false;
  String? _error;

  Map<String, dynamic>? _submission;
  Map<String, dynamic>? _template;
  Map<String, dynamic>? _link;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _signatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  String get _edgeFunctionUrl =>
      '${SupabaseConfig.url}/functions/v1/form-signing';

  @override
  void initState() {
    super.initState();
    _resolveToken();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // API calls
  // ─────────────────────────────────────────────────────────

  Future<void> _resolveToken() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse(_edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({'action': 'resolve', 'token': widget.token}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        setState(() {
          _error = _extractError(data, 'Unable to open signing link');
          _isLoading = false;
        });
        return;
      }

      final link = data['link'] as Map<String, dynamic>?;
      final recipientEmail = link?['recipientEmail'] as String?;
      if (recipientEmail != null && recipientEmail.isNotEmpty) {
        _emailController.text = recipientEmail;
      }

      setState(() {
        _submission = data['submission'] as Map<String, dynamic>?;
        _template = data['template'] as Map<String, dynamic>?;
        _link = link;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unable to load form: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _sign() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      _snack('Enter your full name');
      return;
    }
    if (email.isEmpty) {
      _snack('Enter your email address');
      return;
    }
    if (!_isValidEmail(email)) {
      _snack('Enter a valid email address');
      return;
    }
    if (_signatureController.isEmpty) {
      _snack('Please draw your signature');
      return;
    }

    final signatureBytes = await _signatureController.toPngBytes();
    if (!mounted) return;
    if (signatureBytes == null) {
      _snack('Could not read signature');
      return;
    }

    setState(() => _isSigning = true);
    try {
      final response = await http.post(
        Uri.parse(_edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'action': 'sign',
          'token': widget.token,
          'signedByName': name,
          'signedByEmail': email,
          'signaturePngBase64': base64Encode(signatureBytes),
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(_extractError(data, 'Failed to sign form'));
      }

      // Reload to show signed state
      await _resolveToken();
      if (mounted) _snack('Form signed successfully');
    } catch (e) {
      if (mounted) _snack('Signing failed: $e');
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sub = _submission;
    final isSigned = sub?['customerSignedAt'] != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign Form')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 16),
                        _buildFieldValues(context),
                        const SizedBox(height: 16),
                        if (isSigned)
                          _buildSignedConfirmation(context)
                        else
                          _buildSignatureForm(context),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Unable to Open Form',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final templateName = _submission?['templateName'] as String? ?? 'Form';
    final templateDesc = _template?['description'] as String?;
    final filledBy = _submission?['filledByName'] as String?;
    final submittedAt = _submission?['submittedAt'] as String?;
    final expiresAt = _link?['expiresAt'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(templateName,
                style: Theme.of(context).textTheme.titleLarge),
            if (templateDesc != null && templateDesc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(templateDesc,
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            if (filledBy != null)
              _infoRow(Icons.person_outline, 'Prepared by', filledBy),
            if (submittedAt != null)
              _infoRow(Icons.calendar_today_outlined, 'Submitted',
                  _formatDate(submittedAt)),
            if (expiresAt != null)
              _infoRow(Icons.timer_outlined, 'Link expires',
                  _formatDate(expiresAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldValues(BuildContext context) {
    final rawFields = _template?['fields'] as List?;
    final data = _submission?['data'] as Map<String, dynamic>? ?? {};

    if (rawFields == null || rawFields.isEmpty) {
      return const SizedBox.shrink();
    }

    final fields = rawFields
        .cast<Map<String, dynamic>>()
        .map((f) => FormFieldDefinition.fromJson(f))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Form Responses',
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
                final rows = (data[field.id] as List?)
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

              final value = data[field.id];
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
                    Text(
                      _formatValue(field, value),
                      style: const TextStyle(fontSize: 14),
                    ),
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

  Widget _buildSignatureForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Signature',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Please review the form above and sign below to confirm.',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Full Name *',
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Enter your full name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Email Address *',
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Enter your email address',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Signature *',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
            const SizedBox(height: 8),
            Container(
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Signature(
                  controller: _signatureController,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isSigning
                    ? null
                    : () => setState(() => _signatureController.clear()),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'By signing, you confirm you have reviewed this form and its contents are accurate.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSigning ? null : _sign,
                icon: _isSigning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.draw),
                label: Text(_isSigning ? 'Signing…' : 'Sign Form'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedConfirmation(BuildContext context) {
    final signedBy = _submission?['customerSignedByName'] as String? ?? '';
    final signedAt = _submission?['customerSignedAt'] as String?;

    return Card(
      color: AppColors.success.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: BorderSide(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.verified_outlined,
                size: 48, color: AppColors.success),
            const SizedBox(height: 12),
            Text(
              'Form Signed',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            if (signedBy.isNotEmpty)
              Text('Signed by $signedBy',
                  style: TextStyle(color: AppColors.textSecondary)),
            if (signedAt != null)
              Text(_formatDate(signedAt),
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Utility
  // ─────────────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String label, String value) {
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

  String _formatValue(FormFieldDefinition field, dynamic value) {
    if (value == null) return '—';
    switch (field.type) {
      case FormFieldType.checkbox:
        return (value as bool? ?? false) ? 'Yes' : 'No';
      case FormFieldType.multiSelect:
        final list = (value as List?)?.cast<String>() ?? [];
        return list.isEmpty ? '—' : list.join(', ');
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
        if (value is Map) return (value['fileName'] as String?) ?? 'File';
        return value.toString();
      case FormFieldType.section:
        return '';
      case FormFieldType.table:
        return '(table data)';
      default:
        final s = value.toString();
        return s.isEmpty ? '—' : s;
    }
  }

  static String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('MM/dd/yyyy hh:mm a').format(date.toLocal());
    } catch (_) {
      return isoDate;
    }
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  static String _extractError(Map<String, dynamic> body, String fallback) {
    for (final key in const ['error', 'message', 'msg']) {
      final v = body[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return fallback;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
