import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Shell for card-layout list items (budget item cards, purchase order
/// cards): rounded card with hairline border and tap ripple, 12px inner
/// padding, and the standard 12/10 outer margin with optional hierarchy
/// indent. Extracted so every Financials card reads the same.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.indent = 0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;

  /// Extra left margin for nested rows (e.g. budget hierarchy depth).
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + indent, 0, 12, 10),
      child: Card(
        elevation: 0,
        color: color,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: AppColors.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
        ),
      ),
    );
  }
}
