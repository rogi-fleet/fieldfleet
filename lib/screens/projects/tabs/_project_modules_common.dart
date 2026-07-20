import 'package:flutter/material.dart';
import '../../../theme/theme.dart';

class PmEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const PmEmptyState({
    super.key, required this.icon, required this.title,
    this.subtitle, this.actionLabel, this.onAction,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onAction,
            icon: const Icon(Icons.add), label: Text(actionLabel!)),
        ],
      ]),
    ),
  );
}

class PmStatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const PmStatusChip({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

Color pmStatusColor(String? status) {
  switch (status) {
    case 'active': case 'approved': case 'completed': case 'verified':
    case 'passed': case 'closed': case 'resolved':
      return AppColors.success;
    case 'open': case 'scheduled': case 'draft':
      return AppColors.info;
    case 'in_progress': case 'submitted': case 'investigating':
    case 'ready_review': case 'expiring_soon':
      return AppColors.warning;
    case 'failed': case 'expired': case 'cancelled': case 'denied':
    case 'wont_fix': case 'void': case 'requires_followup': case 'claimed':
      return AppColors.error;
    default:
      return AppColors.secondary;
  }
}

Color pmPriorityColor(String? p) {
  switch (p) {
    case 'critical': return AppColors.error;
    case 'high':     return AppColors.warning;
    case 'medium':   return AppColors.info;
    case 'low':      return AppColors.success;
    default:         return AppColors.secondary;
  }
}

Future<DateTime?> pickPmDate(BuildContext context, {DateTime? initial}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 20),
  );
}

String fmtPmDate(DateTime? d) {
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
}

String fmtPmDateTime(DateTime? d) {
  if (d == null) return '—';
  final t = '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  return '${fmtPmDate(d)} $t';
}

String labelize(String s) {
  if (s.isEmpty) return s;
  return s.split('_').map((w) =>
    w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}
