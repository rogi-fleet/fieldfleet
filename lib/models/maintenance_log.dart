class MaintenanceLog {
  final String id;
  final String workspaceId;
  final String entityId; // ID of the Asset or Vehicle
  final String entityType; // 'asset' or 'vehicle'
  final DateTime date;
  final String type; // 'oil_change', 'repair', 'inspection', 'other'
  final String description;
  final double cost;
  final String? performedBy; // Name of person or vendor
  final DateTime? nextMaintenanceDate;
  final int? nextMaintenanceMileage; // Only for vehicles

  MaintenanceLog({
    required this.id,
    required this.workspaceId,
    required this.entityId,
    required this.entityType,
    required this.date,
    required this.type,
    required this.description,
    required this.cost,
    this.performedBy,
    this.nextMaintenanceDate,
    this.nextMaintenanceMileage,
  });

  MaintenanceLog copyWith({
    String? id,
    String? workspaceId,
    String? entityId,
    String? entityType,
    DateTime? date,
    String? type,
    String? description,
    double? cost,
    String? performedBy,
    DateTime? nextMaintenanceDate,
    int? nextMaintenanceMileage,
  }) {
    return MaintenanceLog(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      entityId: entityId ?? this.entityId,
      entityType: entityType ?? this.entityType,
      date: date ?? this.date,
      type: type ?? this.type,
      description: description ?? this.description,
      cost: cost ?? this.cost,
      performedBy: performedBy ?? this.performedBy,
      nextMaintenanceDate: nextMaintenanceDate ?? this.nextMaintenanceDate,
      nextMaintenanceMileage:
          nextMaintenanceMileage ?? this.nextMaintenanceMileage,
    );
  }
}
