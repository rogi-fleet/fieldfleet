import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import '../../../models/project.dart';
import '../../../models/project_task_metrics.dart';
import '../../../models/project_financial_summary.dart';
import '../../../models/project_status_theme.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../models/customer.dart';
import '../../../theme/theme.dart';
import '../../../utils/address_formatter.dart';
import '../../../utils/project_customer_name.dart';
import '../../../utils/project_terminology.dart';
import '../../../widgets/project_form_popup.dart';
import '../../../widgets/projects/save_as_template_dialog.dart';
import '../../../widgets/table/hover_action_row.dart';
import '../../../widgets/table/table_view_styles.dart';

// Column widths — exported so the header in projects_table_screen stays in sync.
const double kProjectTableColId = 72;
const double kProjectTableColProject = 250;
const double kProjectTableColCustomer = 210;
const double kProjectTableColStatus = 110;
const double kProjectTableColBudget = 110;
const double kProjectTableColMargin = 120;
const double kProjectTableColProfit = 120;
const double kProjectTableColTasks = 120;
const double kProjectTableColTimeline = 160;
const double kProjectTableColProgress = 150;
const double kProjectTableColGap = 12;

String projectTableIdentifierValue(Project project) {
  final serialNumber = project.serialNumber?.trim();
  if (serialNumber != null && serialNumber.isNotEmpty) {
    return serialNumber;
  }

  final id = project.id;
  return id.length > 8 ? id.substring(id.length - 8) : id;
}

bool projectTableUsesSerialNumber(Project project) {
  final serialNumber = project.serialNumber?.trim();
  return serialNumber != null && serialNumber.isNotEmpty;
}

String projectTableDisplayId(Project project) {
  final value = projectTableIdentifierValue(project);
  return projectTableUsesSerialNumber(project) ? '#$value' : value;
}

int compareProjectTableIds(Project a, Project b) {
  final aSerial = a.serialNumber?.trim();
  final bSerial = b.serialNumber?.trim();
  final aHasSerial = aSerial != null && aSerial.isNotEmpty;
  final bHasSerial = bSerial != null && bSerial.isNotEmpty;

  if (aHasSerial && bHasSerial) {
    final aNum = int.tryParse(aSerial);
    final bNum = int.tryParse(bSerial);
    if (aNum != null && bNum != null) {
      return aNum.compareTo(bNum);
    }
  }

  return projectTableDisplayId(
    a,
  ).toLowerCase().compareTo(projectTableDisplayId(b).toLowerCase());
}

class ProjectTableRow extends StatefulWidget {
  final Project project;
  final ProjectTaskMetrics? taskMetrics;
  final Future<ProjectFinancialSummary>? financialsFuture;
  final Future<Customer?>? customerFuture;
  final bool isFavorite;
  final ValueChanged<bool>? onFavoriteToggled;
  final bool isSelected;
  final bool selectionMode;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onLongPress;
  final Map<String, double> columnWidths;

  const ProjectTableRow({
    super.key,
    required this.project,
    this.taskMetrics,
    this.financialsFuture,
    this.customerFuture,
    this.isFavorite = false,
    this.onFavoriteToggled,
    this.isSelected = false,
    this.selectionMode = false,
    this.onSelectionChanged,
    this.onLongPress,
    this.columnWidths = const {},
  });

  @override
  State<ProjectTableRow> createState() => _ProjectTableRowState();
}

class _ProjectTableRowState extends State<ProjectTableRow> {
  late Future<ProjectFinancialSummary> _financialsFuture;
  Future<Customer?>? _customerFuture;

  double _colW(String id, double defaultWidth) =>
      widget.columnWidths[id] ?? defaultWidth;

  @override
  void initState() {
    super.initState();
    _primeFutures();
  }

