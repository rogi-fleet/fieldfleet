import 'package:cloud_firestore/cloud_firestore.dart';
import 'time_entry_status.dart';
import 'overtime_rules.dart';

class TimeEntry {
  final String id;
  final String workspaceId;
  final String workerId;
  final String projectId;
  final String? taskId;
  final String? budgetItemId;
  final DateTime date; // Normalized to day (00:00:00)
  final DateTime clockIn;
  final DateTime? clockOut;
  final int breakDuration; // Minutes
  final int totalDuration; // Minutes (calculated)
  final double regularHours;
  final double overtimeHours;
  final double doubleTimeHours;
  final double hourlyRate;
  final double regularCost;
  final double overtimeCost;
  final double doubleTimeCost;
  final double totalCost;
  final String? notes;
  final TimeEntryStatus status;
  final DateTime? submittedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  // GPS Location fields
  final double? clockInLatitude;
  final double? clockInLongitude;
  final double? clockOutLatitude;
  final double? clockOutLongitude;
  final double? locationAccuracy; // GPS accuracy in meters
  final double? distanceFromProject; // Distance from project in meters

  TimeEntry({
    required this.id,
    required this.workspaceId,
    required this.workerId,
    required this.projectId,
    this.taskId,
    this.budgetItemId,
    required this.date,
    required this.clockIn,
    this.clockOut,
    this.breakDuration = 0,
    this.totalDuration = 0,
    this.regularHours = 0.0,
    this.overtimeHours = 0.0,
    this.doubleTimeHours = 0.0,
    required this.hourlyRate,
    this.regularCost = 0.0,
    this.overtimeCost = 0.0,
    this.doubleTimeCost = 0.0,
    this.totalCost = 0.0,
    this.notes,
    this.status = TimeEntryStatus.draft,
    this.submittedAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.clockInLatitude,
    this.clockInLongitude,
    this.clockOutLatitude,
    this.clockOutLongitude,
    this.locationAccuracy,
    this.distanceFromProject,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> json, String id) {
    return TimeEntry(
      id: id,
      workspaceId: json['workspaceId'] as String,
      workerId: json['workerId'] as String,
      projectId: json['projectId'] as String,
      taskId: json['taskId'] as String?,
      budgetItemId: json['budgetItemId'] as String?,
      date: _parseTimestamp(json['date']),
      clockIn: _parseTimestamp(json['clockIn']),
      clockOut: json['clockOut'] != null ? _parseTimestamp(json['clockOut']) : null,
      breakDuration: json['breakDuration'] as int? ?? 0,
      totalDuration: json['totalDuration'] as int? ?? 0,
      regularHours: (json['regularHours'] as num?)?.toDouble() ?? 0.0,
      overtimeHours: (json['overtimeHours'] as num?)?.toDouble() ?? 0.0,
      doubleTimeHours: (json['doubleTimeHours'] as num?)?.toDouble() ?? 0.0,
      hourlyRate: (json['hourlyRate'] as num).toDouble(),
      regularCost: (json['regularCost'] as num?)?.toDouble() ?? 0.0,
      overtimeCost: (json['overtimeCost'] as num?)?.toDouble() ?? 0.0,
      doubleTimeCost: (json['doubleTimeCost'] as num?)?.toDouble() ?? 0.0,
      totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      status: TimeEntryStatus.fromString(json['status'] as String? ?? 'draft'),
      submittedAt: json['submittedAt'] != null ? _parseTimestamp(json['submittedAt']) : null,
      approvedBy: json['approvedBy'] as String?,
      approvedAt: json['approvedAt'] != null ? _parseTimestamp(json['approvedAt']) : null,
      rejectionReason: json['rejectionReason'] as String?,
      createdAt: _parseTimestamp(json['createdAt']),
      updatedAt: _parseTimestamp(json['updatedAt']),
      clockInLatitude: (json['clockInLatitude'] as num?)?.toDouble(),
      clockInLongitude: (json['clockInLongitude'] as num?)?.toDouble(),
      clockOutLatitude: (json['clockOutLatitude'] as num?)?.toDouble(),
      clockOutLongitude: (json['clockOutLongitude'] as num?)?.toDouble(),
      locationAccuracy: (json['locationAccuracy'] as num?)?.toDouble(),
      distanceFromProject: (json['distanceFromProject'] as num?)?.toDouble(),
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    try {
      return value.toDate();
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'workerId': workerId,
      'projectId': projectId,
      'taskId': taskId,
      'budgetItemId': budgetItemId,
      'date': Timestamp.fromDate(date),
      'clockIn': Timestamp.fromDate(clockIn),
      'clockOut': clockOut != null ? Timestamp.fromDate(clockOut!) : null,
      'breakDuration': breakDuration,
      'totalDuration': totalDuration,
      'regularHours': regularHours,
      'overtimeHours': overtimeHours,
      'doubleTimeHours': doubleTimeHours,
      'hourlyRate': hourlyRate,
      'regularCost': regularCost,
      'overtimeCost': overtimeCost,
      'doubleTimeCost': doubleTimeCost,
      'totalCost': totalCost,
      'notes': notes,
      'status': status.toJson(),
      'submittedAt': submittedAt != null
          ? Timestamp.fromDate(submittedAt!)
          : null,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'rejectionReason': rejectionReason,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'clockInLatitude': clockInLatitude,
      'clockInLongitude': clockInLongitude,
      'clockOutLatitude': clockOutLatitude,
      'clockOutLongitude': clockOutLongitude,
      'locationAccuracy': locationAccuracy,
      'distanceFromProject': distanceFromProject,
    };
  }

  /// Validate time entry data
  String? validate() {
    if (workerId.isEmpty) return 'Worker ID is required';
    if (projectId.isEmpty) return 'Project ID is required';
    if (date.isAfter(DateTime.now())) return 'Date cannot be in the future';
    if (clockOut != null && clockOut!.isBefore(clockIn)) {
      return 'Clock out time must be after clock in time';
    }
    if (breakDuration < 0) return 'Break duration cannot be negative';
    if (hourlyRate <= 0) return 'Hourly rate must be greater than zero';
    return null;
  }

  /// Calculate duration in minutes
  static int calculateDuration(
    DateTime clockIn,
    DateTime? clockOut,
    int breakDuration,
  ) {
    if (clockOut == null) return 0;
    final totalMinutes = clockOut.difference(clockIn).inMinutes;
    return (totalMinutes - breakDuration).clamp(0, double.infinity).toInt();
  }

  /// Calculate hours breakdown (regular, overtime, double time)
  static ({double regular, double overtime, double doubleTime})
  calculateHoursBreakdown(int totalDurationMinutes, OvertimeRules rules) {
    final totalHours = totalDurationMinutes / 60.0;
    return rules.calculateOvertimeForDay(totalHours);
  }

  /// Calculate all costs
  static ({
    double regularCost,
    double overtimeCost,
    double doubleTimeCost,
    double totalCost,
  })
  calculateCosts({
    required double regularHours,
    required double overtimeHours,
    required double doubleTimeHours,
    required double hourlyRate,
    required OvertimeRules rules,
  }) {
    final regularCost = regularHours * hourlyRate;
    final overtimeCost = overtimeHours * hourlyRate * rules.overtimeMultiplier;
    final doubleTimeCost =
        doubleTimeHours * hourlyRate * rules.doubleTimeMultiplier;
    final totalCost = regularCost + overtimeCost + doubleTimeCost;

    return (
      regularCost: regularCost,
      overtimeCost: overtimeCost,
      doubleTimeCost: doubleTimeCost,
      totalCost: totalCost,
    );
  }

  /// Create a finalized time entry with all calculations
  static TimeEntry finalize({
    required String id,
    required String workspaceId,
    required String workerId,
    required String projectId,
    String? taskId,
    String? budgetItemId,
    required DateTime date,
    required DateTime clockIn,
    required DateTime clockOut,
    required int breakDuration,
    required double hourlyRate,
    required OvertimeRules rules,
    String? notes,
    TimeEntryStatus status = TimeEntryStatus.draft,
  }) {
    // Calculate duration
    final totalDuration = calculateDuration(clockIn, clockOut, breakDuration);

    // Calculate hours breakdown
    final hoursBreakdown = calculateHoursBreakdown(totalDuration, rules);

    // Calculate costs
    final costs = calculateCosts(
      regularHours: hoursBreakdown.regular,
      overtimeHours: hoursBreakdown.overtime,
      doubleTimeHours: hoursBreakdown.doubleTime,
      hourlyRate: hourlyRate,
      rules: rules,
    );

    final now = DateTime.now();

    return TimeEntry(
      id: id,
      workspaceId: workspaceId,
      workerId: workerId,
      projectId: projectId,
      taskId: taskId,
      budgetItemId: budgetItemId,
      date: DateTime(date.year, date.month, date.day), // Normalize to day
      clockIn: clockIn,
      clockOut: clockOut,
      breakDuration: breakDuration,
      totalDuration: totalDuration,
      regularHours: hoursBreakdown.regular,
      overtimeHours: hoursBreakdown.overtime,
      doubleTimeHours: hoursBreakdown.doubleTime,
      hourlyRate: hourlyRate,
      regularCost: costs.regularCost,
      overtimeCost: costs.overtimeCost,
      doubleTimeCost: costs.doubleTimeCost,
      totalCost: costs.totalCost,
      notes: notes,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Helper getters
  bool get isActive => clockOut == null;
  bool get isComplete => clockOut != null;
  bool get canEdit =>
      status == TimeEntryStatus.draft || status == TimeEntryStatus.rejected;
  bool get canSubmit => isComplete && canEdit;
  bool get canApprove => status == TimeEntryStatus.submitted;
  bool get isPending => status == TimeEntryStatus.submitted;
  bool get isApproved => status == TimeEntryStatus.approved;
  bool get isRejected => status == TimeEntryStatus.rejected;

  String get formattedDuration {
    final hours = totalDuration ~/ 60;
    final minutes = totalDuration % 60;
    return '${hours}h ${minutes}m';
  }

  String get formattedTotalCost => '\$${totalCost.toStringAsFixed(2)}';

  // GPS Helper getters
  bool get hasClockInLocation =>
      clockInLatitude != null && clockInLongitude != null;
  bool get hasClockOutLocation =>
      clockOutLatitude != null && clockOutLongitude != null;
  bool get hasAnyLocation => hasClockInLocation || hasClockOutLocation;

  String get formattedDistanceFromProject {
    if (distanceFromProject == null) return 'Unknown';
    if (distanceFromProject! < 1000) {
      return '${distanceFromProject!.toStringAsFixed(0)}m';
    } else {
      return '${(distanceFromProject! / 1000).toStringAsFixed(1)}km';
    }
  }

  String get formattedLocationAccuracy {
    if (locationAccuracy == null) return 'Unknown';
    return '±${locationAccuracy!.toStringAsFixed(0)}m';
  }

  TimeEntry copyWith({
    String? id,
    String? workspaceId,
    String? workerId,
    String? projectId,
    String? taskId,
    String? budgetItemId,
    DateTime? date,
    DateTime? clockIn,
    DateTime? clockOut,
    int? breakDuration,
    int? totalDuration,
    double? regularHours,
    double? overtimeHours,
    double? doubleTimeHours,
    double? hourlyRate,
    double? regularCost,
    double? overtimeCost,
    double? doubleTimeCost,
    double? totalCost,
    String? notes,
    TimeEntryStatus? status,
    DateTime? submittedAt,
    String? approvedBy,
    DateTime? approvedAt,
    String? rejectionReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? clockInLatitude,
    double? clockInLongitude,
    double? clockOutLatitude,
    double? clockOutLongitude,
    double? locationAccuracy,
    double? distanceFromProject,
  }) {
    return TimeEntry(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      workerId: workerId ?? this.workerId,
      projectId: projectId ?? this.projectId,
      taskId: taskId ?? this.taskId,
      budgetItemId: budgetItemId ?? this.budgetItemId,
      date: date ?? this.date,
      clockIn: clockIn ?? this.clockIn,
      clockOut: clockOut ?? this.clockOut,
      breakDuration: breakDuration ?? this.breakDuration,
      totalDuration: totalDuration ?? this.totalDuration,
      regularHours: regularHours ?? this.regularHours,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      doubleTimeHours: doubleTimeHours ?? this.doubleTimeHours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      regularCost: regularCost ?? this.regularCost,
      overtimeCost: overtimeCost ?? this.overtimeCost,
      doubleTimeCost: doubleTimeCost ?? this.doubleTimeCost,
      totalCost: totalCost ?? this.totalCost,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clockInLatitude: clockInLatitude ?? this.clockInLatitude,
      clockInLongitude: clockInLongitude ?? this.clockInLongitude,
      clockOutLatitude: clockOutLatitude ?? this.clockOutLatitude,
      clockOutLongitude: clockOutLongitude ?? this.clockOutLongitude,
      locationAccuracy: locationAccuracy ?? this.locationAccuracy,
      distanceFromProject: distanceFromProject ?? this.distanceFromProject,
    );
  }
}
