import 'package:flutter/material.dart';
import '../../models/opportunity.dart';
import '../../theme/theme.dart';

class OpportunityCard extends StatelessWidget {
  final Opportunity opp;
  final VoidCallback onTap;
  const OpportunityCard({super.key, required this.opp, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final closeStr = opp.expectedCloseDate == null
        ? null
        : '${opp.expectedCloseDate!.year}-${opp.expectedCloseDate!.month.toString().padLeft(2, '0')}-${opp.expectedCloseDate!.day.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: AppColors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(opp.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.attach_money,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 2),
                  Text(_money(opp.estimatedValue),
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(width: 10),
                  Icon(Icons.percent,
                      size: 14, color: AppColors.textSecondary),
                  Text('${opp.probability}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
              if (closeStr != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.event,
                        size: 13, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(closeStr,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ],
              if (opp.nextAction != null && opp.nextAction!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Next: ${opp.nextAction}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _money(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(1)}k';
    return '\$${v.toStringAsFixed(0)}';
  }
}
