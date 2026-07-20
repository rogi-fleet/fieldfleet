import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'stacked_field.dart';
import '../../theme/theme.dart';

/// A reusable dialog for capturing a digital signature.
///
/// Collects the signer's name, email address, and a drawn signature,
/// then calls [onSign] with the raw PNG bytes. The caller is responsible
/// for uploading the bytes and persisting the result.
///
/// Usage:
/// ```dart
/// final signed = await SignatureDialog.show(
///   context,
///   title: 'Sign as Technician',
///   disclaimer: 'By signing you confirm the work is complete.',
///   onSign: (name, email, bytes) async {
///     final url = await storageService.uploadSignature(...);
///     await formService.signAsTechnician(url: url, name: name, email: email);
///   },
/// );
/// ```
class SignatureDialog extends StatefulWidget {
  const SignatureDialog({
    super.key,
    required this.title,
    required this.onSign,
    this.disclaimer,
    this.initialName,
    this.initialEmail,
    this.requireEmail = true,
  });

  final String title;

  /// Called with (name, email, pngBytes) when the user confirms.
  /// Throw to show an error; the dialog stays open on throw.
  final Future<void> Function(String name, String email, Uint8List pngBytes)
      onSign;

  final String? disclaimer;
  final String? initialName;
  final String? initialEmail;

  /// When false the email field is still shown but not required.
  final bool requireEmail;

  /// Convenience wrapper that shows the dialog and returns whether signing
  /// completed successfully.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required Future<void> Function(String name, String email, Uint8List pngBytes)
        onSign,
    String? disclaimer,
    String? initialName,
    String? initialEmail,
    bool requireEmail = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SignatureDialog(
        title: title,
        onSign: onSign,
        disclaimer: disclaimer,
        initialName: initialName,
        initialEmail: initialEmail,
        requireEmail: requireEmail,
      ),
    );
    return result ?? false;
  }

  @override
  State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  late final SignatureController _signatureController;
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  bool _isSigning = false;

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _nameController =
        TextEditingController(text: widget.initialName ?? '');
    _emailController =
        TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSign() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      _showSnack('Please enter your name');
      return;
    }
    if (widget.requireEmail && email.isEmpty) {
      _showSnack('Please enter your email');
      return;
    }
    if (_signatureController.isEmpty) {
      _showSnack('Please draw your signature');
      return;
    }

    setState(() => _isSigning = true);
    try {
      final pngBytes = await _signatureController.toPngBytes();
      if (pngBytes == null) throw Exception('Failed to export signature');
      await widget.onSign(name, email, pngBytes);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StackedField(
              label: 'Your Name *',
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
              label: widget.requireEmail ? 'Your Email *' : 'Your Email',
              child: TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  hintText: 'Enter your email address',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Signature',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Container(
              height: 150,
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
            if (widget.disclaimer != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.disclaimer!,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSigning ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSigning ? null : _handleSign,
          icon: _isSigning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_isSigning ? 'Signing…' : 'Sign'),
        ),
      ],
    );
  }
}
