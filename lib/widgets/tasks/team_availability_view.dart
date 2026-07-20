import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../timeline/task_calendar_card.dart';

/// How many days to show in the availability grid
enum AvailabilityRange { oneWeek, twoWeeks }

/// Team availability view: members on Y-axis, days on X-axis, task cards in cells.
class TeamAvailabilityView extends StatefulWidget {
  final List<Task> tasks;
  final Map<String, AppUser> usersMap;
  final void Function(Task)? onTaskTap;
  final void Function(DateTime date, String userId)? onAddTaskForDate;
  final void Function(DateTime date, List<Task> tasks, String userId)?
  onShowMoreTasks;
  final void Function(Task task, DateTime newDate, String newAssigneeId)?
  onTaskMoved;

  const TeamAvailabilityView({
    super.key,
    required this.tasks,
    this.usersMap = const {},
    this.onTaskTap,
    this.onAddTaskForDate,
    this.onShowMoreTasks,
    this.onTaskMoved,
  });

  @override
  State<TeamAvailabilityView> createState() => _TeamAvailabilityViewState();
}

class _TeamAvailabilityViewState extends State<TeamAvailabilityView> {
  late DateTime _weekStart;
  AvailabilityRange _range = AvailabilityRange.oneWeek;
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScrollGrid = ScrollController();
  final ScrollController _verticalScrollMembers = ScrollController();

  static const double _headerHeight = 40.0;
  static const int _maxTasksPerCell = 3;

