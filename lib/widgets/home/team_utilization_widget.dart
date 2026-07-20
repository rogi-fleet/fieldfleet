import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/capacity_planning.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

enum _UtilizationPeriod { lastWeek, thisWeek, nextWeek }

/// Shows team utilization at a glance — each member's hours vs. capacity
/// with color-coded status bars, sorted by utilization descending.
class TeamUtilizationWidget extends StatefulWidget {
  final String workspaceId;

  const TeamUtilizationWidget({super.key, required this.workspaceId});

  @override
  State<TeamUtilizationWidget> createState() => _TeamUtilizationWidgetState();
}

class _TeamUtilizationWidgetState extends State<TeamUtilizationWidget> {
  late Future<CapacitySnapshot> _snapshotFuture;
  _UtilizationPeriod _period = _UtilizationPeriod.thisWeek;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  @override
  void didUpdateWidget(covariant TeamUtilizationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _snapshotFuture = _loadSnapshot();
    }
  }

  Future<CapacitySnapshot> _loadSnapshot() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon
    final thisWeekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: weekday - 1));
    final weekOffset = switch (_period) {
      _UtilizationPeriod.lastWeek => -7,
      _UtilizationPeriod.thisWeek => 0,
      _UtilizationPeriod.nextWeek => 7,
    };
    final weekStart = thisWeekStart.add(Duration(days: weekOffset));
    final weekEnd = weekStart.add(const Duration(days: 6));

    return ServiceLocator.capacityPlanningService.getCapacitySnapshot(
      workspaceId: widget.workspaceId,
      start: weekStart,
      end: weekEnd,
    );
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = _loadSnapshot();
    });
  }

  void _onPeriodChanged(_UtilizationPeriod period) {
    setState(() {
      _period = period;
      _snapshotFuture = _loadSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.base),
            FutureBuilder<CapacitySnapshot>(
              future: _snapshotFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }
                if (snapshot.hasError) {
                  return _buildErrorState();
                }

                final members = snapshot.data?.members ?? [];

                if (members.isEmpty) return _buildEmptyState();

                return _buildContent(members);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<CapacityMemberRow> members) {
    // Summary stats
    final totalCapacity = members.fold<double>(
      0,
      (sum, m) => sum + m.totalCapacityHours,
    );
    final totalCommitted = members.fold<double>(
      0,
      (sum, m) => sum + m.totalCommittedHours,
    );
    final avgUtilization =
        totalCapacity > 0 ? (totalCommitted / totalCapacity * 100) : 0.0;

    final overloaded = members.where((m) => m.utilizationPct > 100).length;
    final underutilized = members.where((m) => m.utilizationPct < 50).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 300;
        final maxVisible = isCompact ? 5 : 8;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary row — wrap on compact layout
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _SummaryChip(
                  label: 'Team Avg',
                  value: '${avgUtilization.round()}%',
                  color: _colorForUtilization(avgUtilization),
                  compact: isCompact,
                ),
                if (overloaded > 0)
                  _SummaryChip(
                    label: 'Overloaded',
                    value: '$overloaded',
                    color: AppColors.error,
                    compact: isCompact,
                  ),
                if (underutilized > 0)
                  _SummaryChip(
                    label: 'Available',
                    value: '$underutilized',
                    color: AppColors.info,
                    compact: isCompact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.iconGap),

            // Member rows
            ...members.take(maxVisible).map(
              (member) => _MemberUtilizationRow(
                member: member,
                compact: isCompact,
              ),
            ),

            if (members.length > maxVisible)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '+${members.length - maxVisible} more team members',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.groups,
            color: Color(0xFF7C3AED),
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Text(
          'Team Utilization',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        DropdownButton<_UtilizationPeriod>(
          value: _period,
          borderRadius: AppRadius.cardRadius,
          isDense: true,
          style: TextStyle(fontSize: 12, color: chrome.scaffoldTextSecondary),
          dropdownColor: chrome.surface,
          iconEnabledColor: chrome.scaffoldTextSecondary,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(
              value: _UtilizationPeriod.lastWeek,
              child: Text('Last week'),
            ),
            DropdownMenuItem(
              value: _UtilizationPeriod.thisWeek,
              child: Text('This week'),
            ),
            DropdownMenuItem(
              value: _UtilizationPeriod.nextWeek,
              child: Text('Next week'),
            ),
          ],
          onChanged: (v) {
            if (v != null) _onPeriodChanged(v);
          },
        ),
        const Spacer(),
        IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: 'Refresh',
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(AppSpacing.sm),
            minimumSize: const Size(32, 32),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/team?tab=capacity'),
          child: const Text('Planner'),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildErrorState() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.base),
      child: Text(
        'Unable to load team data',
        style: TextStyle(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.group_off, size: 48, color: AppColors.cardBorder),
            const SizedBox(height: AppSpacing.iconGap),
            const Text(
              'No team members found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Invite team members to see utilization',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

Color _colorForUtilization(double pct) {
  if (pct > 100) return AppColors.error;
  if (pct >= 90) return AppColors.warningDark; // amber
  if (pct >= 50) return AppColors.success; // green
  return AppColors.info; // blue (underutilized)
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool compact;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // Horizontal chip for narrow layouts
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberUtilizationRow extends StatelessWidget {
  final CapacityMemberRow member;
  final bool compact;

  const _MemberUtilizationRow({
    required this.member,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final pct = member.utilizationPct;
    final color = _colorForUtilization(pct);
    final barPct = (pct / 100).clamp(0.0, 1.5);
    final initials = _getInitials(member.displayName);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: () => context.go('/team?tab=capacity'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Name + optional progress bar
              Expanded(
                child: compact
                    ? Text(
                        member.displayName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 6,
                              child: LinearProgressIndicator(
                                value: barPct.clamp(0.0, 1.0),
                                backgroundColor: AppColors.surfaceAlt,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Percentage + optional hours detail
              compact
                  ? Text(
                      '${pct.round()}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    )
                  : SizedBox(
                      width: 64,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${pct.round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                          Text(
                            '${member.totalCommittedHours.toStringAsFixed(1)}/${member.totalCapacityHours.toStringAsFixed(0)}h',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
