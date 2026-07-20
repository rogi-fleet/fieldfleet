import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../theme/theme.dart';
import '../animated_empty_state_cta.dart';

class EntityEmptyState extends StatelessWidget {
  final bool hasFilters;
  final Animation<double> animation;
  final IconData filteredIcon;
  final IconData defaultIcon;
  final String filteredTitle;
  final String defaultTitle;
  final String filteredSubtitle;
  final String defaultSubtitle;
  final VoidCallback onClearFilters;
  final String createLabel;
  final VoidCallback onCreate;
  /// Optional path to a Lottie JSON asset shown in the default (non-filtered) state.
  final String? lottieAsset;

  const EntityEmptyState({
    super.key,
    required this.hasFilters,
    required this.animation,
    required this.filteredIcon,
    required this.defaultIcon,
    required this.filteredTitle,
    required this.defaultTitle,
    required this.filteredSubtitle,
    required this.defaultSubtitle,
    required this.onClearFilters,
    required this.createLabel,
    required this.onCreate,
    this.lottieAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!hasFilters && lottieAsset != null)
            Lottie.asset(lottieAsset!, width: 120, height: 120, repeat: true)
          else
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Transform.scale(
                  scale: hasFilters ? 1.0 : animation.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: hasFilters
                          ? null
                          : LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: hasFilters ? AppColors.surfaceAlt : null,
                      shape: BoxShape.circle,
                      boxShadow: hasFilters
                          ? null
                          : [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                    ),
                    child: Icon(
                      hasFilters ? filteredIcon : defaultIcon,
                      size: 40,
                      // This widget always renders on the light surfaceAlt
                      // background of the customer/vendor list screens, so use
                      // fixed light-surface tokens rather than the chrome-aware
                      // scaffold colors (which turn white in dark-chrome mode
                      // and become invisible here).
                      color: hasFilters
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          Text(
            hasFilters ? filteredTitle : defaultTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasFilters ? filteredSubtitle : defaultSubtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          if (hasFilters) ...[
            TextButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
            ),
          ] else ...[
            AnimatedEmptyStateCta(
              animation: animation,
              label: createLabel,
              onTap: onCreate,
            ),
            const SizedBox(height: 10),
            Text(
              kIsWeb
                  ? 'Click "$createLabel" to begin'
                  : 'Tap "$createLabel" to begin',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
