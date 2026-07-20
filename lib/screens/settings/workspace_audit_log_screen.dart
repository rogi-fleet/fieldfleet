import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/supabase/settings_audit_service.dart';
import '../../theme/theme.dart';
import '../../utils/app_time_formatter.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class WorkspaceAuditLogScreen extends StatefulWidget {
  const WorkspaceAuditLogScreen({super.key});

  @override
  State<WorkspaceAuditLogScreen> createState() =>
      _WorkspaceAuditLogScreenState();
}

class _WorkspaceAuditLogScreenState extends State<WorkspaceAuditLogScreen> {
  final SupabaseSettingsAuditService _auditService =
      SupabaseSettingsAuditService();

  bool _isLoading = false;
  String? _error;
  String? _nextCursor;
  bool _isLoadingMore = false;
  List<SettingsAuditEvent> _events = [];

  String _selectedEventType = '';
  String _selectedActorUserId = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const List<String> _eventTypes = [
    'workspace.updated',
    'workspace_settings_profile.created',
    'workspace_settings_profile.renamed',
    'workspace_settings_profile.deleted',
    'workspace_settings_profile.applied',
    'workspace_member.added',
    'workspace_member.removed',
    'workspace_member.role_updated',
    'workspace_member.skills_updated',
    'workspace_member.settings_updated',
  ];

  String? _loadedWorkspaceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-run once the workspace hydrates. _loadInitial() from initState
    // captured a null workspace on cold load/refresh and set a permanent
    // "No workspace selected" error with no retry; listen:true re-fires here.
    final wid =
        Provider.of<AuthProvider>(context).appUser?.currentWorkspaceId;
    if (wid != null && wid.isNotEmpty && wid != _loadedWorkspaceId) {
      _loadedWorkspaceId = wid;
      _loadInitial();
    }
  }

  Future<void> _loadInitial() async {
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      setState(() {
        _error = 'No workspace selected';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final page = await _auditService.getEvents(
        workspaceId: workspaceId,
        actorUserId: _selectedActorUserId.isEmpty ? null : _selectedActorUserId,
        eventType: _selectedEventType.isEmpty ? null : _selectedEventType,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _events = page.events;
        _nextCursor = page.nextCursor;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load audit events: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId == null || workspaceId.isEmpty || _nextCursor == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final page = await _auditService.getEvents(
        workspaceId: workspaceId,
        actorUserId: _selectedActorUserId.isEmpty ? null : _selectedActorUserId,
        eventType: _selectedEventType.isEmpty ? null : _selectedEventType,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        beforeCreatedAt: _nextCursor,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _events.addAll(page.events);
        _nextCursor = page.nextCursor;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load more: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initialDate = isFrom ? (_dateFrom ?? now) : (_dateTo ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = DateTime(picked.year, picked.month, picked.day);
      } else {
        _dateTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
    await _loadInitial();
  }

  Map<String, String> _actorOptions() {
    final options = <String, String>{};
    for (final event in _events) {
      options[event.actorUserId] = event.actorDisplayName;
    }
    return options;
  }

  void _showEventDetails(SettingsAuditEvent event) {
    final timezone = context.read<WorkspaceProvider>().timezone;
    final beforeJson = event.beforeData == null
        ? 'null'
        : const JsonEncoder.withIndent('  ').convert(event.beforeData);
    final afterJson = event.afterData == null
        ? 'null'
        : const JsonEncoder.withIndent('  ').convert(event.afterData);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.eventType),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('Actor: ${event.actorDisplayName}'),
                SelectableText('Target: ${event.targetType}:${event.targetId}'),
                SelectableText(
                  'At: ${AppTimeFormatter.formatDateTime(event.createdAt, timezone: timezone)}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Before',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  beforeJson,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'After',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  afterJson,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceTimezone = context.watch<WorkspaceProvider>().timezone;
    final canView =
        authProvider.canManageUsers || authProvider.canAccessSettings;

    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audit Log')),
        body: const Center(
          child: Text(
            'You do not have permission to view the workspace audit log.',
          ),
        ),
      );
    }

    final actorOptions = _actorOptions();

    return Scaffold(
      appBar: AppBar(title: const Text('Workspace Audit Log')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: StackedField(
                    label: 'Event Type',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: _selectedEventType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All events'),
                        ),
                        ..._eventTypes.map(
                          (eventType) => DropdownMenuItem<String>(
                            value: eventType,
                            child: Text(eventType),
                          ),
                        ),
                      ],
                      onChanged: (value) async {
                        setState(() {
                          _selectedEventType = value ?? '';
                        });
                        await _loadInitial();
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: StackedField(
                    label: 'Actor',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: _selectedActorUserId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All actors'),
                        ),
                        ...actorOptions.entries.map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        ),
                      ],
                      onChanged: (value) async {
                        setState(() {
                          _selectedActorUserId = value ?? '';
                        });
                        await _loadInitial();
                      },
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: true),
                  icon: const Icon(Icons.event),
                  label: Text(
                    _dateFrom == null
                        ? 'From'
                        : DateFormat('yyyy-MM-dd').format(_dateFrom!),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: false),
                  icon: const Icon(Icons.event_available),
                  label: Text(
                    _dateTo == null
                        ? 'To'
                        : DateFormat('yyyy-MM-dd').format(_dateTo!),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      _selectedEventType = '';
                      _selectedActorUserId = '';
                      _dateFrom = null;
                      _dateTo = null;
                    });
                    await _loadInitial();
                  },
                  child: const Text('Clear Filters'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: SelectableText(_error!))
                : _events.isEmpty
                ? const Center(child: Text('No audit events found'))
                : ListView.separated(
                    itemCount: _events.length + (_nextCursor != null ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == _events.length) {
                        return ListTile(
                          title: Center(
                            child: _isLoadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: _loadMore,
                                    child: const Text('Load More'),
                                  ),
                          ),
                        );
                      }

                      final event = _events[index];
                      return ListTile(
                        title: Text(event.eventType),
                        subtitle: Text(
                          '${event.actorDisplayName} • ${event.targetType}:${event.targetId} • ${AppTimeFormatter.formatDateTime(event.createdAt, timezone: workspaceTimezone)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showEventDetails(event),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
