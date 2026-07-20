import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../models/time_entry.dart';
import '../../../models/user.dart';
import '../../../models/project.dart';
import '../../../theme/theme.dart';

/// Compact approve/reject row used in the admin dashboard.
///
/// Shows worker avatar, name, date+job, hours, and approve/reject buttons.
/// The full approval screen remains available via [viewAllCount] link.
class InlineApprovalPanel extends StatelessWidget {
  final List<TimeEntry> pendingEntries;
  final Map<String, AppUser> usersMap;
  final Map<String, Project> projectsMap;
  final Future<void> Function(TimeEntry entry) onApprove;
  final Future<void> Function(TimeEntry entry) onReject;
  final Future<void> Function(List<TimeEntry> entries)? onApproveAll;
  final bool isProcessing;

  const InlineApprovalPanel({
    super.key,
    required this.pendingEntries,
    required this.usersMap,
    required this.projectsMap,
    required this.onApprove,
    required this.onReject,
    this.onApproveAll,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = pendingEntries.take(5).toList();
    final remaining = pendingEntries.length - shown.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Text(
                  'Pending Approvals',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                if (pendingEntries.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Text(
                      '${pendingEntries.length} entries',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'All caught up!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shown.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
              itemBuilder: (_, index) => _ApprovalRow(
                entry: shown[index],
                user: usersMap[shown[index].workerId],
                project: projectsMap[shown[index].projectId],
                onApprove: () => onApprove(shown[index]),
                onReject: () => onReject(shown[index]),
                isProcessing: isProcessing,
              ),
            ),
            // Footer: view all link
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextButton(
                onPressed: () => context.go('/time-tracking/approvals'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  remaining > 0
                      ? 'View all (+$remaining more) →'
                      : 'View approval screen →',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            // Approve All button
            if (onApproveAll != null && pendingEntries.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: isProcessing
                        ? null
                        : () => onApproveAll!(pendingEntries),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    child: Text(
                      '✓  Approve All ${pendingEntries.length} Entries',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  final TimeEntry entry;
  final AppUser? user;
  final Project? project;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool isProcessing;

  const _ApprovalRow({
    required this.entry,
    required this.user,
    required this.project,
    required this.onApprove,
    required this.onReject,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = user?.displayName ?? user?.email ?? 'Unknown';
    final initials = _initials(displayName);
    final projectName = project?.name ?? 'Unknown project';
    final dateStr = DateFormat('MMM d').format(entry.date);
    final clockIn = DateFormat('h:mm a').format(entry.clockIn);
    final clockOut = entry.clockOut != null
        ? DateFormat('h:mm a').format(entry.clockOut!)
        : 'N/A';
    final hours = (entry.totalDuration / 60.0).toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          // Avatar
          _Avatar(initials: initials, userId: entry.workerId),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$dateStr · $projectName · $clockIn – $clockOut',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Hours
          Text(
            '${hours}h',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          // Buttons
          _ActionButton(
            label: '✓',
            color: AppColors.success,
            bg: AppColors.successLight,
            onTap: isProcessing ? null : onApprove,
          ),
          const SizedBox(width: 4),
          _ActionButton(
            label: '✕',
            color: theme.colorScheme.onSurfaceVariant,
            bg: theme.colorScheme.surfaceContainerHighest,
            onTap: isProcessing ? null : onReject,
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final String userId;

  const _Avatar({required this.initials, required this.userId});

  @override
  Widget build(BuildContext context) {
    // Stable color based on userId hash
    final colors = [
      [const Color(0xFF2563EB), const Color(0xFF7C3AED)],
      [const Color(0xFF16A34A), const Color(0xFF0891B2)],
      [AppColors.error, const Color(0xFFF97316)],
      [const Color(0xFF7C3AED), const Color(0xFFDB2777)],
      [const Color(0xFF0891B2), const Color(0xFF2563EB)],
    ];
    final pair = colors[userId.hashCode.abs() % colors.length];

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pair,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
