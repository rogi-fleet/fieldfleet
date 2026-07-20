import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/supabase_config.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/forms/stacked_field.dart';

/// Vendor Portal login screen. Mirrors the customer portal login: vendor
/// enters their email and we send a magic link gated by
/// `portal_vendor_can_request_access`.
class VendorPortalLoginScreen extends StatefulWidget {
  const VendorPortalLoginScreen({super.key});

  @override
  State<VendorPortalLoginScreen> createState() =>
      _VendorPortalLoginScreenState();
}

class _VendorPortalLoginScreenState extends State<VendorPortalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _service = ServiceLocator.vendorPortalService;

  bool _isLoading = false;
  bool _emailSent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // If a session already exists, route straight into the portal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_service.isSignedIn && mounted) {
        context.go('/vendor-portal/dashboard');
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _service.requestMagicLink(
        _emailController.text,
        siteUrl: SupabaseConfig.siteUrl,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailSent = true;
      });
    } catch (_) {
      // Show the same success-style screen on failure to avoid leaking
      // whether a given email is a known vendor contact. The user will
      // simply not receive an email if their address is not eligible.
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailSent = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F766E), Color(0xFF1E3A8A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.r16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: _emailSent ? _buildSent() : _buildForm(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSent() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_read,
                size: 48, color: AppColors.success),
          ),
          const SizedBox(height: 24),
          const Text('Check Your Email',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'If ${_emailController.text} is registered as a vendor contact, '
            'a login link is on its way. The link expires in 1 hour.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => setState(() => _emailSent = false),
            child: const Text('Use a different email'),
          ),
        ],
      );

  Widget _buildForm() => Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.construction, size: 48, color: Color(0xFF0F766E)),
            const SizedBox(height: 16),
            const Text('Vendor Portal',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Enter your email to respond to bids, work orders, and submit bills.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 32),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.errorDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.errorDark)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            StackedField(
              label: 'Email Address',
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter your email';
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                      .hasMatch(v)) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send Login Link',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => context.go('/portal'),
                  child: const Text('Customer login'),
                ),
                const Text('·', style: TextStyle(color: AppColors.textTertiary)),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Staff login'),
                ),
              ],
            ),
          ],
        ),
      );
}
