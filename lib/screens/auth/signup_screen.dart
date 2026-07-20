import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taskfleet_ops/config/beta_signup_config.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/logo_widget.dart';

import 'package:taskfleet_ops/widgets/auth/password_strength_indicator.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class SignupScreen extends StatefulWidget {
  final String? initialEmail;
  final String? redirectTo;
  final bool allowSignup;

  const SignupScreen({
    super.key,
    this.initialEmail,
    this.redirectTo,
    required this.allowSignup,
  });

  bool get isInvitation =>
      redirectTo != null && redirectTo!.startsWith('/invite/');

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
    }
    _passwordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.removeListener(_onPasswordChanged);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onPasswordChanged() => setState(() {});

  String get _signupTitle {
    if (widget.isInvitation) {
      return 'Join Your Workspace';
    }
    if (widget.allowSignup) {
      return 'Creator Access';
    }
    return 'Private Beta';
  }

  String get _signupSubtitle {
    if (widget.isInvitation) {
      return 'Create your account to accept this workspace invitation.';
    }
    if (widget.allowSignup) {
      return 'This signup link is reserved for approved creator accounts.';
    }
    return 'FieldFleet signups are currently closed while the product remains in beta.';
  }

  void _showSignupClosedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'FieldFleet is in private beta. New accounts require an invitation or a private creator link.',
        ),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Future<void> _handleSignup() async {
    if (!widget.allowSignup) {
      _showSignupClosedMessage();
      return;
    }

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please agree to the Terms of Service and Privacy Policy',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      try {
        final redirectTo = widget.redirectTo?.trim();
        final hasSafeRedirect = redirectTo != null &&
            redirectTo.isNotEmpty &&
            redirectTo.startsWith('/') &&
            !redirectTo.startsWith('//');
        await authProvider.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
          redirectTo: hasSafeRedirect ? redirectTo : null,
        );

        if (mounted) {
          final email = Uri.encodeComponent(_emailController.text.trim());
          if (hasSafeRedirect) {
            final encodedRedirect = Uri.encodeComponent(redirectTo);
            context.go(
              '/verify-email-pending?email=$email&from=$encodedRedirect',
            );
          } else {
            context.go('/verify-email-pending?email=$email');
          }
        }
      } catch (e) {
        if (mounted) {
          final errorMsg = e.toString().toLowerCase();
          final isAlreadyRegistered = errorMsg.contains('already exists') ||
              errorMsg.contains('already registered') ||
              errorMsg.contains('already been registered');

          if (isAlreadyRegistered) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'An account with this email already exists. Please log in instead.',
                ),
              ),
            );
            if (mounted) {
              final redirectTo = widget.redirectTo?.trim();
              final hasSafeRedirect = redirectTo != null &&
                  redirectTo.isNotEmpty &&
                  redirectTo.startsWith('/') &&
                  !redirectTo.startsWith('//');
              if (hasSafeRedirect) {
                context.go('/login?from=$redirectTo');
              } else {
                context.go('/login');
              }
            }
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(authProvider.errorMessage ?? 'Signup failed'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!widget.allowSignup) {
      _showSignupClosedMessage();
      return;
    }

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please agree to the Terms of Service and Privacy Policy',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    try {
      await authProvider.signInWithGoogle();

      if (authProvider.errorMessage == 'Google sign-in was cancelled') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign-up cancelled'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else if (mounted) {
        final redirectTo = widget.redirectTo?.trim();
        final hasSafeRedirect = redirectTo != null &&
            redirectTo.isNotEmpty &&
            redirectTo.startsWith('/') &&
            !redirectTo.startsWith('//');
        if (hasSafeRedirect) {
          context.go(redirectTo);
        } else {
          // Google accounts are pre-verified, go to onboarding
          context.go('/onboarding');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Google sign-up failed'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _googleAuthIcon() {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0xFFDADCE0)),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Center(
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
                    child: widget.allowSignup
                        ? Form(
                            key: _formKey,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Logo
                                const Center(
                                  child: LogoWidget(
                                    height: 60,
                                    showTagline: false,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Title and subtitle
                                Text(
                                  _signupTitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _signupSubtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 32),

                                // Name field
                                StackedField(
                                  label: 'Full Name',
                                  child: TextFormField(
                                    controller: _nameController,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your name';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Email field
                                StackedField(
                                  label: 'Email',
                                  child: TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your email';
                                      }
                                      if (!value.contains('@')) {
                                        return 'Please enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Password field
                                StackedField(
                                  label: 'Password',
                                  child: TextFormField(
                                    // Stable key so the conditional
                                    // PasswordStrengthIndicator below doesn't
                                    // re-ID this field's Element on rebuild
                                    // and silently drop its FormField state.
                                    key: const ValueKey('signup_password'),
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter a password';
                                      }
                                      if (value.length < 6) {
                                        return 'Password must be at least 6 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                ),

                                // Password strength indicator
                                if (_passwordController.text.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  PasswordStrengthIndicator(
                                    password: _passwordController.text,
                                  ),
                                ],
                                const SizedBox(height: 16),

                                // Confirm password field
                                StackedField(
                                  label: 'Confirm Password',
                                  child: TextFormField(
                                    // Same reason as the password field above:
                                    // the conditional strength indicator was
                                    // shifting this field's index in the
                                    // Column, which discarded its Element +
                                    // FormField state and cleared the input
                                    // on the next rebuild (observed live as
                                    // the confirm pw clearing between Create
                                    // Account submits).
                                    key: const ValueKey(
                                        'signup_confirm_password'),
                                    controller: _confirmPasswordController,
                                    obscureText: _obscureConfirmPassword,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureConfirmPassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureConfirmPassword =
                                                !_obscureConfirmPassword;
                                          });
                                        },
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please confirm your password';
                                      }
                                      if (value != _passwordController.text) {
                                        return 'Passwords do not match';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Terms checkbox
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: Checkbox(
                                        value: _agreedToTerms,
                                        onChanged: (value) {
                                          setState(() {
                                            _agreedToTerms = value ?? false;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                          children: [
                                            const TextSpan(
                                              text: 'I agree to the ',
                                            ),
                                            TextSpan(
                                              text: 'Terms of Service',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).primaryColor,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              recognizer: TapGestureRecognizer()
                                                ..onTap = () => launchUrl(
                                                      Uri.parse(
                                                        'https://example.com/terms/',
                                                      ),
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    ),
                                            ),
                                            const TextSpan(text: ' and '),
                                            TextSpan(
                                              text: 'Privacy Policy',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).primaryColor,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              recognizer: TapGestureRecognizer()
                                                ..onTap = () => launchUrl(
                                                      Uri.parse(
                                                        'https://example.com/privacy/',
                                                      ),
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Sign up button
                                Consumer<AuthProvider>(
                                  builder: (context, authProvider, child) {
                                    return ElevatedButton(
                                      onPressed: authProvider.isLoading
                                          ? null
                                          : _handleSignup,
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppSpacing.base,
                                        ),
                                        backgroundColor: const Color(
                                          0xFF0d4f8b,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: authProvider.isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              widget.isInvitation
                                                  ? 'Create Account'
                                                  : 'Create Creator Account',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Trust indicators
                                if (widget.isInvitation)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildTrustIndicator(
                                        Icons.check_circle_outline,
                                        'Workspace invitation',
                                      ),
                                      const SizedBox(width: 16),
                                      _buildTrustIndicator(
                                        Icons.mail_outline,
                                        'Email verification required',
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 24),

                                // Divider
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.base,
                                      ),
                                      child: Text(
                                        'OR',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColors.textTertiary,
                                            ),
                                      ),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Google sign up button
                                Consumer<AuthProvider>(
                                  builder: (context, authProvider, child) {
                                    return OutlinedButton.icon(
                                      onPressed: authProvider.isLoading
                                          ? null
                                          : _handleGoogleSignIn,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppSpacing.base,
                                        ),
                                      ),
                                      icon: authProvider.isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : _googleAuthIcon(),
                                      label: const Text('Sign up with Google'),
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Login link
                                TextButton(
                                  onPressed: () {
                                    context.go('/login');
                                  },
                                  child: const Text(
                                    'Already have an account? Login',
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _buildSignupClosedState(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustIndicator(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.success),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSignupClosedState(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: LogoWidget(height: 60, showTagline: false)),
        const SizedBox(height: 24),
        Text(
          _signupTitle,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _signupSubtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FB),
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Text(
            'If you already have an account, log in as usual. Team creators can still sign up using their private link with the `${BetaSignupConfig.creatorSignupQueryParam}` access code.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            context.go('/login');
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
            backgroundColor: const Color(0xFF0d4f8b),
            foregroundColor: Colors.white,
          ),
          child: const Text(
            'Back to Login',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