  @override
  void didUpdateWidget(ProjectTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.project.customerName != widget.project.customerName ||
        oldWidget.project.clientId != widget.project.clientId) {
      _primeFutures();
    }
  }

  void _primeFutures() {
    _financialsFuture =
        widget.financialsFuture ??
        ServiceLocator.projectService.getProjectFinancials(
              widget.project.id,
              widget.project,
            )
            as Future<ProjectFinancialSummary>;
    _customerFuture =
        widget.customerFuture ??
        (widget.project.customerName == null && widget.project.clientId != null
            ? ServiceLocator.customerService.getCustomer(
                widget.project.clientId!,
              )
            : null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: HoverActionRow(
        actionWidth: 40,
        actions: [_buildActionsMenu(context)],
        builder: (isHovered) => InkWell(
          onTap: widget.selectionMode
              ? () => widget.onSelectionChanged?.call(!widget.isSelected)
              : () => context.go('/projects/${widget.project.id}'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08)
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
                  if (widget.selectionMode) ...[
                    SizedBox(
                      width: 40,
                      child: Checkbox(
                        value: widget.isSelected,
                        onChanged: (val) =>
                            widget.onSelectionChanged?.call(val ?? false),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  SizedBox(
                    width: _colW('id', kProjectTableColId),
                    child: _buildIdCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('project', kProjectTableColProject),
                    child: _buildProjectCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('customer', kProjectTableColCustomer),
                    child: _buildCustomerCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('status', kProjectTableColStatus),
                    child: _buildStatusCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('budget', kProjectTableColBudget),
                    child: _buildBudgetCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('margin', kProjectTableColMargin),
                    child: _buildMarginCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('profit', kProjectTableColProfit),
                    child: _buildProfitCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('tasks', kProjectTableColTasks),
                    child: _buildTasksCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('timeline', kProjectTableColTimeline),
                    child: _buildTimelineCell(context),
                  ),
                  const SizedBox(width: kProjectTableColGap),
                  SizedBox(
                    width: _colW('progress', kProjectTableColProgress),
                    child: _buildProgressCell(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 12),
              Text('Edit'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.content_copy, size: 18),
              SizedBox(width: 12),
              Text('Duplicate'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'save_template',
          child: Row(
            children: [
              Icon(Icons.bookmark_add, size: 18),
              SizedBox(width: 12),
              Text('Save as Template'),
            ],
          ),
        ),
        if (!widget.project.status.isClosed)
          const PopupMenuItem(
            value: 'close',
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18),
                SizedBox(width: 12),
                Text('Mark Complete'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: AppColors.error),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'edit':
            showProjectFormPopup(context, projectId: widget.project.id);
          case 'duplicate':
            _duplicateProject(context);
          case 'save_template':
            showSaveProjectAsTemplateDialog(
              context,
              projectId: widget.project.id,
              workspaceId: widget.project.workspaceId,
            );
          case 'close':
            _closeProject(context);
          case 'delete':
            _deleteProject(context);
        }
      },
    );
  }

  Widget _buildFavoriteStar() {
    return GestureDetector(
      onTap: () => widget.onFavoriteToggled?.call(!widget.isFavorite),
      child: Icon(
        widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 18,
        color: widget.isFavorite ? Colors.amber : AppColors.textTertiary,
      ),
    );
  }

  Widget _buildIdCell(BuildContext context) {
    final isSerialNumber = projectTableUsesSerialNumber(widget.project);
    final displayId = projectTableDisplayId(widget.project);

    return Text(
      displayId,
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: isSerialNumber
            ? Theme.of(context).colorScheme.primary
            : AppColors.textSecondary,
        fontWeight: isSerialNumber ? FontWeight.w600 : FontWeight.normal,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildProjectCell(BuildContext context) {
    return Row(
      children: [
        _buildFavoriteStar(),
        const SizedBox(width: 6),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: const Border.fromBorderSide(
              BorderSide(color: AppColors.cardBorder),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.project.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: widget.project.photoUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceAlt,
                    child: const Icon(
                      Icons.image,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                  ),
                )
              : Container(
                  color: AppColors.surfaceAlt,
                  child: const Icon(
                    Icons.image,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.project.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                AddressFormatter.condense(widget.project.address),
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

  Widget _buildCustomerCell(BuildContext context) {
    final customerName = projectBusinessName(widget.project);
    final hasCustomerName = customerName.isNotEmpty;

    if (hasCustomerName && _customerFuture == null) {
      return _buildTwoLineCell(
        primary: customerName,
        primaryColor: Theme.of(context).colorScheme.primary,
      );
    }

    if (_customerFuture == null) {
      return _buildTwoLineCell(primary: '—');
    }

    return FutureBuilder<Customer?>(
      future: _customerFuture,
      builder: (context, snapshot) {
        final loadedName = projectBusinessName(
          widget.project,
          customer: snapshot.data,
        );
        return _buildTwoLineCell(
          primary: loadedName.isNotEmpty ? loadedName : '—',
          primaryColor: loadedName.isNotEmpty
              ? Theme.of(context).colorScheme.primary
              : null,
        );
      },
    );
  }

  Widget _buildStatusCell(BuildContext context) {
    final color = ProjectStatusTheme.color(widget.project.status);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 7, color: color),
        const SizedBox(width: 6),
        Text(
          widget.project.status.displayName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetCell(BuildContext context) {
    final budget =
        widget.project.contractAmount ?? widget.project.estimatedBudget;
    if (budget == null) {
      return const Text('—', style: TextStyle(color: AppColors.textTertiary));
    }
    return Text(
      '\$${budget.toStringAsFixed(0)}',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildMarginCell(BuildContext context) {
    return FutureBuilder<ProjectFinancialSummary>(
      future: _financialsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Text(
            '—',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          );
        }

        final margin = snapshot.data!.projectedMargin;
        final colors = _marginColors(margin);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${margin.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.value,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(
                value: (margin.clamp(0, 100)) / 100,
                minHeight: 6,
                backgroundColor: AppColors.cardBorder,
                color: colors.accent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfitCell(BuildContext context) {
    return FutureBuilder<ProjectFinancialSummary>(
      future: _financialsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Text(
            '—',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          );
        }

        final profit = snapshot.data!.projectedProfit;
        final colors = _profitColors(profit);

        return Text(
          _formatCompactCurrency(profit),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colors.value,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  Widget _buildTasksCell(BuildContext context) {
    final taskMetrics = widget.taskMetrics;
    if (taskMetrics == null) {
      return const SizedBox(
        height: 32,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '—',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ),
      );
    }

    final secondary = [
      if (taskMetrics.overdueCount > 0) '${taskMetrics.overdueCount} overdue',
      if (taskMetrics.dueTodayCount > 0) '${taskMetrics.dueTodayCount} due',
      if (taskMetrics.overdueCount == 0 && taskMetrics.dueTodayCount == 0)
        'No urgent tasks',
    ].join(' · ');

    return _buildTwoLineCell(
      primary: '${taskMetrics.openCount} open',
      secondary: secondary,
      secondaryColor: taskMetrics.overdueCount > 0 ? AppColors.error : null,
    );
  }

  Widget _buildTimelineCell(BuildContext context) {
    final start = widget.project.startDate;
    final end = widget.project.targetCompletionDate;

    return _buildTwoLineCell(
      primary: start != null ? _formatDateShort(start) : 'No start date',
      secondary: end != null
          ? 'Target ${_formatDateShort(end)}'
          : 'No target date',
    );
  }

  Widget _buildProgressCell(BuildContext context) {
    final taskMetrics = widget.taskMetrics;
    final progress = (taskMetrics?.progressPercent ?? 0) / 100;
    final progressColor = progress > 0.8
        ? AppColors.success
        : progress > 0.4
        ? AppColors.warningDark
        : AppColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(progress * 100).toInt()}%',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.cardBorder,
          color: progressColor,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          minHeight: 6,
        ),
      ],
    );
  }

  Widget _buildTwoLineCell({
    required String primary,
    String? secondary,
    Color? primaryColor,
    Color? secondaryColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primary,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: primaryColor ?? AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (secondary != null && secondary.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            secondary,
            style: TextStyle(
              fontSize: 11,
              color: secondaryColor ?? AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  String _formatDateShort(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  AppSeverityColors _marginColors(double margin) {
    if (margin < 0) {
      return AppSeverityTheme.colors(AppSeverity.error);
    }
    if (margin < 10) {
      return AppSeverityTheme.colors(AppSeverity.warning);
    }
    return AppSeverityTheme.colors(AppSeverity.neutral);
  }

  AppSeverityColors _profitColors(double profit) {
    if (profit < 0) {
      return AppSeverityTheme.colors(AppSeverity.error);
    }
    if (profit == 0) {
      return AppSeverityTheme.colors(AppSeverity.warning);
    }
    return AppSeverityTheme.colors(AppSeverity.neutral);
  }

  String _formatCompactCurrency(double amount) {
    final prefix = amount < 0 ? '-\$' : '\$';
    final absAmount = amount.abs();

    if (absAmount >= 1000000) {
      return '$prefix${(absAmount / 1000000).toStringAsFixed(1)}M';
    }
    if (absAmount >= 1000) {
      return '$prefix${(absAmount / 1000).toStringAsFixed(0)}K';
    }
    return '$prefix${absAmount.toStringAsFixed(0)}';
  }

  Future<void> _duplicateProject(BuildContext context) async {
    final projectTerminology = context.read<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Duplicate $singular'),
        content: Text('Create a copy of "${widget.project.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.projectService.duplicateProject(widget.project.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$singular duplicated successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'duplicating project'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _closeProject(BuildContext context) async {
    final projectTerminology = context.read<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close $singular'),
        content: Text('Mark "${widget.project.name}" as complete?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.projectService.updateProject(
          projectId: widget.project.id,
          status: ProjectStatus.complete,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$singular closed')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'closing project'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteProject(BuildContext context) async {
    final projectTerminology = context.read<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $singular'),
        content: Text(
          'Are you sure you want to delete "${widget.project.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.projectService.deleteProject(widget.project.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$singular deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting project'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}