  bool get _isMobile => MediaQuery.of(context).size.width < 768;
  double get _memberColumnWidth => _isMobile ? 120.0 : 200.0;
  double get _dayColumnWidth => _isMobile ? 90.0 : 160.0;
  double get _rowHeight => _isMobile ? 80.0 : 120.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Start on Monday of current week
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);

    // Sync vertical scrolling between member column and grid
    _verticalScrollGrid.addListener(_syncScrollFromGrid);
    _verticalScrollMembers.addListener(_syncScrollFromMembers);
  }

  void _syncScrollFromGrid() {
    if (_verticalScrollMembers.hasClients &&
        _verticalScrollGrid.hasClients &&
        _verticalScrollMembers.offset != _verticalScrollGrid.offset) {
      _verticalScrollMembers.jumpTo(_verticalScrollGrid.offset);
    }
  }

  void _syncScrollFromMembers() {
    if (_verticalScrollGrid.hasClients &&
        _verticalScrollMembers.hasClients &&
        _verticalScrollGrid.offset != _verticalScrollMembers.offset) {
      _verticalScrollGrid.jumpTo(_verticalScrollMembers.offset);
    }
  }

  @override
  void dispose() {
    _verticalScrollGrid.removeListener(_syncScrollFromGrid);
    _verticalScrollMembers.removeListener(_syncScrollFromMembers);
    _horizontalScroll.dispose();
    _verticalScrollGrid.dispose();
    _verticalScrollMembers.dispose();
    super.dispose();
  }

  int get _dayCount => _range == AvailabilityRange.oneWeek ? 7 : 14;

  List<DateTime> get _days =>
      List.generate(_dayCount, (i) => _weekStart.add(Duration(days: i)));

  /// Build grid: userId → dateKey → tasks
  Map<String, Map<String, List<Task>>> _buildGrid() {
    final grid = <String, Map<String, List<Task>>>{};

    for (final task in widget.tasks) {
      final rawAssignees = task.assignedToIds.isEmpty
          ? const ['__unassigned__']
          : task.assignedToIds;
      // Fold assignees that no longer resolve to a workspace user into the
      // "Unassigned" bucket instead of rendering a phantom "Unknown" row.
      final assignees = rawAssignees
          .map(
            (id) => id == '__unassigned__' || widget.usersMap.containsKey(id)
                ? id
                : '__unassigned__',
          )
          .toSet();

      // Determine date range for the task
      final dates = _taskDates(task);

      for (final userId in assignees) {
        grid.putIfAbsent(userId, () => {});
        for (final date in dates) {
          final key = _dateKey(date);
          grid[userId]!.putIfAbsent(key, () => []);
          grid[userId]![key]!.add(task);
        }
      }
    }

    return grid;
  }

  /// Returns all dates this task spans that fall within the current view range.
  List<DateTime> _taskDates(Task task) {
    final viewStart = _weekStart;
    final viewEnd = _weekStart.add(Duration(days: _dayCount));

    DateTime? start = task.startDate;
    DateTime? end = task.dueDate;

    // If neither date is set, skip
    if (start == null && end == null) return [];

    // Normalize to day boundaries
    start = start != null
        ? DateTime(start.year, start.month, start.day)
        : DateTime(end!.year, end.month, end.day);
    end = end != null ? DateTime(end.year, end.month, end.day) : start;

    // Clamp to view range
    if (end.isBefore(viewStart) || start.isAfter(viewEnd)) return [];

    final clampedStart = start.isBefore(viewStart) ? viewStart : start;
    final clampedEnd = end.isAfter(viewEnd.subtract(const Duration(days: 1)))
        ? viewEnd.subtract(const Duration(days: 1))
        : end;

    final result = <DateTime>[];
    var current = clampedStart;
    while (!current.isAfter(clampedEnd)) {
      result.add(current);
      current = current.add(const Duration(days: 1));
    }
    return result;
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// Get sorted member IDs — alphabetically by displayName, unassigned at end
  List<String> _getSortedMemberIds(Map<String, Map<String, List<Task>>> grid) {
    final ids = grid.keys.where((id) => id != '__unassigned__').toList();
    ids.sort((a, b) {
      final nameA = widget.usersMap[a]?.displayName?.toLowerCase() ?? '';
      final nameB = widget.usersMap[b]?.displayName?.toLowerCase() ?? '';
      return nameA.compareTo(nameB);
    });
    if (grid.containsKey('__unassigned__')) {
      ids.add('__unassigned__');
    }
    return ids;
  }

  void _previous() {
    setState(() {
      _weekStart = _weekStart.subtract(Duration(days: _dayCount));
    });
  }

  void _next() {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: _dayCount));
    });
  }

  void _goToToday() {
    setState(() {
      final now = DateTime.now();
      _weekStart = now.subtract(Duration(days: now.weekday - 1));
      _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final grid = _buildGrid();
    final memberIds = _getSortedMemberIds(grid);
    final days = _days;

    Widget content = Column(
      children: [
        _buildHeaderBar(),
        Divider(
          height: 1,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
        Expanded(
          child: memberIds.isEmpty
              ? _buildEmptyState()
              : Row(
                  children: [
                    // Fixed left column: member names
                    SizedBox(
                      width: _memberColumnWidth,
                      child: Column(
                        children: [
                          // Spacer for day header row
                          SizedBox(height: _headerHeight),
                          Expanded(
                            child: ListView.builder(
                              controller: _verticalScrollMembers,
                              itemCount: memberIds.length,
                              itemBuilder: (context, index) =>
                                  _buildMemberCell(memberIds[index]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Vertical divider
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.3),
                    ),
                    // Scrollable grid area
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final gridWidth = _dayColumnWidth * days.length;
                          final needsHorizontalScroll =
                              gridWidth > constraints.maxWidth;

                          return ScrollbarTheme(
                            data: ScrollbarThemeData(
                              thumbVisibility: WidgetStateProperty.all(
                                needsHorizontalScroll,
                              ),
                              trackVisibility: WidgetStateProperty.all(
                                needsHorizontalScroll,
                              ),
                              thickness: WidgetStateProperty.all(10),
                              radius: const Radius.circular(6),
                              thumbColor: WidgetStateProperty.all(
                                AppColors.textTertiary,
                              ),
                              trackColor: WidgetStateProperty.all(
                                AppColors.cardBorder,
                              ),
                            ),
                            child: Scrollbar(
                              controller: _horizontalScroll,
                              thumbVisibility: needsHorizontalScroll,
                              trackVisibility: needsHorizontalScroll,
                              notificationPredicate: (notification) =>
                                  notification.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: _horizontalScroll,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: gridWidth,
                                  child: Column(
                                    children: [
                                      // Day headers
                                      SizedBox(
                                        height: _headerHeight,
                                        child: Row(
                                          children: days
                                              .map((d) => _buildDayHeader(d))
                                              .toList(),
                                        ),
                                      ),
                                      // Grid rows
                                      Expanded(
                                        child: ListView.builder(
                                          controller: _verticalScrollGrid,
                                          itemCount: memberIds.length,
                                          itemBuilder: (context, index) {
                                            final userId = memberIds[index];
                                            return _buildGridRow(
                                              userId,
                                              days,
                                              grid[userId] ?? {},
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );

    if (chrome.isDark) {
      content = Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: content,
      );
    }

    return content;
  }

  Widget _buildHeaderBar() {
    final days = _days;
    final isMobile = _isMobile;
    final startLabel = DateFormat('MMM d').format(days.first);
    final endLabel = DateFormat('MMM d, y').format(days.last);

    return Container(
      padding: EdgeInsets.only(
        left: isMobile ? 4 : 16,
        right: isMobile ? 8 : 16,
        top: isMobile ? 6 : 10,
        bottom: isMobile ? 6 : 10,
      ),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previous,
            tooltip: 'Previous',
            iconSize: isMobile ? 20 : 24,
            constraints: isMobile
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            padding: isMobile ? EdgeInsets.zero : null,
          ),
          GestureDetector(
            onTap: _goToToday,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 12),
              child: Text(
                '$startLabel - $endLabel',
                style: isMobile
                    ? Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      )
                    : Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _next,
            tooltip: 'Next',
            iconSize: isMobile ? 20 : 24,
            constraints: isMobile
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            padding: isMobile ? EdgeInsets.zero : null,
          ),
          const Spacer(),
          if (!isMobile) ...[
            TextButton.icon(
              onPressed: _goToToday,
              icon: const Icon(Icons.today, size: 18),
              label: const Text('Today'),
            ),
            const SizedBox(width: 8),
          ],
          if (isMobile)
            IconButton(
              onPressed: _goToToday,
              icon: const Icon(Icons.today, size: 18),
              tooltip: 'Today',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          SegmentedButton<AvailabilityRange>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: AvailabilityRange.oneWeek,
                label: Text('1W'),
              ),
              ButtonSegment(
                value: AvailabilityRange.twoWeeks,
                label: Text('2W'),
              ),
            ],
            selected: {_range},
            onSelectionChanged: (s) => setState(() => _range = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
              ),
              textStyle: WidgetStateProperty.all(
                TextStyle(fontSize: isMobile ? 11 : 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeader(DateTime date) {
    final isToday = _isToday(date);
    final dayName = DateFormat('E').format(date); // Mon, Tue...
    final dayNum = date.day.toString();

    return SizedBox(
      width: _dayColumnWidth,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isToday
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
            right: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: Text(
          _isMobile ? '$dayName\n$dayNum' : '$dayName $dayNum',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _isMobile ? 10 : 12,
            fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
            color: isToday
                ? Theme.of(context).colorScheme.primary
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCell(String userId) {
    final isUnassigned = userId == '__unassigned__';
    final user = isUnassigned ? null : widget.usersMap[userId];
    final name = isUnassigned
        ? 'Unassigned'
        : user?.displayName ?? user?.email ?? 'Unknown';
    final initials = isUnassigned ? '?' : (user?.getInitials() ?? '?');
    final isMobile = _isMobile;

    return Container(
      height: _rowHeight,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          _buildAvatar(user, initials, isUnassigned),
          SizedBox(width: isMobile ? 6 : 10),
          // Name
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: isMobile ? 11 : 13,
                fontWeight: FontWeight.w500,
                color: isUnassigned
                    ? AppColors.textSecondary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(AppUser? user, String initials, bool isUnassigned) {
    final double size = _isMobile ? 24 : 32;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    final bgColor = isUnassigned
        ? AppColors.textTertiary
        : colors[(user?.id.hashCode.abs() ?? 0) % colors.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: user == null
          ? Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : StreamBuilder<AppUser?>(
              stream: ServiceLocator.userService.getUserStream(user.id),
              builder: (context, snapshot) {
                final liveUser = snapshot.data ?? user;
                if (liveUser.profilePictureUrl != null) {
                  return ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: liveUser.profilePictureUrl!,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return Center(
                  child: Text(
                    liveUser.getInitials(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildGridRow(
    String userId,
    List<DateTime> days,
    Map<String, List<Task>> userGrid,
  ) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: days.map((date) {
          final key = _dateKey(date);
          final tasks = userGrid[key] ?? [];
          return _buildGridCell(userId, date, tasks);
        }).toList(),
      ),
    );
  }

  Widget _buildGridCell(String userId, DateTime date, List<Task> tasks) {
    final isToday = _isToday(date);
    final visibleTasks = tasks.take(_maxTasksPerCell).toList();
    final overflow = tasks.length - _maxTasksPerCell;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final assigneeId = userId == '__unassigned__' ? '' : userId;
        widget.onTaskMoved?.call(
          details.data,
          DateTime(date.year, date.month, date.day),
          assigneeId,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;

        return SizedBox(
          width: _dayColumnWidth,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: isDragOver
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15)
                  : isToday
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.04)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
                right: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Task cards
                ...visibleTasks.map((task) {
                  final isMobile = !kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.iOS ||
                          defaultTargetPlatform == TargetPlatform.android);
                  final feedbackWidget = Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                  final whenDragging = Opacity(
                    opacity: 0.3,
                    child: TaskCalendarCard(
                      task: task,
                      usersMap: widget.usersMap,
                      onTap: () => widget.onTaskTap?.call(task),
                    ),
                  );
                  final cardChild = TaskCalendarCard(
                    task: task,
                    usersMap: widget.usersMap,
                    onTap: () => widget.onTaskTap?.call(task),
                  );
                  if (isMobile) {
                    return LongPressDraggable<Task>(
                      data: task,
                      feedback: feedbackWidget,
                      childWhenDragging: whenDragging,
                      hapticFeedbackOnStart: true,
                      child: cardChild,
                    );
                  }
                  return Draggable<Task>(
                    data: task,
                    feedback: feedbackWidget,
                    childWhenDragging: whenDragging,
                    child: cardChild,
                  );
                }),
                // Overflow indicator
                if (overflow > 0)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () =>
                          widget.onShowMoreTasks?.call(date, tasks, userId),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, left: 4),
                        child: Text(
                          '+$overflow more',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                // Add task button (only visible on hover via parent)
                if (widget.onAddTaskForDate != null && tasks.isEmpty)
                  Align(
                    alignment: Alignment.center,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          final assigneeId = userId == '__unassigned__'
                              ? ''
                              : userId;
                          widget.onAddTaskForDate?.call(date, assigneeId);
                        },
                        child: Icon(
                          Icons.add_circle_outline,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups_outlined, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'No tasks with dates in this range',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Assign dates and team members to tasks to see them here',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
