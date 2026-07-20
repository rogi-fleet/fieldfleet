import 'package:flutter/material.dart';
import '../models/generated_document.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import '../theme/theme.dart';

/// Data for a single recipient in the send dialog.
class _Recipient {
  final TextEditingController emailController;
  bool requireSignature = false;

  _Recipient({String email = ''})
      : emailController = TextEditingController(text: email);

  void dispose() => emailController.dispose();
}

/// Enhanced send document dialog with multiple recipients and signature toggles.
class SendDocumentDialog extends StatefulWidget {
  final GeneratedDocument document;
  final Future<void> Function(
    String email,
    String subject,
    String message, {
    bool requireSignature,
  }) sendDocument;

  const SendDocumentDialog({
    super.key,
    required this.document,
    required this.sendDocument,
  });

  /// Show the dialog and return true if any documents were sent.
  static Future<bool?> show(
    BuildContext context, {
    required GeneratedDocument document,
    required Future<void> Function(
      String email,
      String subject,
      String message, {
      bool requireSignature,
    }) sendDocument,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => SendDocumentDialog(
        document: document,
        sendDocument: sendDocument,
      ),
    );
  }

  @override
  State<SendDocumentDialog> createState() => _SendDocumentDialogState();
}

class _SendDocumentDialogState extends State<SendDocumentDialog> {
  final List<_Recipient> _recipients = [];
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  final _newRecipientController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _subjectController = TextEditingController(
      text: widget.document.emailSubject ?? 'Document for your signature',
    );
    _messageController = TextEditingController(
      text: widget.document.emailMessage ??
          'Please review and sign the attached document at your earliest convenience.',
    );

    // Pre-fill first recipient from preparedFor email, or start with an empty row
    final preparedForEmail = widget.document.preparedFor?.email;
    if (preparedForEmail != null && preparedForEmail.isNotEmpty) {
      _recipients.add(_Recipient(email: preparedForEmail));
    } else {
      _recipients.add(_Recipient());
    }
  }

  @override
  void dispose() {
    for (final r in _recipients) {
      r.dispose();
    }
    _subjectController.dispose();
    _messageController.dispose();
    _newRecipientController.dispose();
    super.dispose();
  }

  void _addRecipient([String email = '']) {
    setState(() {
      _recipients.add(_Recipient(email: email));
    });
  }

  void _removeRecipient(int index) {
    setState(() {
      _recipients[index].dispose();
      _recipients.removeAt(index);
    });
  }

  void _addFromField() {
    final email = _newRecipientController.text.trim();
    if (email.isNotEmpty) {
      _addRecipient(email);
      _newRecipientController.clear();
    }
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  Future<void> _send() async {
    // Auto-absorb any draft text in the "add recipient" field
    final draftEmail = _newRecipientController.text.trim();
    if (draftEmail.isNotEmpty) {
      _addRecipient(draftEmail);
      _newRecipientController.clear();
    }

    final validRecipients = _recipients
        .where((r) => r.emailController.text.trim().isNotEmpty)
        .toList();

    if (validRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one recipient')),
      );
      return;
    }

    // Validate all email formats
    final invalidEmails = validRecipients
        .where((r) => !_isValidEmail(r.emailController.text.trim()))
        .map((r) => r.emailController.text.trim())
        .toList();
    if (invalidEmails.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid email: ${invalidEmails.first}')),
      );
      return;
    }

    setState(() => _isSending = true);

    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    final failed = <String>[];
    var succeeded = 0;

    for (final recipient in validRecipients) {
      try {
        await widget.sendDocument(
          recipient.emailController.text.trim(),
          subject,
          message,
          requireSignature: recipient.requireSignature,
        );
        succeeded++;
      } catch (_) {
        failed.add(recipient.emailController.text.trim());
      }
    }

    if (!mounted) return;

    if (failed.isEmpty) {
      Navigator.pop(context, true);
    } else {
      setState(() => _isSending = false);
      final msg = succeeded > 0
          ? 'Sent to $succeeded recipient(s), but failed for: ${failed.join(", ")}'
          : 'Failed to send to: ${failed.join(", ")}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send Document'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recipients section
              const Text(
                'Recipients',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),

              // Existing recipients
              ...List.generate(_recipients.length, (index) {
                final recipient = _recipients[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: recipient.emailController,
                        decoration: InputDecoration(
                          hintText: 'recipient@example.com',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: const Icon(Icons.email, size: 18),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _removeRecipient(index),
                            tooltip: 'Remove',
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      Row(
                        children: [
                          Checkbox(
                            value: recipient.requireSignature,
                            onChanged: (value) {
                              setState(() {
                                recipient.requireSignature = value ?? false;
                              });
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                          const Text('Signature',
                              style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              // Add recipient field
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newRecipientController,
                      decoration: const InputDecoration(
                        hintText: 'Add a recipient...',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.person_add, size: 18),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => _addFromField(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _addFromField,
                    tooltip: 'Add recipient',
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Quick add button
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addRecipient(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add another recipient'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),

              const Divider(height: 24),

              // Email Message section
              StackedField(
                label: 'Subject',
                child: TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.subject),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StackedField(
                label: 'Message',
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _isSending ? null : _send,
          icon: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(_isSending ? 'Sending...' : 'Send'),
        ),
      ],
    );
  }
}
