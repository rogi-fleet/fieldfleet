import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/chrome_provider.dart';
import '../../../theme/theme.dart';

/// Profile card for visual preferences. Currently just dark/light mode.
class ProfileAppearanceCard extends StatelessWidget {
  const ProfileAppearanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final chromeProvider = context.watch<ChromeProvider>();

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Appearance',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Switch between dark and light mode for the interface.',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode),
                  ),
                ],
                selected: {chromeProvider.isDarkChrome},
                onSelectionChanged: (values) {
                  chromeProvider.setDarkChrome(values.first);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
