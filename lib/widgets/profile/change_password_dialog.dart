import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../auth/password_strength_indicator.dart';
import '../forms/stacked_field.dart';

/// Modal dialog for in-app password change. Reauthenticates with the
/// current password before applying the new one.
class ChangePasswordDialog {
  const ChangePasswordDialog._();

  static Future<bool> show(BuildContext context) async {
    final result = await showFormPopup<bool>(
      context,
      icon: Icons.lock_reset,
      title: 'Change Password',
      width: 420,
      builder: (ctx, scrollController) =>
          _ChangePasswordFormContent(scrollController: scrollController),
    );
    return result ?? false;
  }
}

class _ChangePasswordFormContent extends StatefulWidget {
  final ScrollController? scrollController;
  const _ChangePasswordFormContent({this.scrollController});

  @override
  State<_ChangePasswordFormContent> createState() =>
      _ChangePasswordFormContentState();
}

class _ChangePasswordFormContentState
    extends State<_ChangePasswordFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _newController.addListener(_onNewChanged);
  }

  @override
  void dispose() {
    _newController.removeListener(_onNewChanged);
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onNewChanged() => setState(() {});

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Capture before await — the dialog may be torn down before this
    // future resolves and `context` becomes unsafe to use.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authProvider = context.read<AuthProvider>();

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await authProvider.updatePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      navigator.pop(true);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('Password updated'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Sign out other devices',
              onPressed: () => _signOutOtherDevices(authProvider, messenger),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = UserFacingError.uiMessage(e, action: 'update password');
        _saving = false;
      });
    }
  }

  Future<void> _signOutOtherDevices(
    AuthProvider authProvider,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      await authProvider.signOutEverywhere();
      // Auth listener handles the redirect to login.
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'sign out other devices'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PasswordField(
                label: 'Current password',
                prefixIcon: Icons.lock_outline,
                controller: _currentController,
                autofillHints: const [AutofillHints.password],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter your current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _PasswordField(
                label: 'New password',
                prefixIcon: Icons.lock_reset,
                controller: _newController,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'Use at least 8 characters';
                  }
                  if (value == _currentController.text) {
                    return 'New password must differ from current';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              PasswordStrengthIndicator(password: _newController.text),
              const SizedBox(height: 16),
              _PasswordField(
                label: 'Confirm new password',
                prefixIcon: Icons.check,
                controller: _confirmController,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  if (value != _newController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
                ],
              ),
            ),
          ),
        ),
        FormPopupFooter(
          onCancel: _saving ? null : () => Navigator.of(context).pop(false),
          onSubmit: _saving ? null : _submit,
          submitLabel: 'Update password',
          busy: _saving,
        ),
      ],
    );
  }
}

class _PasswordField extends StatefulWidget {
  final String label;
  final IconData prefixIcon;
  final TextEditingController controller;
  final List<String> autofillHints;
  final FormFieldValidator<String> validator;

  const _PasswordField({
    required this.label,
    required this.prefixIcon,
    required this.controller,
    required this.autofillHints,
    required this.validator,
  });

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return StackedField(
      label: widget.label,
      child: TextFormField(
        controller: widget.controller,
        obscureText: _obscure,
        autofillHints: widget.autofillHints,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          prefixIcon: Icon(widget.prefixIcon),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        validator: widget.validator,
      ),
    );
  }
}
