import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase/calendar_aggregator_service.dart';
import '../../theme/theme.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/view_toolbar.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;
  Future<List<CalendarEvent>>? _eventsFuture;
  String? _loadedWorkspaceId;
  Set<CalendarEventType> _activeFilters =
      CalendarEventType.values.toSet();
  bool _overdueOnly = false;
  String _searchQuery = '';

  /// One of: 'calendar', 'grid', 'list', 'kanban', 'gantt'.
  String _viewType = 'calendar';

  static const List<(String, IconData, String)> _viewOptions = [
    ('calendar', Icons.calendar_view_month_outlined, 'Calendar'),
    ('grid', Icons.grid_view, 'Grid'),
    ('list', Icons.view_list, 'List'),
    ('kanban', Icons.view_kanban, 'Kanban'),
    ('gantt', Icons.view_timeline, 'Gantt'),
  ];

  void _loadEvents(String workspaceId) {
    if (_loadedWorkspaceId == workspaceId && _eventsFuture != null) return;
    _loadedWorkspaceId = workspaceId;
    _eventsFuture =
        CalendarAggregatorService(workspaceId: workspaceId).fetchEvents();
  }

  void _refresh(String workspaceId) {
    setState(() {
      _loadedWorkspaceId = null;
      _loadEvents(workspaceId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final workspaceId = auth.appUser?.currentWorkspaceId ?? '';

    if (workspaceId.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('No active workspace.')));
    }

    _loadEvents(workspaceId);

    final allTypesSelected =
        _activeFilters.length == CalendarEventType.values.length;
    final filterCount =
        (allTypesSelected ? 0 : 1) + (_overdueOnly ? 1 : 0);

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Column(
        children: [
          ModuleHeader(
            icon: Icons.calendar_today_outlined,
            title: 'Calendar',
            description: 'Unified view of all deadlines, reminders and scheduled events '
                'across every module.',
            trailing: [
              IconButton(
                icon: const Icon(Icons.refresh_outlined, size: 20),
                tooltip: 'Refresh',
                onPressed: () => _refresh(workspaceId),
              ),
            ],
          ),
          ViewToolbar(
            searchHint: 'Search calendar...',
            searchQuery: _searchQuery,
            onSearch: (value) => setState(() => _searchQuery = value),
            centerSlot: _buildViewIcons(),
            filterCount: filterCount,
            onFilterTap: _showFilterDialog,
          ),
          Expanded(
            child: FutureBuilder<List<CalendarEvent>>(
              future: _eventsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error loading calendar data.',
                          style: TextStyle(color: AppColors.error)));
                }
                final allEvents = snapshot.data ?? [];
                final q = _searchQuery.trim().toLowerCase();
                final filtered = allEvents.where((e) {
                  if (!_activeFilters.contains(e.type)) return false;
                  if (_overdueOnly && !e.isOverdue) return false;
                  if (q.isEmpty) return true;
                  bool m(String? s) =>
                      s != null && s.toLowerCase().contains(q);
                  return m(e.title) ||
                      m(e.subtitle) ||
                      m(e.jobNumber) ||
                      m(e.jobName) ||
                      m(e.customerName) ||
                      m(e.customerAddress);
                }).toList();

                switch (_viewType) {
                  case 'grid':
                    return _GridTabView(events: filtered);
                  case 'list':
                    return _AgendaTabView(events: filtered);
                  case 'kanban':
                    return _KanbanTabView(events: filtered);
                  case 'gantt':
                    return _GanttTabView(events: filtered);
                  case 'calendar':
                  default:
                    return _MonthTabView(
                      events: filtered,
                      focusedMonth: _focusedMonth,
                      selectedDay: _selectedDay,
                      onMonthChanged: (m) =>
                          setState(() => _focusedMonth = m),
                      onDaySelected: (d) =>
                          setState(() => _selectedDay = d),
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, icon, tooltip) in _viewOptions)
          ViewIconButton(
            icon: icon,
            tooltip: tooltip,
            isSelected: _viewType == value,
            onTap: () => setState(() => _viewType = value),
          ),
      ],
    );
  }

  Future<void> _showFilterDialog() async {
    final result = await showDialog<({Set<CalendarEventType> types, bool overdueOnly})>(
      context: context,
      builder: (_) => _CalendarFilterDialog(
        initialTypes: _activeFilters,
        initialOverdueOnly: _overdueOnly,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _activeFilters = result.types;
        _overdueOnly = result.overdueOnly;
      });
    }
  }
}

