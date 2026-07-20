import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Compact strength meter for new-password fields. Renders nothing for
/// empty input. Shared by signup and the profile change-password dialog.
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  static double scoreOf(String password) {
    double strength = 0;
    if (password.length >= 6) strength += 0.2;
    if (password.length >= 8) strength += 0.2;
    if (password.contains(RegExp(r'[A-Z]'))) strength += 0.2;
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.2;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.2;
    return strength;
  }

  static Color colorFor(double score) {
    if (score <= 0.2) return AppColors.error;
    if (score <= 0.4) return AppColors.warning;
    if (score <= 0.6) return Colors.yellow.shade700;
    if (score <= 0.8) return Colors.lightGreen;
    return AppColors.success;
  }

  static String labelFor(double score) {
    if (score <= 0.2) return 'Weak';
    if (score <= 0.4) return 'Fair';
    if (score <= 0.6) return 'Good';
    if (score <= 0.8) return 'Strong';
    return 'Very Strong';
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final score = scoreOf(password);
    final color = colorFor(score);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: score,
              backgroundColor: AppColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          labelFor(score),
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
