import 'package:flutter/material.dart';
import '../models/price_type.dart';
import '../theme/theme.dart';

class PriceTypeBadge extends StatelessWidget {
  final PriceType priceType;
  final bool showLabel;
  final bool compact;

  const PriceTypeBadge({
    super.key,
    required this.priceType,
    this.showLabel = true,
    this.compact = false,
  });

  Color _getColor() {
    switch (priceType) {
      case PriceType.fixedPrice:
        return AppColors.info;
      case PriceType.timeAndMaterial:
        return AppColors.success;
      case PriceType.costPlus:
        return AppColors.messageAccent;
      case PriceType.unitPrice:
        return AppColors.warning;
    }
  }

  IconData _getIcon() {
    switch (priceType) {
      case PriceType.fixedPrice:
        return Icons.lock;
      case PriceType.timeAndMaterial:
        return Icons.schedule;
      case PriceType.costPlus:
        return Icons.add_circle_outline;
      case PriceType.unitPrice:
        return Icons.grid_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final color = _getColor();
    final borderAlpha = chrome.isDark ? 0.6 : 0.3;

    if (!showLabel) {
      return Tooltip(
        message: priceType.displayName,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: chrome.isDark ? null : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: chrome.isDark ? Border.all(color: color.withValues(alpha: borderAlpha)) : null,
          ),
          child: Icon(_getIcon(), size: 16, color: color),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: chrome.isDark ? null : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(compact ? AppRadius.xs : 12),
        border: Border.all(color: color.withValues(alpha: borderAlpha)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getIcon(), size: compact ? 14 : 16, color: color),
          SizedBox(width: compact ? 5 : 6),
          Text(
            priceType.displayName,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