// ============================================================================
// Filter Dialog — event types + overdue toggle
// ============================================================================

class _CalendarFilterDialog extends StatefulWidget {
  final Set<CalendarEventType> initialTypes;
  final bool initialOverdueOnly;

  const _CalendarFilterDialog({
    required this.initialTypes,
    required this.initialOverdueOnly,
  });

  @override
  State<_CalendarFilterDialog> createState() => _CalendarFilterDialogState();
}

class _CalendarFilterDialogState extends State<_CalendarFilterDialog> {
  late Set<CalendarEventType> _types;
  late bool _overdueOnly;

  @override
  void initState() {
    super.initState();
    _types = {...widget.initialTypes};
    _overdueOnly = widget.initialOverdueOnly;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = _types.length == CalendarEventType.values.length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 20),
          const SizedBox(width: 8),
          const Text('Filters'),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _types = allSelected
                    ? <CalendarEventType>{}
                    : CalendarEventType.values.toSet();
              });
            },
            child: Text(allSelected ? 'Clear all' : 'Select all'),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Event types',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CalendarEventType.values.map((type) {
                final active = _types.contains(type);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (active) {
                      _types.remove(type);
                    } else {
                      _types.add(type);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? type.color.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: active
                            ? type.color
                            : Colors.grey.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(type.icon,
                            size: 14,
                            color: active ? type.color : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active ? type.color : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Overdue only'),
              subtitle: Text(
                'Show only events past their due date',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              value: _overdueOnly,
              onChanged: (v) => setState(() => _overdueOnly = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            types: _types,
            overdueOnly: _overdueOnly,
          )),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ============================================================================
// Month Tab
// ============================================================================

class _MonthTabView extends StatelessWidget {
  final List<CalendarEvent> events;
  final DateTime focusedMonth;
  final DateTime? selectedDay;
  final void Function(DateTime) onMonthChanged;
  final void Function(DateTime) onDaySelected;

  const _MonthTabView({
    required this.events,
    required this.focusedMonth,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final dayEvents = selectedDay == null
        ? <CalendarEvent>[]
        : events.where((e) => e.isOnDay(selectedDay!)).toList();

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 680;

      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 340,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: _buildCalendarPanel(context),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildDayEventsPanelWide(context, dayEvents)),
          ],
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCalendarPanel(context),
            const Divider(height: 24),
            _buildDayEventsNarrow(context, dayEvents),
          ],
        ),
      );
    });
  }

  Widget _buildCalendarPanel(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final daysInMonth =
        DateUtils.getDaysInMonth(focusedMonth.year, focusedMonth.month);
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final leadingBlanks = (firstDay.weekday - 1) % 7;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final today = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month navigation
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month - 1, 1)),
            ),
            Expanded(
              child: Center(
                child: Text(
                  DateFormat('MMMM yyyy').format(focusedMonth),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month + 1, 1)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Day of week headers
        Row(
          children: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        // Day grid rows
        for (int row = 0; row < rows; row++)
          Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final day = cellIndex - leadingBlanks + 1;
              if (day < 1 || day > daysInMonth) {
                return const Expanded(child: SizedBox(height: 52));
              }
              final date =
                  DateTime(focusedMonth.year, focusedMonth.month, day);
              final dayEvts =
                  events.where((e) => e.isOnDay(date)).toList();
              final isToday = DateUtils.isSameDay(date, today);
              final isSelected = selectedDay != null &&
                  DateUtils.isSameDay(date, selectedDay!);
              final dotColors =
                  dayEvts.map((e) => e.type.color).toSet().take(3).toList();

              return Expanded(
                child: GestureDetector(
                  onTap: () => onDaySelected(date),
                  child: Container(
                    height: 52,
                    margin: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primary.withValues(alpha: 0.14)
                          : null,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: isToday
                          ? Border.all(color: primary, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: (isToday || isSelected)
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isToday ? primary : null,
                          ),
                        ),
                        if (dotColors.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: dotColors
                                  .map((c) => Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 1),
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildDayEventsPanelWide(
      BuildContext context, List<CalendarEvent> dayEvents) {
    final theme = Theme.of(context);

    if (selectedDay == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 48,
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(
              'Select a day to see events',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, MMMM d').format(selectedDay!),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${dayEvents.length} event${dayEvents.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        if (dayEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Text(
              'No events on this day.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.45)),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              itemCount: dayEvents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) =>
                  _EventTile(event: dayEvents[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildDayEventsNarrow(
      BuildContext context, List<CalendarEvent> dayEvents) {
    final theme = Theme.of(context);

    if (selectedDay == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
          child: Text(
            'Tap a day to see events',
            style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.45)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            DateFormat('EEEE, MMMM d').format(selectedDay!),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (dayEvents.isEmpty)
          Text(
            'No events on this day.',
            style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.45)),
          )
        else
          ...dayEvents.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _EventTile(event: e),
              )),
      ],
    );
  }
}

// ============================================================================
// Agenda Tab
// ============================================================================

class _AgendaTabView extends StatelessWidget {
  final List<CalendarEvent> events;

  const _AgendaTabView({required this.events});

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<CalendarEvent>>{};
    for (final e in events) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      grouped.putIfAbsent(day, () => []).add(e);
    }
    final days = grouped.keys.toList()..sort();

    if (days.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_outlined,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text('No events to display.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45))),
          ],
        ),
      );
    }

    final today = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final dayEvents = grouped[day]!;
        final isToday = day == today;
        final isPast = day.isBefore(today);
        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                  bottom: 8, top: index == 0 ? 0 : 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: isToday
                          ? theme.colorScheme.primary
                          : isPast
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.08)
                              : theme.colorScheme.primary
                                  .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Text(
                      isToday
                          ? 'Today'
                          : DateFormat('EEEE, MMMM d, yyyy').format(day),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isToday
                            ? Colors.white
                            : isPast
                                ? theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5)
                                : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dayEvents.length} event${dayEvents.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            ...dayEvents.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _EventTile(event: e),
                )),
          ],
        );
      },
    );
  }
}


