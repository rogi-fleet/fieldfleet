import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/capacity_planning.dart';

class SupabaseCapacityPlanningService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<CapacitySnapshot> getCapacitySnapshot({
    required String workspaceId,
    required DateTime start,
    required DateTime end,
    String? projectId,
    String? memberId,
  }) async {
    final startDate = _dayOnly(start);
    final endDate = _dayOnly(end);
    final days = _daysInRange(startDate, endDate);

    final workspace = await _supabase
        .from('workspaces')
        .select('show_business_days_only, default_weekly_capacity_hours')
        .eq('id', workspaceId)
        .maybeSingle();

    final showBusinessDaysOnly =
        workspace?['show_business_days_only'] as bool? ?? false;
    final workspaceWeeklyCapacity =
        (workspace?['default_weekly_capacity_hours'] as num?)?.toDouble() ??
        40.0;

    var memberRows = await _supabase
        .from('workspace_members')
        .select('user_id, weekly_capacity_hours, module_permissions')
        .eq('workspace_id', workspaceId);

    if (memberId != null && memberId.isNotEmpty) {
      memberRows = memberRows
          .where((row) => row['user_id'] == memberId)
          .toList();
    }

    final userIds = memberRows
        .map((row) => row['user_id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();

    if (userIds.isEmpty) {
      return CapacitySnapshot(
        start: startDate,
        end: endDate,
        members: const [],
        issues: const [],
      );
    }

    final users = await _supabase
        .from('users')
        .select('id, display_name, email')
        .inFilter('id', userIds);
    final usersById = <String, Map<String, dynamic>>{
      for (final row in users) row['id'] as String: row,
    };

    final exceptions = await _supabase
        .from('workspace_member_capacity_exceptions')
        .select()
        .eq('workspace_id', workspaceId)
        .lte('start_date', endDate.toIso8601String().split('T').first)
        .gte('end_date', startDate.toIso8601String().split('T').first);

    final exceptionsByUser = <String, List<MemberCapacityException>>{};
    for (final row in exceptions) {
      final ex = MemberCapacityException.fromRow(row);
      exceptionsByUser.putIfAbsent(ex.userId, () => []).add(ex);
    }

    var taskRows = await _supabase
        .from('tasks')
        .select(
          'id, title, project_id, is_complete, estimated_duration, start_date, due_date, assigned_to_ids',
        )
        .eq('workspace_id', workspaceId);
    if (projectId != null && projectId.isNotEmpty) {
      taskRows = taskRows
          .where((row) => row['project_id'] == projectId)
          .toList();
    }

    var timeRows = await _supabase
        .from('time_entries')
        .select(
          'worker_id, project_id, date, regular_hours, overtime_hours, double_time_hours, status',
        )
        .eq('workspace_id', workspaceId)
        .eq('status', 'approved')
        .gte('date', startDate.toIso8601String())
        .lte('date', endDate.toIso8601String());

    if (projectId != null && projectId.isNotEmpty) {
      timeRows = timeRows
          .where((row) => row['project_id'] == projectId)
          .toList();
    }
    if (memberId != null && memberId.isNotEmpty) {
      timeRows = timeRows.where((row) => row['worker_id'] == memberId).toList();
    }

    final plannedByUserAndDay = <String, Map<String, double>>{};
    for (final row in taskRows) {
      final isComplete = row['is_complete'] as bool? ?? false;
      if (isComplete) continue;

      final assigneesRaw = row['assigned_to_ids'];
      if (assigneesRaw is! List || assigneesRaw.isEmpty) continue;
      final assignees = assigneesRaw
          .cast<String>()
          .where((id) => id.isNotEmpty)
          .toList();
      if (assignees.isEmpty) continue;
      if (memberId != null &&
          memberId.isNotEmpty &&
          !assignees.contains(memberId)) {
        continue;
      }

      final taskStart = _parseDateOrNull(row['start_date']);
      final taskDue = _parseDateOrNull(row['due_date']);
      final normalized = _normalizeTaskRange(taskStart, taskDue);
      final rangeDays = _daysInRange(
        normalized.$1,
        normalized.$2,
      ).where((d) => !showBusinessDaysOnly || _isBusinessDay(d)).toList();
      final activeDays = rangeDays.isNotEmpty ? rangeDays : [normalized.$1];

      final estimated = (row['estimated_duration'] as num?)?.toDouble();
      final taskHours =
          estimated ??
          _estimateFallbackHours(
            normalized.$1,
            normalized.$2,
            showBusinessDaysOnly,
          );
      final perAssigneePerDay =
          taskHours / assignees.length / activeDays.length;

      for (final assignee in assignees) {
        final userMap = plannedByUserAndDay.putIfAbsent(assignee, () => {});
        for (final day in activeDays) {
          if (day.isBefore(startDate) || day.isAfter(endDate)) continue;
          final key = _dayKey(day);
          userMap[key] = (userMap[key] ?? 0.0) + perAssigneePerDay;
        }
      }
    }

    final actualByUserAndDay = <String, Map<String, double>>{};
    for (final row in timeRows) {
      final userId = row['worker_id'] as String?;
      if (userId == null || userId.isEmpty) continue;
      final day = _dayOnly(DateTime.parse(row['date'] as String));
      final key = _dayKey(day);
      final hours =
          ((row['regular_hours'] as num?)?.toDouble() ?? 0.0) +
          ((row['overtime_hours'] as num?)?.toDouble() ?? 0.0) +
          ((row['double_time_hours'] as num?)?.toDouble() ?? 0.0);
      final userMap = actualByUserAndDay.putIfAbsent(userId, () => {});
      userMap[key] = (userMap[key] ?? 0.0) + hours;
    }

    final rows = <CapacityMemberRow>[];
    final issues = <CapacityIssue>[];

    for (final member in memberRows) {
      final userId = member['user_id'] as String;
      final user = usersById[userId];
      final displayName =
          (user?['display_name'] as String?) ??
          (user?['email'] as String?) ??
          userId;
      final weeklyCapacity =
          (member['weekly_capacity_hours'] as num?)?.toDouble() ??
          workspaceWeeklyCapacity;
      final dailyBaseCapacity =
          weeklyCapacity / (showBusinessDaysOnly ? 5.0 : 7.0);

      final dayCells = <CapacityDayCell>[];
      double totalPlanned = 0;
      double totalActual = 0;
      double totalCommitted = 0;
      double totalCapacity = 0;

      for (final day in days) {
        final key = _dayKey(day);
        final planned = plannedByUserAndDay[userId]?[key] ?? 0.0;
        final actual = actualByUserAndDay[userId]?[key] ?? 0.0;
        final committed = planned + actual;
        var capacity = showBusinessDaysOnly && !_isBusinessDay(day)
            ? 0.0
            : dailyBaseCapacity;

        final userExceptions = exceptionsByUser[userId] ?? const [];
        for (final ex in userExceptions) {
          if (!_isWithin(day, ex.startDate, ex.endDate)) continue;
          capacity *= ex.capacityMultiplier;
        }

        final utilization = capacity <= 0
            ? (committed > 0 ? 1.0 : 0.0)
            : committed / capacity;

        dayCells.add(
          CapacityDayCell(
            date: day,
            plannedHours: planned,
            actualHours: actual,
            committedHours: committed,
            capacityHours: capacity,
            utilizationPct: utilization,
          ),
        );

        if (utilization > 1.0) {
          issues.add(
            CapacityIssue(
              userId: userId,
              displayName: displayName,
              date: day,
              issueType: 'over_capacity',
              committedHours: committed,
              capacityHours: capacity,
              utilizationPct: utilization,
            ),
          );
        } else if (utilization >= 0.9) {
          issues.add(
            CapacityIssue(
              userId: userId,
              displayName: displayName,
              date: day,
              issueType: 'high_risk',
              committedHours: committed,
              capacityHours: capacity,
              utilizationPct: utilization,
            ),
          );
        }

        totalPlanned += planned;
        totalActual += actual;
        totalCommitted += committed;
        totalCapacity += capacity;
      }

      rows.add(
        CapacityMemberRow(
          userId: userId,
          displayName: displayName,
          days: dayCells,
          totalPlannedHours: totalPlanned,
          totalActualHours: totalActual,
          totalCommittedHours: totalCommitted,
          totalCapacityHours: totalCapacity,
          utilizationPct: totalCapacity <= 0
              ? 0
              : totalCommitted / totalCapacity,
        ),
      );
    }

    rows.sort((a, b) => b.utilizationPct.compareTo(a.utilizationPct));
    issues.sort((a, b) {
      final util = b.utilizationPct.compareTo(a.utilizationPct);
      if (util != 0) return util;
      return a.date.compareTo(b.date);
    });

    return CapacitySnapshot(
      start: startDate,
      end: endDate,
      members: rows,
      issues: issues,
    );
  }

  Future<List<CapacityIssue>> getCapacityIssues({
    required String workspaceId,
    required DateTime start,
    required DateTime end,
    String? projectId,
    String? memberId,
  }) async {
    final snapshot = await getCapacitySnapshot(
      workspaceId: workspaceId,
      start: start,
      end: end,
      projectId: projectId,
      memberId: memberId,
    );
    return snapshot.issues;
  }

  Future<void> reassignTask({
    required String taskId,
    required List<String> assigneeIds,
  }) async {
    final cleaned = assigneeIds.where((id) => id.isNotEmpty).toList();
    await _supabase
        .from('tasks')
        .update({
          'assigned_to_ids': cleaned,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', taskId);
  }

  Future<void> shiftTask({
    required String taskId,
    required DateTime newStart,
    required DateTime newDue,
  }) async {
    await _supabase
        .from('tasks')
        .update({
          'start_date': newStart.toIso8601String(),
          'due_date': newDue.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', taskId);
  }

  Future<void> upsertMemberCapacity({
    required String workspaceId,
    required String userId,
    double? weeklyCapacityHours,
  }) async {
    await _supabase
        .from('workspace_members')
        .update({
          'weekly_capacity_hours': weeklyCapacityHours,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId);
  }

  Future<double?> getMemberWeeklyCapacity({
    required String workspaceId,
    required String userId,
  }) async {
    final row = await _supabase
        .from('workspace_members')
        .select('weekly_capacity_hours')
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId)
        .maybeSingle();
    return (row?['weekly_capacity_hours'] as num?)?.toDouble();
  }

  Future<List<MemberCapacityException>> getMemberCapacityExceptions({
    required String workspaceId,
    required String userId,
    DateTime? start,
    DateTime? end,
  }) async {
    var query = _supabase
        .from('workspace_member_capacity_exceptions')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId);

    if (start != null) {
      query = query.gte(
        'end_date',
        _dayOnly(start).toIso8601String().split('T').first,
      );
    }
    if (end != null) {
      query = query.lte(
        'start_date',
        _dayOnly(end).toIso8601String().split('T').first,
      );
    }

    final rows = await query.order('start_date', ascending: true);
    return rows.map((row) => MemberCapacityException.fromRow(row)).toList();
  }

  Future<String> createCapacityException({
    required String workspaceId,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required double capacityMultiplier,
    String? reason,
  }) async {
    final row = await _supabase
        .from('workspace_member_capacity_exceptions')
        .insert({
          'workspace_id': workspaceId,
          'user_id': userId,
          'start_date': _dayOnly(startDate).toIso8601String().split('T').first,
          'end_date': _dayOnly(endDate).toIso8601String().split('T').first,
          'capacity_multiplier': capacityMultiplier,
          'reason': reason,
          'created_by': _supabase.auth.currentUser?.id,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateCapacityException({
    required String exceptionId,
    required DateTime startDate,
    required DateTime endDate,
    required double capacityMultiplier,
    String? reason,
  }) async {
    await _supabase
        .from('workspace_member_capacity_exceptions')
        .update({
          'start_date': _dayOnly(startDate).toIso8601String().split('T').first,
          'end_date': _dayOnly(endDate).toIso8601String().split('T').first,
          'capacity_multiplier': capacityMultiplier,
          'reason': reason,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', exceptionId);
  }

  Future<void> deleteCapacityException(String exceptionId) async {
    await _supabase
        .from('workspace_member_capacity_exceptions')
        .delete()
        .eq('id', exceptionId);
  }

  Future<bool> canExecuteRebalanceActions({
    required String workspaceId,
    required String userId,
  }) async {
    final row = await _supabase
        .from('workspace_members')
        .select('role, module_permissions')
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return false;
    final role = (row['role'] as String?) ?? 'field_technician';
    if (role == 'admin' || role == 'master_admin') return true;

    final permissions = row['module_permissions'] is Map
        ? Map<String, dynamic>.from(row['module_permissions'] as Map)
        : <String, dynamic>{};
    final projects = (permissions['projects'] as String?) ?? 'read';
    final team = (permissions['team'] as String?) ?? 'read';

    return projects == 'write' && team == 'write';
  }

  Future<void> syncCapacityAlerts({
    required String workspaceId,
    required DateTime start,
    required DateTime end,
    String? projectId,
    String? memberId,
  }) async {
    final snapshot = await getCapacitySnapshot(
      workspaceId: workspaceId,
      start: start,
      end: end,
      projectId: projectId,
      memberId: memberId,
    );
    await syncCapacityAlertsFromSnapshot(
      workspaceId: workspaceId,
      snapshot: snapshot,
      projectId: projectId,
    );
  }

  Future<void> syncCapacityAlertsFromSnapshot({
    required String workspaceId,
    required CapacitySnapshot snapshot,
    String? projectId,
  }) async {
    final issues = snapshot.issues.take(30).toList();
    if (issues.isEmpty) return;

    try {
      final members = await _supabase
          .from('workspace_members')
          .select('user_id, role')
          .eq('workspace_id', workspaceId);

      final notifyLeads = members
          .where((m) {
            final role = (m['role'] as String?) ?? '';
            return role == 'admin' ||
                role == 'master_admin' ||
                role == 'project_manager';
          })
          .map((m) => m['user_id'] as String)
          .where((id) => id.isNotEmpty)
          .toSet();

      for (final issue in issues) {
        final recipients = <String>{...notifyLeads, issue.userId};
        final dateKey = _dayKey(issue.date);
        final scope = projectId?.isNotEmpty == true ? projectId! : 'workspace';
        final alertKey = '${issue.issueType}:${issue.userId}:$dateKey:$scope';
        final deepLink = '/team?tab=capacity&memberId=${issue.userId}';
        final isOver = issue.issueType == 'over_capacity';
        final level = isOver ? 'Over capacity' : 'High risk';

        for (final recipientId in recipients) {
          final isSelf = recipientId == issue.userId;
          final title = isSelf
              ? '$level on ${issue.date.month}/${issue.date.day}'
              : '$level: ${issue.displayName} on ${issue.date.month}/${issue.date.day}';
          final body =
              '${issue.committedHours.toStringAsFixed(1)}h committed vs ${issue.capacityHours.toStringAsFixed(1)}h capacity (${(issue.utilizationPct * 100).toStringAsFixed(0)}%)';

          // Dedupe via the unified RPC: the same (recipient, type, alertKey)
          // within a 24h window is suppressed, replacing the prior
          // ad-hoc lookup-then-insert pattern.
          await _supabase.rpc(
            'create_notification',
            params: {
              'p_user_id': recipientId,
              'p_workspace_id': workspaceId,
              'p_type': 'capacity_alert',
              'p_title': title,
              'p_body': body,
              'p_metadata': {
                'alert_key': alertKey,
                'issue_type': issue.issueType,
                'member_id': issue.userId,
                'member_name': issue.displayName,
                'date': dateKey,
                'utilization_pct': issue.utilizationPct,
                'committed_hours': issue.committedHours,
                'capacity_hours': issue.capacityHours,
                'tab': 'capacity',
                'deeplink_path': deepLink,
                if (projectId != null && projectId.isNotEmpty)
                  'project_id': projectId,
              },
              'p_dedupe_key': alertKey,
              'p_dedupe_window_seconds': 24 * 60 * 60,
            },
          );
        }
      }
    } catch (_) {
      // Alerts are best-effort and must not block planner loading.
    }
  }

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _isBusinessDay(DateTime d) =>
      d.weekday != DateTime.saturday && d.weekday != DateTime.sunday;

  static List<DateTime> _daysInRange(DateTime start, DateTime end) {
    final dates = <DateTime>[];
    var cursor = _dayOnly(start);
    final last = _dayOnly(end);
    while (!cursor.isAfter(last)) {
      dates.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return dates;
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static (DateTime, DateTime) _normalizeTaskRange(
    DateTime? start,
    DateTime? due,
  ) {
    final today = _dayOnly(DateTime.now());
    var s = _dayOnly(start ?? due ?? today);
    var e = _dayOnly(due ?? start ?? today);
    if (e.isBefore(s)) {
      final tmp = s;
      s = e;
      e = tmp;
    }
    return (s, e);
  }

  static DateTime? _parseDateOrNull(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static bool _isWithin(DateTime day, DateTime start, DateTime end) {
    final d = _dayOnly(day);
    final s = _dayOnly(start);
    final e = _dayOnly(end);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  static double _estimateFallbackHours(
    DateTime start,
    DateTime end,
    bool businessDaysOnly,
  ) {
    if (start == end) return 8;
    final days = _daysInRange(
      start,
      end,
    ).where((d) => !businessDaysOnly || _isBusinessDay(d)).length;
    if (days <= 0) return 8;
    return days * 8.0;
  }
}
