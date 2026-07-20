import 'package:flutter/material.dart';
import '../../../models/user.dart';
import '../../../models/workspace_member.dart';
import '../../../models/time_entry.dart';
import '../../../models/time_entry_status.dart';
import '../../../theme/theme.dart';
import '../../../widgets/table/hover_action_row.dart';
import '../../../widgets/table/table_view_styles.dart';
import '../../../widgets/user_avatar.dart';

// Column widths
const double kEmployeeTimeColCheckbox = 36.0;
const double kEmployeeTimeColEmployee = 240;
const double kEmployeeTimeColRole = 140;
const double kEmployeeTimeColRate = 90;
const double kEmployeeTimeColTotalHours = 100;
const double kEmployeeTimeColRegularHours = 100;
const double kEmployeeTimeColOvertimeHours = 100;
const double kEmployeeTimeColTotalCost = 110;
const double kEmployeeTimeColPending = 80;
const double kEmployeeTimeColApproved = 80;
const double kEmployeeTimeColStatus = 100;
const double kEmployeeTimeColGap = 12;

/// Aggregated time data for a single employee.
class EmployeeTimeSummary {
  final String workerId;
  final double totalHours;
  final double regularHours;
  final double overtimeHours;
  final double doubleTimeHours;
  final double totalCost;
  final int totalEntries;
  final int pendingEntries;
  final int approvedEntries;
  final int rejectedEntries;
  final int draftEntries;
  final bool isClockedIn;

  const EmployeeTimeSummary({
    required this.workerId,
    this.totalHours = 0,
    this.regularHours = 0,
    this.overtimeHours = 0,
    this.doubleTimeHours = 0,
    this.totalCost = 0,
    this.totalEntries = 0,
    this.pendingEntries = 0,
    this.approvedEntries = 0,
    this.rejectedEntries = 0,
    this.draftEntries = 0,
    this.isClockedIn = false,
  });

  factory EmployeeTimeSummary.fromEntries(
    String workerId,
    List<TimeEntry> entries,
  ) {
    double totalHours = 0;
    double regularHours = 0;
    double overtimeHours = 0;
    double doubleTimeHours = 0;
    double totalCost = 0;
    int pendingEntries = 0;
    int approvedEntries = 0;
    int rejectedEntries = 0;
    int draftEntries = 0;
    bool isClockedIn = false;

    for (final entry in entries) {
      totalHours += entry.totalDuration / 60.0;
      regularHours += entry.regularHours;
      overtimeHours += entry.overtimeHours;
      doubleTimeHours += entry.doubleTimeHours;
      totalCost += entry.totalCost;

      switch (entry.status) {
        case TimeEntryStatus.submitted:
          pendingEntries++;
        case TimeEntryStatus.approved:
          approvedEntries++;
        case TimeEntryStatus.rejected:
          rejectedEntries++;
        case TimeEntryStatus.draft:
          draftEntries++;
      }

      if (entry.isActive) isClockedIn = true;
    }

    return EmployeeTimeSummary(
      workerId: workerId,
      totalHours: totalHours,
      regularHours: regularHours,
      overtimeHours: overtimeHours,
      doubleTimeHours: doubleTimeHours,
      totalCost: totalCost,
      totalEntries: entries.length,
      pendingEntries: pendingEntries,
      approvedEntries: approvedEntries,
      rejectedEntries: rejectedEntries,
      draftEntries: draftEntries,
      isClockedIn: isClockedIn,
    );
  }

  static const empty = EmployeeTimeSummary(workerId: '');
}

class EmployeeTimeTableRow extends StatelessWidget {
  final AppUser user;
  final WorkspaceMember member;
  final EmployeeTimeSummary summary;
  final Map<String, double> columnWidths;
  final VoidCallback? onTap;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onExport;
  final VoidCallback? onApprovePending;

  const EmployeeTimeTableRow({
    super.key,
    required this.user,
    required this.member,
    required this.summary,
    this.columnWidths = const {},
    this.onTap,
    this.isSelected = false,
    this.onToggleSelect,
    this.onExport,
    this.onApprovePending,
  });

  double _colW(String id, double defaultWidth) =>
      columnWidths[id] ?? defaultWidth;

