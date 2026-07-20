import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme/theme.dart';

class WorkspaceStatsWidget extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final bool isLoading;

  const WorkspaceStatsWidget({
    super.key,
    this.stats,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (stats == null) {
      return const SizedBox.shrink();
    }

    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final cards = [
      _buildStatCard(
        context,
        'Total Projects',
        stats!['totalProjects'].toString(),
        Icons.folder,
        AppColors.info,
      ),
      _buildStatCard(
        context,
        'Active Projects',
        stats!['activeProjects'].toString(),
        Icons.folder_open,
        AppColors.success,
      ),
      _buildStatCard(
        context,
        'Monthly Revenue',
        currencyFormat.format(stats!['monthlyRevenue']),
        Icons.attach_money,
        AppColors.messageAccent,
      ),
      _buildStatCard(
        context,
        'Monthly Hours',
        '${stats!['monthlyLaborHours'].toStringAsFixed(1)} hrs',
        Icons.access_time,
        AppColors.warning,
      ),
    ];

    final chrome = ChromeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: chrome.scaffoldDivider,
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < AppBreakpoints.mobile) {
            // 2x2 grid on narrow screens
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: cards[2]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[3]),
                  ],
                ),
              ],
            );
          }
          // 4-across on wider screens
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