// ============================================================================
// Shared Event Tile
// ============================================================================

class _EventTile extends StatelessWidget {
  final CalendarEvent event;

  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.type.color;
    final dateStr = DateFormat('MMM d').format(event.date);
    final endStr = event.endDate != null
        ? ' – ${DateFormat('MMM d').format(event.endDate!)}'
        : '';
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _EventDetailsDialog(event: event),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(event.type.icon, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (event.jobNumber != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              event.jobNumber!,
                              style: TextStyle(
                                fontSize: 10,
                                color: color,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            event.title,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (event.jobName != null && event.jobName != event.title)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.folder_outlined,
                                size: 12, color: color),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.jobName!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (event.customerName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 12, color: muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.customerName!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (event.customerAddress != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 12, color: muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.customerAddress!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (event.subtitle != null &&
                        event.customerName == null &&
                        event.customerAddress == null)
                      Text(
                        event.subtitle!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$dateStr$endStr',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: event.isOverdue
                          ? AppColors.error
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.45),
                      fontWeight: event.isOverdue
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      event.type.label,
                      style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Event Details Dialog
// ============================================================================

class _EventDetailsDialog extends StatelessWidget {
  final CalendarEvent event;

  const _EventDetailsDialog({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.type.color;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    final dateStr = event.endDate != null
        ? '${DateFormat('EEE, MMM d, yyyy').format(event.date)} – '
            '${DateFormat('EEE, MMM d, yyyy').format(event.endDate!)}'
        : DateFormat('EEEE, MMMM d, yyyy').format(event.date);

    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: 460, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                border: Border(
                  left: BorderSide(color: color, width: 4),
                  bottom: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.5)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(event.type.icon, color: color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                event.type.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            if (event.jobNumber != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Job ${event.jobNumber}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                            if (event.isOverdue) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'OVERDUE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          event.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(
                      context, Icons.event_outlined, 'Date', dateStr),
                  if (event.jobName != null && event.jobName != event.title)
                    _detailRow(context, Icons.folder_outlined, 'Job',
                        event.jobName!),
                  if (event.status != null && event.status!.isNotEmpty)
                    _detailRow(
                        context,
                        Icons.flag_outlined,
                        'Status',
                        event.status!
                            .replaceAll('_', ' ')
                            .toUpperCase()),
                  if (event.customerName != null)
                    _detailRow(context, Icons.person_outline, 'Customer',
                        event.customerName!),
                  if (event.customerAddress != null)
                    _detailRow(context, Icons.place_outlined, 'Address',
                        event.customerAddress!),
                  if (event.subtitle != null &&
                      event.subtitle != event.customerName &&
                      event.subtitle != event.status)
                    _detailRow(context, Icons.info_outline, 'Note',
                        event.subtitle!),
                  if (event.extraDetails != null)
                    ...event.extraDetails!.entries.map((e) => _detailRow(
                        context, Icons.label_outline, e.key, e.value)),
                ],
                ),
              ),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  if (event.route != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: color),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('View details'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.go(event.route!);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              color: muted.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base, vertical: 6),
              child: Text(
                'Click "View details" to dive into this ${event.type.label.toLowerCase()}.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: muted, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Grid View — responsive card grid sorted by date
// ============================================================================

class _GridTabView extends StatelessWidget {
  final List<CalendarEvent> events;

  const _GridTabView({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const _EmptyEvents();
    final sorted = [...events]..sort((a, b) => a.date.compareTo(b.date));

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = w >= 1400
          ? 4
          : w >= 1000
              ? 3
              : w >= 640
                  ? 2
                  : 1;
      return GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.base),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
        ),
        itemCount: sorted.length,
        itemBuilder: (context, i) => _EventCard(event: sorted[i]),
      );
    });
  }
}

class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.type.color;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final dateStr = DateFormat('MMM d, yyyy').format(event.date);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _EventDetailsDialog(event: event),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(event.type.icon, size: 12, color: color),
                        const SizedBox(width: 4),
                        Text(event.type.label,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ],
                    ),
                  ),
                  if (event.jobNumber != null) ...[
                    const SizedBox(width: 6),
                    Text(event.jobNumber!,
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w700)),
                  ],
                  const Spacer(),
                  if (event.isOverdue)
                    Text('OVERDUE',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.error,
                            fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (event.jobName != null && event.jobName != event.title)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(event.jobName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: color, fontSize: 11)),
                ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 12, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(dateStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 11)),
                  ),
                ],
              ),
              if (event.customerName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(event.customerName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted, fontSize: 11)),
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
}

