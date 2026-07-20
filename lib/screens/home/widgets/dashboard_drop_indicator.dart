import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// A colored line indicator shown at drop positions during drag.
class DashboardDropIndicator extends StatelessWidget {
  const DashboardDropIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        height: 2,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
