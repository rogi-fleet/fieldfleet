import 'wire_parsing.dart';

class ProjectDailyLog {
  final String id;
  final String workspaceId;
  final String projectId;
  final DateTime logDate;
  final String? weatherConditions;
  final double? temperatureHigh;
  final double? temperatureLow;
  final String? wind;
  final int crewCount;
  final double? hoursWorked;
  final String? workPerformed;
  final String? materialsDelivered;
  final String? equipmentOnSite;
  final String? subcontractors;
  final String? visitors;
  final String? delays;
  final String? safetyNotes;
  final String? incidents;
  final String? notes;
  final List<Map<String, dynamic>> photos;
  final String status;
  final String? submittedBy;
  final DateTime? submittedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;

  ProjectDailyLog({
    required this.id, required this.workspaceId, required this.projectId,
    required this.logDate, this.weatherConditions,
    this.temperatureHigh, this.temperatureLow, this.wind,
    this.crewCount = 0, this.hoursWorked,
    this.workPerformed, this.materialsDelivered, this.equipmentOnSite,
    this.subcontractors, this.visitors, this.delays, this.safetyNotes,
    this.incidents, this.notes, this.photos = const [],
    this.status = 'draft', this.submittedBy, this.submittedAt,
    this.approvedBy, this.approvedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ProjectDailyLog.fromRow(Map<String, dynamic> r) {
    final raw = r['photos'];
    final photos = raw is List
      ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[];
    return ProjectDailyLog(
      id: r['id'] as String,
      workspaceId: r['workspace_id'] as String,
      projectId: r['project_id'] as String,
      logDate: parseDate(r['log_date']) ?? DateTime.now(),
      weatherConditions: r['weather_conditions'] as String?,
      temperatureHigh: r['temperature_high'] == null ? null : parseNum(r['temperature_high']),
      temperatureLow: r['temperature_low'] == null ? null : parseNum(r['temperature_low']),
      wind: r['wind'] as String?,
      crewCount: (r['crew_count'] as int?) ?? 0,
      hoursWorked: r['hours_worked'] == null ? null : parseNum(r['hours_worked']),
      workPerformed: r['work_performed'] as String?,
      materialsDelivered: r['materials_delivered'] as String?,
      equipmentOnSite: r['equipment_on_site'] as String?,
      subcontractors: r['subcontractors'] as String?,
      visitors: r['visitors'] as String?,
      delays: r['delays'] as String?,
      safetyNotes: r['safety_notes'] as String?,
      incidents: r['incidents'] as String?,
      notes: r['notes'] as String?,
      photos: photos,
      status: (r['status'] as String?) ?? 'draft',
      submittedBy: r['submitted_by'] as String?,
      submittedAt: parseDate(r['submitted_at']),
      approvedBy: r['approved_by'] as String?,
      approvedAt: parseDate(r['approved_at']),
      createdAt: parseDate(r['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsert() => {
    'workspace_id': workspaceId,
    'project_id': projectId,
    'log_date': dateOnly(logDate),
    'weather_conditions': weatherConditions,
    'temperature_high': temperatureHigh,
    'temperature_low': temperatureLow,
    'wind': wind,
    'crew_count': crewCount,
    'hours_worked': hoursWorked,
    'work_performed': workPerformed,
    'materials_delivered': materialsDelivered,
    'equipment_on_site': equipmentOnSite,
    'subcontractors': subcontractors,
    'visitors': visitors,
    'delays': delays,
    'safety_notes': safetyNotes,
    'incidents': incidents,
    'notes': notes,
    'photos': photos,
    'status': status,
    'submitted_by': submittedBy,
    'submitted_at': submittedAt?.toIso8601String(),
  };
}
