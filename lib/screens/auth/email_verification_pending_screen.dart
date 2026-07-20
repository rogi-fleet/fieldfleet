import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';

class EmailVerificationPendingScreen extends StatefulWidget {
  final String? initialEmail;
  final String? redirectTo;

  const EmailVerificationPendingScreen({
    super.key,
    this.initialEmail,
    this.redirectTo,
  });

  @override
  State<EmailVerificationPendingScreen> createState() =>
      _EmailVerificationPendingScreenState();
}

class _EmailVerificationPendingScreenState
    extends State<EmailVerificationPendingScreen> {
  bool _isSending = false;
  bool _emailSent = false;
  String? _error;
  Timer? _checkTimer;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  final TextEditingController _otpController = TextEditingController();
  bool _isVerifyingOtp = false;

  @override
  void initState() {
    super.initState();
    if (_resolvedEmail.isNotEmpty) {
      _emailSent = true;
    }
    AppLogger.debug('Email verification check started');
    _checkVerificationStatus();
    _startVerificationCheck();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _cooldownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startVerificationCheck() {
    // Check every 5 seconds if email has been verified
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _checkVerificationStatus();
    });
  }

  Future<void> _checkVerificationStatus() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = supabase.Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      try {
        await supabase.Supabase.instance.client.auth.refreshSession();
      } catch (_) {
        // Still waiting for verification.
      }
      final refreshedUser = supabase.Supabase.instance.client.auth.currentUser;
      if (refreshedUser?.emailConfirmedAt == null) {
        return;
      }
    } else if (currentUser.emailConfirmedAt == null) {
      return;
    }

    await authProvider.refreshUser();
    if (!mounted) return;

    final appUser = authProvider.appUser;
    if (appUser?.emailVerified == true) {
      _checkTimer?.cancel();
      final route = await _resolvePostVerificationRoute(
        appUser!.currentWorkspaceId,
      );
      if (!mounted) return;
      context.go(route);
    }
  }

  Future<String> _resolvePostVerificationRoute(String workspaceId) async {
    final redirectPath = _safeRedirectPath(widget.redirectTo);
    if (redirectPath != null) {
      return redirectPath;
    }

    if (workspaceId.isEmpty) {
      return '/';
    }

    final workspaceData =
        await ServiceLocator.workspaceService.getWorkspace(workspaceId).first;
    final onboardingCompleted = workspaceData?['onboardingCompleted'] == true;
    return onboardingCompleted ? '/' : '/onboarding';
  }

  String? _safeRedirectPath(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (!trimmed.startsWith('/')) {
      return null;
    }
    if (trimmed.startsWith('//')) {
      return null;
    }
    return trimmed;
  }

  Future<void> _verifyOtpCode() async {
    if (_isVerifyingOtp) return;

    final email = _resolvedEmail;
    final code = _otpController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = 'Missing email address for verification.';
      });
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = 'Enter the 6-digit verification code from your email.';
      });
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _error = null;
    });

    try {
      await supabase.Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: code,
        type: supabase.OtpType.signup,
      );

      await ServiceLocator.authService.ensureCurrentUserBootstrap();

      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      for (int i = 0; i < 5; i++) {
        await authProvider.refreshUser();
        if (!mounted) return;
        final appUser = authProvider.appUser;
        if (appUser?.emailVerified == true) {
          _checkTimer?.cancel();
          final route = await _resolvePostVerificationRoute(
            appUser!.currentWorkspaceId,
          );
          if (!mounted) return;
          context.go(route);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      await _checkVerificationStatus();
    } on supabase.AuthException catch (e) {
      final message = e.message.toLowerCase();
      setState(() {
        if (message.contains('expired') || message.contains('invalid')) {
          _error =
              'This code is expired or invalid. If you resent the verification email, use the code from the most recent email.';
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to verify code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
        });
      }
    }
  }

  Future<void> _sendVerificationEmail() async {
    if (_isSending || _resendCooldown > 0) return;

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final email = _resolvedEmail;
      if (email.isEmpty) {
        throw Exception('No email available for verification resend');
      }

      await ServiceLocator.authService.resendVerificationEmail(email: email);
      if (!mounted) return;
      setState(() {
        _emailSent = true;
        _resendCooldown = 30;
      });
      _startCooldownTimer();
      return;

      AppLogger.debug('Sending verification email via HTTP');

      // Use direct HTTP call to avoid dart2js Int64 issues with Firebase callable
      final user = (ServiceLocator.authService as dynamic).currentUser;
      if (user == null) {
        throw Exception('No authenticated user');
      }

      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse(
          'https://us-central1-your-firebase-project-id.cloudfunctions.net/sendVerificationEmailHttp',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'data': {}}),
      );

      AppLogger.debug(
        'Verification email response',
        metadata: {'statusCode': response.statusCode},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'] ?? data;

        if (result['success'] == true) {
          if (!mounted) return;
          setState(() {
            _emailSent = true;
            _resendCooldown = 30;
          });
          _startCooldownTimer();
        } else {
          if (!mounted) return;
          setState(() {
            _error = result['message'] ?? 'Failed to send verification email';
          });
        }
      } else {
        AppLogger.warning(
          'Verification email HTTP error',
          metadata: {'statusCode': response.statusCode},
        );
        final error = jsonDecode(response.body);
        final errorMessage =
            error['error']?['message'] ?? 'Failed to send verification email';

        if (errorMessage.contains('resource-exhausted') ||
            errorMessage.contains('Too many')) {
          if (!mounted) return;
          setState(() {
            _error =
                'Too many emails sent. Please wait an hour before trying again.';
          });
        } else {
          if (!mounted) return;
          setState(() {
            _error = errorMessage;
          });
        }
      }
    } catch (e) {
      AppLogger.error('Failed to send verification email', error: e);
      if (!mounted) return;
      setState(() {
        _error = 'Failed to send verification email. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() {
          _resendCooldown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  String get _resolvedEmail {
    final initial = widget.initialEmail?.trim();
    if (initial != null && initial.isNotEmpty) {
      return initial;
    }

    final appUserEmail = context.read<AuthProvider>().appUser?.email.trim();
    if (appUserEmail != null && appUserEmail.isNotEmpty) {
      return appUserEmail;
    }

    final supabaseEmail =
        supabase.Supabase.instance.client.auth.currentUser?.email?.trim();
    return supabaseEmail ?? '';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();
    final email = _resolvedEmail;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0a1628), Color(0xFF0d4f8b), Color(0xFF1565a8)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _GridPainter())),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.r16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Email icon
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0d4f8b,
                              ).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.mark_email_unread_outlined,
                              size: 40,
                              color: Color(0xFF0d4f8b),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Title
                          Text(
                            'Check your email',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),

                          // Subtitle
                          Text(
                            'We sent a 6-digit verification code to',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // Status indicator
                          if (_emailSent && _error == null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.base,
                                vertical: AppSpacing.md,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: AppColors.success),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    color: AppColors.successDark,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Verification email sent! Check your inbox.',
                                      style: TextStyle(
                                        color: AppColors.successDark,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Error message
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.base,
                                vertical: AppSpacing.md,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.errorLight,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: AppColors.error),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: AppColors.errorDark,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: AppColors.errorDark,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Instructions
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.base),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Next steps:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildStep('1', 'Open your email inbox'),
                                _buildStep(
                                  '2',
                                  'Find the email from FieldFleet',
                                ),
                                _buildStep(
                                  '3',
                                  'Copy the 6-digit code and paste it below',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          ...[
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.base),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Enter 6-digit verification code',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _otpController,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(6),
                                    ],
                                    decoration: const InputDecoration(
                                      hintText: '000000',
                                      border: OutlineInputBorder(),
                                    ),
                                    onSubmitted: (_) => _verifyOtpCode(),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _isVerifyingOtp
                                          ? null
                                          : _verifyOtpCode,
                                      child: _isVerifyingOtp
                                          ? const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Verify code'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Resend button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _isSending || _resendCooldown > 0
                                  ? null
                                  : _sendVerificationEmail,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: _isSending
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _resendCooldown > 0
                                          ? 'Resend in ${_resendCooldown}s'
                                          : 'Resend verification email',
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Sign out button
                          TextButton(
                            onPressed: () async {
                              await context.read<AuthProvider>().signOut();
                              if (!context.mounted) return;
                              context.go('/login');
                            },
                            child: Text(
                              'Sign out and use different email',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),

                          // Checking status indicator
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Waiting for verification...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF0d4f8b).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0d4f8b),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    const spacing = 50.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