// ============================================================================
// Kanban View — columns grouped by event type
// ============================================================================

class _KanbanTabView extends StatelessWidget {
  final List<CalendarEvent> events;

  const _KanbanTabView({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const _EmptyEvents();
    final byType = <CalendarEventType, List<CalendarEvent>>{};
    for (final type in CalendarEventType.values) {
      byType[type] = <CalendarEvent>[];
    }
    for (final e in events) {
      byType[e.type]!.add(e);
    }
    for (final list in byType.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }
    final activeTypes = byType.entries
        .where((e) => e.value.isNotEmpty)
        .toList();

    // Each column is height-bounded by the parent viewport and scrolls
    // its own card list vertically so large columns do not overflow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.base),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in activeTypes)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _KanbanColumn(
                  type: entry.key,
                  events: entry.value,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final CalendarEventType type;
  final List<CalendarEvent> events;
  const _KanbanColumn({required this.type, required this.events});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = type.color;
    return SizedBox(
      width: 290,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8)),
              border: Border(
                  top: BorderSide(color: color, width: 3)),
            ),
            child: Row(
              children: [
                Icon(type.icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(type.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: color)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text('${events.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 100),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8)),
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _EventTile(event: events[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Gantt View — horizontal timeline of event date ranges
// ============================================================================

class _GanttTabView extends StatelessWidget {
  final List<CalendarEvent> events;

  const _GanttTabView({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const _EmptyEvents();
    final theme = Theme.of(context);
    final sorted = [...events]..sort((a, b) => a.date.compareTo(b.date));

    final firstDay = DateTime(
        sorted.first.date.year,
        sorted.first.date.month,
        sorted.first.date.day);
    DateTime lastDay = firstDay;
    for (final e in sorted) {
      final end = e.endDate ?? e.date;
      final endDay = DateTime(end.year, end.month, end.day);
      if (endDay.isAfter(lastDay)) lastDay = endDay;
    }
    // Pad a few days on each side for breathing room.
    final timelineStart = firstDay.subtract(const Duration(days: 2));
    final timelineEnd = lastDay.add(const Duration(days: 2));
    final totalDays = timelineEnd.difference(timelineStart).inDays + 1;
    final today = DateUtils.dateOnly(DateTime.now());

    const labelW = 240.0;
    const dayPx = 28.0;
    const rowH = 38.0;
    final timelineW = totalDays * dayPx;

    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: labelW + timelineW + 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: month + day numbers
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: labelW,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, top: 14),
                      child: Text('Event',
                          style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700, color: muted)),
                    ),
                  ),
                  SizedBox(
                    width: timelineW,
                    child: Stack(
                      children: [
                        // Month labels
                        Positioned(
                          top: 4,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              for (int i = 0; i < totalDays; i++)
                                _ganttDayHeader(
                                  context,
                                  timelineStart.add(Duration(days: i)),
                                  i,
                                  totalDays,
                                  dayPx,
                                  today,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final e in sorted)
                      _GanttRow(
                        event: e,
                        timelineStart: timelineStart,
                        totalDays: totalDays,
                        dayPx: dayPx,
                        labelW: labelW,
                        rowH: rowH,
                        today: today,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ganttDayHeader(BuildContext context, DateTime day, int i,
      int totalDays, double dayPx, DateTime today) {
    final theme = Theme.of(context);
    final isFirstOfMonth = day.day == 1 || i == 0;
    final isToday = DateUtils.isSameDay(day, today);
    return SizedBox(
      width: dayPx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isFirstOfMonth)
            Text(DateFormat('MMM yy').format(day),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary))
          else
            const SizedBox(height: 11),
          Text('${day.day}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: isToday
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              )),
        ],
      ),
    );
  }
}

class _GanttRow extends StatelessWidget {
  final CalendarEvent event;
  final DateTime timelineStart;
  final int totalDays;
  final double dayPx;
  final double labelW;
  final double rowH;
  final DateTime today;

  const _GanttRow({
    required this.event,
    required this.timelineStart,
    required this.totalDays,
    required this.dayPx,
    required this.labelW,
    required this.rowH,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.type.color;
    final start = DateUtils.dateOnly(event.date);
    final end = DateUtils.dateOnly(event.endDate ?? event.date);
    final startOffset = start.difference(timelineStart).inDays;
    final span = end.difference(start).inDays + 1;
    final left = startOffset * dayPx;
    final width = (span * dayPx).clamp(8.0, double.infinity);
    final todayOffset = today.difference(timelineStart).inDays;

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => _EventDetailsDialog(event: event),
      ),
      child: SizedBox(
        height: rowH,
        child: Row(
          children: [
            SizedBox(
              width: labelW,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                child: Row(
                  children: [
                    Icon(event.type.icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    if (event.jobNumber != null) ...[
                      Text(event.jobNumber!,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color)),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: totalDays * dayPx,
              child: Stack(
                children: [
                  // Today vertical line
                  if (todayOffset >= 0 && todayOffset < totalDays)
                    Positioned(
                      left: todayOffset * dayPx + dayPx / 2,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.35),
                      ),
                    ),
                  // Event bar
                  Positioned(
                    left: left,
                    top: rowH / 2 - 9,
                    child: Tooltip(
                      message:
                          '${event.title}\n${DateFormat('MMM d').format(start)}'
                          '${event.endDate != null ? ' – ${DateFormat('MMM d').format(end)}' : ''}',
                      child: Container(
                        width: width,
                        height: 18,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: event.isOverdue
                              ? Border.all(
                                  color: AppColors.error, width: 1.5)
                              : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Empty placeholder
// ============================================================================

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text('No events to display.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.45))),
        ],
      ),
    );
  }
}
