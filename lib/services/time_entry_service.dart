import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../models/time_entry.dart';
import '../models/time_entry_status.dart';
import '../models/overtime_rules.dart';
import '../utils/app_logger.dart';
import '../utils/user_facing_error.dart';
import 'location_service.dart';

class TimeEntryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  // Get time entries for a specific worker
  Stream<List<TimeEntry>> getTimeEntries(
    String workerId, {
    String? workspaceId,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('time_entries')
        .where('workerId', isEqualTo: workerId)
        .orderBy('date', descending: true);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => TimeEntry.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get a single time entry
  Future<TimeEntry?> getTimeEntry(String entryId) async {
    try {
      final doc = await _firestore
          .collection('time_entries')
          .doc(entryId)
          .get();
      if (doc.exists) {
        return TimeEntry.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching time entry'),
        cause: e,
      );
    }
  }

  // Create a new time entry
  Future<TimeEntry> createTimeEntry({
    required String workspaceId,
    required String workerId,
    required String projectId,
    String? taskId,
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

      TimeEntry entry;
      if (clockOut != null) {
        // Finalized entry with calculations
        entry = TimeEntry.finalize(
          id: entryId,
          workspaceId: workspaceId,
          workerId: workerId,
          projectId: projectId,
          taskId: taskId,
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

      await _firestore
          .collection('time_entries')
          .doc(entryId)
          .set(entry.toJson());
      return entry;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'creating time entry'),
        cause: e,
      );
    }
  }

  // Update an existing time entry
  Future<void> updateTimeEntry(
    String entryId,
    Map<String, dynamic> updates,
  ) async {
    try {
      updates['updatedAt'] = Timestamp.now();
      await _firestore.collection('time_entries').doc(entryId).update(updates);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating time entry'),
        cause: e,
      );
    }
  }

  // Delete a time entry (only if status = draft)
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

      await _firestore.collection('time_entries').doc(entryId).delete();
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'deleting time entry'),
        cause: e,
      );
    }
  }

  // Clock in - create a new active time entry with GPS location
  Future<TimeEntry> clockIn({
    required String workspaceId,
    required String workerId,
    required String projectId,
    String? taskId,
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

  // Clock out - finalize an active time entry with GPS location
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

      final costs = TimeEntry.calculateCosts(
        regularHours: hoursBreakdown.regular,
        overtimeHours: hoursBreakdown.overtime,
        doubleTimeHours: hoursBreakdown.doubleTime,
        hourlyRate: entry.hourlyRate,
        rules: rules,
      );

      // Update entry with calculations and location
      await updateTimeEntry(entryId, {
        'clockOut': Timestamp.fromDate(clockOut),
        'breakDuration': breakDuration,
        'totalDuration': totalDuration,
        'regularHours': hoursBreakdown.regular,
        'overtimeHours': hoursBreakdown.overtime,
        'doubleTimeHours': hoursBreakdown.doubleTime,
        'regularCost': costs.regularCost,
        'overtimeCost': costs.overtimeCost,
        'doubleTimeCost': costs.doubleTimeCost,
        'totalCost': costs.totalCost,
        'clockOutLatitude': clockOutLocation?.latitude,
        'clockOutLongitude': clockOutLocation?.longitude,
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'clocking out'),
        cause: e,
      );
    }
  }

  // Get active entry for a worker (clockOut = null)
  Future<TimeEntry?> getActiveEntry(String workerId, String workspaceId) async {
    try {
      final snapshot = await _firestore
          .collection('time_entries')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('workerId', isEqualTo: workerId)
          .where('clockOut', isEqualTo: null)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return TimeEntry.fromJson(
          snapshot.docs.first.data(),
          snapshot.docs.first.id,
        );
      }
      return null;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching active entry'),
        cause: e,
      );
    }
  }

  // Submit time entry for approval
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

      await updateTimeEntry(entryId, {
        'status': TimeEntryStatus.submitted.toJson(),
        'submittedAt': Timestamp.now(),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'submitting time entry'),
        cause: e,
      );
    }
  }

  // Approve time entry (manager only)
  Future<void> approveTimeEntry(String entryId, String managerId) async {
    try {
      final entry = await getTimeEntry(entryId);
      if (entry == null) {
        throw Exception('Time entry not found');
      }

      if (entry.status != TimeEntryStatus.submitted) {
        throw Exception('Can only approve submitted entries');
      }

      await updateTimeEntry(entryId, {
        'status': TimeEntryStatus.approved.toJson(),
        'approvedBy': managerId,
        'approvedAt': Timestamp.now(),
      });

      // TODO: Optionally create cost item in job costing
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'approving time entry'),
        cause: e,
      );
    }
  }

  // Reject time entry (manager only)
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

      await updateTimeEntry(entryId, {
        'status': TimeEntryStatus.rejected.toJson(),
        'rejectionReason': reason,
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'rejecting time entry'),
        cause: e,
      );
    }
  }

  // Bulk approve multiple entries
  Future<void> bulkApprove(List<String> entryIds, String managerId) async {
    for (final entryId in entryIds) {
      try {
        await approveTimeEntry(entryId, managerId);
      } catch (e) {
        AppLogger.error(
          'Failed to approve time entry in bulk operation',
          error: e,
          metadata: {'entryId': entryId, 'managerId': managerId},
        );
        // Continue with other entries
      }
    }
  }

  // Get time entries for a specific project
  Stream<List<TimeEntry>> getTimeEntriesForProject(
    String projectId, {
    String? workspaceId,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('time_entries')
        .where('projectId', isEqualTo: projectId)
        .orderBy('date', descending: true);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => TimeEntry.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get time entries for a specific task
  Stream<List<TimeEntry>> getTimeEntriesForTask(
    String taskId, {
    String? workspaceId,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('time_entries')
        .where('taskId', isEqualTo: taskId)
        .orderBy('date', descending: true);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => TimeEntry.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get time entries for a date range
  Stream<List<TimeEntry>> getTimeEntriesForDateRange(
    String workerId,
    DateTime startDate,
    DateTime endDate, {
    String? workspaceId,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('time_entries')
        .where('workerId', isEqualTo: workerId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('date', descending: true);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => TimeEntry.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get pending time entries (submitted, awaiting approval)
  Stream<List<TimeEntry>> getPendingTimeEntries(String workspaceId) {
    return _firestore
        .collection('time_entries')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('status', isEqualTo: TimeEntryStatus.submitted.toJson())
        .orderBy('submittedAt', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => TimeEntry.fromJson(doc.data(), doc.id))
              .toList();
        });
  }

  // Get approved time entries for payroll export
  Future<List<TimeEntry>> getTimeEntriesForPayroll(
    String workspaceId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('time_entries')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: TimeEntryStatus.approved.toJson())
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date')
          .orderBy('workerId')
          .get();

      return snapshot.docs
          .map((doc) => TimeEntry.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching payroll entries'),
        cause: e,
      );
    }
  }

  // Get all time entries for a workspace in a date range
  Future<List<TimeEntry>> getWorkspaceTimeEntries(
    String workspaceId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('time_entries')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => TimeEntry.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching workspace time entries'),
        cause: e,
      );
    }
  }

  // Calculate total hours for a worker in a date range
  Future<
    ({
      double regularHours,
      double overtimeHours,
      double doubleTimeHours,
      double totalCost,
    })
  >
  calculateTotalHours(
    String workerId,
    DateTime startDate,
    DateTime endDate, {
    String? workspaceId,
  }) async {
    final entries = await getTimeEntriesForDateRange(
      workerId,
      startDate,
      endDate,
      workspaceId: workspaceId,
    ).first;

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
}
