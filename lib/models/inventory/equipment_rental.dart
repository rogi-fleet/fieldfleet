/// A single deployment of a leasable asset (air mover, dehumidifier, etc.)
/// to a job. Snapshots the rate at the time of deployment so that
/// historical revenue isn't distorted by later master-rate edits.
class EquipmentRental {
  final String id;
  final String workspaceId;
  final String assetId;
  final String projectId;
  final DateTime startDate;
  final DateTime? endDate; // null = still on site
  final double dailyRate;
  final double? weeklyRate;
  final double? monthlyRate;
  final bool isBillable;
  final String? notes;
  final String? costItemId;
  final DateTime createdAt;
  final DateTime updatedAt;

  EquipmentRental({
    required this.id,
    required this.workspaceId,
    required this.assetId,
    required this.projectId,
    required this.startDate,
    this.endDate,
    required this.dailyRate,
    this.weeklyRate,
    this.monthlyRate,
    this.isBillable = true,
    this.notes,
    this.costItemId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOpen => endDate == null;

  /// Number of billable days. Inclusive of start, exclusive of end. If still
  /// on site (no endDate), counted up to today.
  int daysBilled({DateTime? asOf}) {
    final end = endDate ?? asOf ?? DateTime.now();
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final stop = DateTime(end.year, end.month, end.day);
    final diff = stop.difference(start).inDays;
    return diff < 1 ? 1 : diff; // minimum one billable day
  }

  /// Best-effort billed total: prefer monthly, then weekly, then daily,
  /// based on duration. This matches how restoration contractors invoice.
  double billedAmount({DateTime? asOf}) {
    final days = daysBilled(asOf: asOf);
    if (monthlyRate != null && days >= 28) {
      final months = days / 30.0;
      return months * monthlyRate!;
    }
    if (weeklyRate != null && days >= 7) {
      final weeks = days / 7.0;
      return weeks * weeklyRate!;
    }
    return days * dailyRate;
  }

  factory EquipmentRental.fromRow(Map<String, dynamic> r) => EquipmentRental(
        id: r['id'],
        workspaceId: r['workspace_id'],
        assetId: r['asset_id'],
        projectId: r['project_id'],
        startDate: DateTime.parse(r['start_date']),
        endDate:
            r['end_date'] != null ? DateTime.parse(r['end_date']) : null,
        dailyRate: (r['daily_rate'] as num?)?.toDouble() ?? 0,
        weeklyRate: (r['weekly_rate'] as num?)?.toDouble(),
        monthlyRate: (r['monthly_rate'] as num?)?.toDouble(),
        isBillable: r['is_billable'] ?? true,
        notes: r['notes'],
        costItemId: r['cost_item_id'],
        createdAt: r['created_at'] != null
            ? DateTime.parse(r['created_at'])
            : DateTime.now(),
        updatedAt: r['updated_at'] != null
            ? DateTime.parse(r['updated_at'])
            : DateTime.now(),
      );

  Map<String, dynamic> toDb() => {
        'workspace_id': workspaceId,
        'asset_id': assetId,
        'project_id': projectId,
        'start_date': startDate.toIso8601String().split('T').first,
        'end_date': endDate?.toIso8601String().split('T').first,
        'daily_rate': dailyRate,
        'weekly_rate': weeklyRate,
        'monthly_rate': monthlyRate,
        'is_billable': isBillable,
        'notes': notes,
        'cost_item_id': costItemId,
      };

  EquipmentRental copyWith({
    String? assetId,
    String? projectId,
    DateTime? startDate,
    DateTime? endDate,
    double? dailyRate,
    double? weeklyRate,
    double? monthlyRate,
    bool? isBillable,
    String? notes,
    String? costItemId,
  }) =>
      EquipmentRental(
        id: id,
        workspaceId: workspaceId,
        assetId: assetId ?? this.assetId,
        projectId: projectId ?? this.projectId,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        dailyRate: dailyRate ?? this.dailyRate,
        weeklyRate: weeklyRate ?? this.weeklyRate,
        monthlyRate: monthlyRate ?? this.monthlyRate,
        isBillable: isBillable ?? this.isBillable,
        notes: notes ?? this.notes,
        costItemId: costItemId ?? this.costItemId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
