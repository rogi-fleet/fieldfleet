import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../models/time_entry.dart';
import '../../../models/time_entry_status.dart';
import '../../../theme/theme.dart';

/// Shows the last few time entries with status badges below the clock widget.
///
/// Tapping "View full log" navigates to the daily timesheet.
class RecentEntriesStrip extends StatefulWidget {
  final List<TimeEntry> entries;
  final bool isLoading;
  final Map<String, String> projectNames;

  const RecentEntriesStrip({
    super.key,
    required this.entries,
    this.isLoading = false,
    this.projectNames = const {},
  });

  @override
  State<RecentEntriesStrip> createState() => _RecentEntriesStripState();
}

class _RecentEntriesStripState extends State<RecentEntriesStrip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Tick every minute so any active (ongoing) entry stays current.
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = widget.entries.take(5).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  'Recent Time Entries',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/time-tracking/timesheet'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'View full log',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (widget.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.base),
              child: Center(
                child: Text(
                  'No entries in the last 7 days',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
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
              itemBuilder: (context, index) =>
                  _EntryRow(entry: shown[index], projectNames: widget.projectNames),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final TimeEntry entry;
  final Map<String, String> projectNames;

  const _EntryRow({required this.entry, required this.projectNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayFmt = DateFormat('E').format(entry.date).toUpperCase();
    final projectName = projectNames[entry.projectId] ?? 'Project';
    final clockInFmt = DateFormat('h:mm a').format(entry.clockIn);
    final clockOutFmt = entry.clockOut != null
        ? DateFormat('h:mm a').format(entry.clockOut!)
        : 'ongoing';
    final timeRange = '$clockInFmt – $clockOutFmt';
    final duration = entry.clockOut == null
        ? _liveElapsed(entry.clockIn)
        : _fmtMinutes(
            (entry.clockOut!.difference(entry.clockIn).inMinutes -
                    entry.breakDuration)
                .clamp(0, 999999),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
      child: Row(
        children: [
          // Day label
          SizedBox(
            width: 34,
            child: Text(
              dayFmt,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: entry.clockOut == null
                    ? const Color(0xFFF97316)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Project + optional notes + time range
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  projectName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.notes != null && entry.notes!.isNotEmpty)
                  Text(
                    entry.notes!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  timeRange,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: entry.notes != null && entry.notes!.isNotEmpty
                        ? 10
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Duration
          Text(
            duration,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: entry.clockOut == null
                  ? const Color(0xFFF97316)
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          // Status badge
          _StatusBadge(status: entry.status, isActive: entry.clockOut == null),
        ],
      ),
    );
  }

  String _fmtMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0 && m == 0) return '—';
    if (m == 0) return '${h}:00';
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  String _liveElapsed(DateTime start) {
    final elapsed = DateTime.now().difference(start);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }
}

class _StatusBadge extends StatelessWidget {
  final TimeEntryStatus status;
  final bool isActive;

  const _StatusBadge({required this.status, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    // Draft + no clockOut = currently running session → "Active" in orange.
    // Draft + clockOut = logged but not submitted → "Draft" in grey.
    final (label, bg, fg) = switch (status) {
      TimeEntryStatus.draft when isActive =>
        ('Active', const Color(0xFFFFF3E0), const Color(0xFFF97316)),
      TimeEntryStatus.draft =>
        ('Draft', const Color(0xFFF3F4F6), AppColors.textSecondary),
      TimeEntryStatus.submitted =>
        ('Pending', AppColors.warningLight, AppColors.warningDark),
      TimeEntryStatus.approved =>
        ('Approved', AppColors.successLight, AppColors.success),
      TimeEntryStatus.rejected =>
        ('Rejected', AppColors.errorLight, AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
