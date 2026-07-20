import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/app_notification.dart';
import '../../models/time_entry.dart';
import '../../models/time_entry_status.dart';
import '../../models/overtime_rules.dart';
import '../../utils/app_logger.dart';
import '../../utils/user_facing_error.dart';
import '../location_service.dart';
import 'automation_service.dart';
import 'budget_service.dart';
import 'notification_service.dart';

/// Supabase implementation of TimeEntryService
class SupabaseTimeEntryService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  /// Get time entries for a specific worker
  Stream<List<TimeEntry>> getTimeEntries(
    String workerId, {
    String? workspaceId,
  }) {
    return _supabase
        .from('time_entries')
        .stream(primaryKey: ['id'])
        .eq('worker_id', workerId)
        .order('date', ascending: false)
        .map((data) {
          var entries = data.map((row) => _toTimeEntry(row)).toList();
          if (workspaceId != null) {
            entries =
                entries.where((e) => e.workspaceId == workspaceId).toList();
          }
          return entries;
        });
  }

  /// Get a single time entry
  Future<TimeEntry?> getTimeEntry(String entryId) async {
    try {
      final response = await _supabase
          .from('time_entries')
          .select()
          .eq('id', entryId)
          .maybeSingle();

      if (response == null) return null;
      return _toTimeEntry(response);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching time entry'),
        cause: e,
      );
    }
  }

  /// Create a new time entry
  Future<TimeEntry> createTimeEntry({
    required String workspaceId,
    required String workerId,
    required String projectId,
    String? taskId,
    String? budgetItemId,
    required DateTime date,
    required DateTime clockIn,
    DateTime? clockOut,
    int breakDuration = 0,
    required double hourlyRate,
    OvertimeRules? overtimeRules,
    String? notes,
    TimeEntryStatus status = TimeEntryStatus.draft,
    double? clockInLatitude,
    double? clockInLongitude,
    double? clockOutLatitude,
    double? clockOutLongitude,
    double? locationAccuracy,
  }) async {
    try {
      final entryId = _uuid.v4();
      final rules = overtimeRules ?? const OvertimeRules();

      // Auto-assign uncategorized labor budget item if none provided
      final resolvedBudgetItemId = budgetItemId ??
          await _getOrCreateUncategorizedLaborItem(projectId, workspaceId);

      TimeEntry entry;
      if (clockOut != null) {
        // Finalized entry with calculations
        entry = TimeEntry.finalize(
          id: entryId,
          workspaceId: workspaceId,
          workerId: workerId,
          projectId: projectId,
          taskId: taskId,
          budgetItemId: resolvedBudgetItemId,
          date: date,
          clockIn: clockIn,
          clockOut: clockOut,
          breakDuration: breakDuration,
          hourlyRate: hourlyRate,
          rules: rules,
          notes: notes,
          status: status,
        );
      } else {
        // Active entry (clocked in, not out yet)
        final now = DateTime.now();
        entry = TimeEntry(
          id: entryId,
          workspaceId: workspaceId,
          workerId: workerId,
          projectId: projectId,
          taskId: taskId,
          budgetItemId: resolvedBudgetItemId,
          date: DateTime(date.year, date.month, date.day),
          clockIn: clockIn,
          clockOut: null,
          breakDuration: breakDuration,
          hourlyRate: hourlyRate,
          notes: notes,
          status: status,
          createdAt: now,
          updatedAt: now,
          clockInLatitude: clockInLatitude,
          clockInLongitude: clockInLongitude,
          clockOutLatitude: clockOutLatitude,
          clockOutLongitude: clockOutLongitude,
          locationAccuracy: locationAccuracy,
        );
      }

      // Validate
      final validationError = entry.validate();
      if (validationError != null) {
        throw Exception(validationError);
      }

      final entryData = _toSupabaseFormat(entry);
      entryData['id'] = entryId;

      await _supabase.from('time_entries').insert(entryData);
      return entry;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'creating time entry'),
        cause: e,
      );
    }
  }

  /// Update an existing time entry
  Future<void> updateTimeEntry(
    String entryId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final supabaseUpdates = <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Convert camelCase to snake_case
      updates.forEach((key, value) {
        final snakeKey = _camelToSnake(key);
        if (value is DateTime) {
          supabaseUpdates[snakeKey] = value.toUtc().toIso8601String();
        } else if (value is TimeEntryStatus) {
          supabaseUpdates[snakeKey] = value.toJson();
        } else {
          supabaseUpdates[snakeKey] = value;
        }
      });

      await _supabase
          .from('time_entries')
          .update(supabaseUpdates)
          .eq('id', entryId);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating time entry'),
        cause: e,
      );
    }
  }

  /// Delete a time entry (only if status = draft)
  Future<void> deleteTimeEntry(String entryId) async {
    try {
      final entry = await getTimeEntry(entryId);
      if (entry == null) {
        throw Exception('Time entry not found');
      }

      if (entry.status != TimeEntryStatus.draft) {
        throw Exception(
          'Can only delete draft entries. Current status: ${entry.status.displayName}',
        );
      }

      await _supabase.from('time_entries').delete().eq('id', entryId);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'deleting time entry'),
        cause: e,
      );
    }
  }

  /// Clock in - create a new active time entry with GPS location
  Future<TimeEntry> clockIn({
    required String workspaceId,
    required String workerId,
    required String projectId,
    String? taskId,
    String? budgetItemId,
    required double hourlyRate,
    String? notes,
    Position? location, // Optional pre-fetched location
  }) async {
    try {
      // Auto clock out any existing active entries for this worker
      final activeEntry = await getActiveEntry(workerId, workspaceId);
      if (activeEntry != null) {
        await clockOut(
          activeEntry.id,
          breakDuration: 0, // Default no break for auto clock-out
        );
      }

      // Get location if not provided
      Position? clockInLocation = location;
      if (clockInLocation == null) {
        final locationService = LocationService();
        if (await locationService.hasPermission()) {
          clockInLocation = await locationService.getCurrentPosition();
        }
      }

      // Create new active entry with location
      return await createTimeEntry(
        workspaceId: workspaceId,
        workerId: workerId,
        projectId: projectId,
        taskId: taskId,
        budgetItemId: budgetItemId,
        date: DateTime.now(),
        clockIn: DateTime.now(),
        clockOut: null, // Active entry
        hourlyRate: hourlyRate,
        notes: notes,
        clockInLatitude: clockInLocation?.latitude,
        clockInLongitude: clockInLocation?.longitude,
        locationAccuracy: clockInLocation?.accuracy,
      );
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'clocking in'),
        cause: e,
      );
    }
  }

  /// Clock out - finalize an active time entry with GPS location
  /// Sum of a worker's `regular_hours` already logged earlier in the same
  /// (Monday-start) workweek as [clockIn], excluding [excludeEntryId]. Used by
  /// the opt-in weekly-overtime rule. [E2]
  Future<double> _priorWeekRegularHours({
    required String workerId,
    required String workspaceId,
    required DateTime clockIn,
    required String excludeEntryId,
  }) async {
    final day = DateTime(clockIn.year, clockIn.month, clockIn.day);
    final weekStart = day.subtract(Duration(days: day.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final rows = await _supabase
        .from('time_entries')
        .select('id, regular_hours')
        .eq('worker_id', workerId)
        .eq('workspace_id', workspaceId)
        .gte('clock_in', weekStart.toUtc().toIso8601String())
        .lt('clock_in', weekEnd.toUtc().toIso8601String());
    var sum = 0.0;
    for (final r in rows as List) {
      if (r['id'] == excludeEntryId) continue;
      sum += (r['regular_hours'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  Future<void> clockOut(
    String entryId, {
    required int breakDuration,
    OvertimeRules? overtimeRules,
    Position? location, // Optional pre-fetched location
  }) async {
    try {
      final entry = await getTimeEntry(entryId);
      if (entry == null) {
        throw Exception('Time entry not found');
      }

      if (entry.clockOut != null) {
        throw Exception('Already clocked out');
      }

      final clockOut = DateTime.now();
      final rules = overtimeRules ?? const OvertimeRules();

      // Get location if not provided
      Position? clockOutLocation = location;
      if (clockOutLocation == null) {
        final locationService = LocationService();
        if (await locationService.hasPermission()) {
          clockOutLocation = await locationService.getCurrentPosition();
        }
      }

      // Calculate everything
      final totalDuration = TimeEntry.calculateDuration(
        entry.clockIn,
        clockOut,
        breakDuration,
      );

      final hoursBreakdown = TimeEntry.calculateHoursBreakdown(
        totalDuration,
        rules,
      );

      // Weekly OT (opt-in): convert this entry's regular hours over the 40h
      // weekly line into overtime, using the worker's regular hours already
      // logged earlier this workweek. Daily OT/DT above is untouched. [E2]
      var regularHours = hoursBreakdown.regular;
      var overtimeHours = hoursBreakdown.overtime;
      if (rules.applyWeeklyOvertime) {
        final priorRegular = await _priorWeekRegularHours(
          workerId: entry.workerId,
          workspaceId: entry.workspaceId,
          clockIn: entry.clockIn,
          excludeEntryId: entryId,
        );
        final adj = rules.applyWeeklyToEntry(regularHours, priorRegular);
        regularHours = adj.regular;
        overtimeHours += adj.extraOvertime;
      }

      final costs = TimeEntry.calculateCosts(
        regularHours: regularHours,
        overtimeHours: overtimeHours,
        doubleTimeHours: hoursBreakdown.doubleTime,
        hourlyRate: entry.hourlyRate,
        rules: rules,
      );

      // Update entry with calculations and location
      await _supabase.from('time_entries').update({
        'clock_out': clockOut.toUtc().toIso8601String(),
        'break_duration': breakDuration,
        'total_duration': totalDuration,
        'regular_hours': regularHours,
        'overtime_hours': overtimeHours,
        'double_time_hours': hoursBreakdown.doubleTime,
        'regular_cost': costs.regularCost,
        'overtime_cost': costs.overtimeCost,
        'double_time_cost': costs.doubleTimeCost,
        'total_cost': costs.totalCost,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'clock_out_latitude': clockOutLocation?.latitude,
        'clock_out_longitude': clockOutLocation?.longitude,
      }).eq('id', entryId);

      // Fire-and-forget automations (e.g. "remind crew to file a daily log
      // after clock-out"); _processEvent logs its own failures.
      unawaited(SupabaseAutomationService().processTimeEntryClockedOut(
        workspaceId: entry.workspaceId,
        timeEntryId: entryId,
        workerId: entry.workerId,
        projectId: entry.projectId,
        taskId: entry.taskId,
        actorUserId:
            Supabase.instance.client.auth.currentUser?.id ?? entry.workerId,
      ));
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'clocking out'),
        cause: e,
      );
    }
  }

  /// Get active entry for a worker (clockOut = null)
  Future<TimeEntry?> getActiveEntry(String workerId, String workspaceId) async {
    try {
      final response = await _supabase
          .from('time_entries')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('worker_id', workerId)
          .isFilter('clock_out', null)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return _toTimeEntry(response);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching active entry'),
        cause: e,
      );
    }
  }

  /// Submit time entry for approval
  Future<void> submitTimeEntry(String entryId) async {
    try {
      final entry = await getTimeEntry(entryId);
      if (entry == null) {
        throw Exception('Time entry not found');
      }

      if (entry.clockOut == null) {
        throw Exception(
          'Cannot submit incomplete entry. Please clock out first.',
        );
      }

      if (!entry.canEdit) {
        throw Exception('Entry cannot be edited');
      }

      await _supabase.from('time_entries').update({
        'status': TimeEntryStatus.submitted.toJson(),
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', entryId);

      await _notifyApproversOfSubmittedTimeEntry(entry);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'submitting time entry'),
        cause: e,
      );
    }
  }

  Future<void> _notifyApproversOfSubmittedTimeEntry(TimeEntry entry) async {
    try {
      final approvers = await _supabase
          .from('workspace_members')
          .select('user_id')
          .eq('workspace_id', entry.workspaceId)
          .inFilter('role', const ['admin', 'project_manager']);

      final recipientIds = approvers
          .map((row) => row['user_id'] as String?)
          .whereType<String>()
          .where((userId) => userId != entry.workerId)
          .toSet()
          .toList();

      if (recipientIds.isEmpty) {
        return;
      }

      final workerRow = await _supabase
          .from('users')
          .select('display_name, email')
          .eq('id', entry.workerId)
          .maybeSingle();
      final workerName =
          (workerRow?['display_name'] as String?)?.trim().isNotEmpty == true
              ? (workerRow!['display_name'] as String).trim()
              : ((workerRow?['email'] as String?)?.trim().isNotEmpty == true
                  ? (workerRow!['email'] as String).trim()
                  : 'A team member');

      final projectRow = await _supabase
          .from('projects')
          .select('name')
          .eq('id', entry.projectId)
          .maybeSingle();
      final projectName = (projectRow?['name'] as String?)?.trim() ?? '';

      final totalHours =
          entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
      final normalizedHours =
          totalHours > 0 ? totalHours : entry.totalDuration / 60.0;
      final dateLabel =
          '${entry.date.month}/${entry.date.day}/${entry.date.year}';
      final body = projectName.isNotEmpty
          ? '${normalizedHours.toStringAsFixed(1)}h on $dateLabel for $projectName.'
          : '${normalizedHours.toStringAsFixed(1)}h on $dateLabel.';

      final notificationService = SupabaseNotificationService();
      for (final recipientId in recipientIds) {
        await notificationService.createNotification(
          userId: recipientId,
          workspaceId: entry.workspaceId,
          type: AppNotificationTypes.timeEntrySubmitted,
          title: '$workerName submitted time for approval',
          body: body,
          metadata: {
            'target_type': 'time_entry',
            'time_entry_id': entry.id,
            'worker_id': entry.workerId,
            'project_id': entry.projectId,
            'tab': 'approvals',
            'deeplink_path': '/time-tracking/approvals',
          },
          dispatchPush: false,
        );
      }
    } catch (e) {
      AppLogger.warning(
        'Failed to create time entry submission notifications',
        metadata: {
          'timeEntryId': entry.id,
          'workspaceId': entry.workspaceId,
          'workerId': entry.workerId,
          'error': e.toString(),
        },
      );
    }
  }

  /// Approve time entry (manager only)
  Future<void> approveTimeEntry(String entryId, String managerId) async {
    try {
      final entry = await getTimeEntry(entryId);
      if (entry == null) {
        throw Exception('Time entry not found');
      }

      if (entry.status != TimeEntryStatus.submitted) {
        throw Exception('Can only approve submitted entries');
      }

      await _supabase.from('time_entries').update({
        'status': TimeEntryStatus.approved.toJson(),
        'approved_by': managerId,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', entryId);

      await _notifyWorkerOfTimeEntryDecision(
        entry: entry,
        managerId: managerId,
        type: AppNotificationTypes.timeEntryApproved,
        title: 'Your time entry was approved',
      );

      // Clear budget service cost cache for the linked budget item
      if (entry.budgetItemId != null) {
        try {
          SupabaseBudgetService().clearCostCache();
        } catch (_) {
          // Non-critical: cache will expire naturally
        }
      }
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'approving time entry'),
        cause: e,
      );
    }
  }

  /// Reject time entry (manager only)
  Future<void> rejectTimeEntry(
    String entryId,
    String managerId,
    String reason,
  ) async {
    try {
      final entry = await getTimeEntry(entryId);
      if (entry == null) {
        throw Exception('Time entry not found');
      }

      if (entry.status != TimeEntryStatus.submitted) {
        throw Exception('Can only reject submitted entries');
      }

      await _supabase.from('time_entries').update({
        'status': TimeEntryStatus.rejected.toJson(),
        'rejection_reason': reason,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', entryId);

      await _notifyWorkerOfTimeEntryDecision(
        entry: entry,
        managerId: managerId,
        type: AppNotificationTypes.timeEntryRejected,
        title: 'Your time entry was rejected',
        rejectionReason: reason,
      );
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'rejecting time entry'),
        cause: e,
      );
    }
  }

  /// Bulk approve multiple entries
  Future<void> bulkApprove(List<String> entryIds, String managerId) async {
    for (final entryId in entryIds) {
      try {
        await approveTimeEntry(entryId, managerId);
      } catch (e) {
        // Continue with other entries
      }
    }
  }

  Future<void> _notifyWorkerOfTimeEntryDecision({
    required TimeEntry entry,
    required String managerId,
    required String type,
    required String title,
    String? rejectionReason,
  }) async {
    try {
      if (entry.workerId == managerId) {
        return;
      }

      final projectRow = await _supabase
          .from('projects')
          .select('name')
          .eq('id', entry.projectId)
          .maybeSingle();
      final projectName = (projectRow?['name'] as String?)?.trim() ?? '';

      final totalHours =
          entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
      final normalizedHours =
          totalHours > 0 ? totalHours : entry.totalDuration / 60.0;
      final dateLabel =
          '${entry.date.month}/${entry.date.day}/${entry.date.year}';
      final baseBody = projectName.isNotEmpty
          ? '${normalizedHours.toStringAsFixed(1)}h on $dateLabel for $projectName.'
          : '${normalizedHours.toStringAsFixed(1)}h on $dateLabel.';
      final trimmedReason = rejectionReason?.trim();
      final body = trimmedReason != null && trimmedReason.isNotEmpty
          ? '$baseBody Reason: $trimmedReason'
          : baseBody;

      final notificationService = SupabaseNotificationService();
      await notificationService.createNotification(
        userId: entry.workerId,
        workspaceId: entry.workspaceId,
        type: type,
        title: title,
        body: body,
        metadata: {
          'target_type': 'time_entry',
          'time_entry_id': entry.id,
          'worker_id': entry.workerId,
          'project_id': entry.projectId,
          'tab': 'timesheet',
          'deeplink_path': '/time-tracking/timesheet',
        },
        dispatchPush: false,
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to create time entry decision notification',
        metadata: {
          'timeEntryId': entry.id,
          'workspaceId': entry.workspaceId,
          'workerId': entry.workerId,
          'managerId': managerId,
          'type': type,
          'error': e.toString(),
        },
      );
    }
  }

  /// Get time entries for a specific project
  Stream<List<TimeEntry>> getTimeEntriesForProject(
    String projectId, {
    String? workspaceId,
  }) {
    return _supabase
        .from('time_entries')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('date', ascending: false)
        .map((data) {
          var entries = data.map((row) => _toTimeEntry(row)).toList();
          if (workspaceId != null) {
            entries =
                entries.where((e) => e.workspaceId == workspaceId).toList();
          }
          return entries;
        });
  }

  /// Get time entries for a specific task
  Stream<List<TimeEntry>> getTimeEntriesForTask(
    String taskId, {
    String? workspaceId,
  }) {
    return _supabase
        .from('time_entries')
        .stream(primaryKey: ['id'])
        .eq('task_id', taskId)
        .order('date', ascending: false)
        .map((data) {
          var entries = data.map((row) => _toTimeEntry(row)).toList();
          if (workspaceId != null) {
            entries =
                entries.where((e) => e.workspaceId == workspaceId).toList();
          }
          return entries;
        });
  }

  /// Get time entries for a date range
  Stream<List<TimeEntry>> getTimeEntriesForDateRange(
    String workerId,
    DateTime startDate,
    DateTime endDate, {
    String? workspaceId,
  }) {
    return _supabase
        .from('time_entries')
        .stream(primaryKey: ['id'])
        .eq('worker_id', workerId)
        .order('date', ascending: false)
        .map((data) {
          return data.map((row) => _toTimeEntry(row)).where((entry) {
            if (workspaceId != null && entry.workspaceId != workspaceId) {
              return false;
            }
            return entry.date.isAfter(
                  startDate.subtract(const Duration(days: 1)),
                ) &&
                entry.date.isBefore(endDate.add(const Duration(days: 1)));
          }).toList();
        });
  }

  /// Get time entries for a date range (one-time)
  Future<List<TimeEntry>> getTimeEntriesForDateRangeOnce(
    String workerId,
    DateTime startDate,
    DateTime endDate, {
    String? workspaceId,
  }) async {
    try {
      var query = _supabase
          .from('time_entries')
          .select()
          .eq('worker_id', workerId)
          .gte('date', startDate.toIso8601String())
          .lte('date', endDate.toIso8601String());

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query.order('date', ascending: false);
      return response.map((row) => _toTimeEntry(row)).toList();
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching time entries'),
        cause: e,
      );
    }
  }

  /// Get pending time entries (submitted, awaiting approval)
  Stream<List<TimeEntry>> getPendingTimeEntries(String workspaceId) {
    return _supabase
        .from('time_entries')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('submitted_at', ascending: true)
        .map((data) {
          return data
              .where(
                (row) => row['status'] == TimeEntryStatus.submitted.toJson(),
              )
              .map((row) => _toTimeEntry(row))
              .toList();
        });
  }

  /// Get approved time entries for payroll export
  Future<List<TimeEntry>> getTimeEntriesForPayroll(
    String workspaceId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final response = await _supabase
          .from('time_entries')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('status', TimeEntryStatus.approved.toJson())
          .gte('date', startDate.toIso8601String())
          .lte('date', endDate.toIso8601String())
          .order('date')
          .order('worker_id');

      return response.map((row) => _toTimeEntry(row)).toList();
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching payroll entries'),
        cause: e,
      );
    }
  }

  /// Get all time entries for a workspace in a date range
  Future<List<TimeEntry>> getWorkspaceTimeEntries(
    String workspaceId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final response = await _supabase
          .from('time_entries')
          .select()
          .eq('workspace_id', workspaceId)
          .gte('date', startDate.toIso8601String())
          .lte('date', endDate.toIso8601String())
          .order('date', ascending: false);

      return response.map((row) => _toTimeEntry(row)).toList();
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching workspace time entries'),
        cause: e,
      );
    }
  }

  /// Calculate total hours for a worker in a date range
  Future<
      ({
        double regularHours,
        double overtimeHours,
        double doubleTimeHours,
        double totalCost,
      })> calculateTotalHours(
    String workerId,
    DateTime startDate,
    DateTime endDate, {
    String? workspaceId,
  }) async {
    final entries = await getTimeEntriesForDateRangeOnce(
      workerId,
      startDate,
      endDate,
      workspaceId: workspaceId,
    );

    double totalRegular = 0;
    double totalOvertime = 0;
    double totalDoubleTime = 0;
    double totalCost = 0;

    for (final entry in entries) {
      if (entry.status == TimeEntryStatus.approved) {
        totalRegular += entry.regularHours;
        totalOvertime += entry.overtimeHours;
        totalDoubleTime += entry.doubleTimeHours;
        totalCost += entry.totalCost;
      }
    }

    return (
      regularHours: totalRegular,
      overtimeHours: totalOvertime,
      doubleTimeHours: totalDoubleTime,
      totalCost: totalCost,
    );
  }

  /// Get or create the default "Uncategorized Labor" budget item for a project.
  Future<String?> _getOrCreateUncategorizedLaborItem(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = await _supabase.rpc(
        'get_or_create_uncategorized_labor_item',
        params: {
          'p_project_id': projectId,
          'p_workspace_id': workspaceId,
        },
      );
      return result as String?;
    } catch (e) {
      AppLogger.warning(
        'Failed to get/create uncategorized labor item, continuing without',
        metadata: {
          'projectId': projectId,
          'error': e.toString(),
        },
      );
      return null;
    }
  }

  /// Convert database row to TimeEntry
  TimeEntry _toTimeEntry(Map<String, dynamic> row) {
    return TimeEntry.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to Firestore camelCase format
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'workerId': row['worker_id'],
      'projectId': row['project_id'],
      'taskId': row['task_id'],
      'budgetItemId': row['budget_item_id'],
      'date': row['date'] != null
          ? _FakeTimestamp(DateTime.parse(row['date']).toLocal())
          : _FakeTimestamp(DateTime.now()),
      'clockIn': row['clock_in'] != null
          ? _FakeTimestamp(DateTime.parse(row['clock_in']).toLocal())
          : _FakeTimestamp(DateTime.now()),
      'clockOut': row['clock_out'] != null
          ? _FakeTimestamp(DateTime.parse(row['clock_out']).toLocal())
          : null,
      'breakDuration': row['break_duration'] ?? 0,
      'totalDuration': row['total_duration'] ?? 0,
      'regularHours': (row['regular_hours'] as num?)?.toDouble() ?? 0.0,
      'overtimeHours': (row['overtime_hours'] as num?)?.toDouble() ?? 0.0,
      'doubleTimeHours': (row['double_time_hours'] as num?)?.toDouble() ?? 0.0,
      'hourlyRate': (row['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      'regularCost': (row['regular_cost'] as num?)?.toDouble() ?? 0.0,
      'overtimeCost': (row['overtime_cost'] as num?)?.toDouble() ?? 0.0,
      'doubleTimeCost': (row['double_time_cost'] as num?)?.toDouble() ?? 0.0,
      'totalCost': (row['total_cost'] as num?)?.toDouble() ?? 0.0,
      'notes': row['notes'],
      'status': row['status'],
      'submittedAt': row['submitted_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['submitted_at']).toLocal())
          : null,
      'approvedBy': row['approved_by'],
      'approvedAt': row['approved_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['approved_at']).toLocal())
          : null,
      'rejectionReason': row['rejection_reason'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']).toLocal())
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']).toLocal())
          : _FakeTimestamp(DateTime.now()),
      // GPS Location fields
      'clockInLatitude': (row['clock_in_latitude'] as num?)?.toDouble(),
      'clockInLongitude': (row['clock_in_longitude'] as num?)?.toDouble(),
      'clockOutLatitude': (row['clock_out_latitude'] as num?)?.toDouble(),
      'clockOutLongitude': (row['clock_out_longitude'] as num?)?.toDouble(),
      'locationAccuracy': (row['location_accuracy'] as num?)?.toDouble(),
      'distanceFromProject': (row['distance_from_project'] as num?)?.toDouble(),
    };
  }

  /// Convert TimeEntry to Supabase format
  Map<String, dynamic> _toSupabaseFormat(TimeEntry entry) {
    return {
      'workspace_id': entry.workspaceId,
      'worker_id': entry.workerId,
      'project_id': entry.projectId,
      'task_id': entry.taskId,
      'budget_item_id': entry.budgetItemId,
      'date': entry.date.toIso8601String(),
      'clock_in': entry.clockIn.toUtc().toIso8601String(),
      'clock_out': entry.clockOut?.toUtc().toIso8601String(),
      'break_duration': entry.breakDuration,
      'total_duration': entry.totalDuration,
      'regular_hours': entry.regularHours,
      'overtime_hours': entry.overtimeHours,
      'double_time_hours': entry.doubleTimeHours,
      'hourly_rate': entry.hourlyRate,
      'regular_cost': entry.regularCost,
      'overtime_cost': entry.overtimeCost,
      'double_time_cost': entry.doubleTimeCost,
      'total_cost': entry.totalCost,
      'notes': entry.notes,
      'status': entry.status.toJson(),
      'submitted_at': entry.submittedAt?.toUtc().toIso8601String(),
      'approved_by': entry.approvedBy,
      'approved_at': entry.approvedAt?.toUtc().toIso8601String(),
      'rejection_reason': entry.rejectionReason,
      'created_at': entry.createdAt.toUtc().toIso8601String(),
      'updated_at': entry.updatedAt.toUtc().toIso8601String(),
      // GPS Location fields
      'clock_in_latitude': entry.clockInLatitude,
      'clock_in_longitude': entry.clockInLongitude,
      'clock_out_latitude': entry.clockOutLatitude,
      'clock_out_longitude': entry.clockOutLongitude,
      'location_accuracy': entry.locationAccuracy,
      'distance_from_project': entry.distanceFromProject,
    };
  }

  /// Stream all currently active (clocked-in) entries across a workspace.
  ///
  /// Active entries have a clock_in but no clock_out yet. Used by the admin
  /// dashboard to show the live crew list and map.
  Stream<List<TimeEntry>> getActiveTimeEntries(String workspaceId) {
    return _supabase
        .from('time_entries')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('clock_in', ascending: false)
        .map((data) {
          return data
              .map((row) => _toTimeEntry(row))
              .where((e) => e.clockOut == null)
              .toList();
        });
  }

  /// Stream all entries for a workspace within a date range.
  ///
  /// Used by the admin dashboard for week-summary-by-person and KPI totals.
  /// Client-side date filter because Supabase .stream() only supports .eq().
  Stream<List<TimeEntry>> getWorkspaceTimeEntriesForDateRange(
    String workspaceId,
    DateTime startDate,
    DateTime endDate,
  ) {
    return _supabase
        .from('time_entries')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('date', ascending: false)
        .map((data) {
          return data.map((row) => _toTimeEntry(row)).where((entry) {
            return !entry.date.isBefore(
                  DateTime(startDate.year, startDate.month, startDate.day),
                ) &&
                !entry.date.isAfter(
                  DateTime(
                      endDate.year, endDate.month, endDate.day, 23, 59, 59),
                );
          }).toList();
        });
  }

  /// Convert camelCase to snake_case
  String _camelToSnake(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
