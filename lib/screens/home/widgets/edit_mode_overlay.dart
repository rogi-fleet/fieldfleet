import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// Overlay shown on each widget card during edit mode.
///
/// Provides remove (X) button, resize chip, and directional arrows.
class EditModeOverlay extends StatelessWidget {
  final String widgetId;
  final String currentSize; // "half" | "full"
  final VoidCallback onRemove;
  final VoidCallback onToggleSize;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const EditModeOverlay({
    super.key,
    required this.widgetId,
    required this.currentSize,
    required this.onRemove,
    required this.onToggleSize,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Semi-transparent scrim
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        // Remove button (top-left)
        Positioned(
          top: 4,
          left: 4,
          child: _RemoveButton(onTap: onRemove),
        ),
        // Resize chip (top-right)
        Positioned(
          top: 4,
          right: 4,
          child: _ResizeChip(
            currentSize: currentSize,
            onTap: onToggleSize,
          ),
        ),
        // Directional arrows (bottom-center)
        Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onMoveLeft != null)
                _ArrowButton(
                  icon: Icons.arrow_back,
                  onTap: onMoveLeft!,
                ),
              if (onMoveUp != null)
                _ArrowButton(
                  icon: Icons.arrow_upward,
                  onTap: onMoveUp!,
                ),
              if (onMoveDown != null)
                _ArrowButton(
                  icon: Icons.arrow_downward,
                  onTap: onMoveDown!,
                ),
              if (onMoveRight != null)
                _ArrowButton(
                  icon: Icons.arrow_forward,
                  onTap: onMoveRight!,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(
          icon,
          size: 20,
          color: AppColors.textSecondary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RemoveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 14, color: Colors.white),
      ),
    );
  }
}

class _ResizeChip extends StatelessWidget {
  final String currentSize;
  final VoidCallback onTap;

  const _ResizeChip({required this.currentSize, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isHalf = currentSize == 'half';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHalf ? Icons.width_full : Icons.width_normal,
              size: 14,
              color: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              isHalf ? 'Half' : 'Full',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