  @override
  Widget build(BuildContext context) {
    return HoverActionRow(
      actionWidth: 40,
      actions: [_buildActionsMenu(context)],
      builder: (isHovered) => InkWell(
        onTap: onToggleSelect ?? onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.info.withValues(alpha: 0.08)
                : isHovered
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            border: Border(bottom: TableViewStyles.rowDivider(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: kEmployeeTimeColCheckbox,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelect?.call(),
                    activeColor: AppColors.info,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('employee', kEmployeeTimeColEmployee),
                  child: _buildEmployeeCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('role', kEmployeeTimeColRole),
                  child: _buildRoleCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('rate', kEmployeeTimeColRate),
                  child: _buildRateCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('total_hours', kEmployeeTimeColTotalHours),
                  child: _buildTotalHoursCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('regular_hours', kEmployeeTimeColRegularHours),
                  child: _buildRegularHoursCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('overtime_hours', kEmployeeTimeColOvertimeHours),
                  child: _buildOvertimeHoursCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('total_cost', kEmployeeTimeColTotalCost),
                  child: _buildTotalCostCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('pending', kEmployeeTimeColPending),
                  child: _buildPendingCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('approved', kEmployeeTimeColApproved),
                  child: _buildApprovedCell(context),
                ),
                const SizedBox(width: kEmployeeTimeColGap),
                SizedBox(
                  width: _colW('status', kEmployeeTimeColStatus),
                  child: _buildStatusCell(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      iconColor: AppColors.textSecondary,
      itemBuilder: (context) => [
        if (onApprovePending != null)
          PopupMenuItem(
            value: 'approve',
            child: Row(
              children: [
                const Icon(Icons.verified_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Approve ${summary.pendingEntries} pending',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        if (onApprovePending != null) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: const [
              Icon(Icons.file_upload_outlined, size: 18),
              SizedBox(width: 8),
              Text('Export', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'approve':
            onApprovePending?.call();
          case 'export':
            onExport?.call();
        }
      },
    );
  }

  Widget _buildEmployeeCell(BuildContext context) {
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : user.email;
    final subtitle = user.jobTitle?.isNotEmpty == true
        ? user.jobTitle!
        : user.email;

    return Row(
      children: [
        UserAvatar(user: user, size: AvatarSize.small),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCell(BuildContext context) {
    final roleLabel = member.displayRoleName;
    return Text(
      roleLabel,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildRateCell(BuildContext context) {
    final rate = member.hourlyRate;
    if (rate == null) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }
    return Text(
      '\$${rate.toStringAsFixed(2)}/hr',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildTotalHoursCell(BuildContext context) {
    if (summary.totalEntries == 0) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }
    return Text(
      '${summary.totalHours.toStringAsFixed(1)}h',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildRegularHoursCell(BuildContext context) {
    if (summary.totalEntries == 0) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }
    return Text(
      '${summary.regularHours.toStringAsFixed(1)}h',
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _buildOvertimeHoursCell(BuildContext context) {
    if (summary.overtimeHours == 0 && summary.doubleTimeHours == 0) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }
    final ot = summary.overtimeHours + summary.doubleTimeHours;
    return Text(
      '${ot.toStringAsFixed(1)}h',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ot > 0 ? AppColors.warningDark : null,
      ),
    );
  }

  Widget _buildTotalCostCell(BuildContext context) {
    if (summary.totalEntries == 0) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }
    return Text(
      '\$${summary.totalCost.toStringAsFixed(2)}',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildPendingCell(BuildContext context) {
    if (summary.pendingEntries == 0) {
      return const Text(
        '0',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }
    return Text(
      '${summary.pendingEntries}',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.warningDark,
      ),
    );
  }

  Widget _buildApprovedCell(BuildContext context) {
    if (summary.approvedEntries == 0) {
      return const Text(
        '0',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }
    return Text(
      '${summary.approvedEntries}',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.success,
      ),
    );
  }

  Widget _buildStatusCell(BuildContext context) {
    if (summary.isClockedIn) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Clocked In',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.success,
            ),
          ),
        ],
      );
    }

    if (summary.totalEntries == 0) {
      return const Text(
        'No entries',
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      );
    }

    return const Text(
      'Clocked Out',
      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}
