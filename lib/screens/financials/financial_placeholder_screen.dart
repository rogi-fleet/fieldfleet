import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class FinancialPlaceholderScreen extends StatelessWidget {
  final String title;
  final String iconName;
  final IconData iconData;
  final String description;

  const FinancialPlaceholderScreen({
    super.key,
    required this.title,
    required this.iconName,
    required this.iconData,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            iconData,
            size: 64,
            color: AppColors.cardBorder,
          ),
          const SizedBox(height: 24),
          Text(
            'No $title yet',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Create $title feature coming soon!')),
              );
            },
            icon: const Icon(Icons.add),
            label: Text('Create $iconName'),
          ),
        ],
      ),
    );
  }
}
