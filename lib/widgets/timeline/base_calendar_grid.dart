import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Calendar range options shared across all calendar views.
enum CalendarRange { day, week, month, year }

/// Mixin that provides shared calendar grid infrastructure (navigation,
/// headers, date layout, week generation) so that task and project
/// calendars do not duplicate this logic.
///
/// The host [State] must:
///  1. Mix in [BaseCalendarGrid] and call [initCalendar] / [disposeCalendar].
///  2. Implement the three abstract builder methods that vary per item type:
///     [buildDayViewBody], [buildWeekCellBody], [buildMonthCellBody].
///  3. Optionally override [buildMonthCellFooter] to render "+N more" or
///     add-item buttons.
mixin BaseCalendarGrid<T extends StatefulWidget> on State<T> {
  late DateTime currentDate;
  CalendarRange calendarRange = CalendarRange.month;
  final ScrollController calendarScrollController = ScrollController();

  // ── Lifecycle ─────────────────────────────────────────────────────────

  void initCalendar() {
    currentDate = DateTime.now();
  }

  void disposeCalendar() {
    calendarScrollController.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────

  void calendarPrevious() {
    setState(() {
      switch (calendarRange) {
        case CalendarRange.day:
          currentDate = currentDate.subtract(const Duration(days: 1));
          break;
        case CalendarRange.week:
          currentDate = currentDate.subtract(const Duration(days: 7));
          break;
        case CalendarRange.month:
          currentDate = DateTime(currentDate.year, currentDate.month - 1, 1);
          break;
        case CalendarRange.year:
          currentDate = DateTime(currentDate.year - 1, currentDate.month, 1);
          break;
      }
    });
  }

  void calendarNext() {
    setState(() {
      switch (calendarRange) {
        case CalendarRange.day:
          currentDate = currentDate.add(const Duration(days: 1));
          break;
        case CalendarRange.week:
          currentDate = currentDate.add(const Duration(days: 7));
          break;
        case CalendarRange.month:
          currentDate = DateTime(currentDate.year, currentDate.month + 1, 1);
          break;
        case CalendarRange.year:
          currentDate = DateTime(currentDate.year + 1, currentDate.month, 1);
          break;
      }
    });
  }

  void calendarGoToToday() {
    setState(() {
      currentDate = DateTime.now();
    });
  }

  // ── Date helpers ──────────────────────────────────────────────────────

  bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  List<List<DateTime?>> getWeeksInMonth() {
    final List<List<DateTime?>> weeks = [];

    final firstDayOfMonth = DateTime(currentDate.year, currentDate.month, 1);
    final lastDayOfMonth = DateTime(
      currentDate.year,
      currentDate.month + 1,
      0,
    );

    int startOffset = firstDayOfMonth.weekday % 7;
    DateTime day = firstDayOfMonth.subtract(Duration(days: startOffset));

    while (day.isBefore(lastDayOfMonth) ||
        day.isAtSameMomentAs(lastDayOfMonth) ||
        weeks.isEmpty ||
        (weeks.isNotEmpty &&
            weeks.last.any(
              (d) => d != null && d.month == currentDate.month,
            ))) {
      final List<DateTime?> week = [];
      for (int i = 0; i < 7; i++) {
        if (day.month == currentDate.month) {
          week.add(day);
        } else if (day.isBefore(firstDayOfMonth) ||
            day.isAfter(lastDayOfMonth)) {
          week.add(day);
        }
        day = day.add(const Duration(days: 1));
      }
      weeks.add(week);

      if (weeks.length > 6) break;
    }

    return weeks;
  }

  String getDateRangeLabel() {
    final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

    const monthNamesFull = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const monthNamesShort = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    final monthNames = isMobile ? monthNamesShort : monthNamesFull;
    final now = DateTime.now();
    final isCurrentYear = currentDate.year == now.year;

    switch (calendarRange) {
      case CalendarRange.day:
        final label =
            '${dayNames[currentDate.weekday % 7]}, ${monthNames[currentDate.month - 1]} ${currentDate.day}';
        return isCurrentYear && isMobile
            ? label
            : '$label, ${currentDate.year}';
      case CalendarRange.week:
        final weekStart = currentDate.subtract(
          Duration(days: currentDate.weekday % 7),
        );
        final weekEnd = weekStart.add(const Duration(days: 6));
        if (weekStart.month == weekEnd.month) {
          final label =
              '${monthNames[weekStart.month - 1]} ${weekStart.day} - ${weekEnd.day}';
          return isCurrentYear && isMobile
              ? label
              : '$label, ${weekStart.year}';
        } else {
          final label =
              '${monthNames[weekStart.month - 1]} ${weekStart.day} - ${monthNames[weekEnd.month - 1]} ${weekEnd.day}';
          return isCurrentYear && isMobile ? label : '$label, ${weekEnd.year}';
        }
      case CalendarRange.month:
        return '${monthNames[currentDate.month - 1]} ${currentDate.year}';
      case CalendarRange.year:
        return '${currentDate.year}';
    }
  }

  // ── Abstract builders (implemented by each calendar) ──────────────────

  /// Build the full content for the day view (single-day expanded list).
  Widget buildDayViewBody(DateTime date);

  /// Build the item cards shown inside a week-view cell.
  Widget buildWeekCellBody(DateTime date);

  /// Build the item cards shown inside a month-view day cell.
  /// [isCurrentMonth] is false for grey dates from adjacent months.
  Widget buildMonthCellBody(DateTime date, bool isCurrentMonth);

  /// Build the footer row inside a month-view day cell ("+N more", add button).
  /// Override to customise; default is empty.
  Widget buildMonthCellFooter(DateTime date) => const SizedBox.shrink();

  /// The number of items for a given date, used to calculate row height.
  int itemCountForDate(DateTime date);

  /// Optional: called when a date cell is tapped in month view.
  void onCalendarDateTap(DateTime date) {}

  /// Optional: called when a date cell is double-tapped in month view.
  void onCalendarDateDoubleTap(DateTime date) {}

  /// Optional: build an add-item button inside week-view cell headers.
  Widget? buildWeekCellAddButton(DateTime date) => null;

  /// Optional: wrap the month-view day cell widget (e.g. for DragTarget).
  /// By default returns [child] unwrapped.
  Widget wrapMonthDayCell(DateTime date, Widget child) => child;

  /// Optional: override the month cell background color (e.g. for drag highlight).
  /// Return null to use the default (today highlight or transparent).
  Color? monthCellBackgroundColor(DateTime date) => null;

  /// Optional: override the month cell right border (e.g. for drag highlight).
  /// Return null to use the default.
  BorderSide? monthCellRightBorder(DateTime date) => null;

  // ── Shared UI builders ────────────────────────────────────────────────

  /// Builds the full calendar widget (header + day headers + content).
  Widget buildCalendar() {
    final chrome = ChromeColors.of(context);

    Widget content = Column(
      children: [
        _buildCalendarHeader(),
        if (calendarRange != CalendarRange.day &&
            calendarRange != CalendarRange.year)
          _buildDayHeaders(),
        Expanded(child: _buildCalendarContent()),
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

  Widget _buildCalendarHeader() {
    final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 4 : 16,
        vertical: isMobile ? 6 : 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, size: isMobile ? 20 : 24),
            onPressed: calendarPrevious,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: isMobile ? 28 : 36,
              minHeight: isMobile ? 28 : 36,
            ),
            tooltip: switch (calendarRange) {
              CalendarRange.day => 'Previous day',
              CalendarRange.week => 'Previous week',
              CalendarRange.month => 'Previous month',
              CalendarRange.year => 'Previous year',
            },
          ),
          Expanded(
            child: GestureDetector(
              onTap: calendarGoToToday,
              child: Text(
                getDateRangeLabel(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: isMobile ? 14 : null,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, size: isMobile ? 20 : 24),
            onPressed: calendarNext,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: isMobile ? 28 : 36,
              minHeight: isMobile ? 28 : 36,
            ),
            tooltip: switch (calendarRange) {
              CalendarRange.day => 'Next day',
              CalendarRange.week => 'Next week',
              CalendarRange.month => 'Next month',
              CalendarRange.year => 'Next year',
            },
          ),
          SizedBox(width: isMobile ? 4 : 8),
          SegmentedButton<CalendarRange>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: CalendarRange.day,
                label: Text(isMobile ? 'D' : 'Day'),
              ),
              ButtonSegment(
                value: CalendarRange.week,
                label: Text(isMobile ? 'W' : 'Week'),
              ),
              ButtonSegment(
                value: CalendarRange.month,
                label: Text(isMobile ? 'M' : 'Month'),
              ),
              ButtonSegment(
                value: CalendarRange.year,
                label: Text(isMobile ? 'Y' : 'Year'),
              ),
            ],
            selected: {calendarRange},
            onSelectionChanged: (Set<CalendarRange> newSelection) {
              setState(() {
                calendarRange = newSelection.first;
              });
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: isMobile ? 6 : 12),
              ),
              textStyle: WidgetStateProperty.all(
                TextStyle(fontSize: isMobile ? 11 : 12),
              ),
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: calendarGoToToday,
              icon: const Icon(Icons.today, size: 18),
              label: const Text('Today'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarContent() {
    switch (calendarRange) {
      case CalendarRange.day:
        return buildDayViewBody(currentDate);
      case CalendarRange.week:
        return _buildWeekView();
      case CalendarRange.month:
        return _buildMonthView();
      case CalendarRange.year:
        return _buildYearView();
    }
  }

  Widget _buildDayHeaders() {
    const dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: dayNames.map((day) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Week view ─────────────────────────────────────────────────────────

  Widget _buildWeekView() {
    final weekStart = currentDate.subtract(
      Duration(days: currentDate.weekday % 7),
    );
    final List<DateTime> weekDays = List.generate(
      7,
      (i) => weekStart.add(Duration(days: i)),
    );

    return SingleChildScrollView(
      controller: calendarScrollController,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: weekDays
            .map((day) => Expanded(child: _buildWeekDayCell(day)))
            .toList(),
      ),
    );
  }

  Widget _buildWeekDayCell(DateTime date) {
    final today = isToday(date);

    return Container(
      constraints: const BoxConstraints(minHeight: 300),
      decoration: BoxDecoration(
        color: today
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
            : null,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: today
                      ? BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        )
                      : null,
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: today ? FontWeight.bold : FontWeight.w500,
                        color: today
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (buildWeekCellAddButton(date) != null)
                  buildWeekCellAddButton(date)!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: buildWeekCellBody(date),
          ),
        ],
      ),
    );
  }

  // ── Month view ────────────────────────────────────────────────────────

  Widget _buildMonthView() {
    final weeks = getWeeksInMonth();

    return SingleChildScrollView(
      controller: calendarScrollController,
      child: Column(
        children: weeks.map((week) => _buildWeekRow(week)).toList(),
      ),
    );
  }

  Widget _buildWeekRow(List<DateTime?> week) {
    int maxItems = 0;
    for (final day in week) {
      if (day != null) {
        final count = itemCountForDate(day);
        if (count > maxItems) maxItems = count;
      }
    }

    final rowHeight = 80.0 + (maxItems * 26.0).clamp(0.0, 130.0);

    return Container(
      height: rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: week.map((day) => _buildMonthDayCell(day)).toList(),
      ),
    );
  }

  Widget _buildMonthDayCell(DateTime? date) {
    if (date == null) {
      return Expanded(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
      );
    }

    final today = isToday(date);
    final isCurrentMonth = date.month == currentDate.month;
    final count = itemCountForDate(date);

    final cellContent = GestureDetector(
      onTap: () => onCalendarDateTap(date),
      onDoubleTap: () => onCalendarDateDoubleTap(date),
      child: Container(
          decoration: BoxDecoration(
            color: monthCellBackgroundColor(date) ??
                (today
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.05)
                    : null),
            border: Border(
              right: monthCellRightBorder(date) ??
                  BorderSide(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date number
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: today
                          ? BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                today ? FontWeight.bold : FontWeight.w500,
                            color: today
                                ? Colors.white
                                : isCurrentMonth
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                    if (count > 3) ...[
                      const Spacer(),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Item cards
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: SingleChildScrollView(
                    child: buildMonthCellBody(date, isCurrentMonth),
                  ),
                ),
              ),
              // Footer ("+N more", add button)
              buildMonthCellFooter(date),
            ],
          ),
        ),
      );

    return Expanded(child: wrapMonthDayCell(date, cellContent));
  }

  // ── Year view ─────────────────────────────────────────────────────────

  Widget _buildYearView() {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final now = DateTime.now();

    return SingleChildScrollView(
      controller: calendarScrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= AppBreakpoints.tablet
              ? 4
              : constraints.maxWidth >= 500
                  ? 3
                  : 2;
          final rows = (12 / columns).ceil();

          return Column(
            children: List.generate(rows, (row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(columns, (col) {
                    final monthIndex = row * columns + col;
                    if (monthIndex >= 12) {
                      return const Expanded(child: SizedBox.shrink());
                    }
                    final month = monthIndex + 1;
                    final isCurrentMonth = currentDate.year == now.year &&
                        month == now.month;

                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            currentDate =
                                DateTime(currentDate.year, month, 1);
                            calendarRange = CalendarRange.month;
                          });
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            margin: EdgeInsets.only(
                              right: col < columns - 1 ? 12 : 0,
                            ),
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: isCurrentMonth
                                  ? Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.4),
                                    )
                                  : Border.all(
                                      color: Theme.of(context)
                                          .dividerColor
                                          .withValues(alpha: 0.2),
                                    ),
                              color: isCurrentMonth
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.04)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  monthNames[monthIndex],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrentMonth
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildMiniMonth(
                                  currentDate.year,
                                  month,
                                  dayLabels,
                                  now,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildMiniMonth(
    int year,
    int month,
    List<String> dayLabels,
    DateTime now,
  ) {
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startOffset = firstDay.weekday % 7;
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // Day-of-week header row
    final headerRow = Row(
      children: dayLabels
          .map(
            (d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );

    // Build week rows
    final List<Widget> weekRows = [headerRow, const SizedBox(height: 2)];
    int dayNum = 1 - startOffset;

    while (dayNum <= lastDay.day) {
      final List<Widget> cells = [];
      for (int i = 0; i < 7; i++) {
        if (dayNum < 1 || dayNum > lastDay.day) {
          cells.add(const Expanded(child: SizedBox(height: 18)));
        } else {
          final date = DateTime(year, month, dayNum);
          final isTodayDate =
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
          final count = itemCountForDate(date);

          cells.add(
            Expanded(
              child: SizedBox(
                height: 18,
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: isTodayDate
                        ? BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isTodayDate
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isTodayDate
                                ? Colors.white
                                : onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        if (count > 0 && !isTodayDate)
                          Positioned(
                            bottom: 0,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        dayNum++;
      }
      weekRows.add(Row(children: cells));
    }

    return Column(children: weekRows);
  }
}
