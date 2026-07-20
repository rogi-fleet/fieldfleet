class Asset {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final String? serialNumber;
  final String? qrCode;
  final String status; // 'available', 'assigned', 'maintenance', 'retired'
  final String category; // see AssetCategory
  final String? location;
  final String? assignedToProjectId;
  final String? assignedToUserId;
  final DateTime? purchaseDate;
  final double? purchasePrice;
  final String? notes;
  final List<String> photoUrls;
  final List<String> tags;

  // ---- Leasing fields (added for restoration / GC equipment rentals) ----
  /// Whether this asset can be rented out to a job at a daily rate.
  /// When true, the asset shows up in the Equipment Rentals picker and
  /// rentals are billed against the rates below.
  final bool isLeasable;
  final double? dailyRentalRate;
  final double? weeklyRentalRate;
  final double? monthlyRentalRate;

  /// What it would cost to replace if lost or damaged on a job.
  final double? replacementCost;

  // ---- Room placement ----
  /// The room/area this asset is currently deployed in (if any).
  final String? areaId;
  /// Normalized 0..1 x position on the room sketch.
  final double? positionX;
  /// Normalized 0..1 y position on the room sketch.
  final double? positionY;

  Asset({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    this.serialNumber,
    this.qrCode,
    this.status = 'available',
    this.category = 'other',
    this.location,
    this.assignedToProjectId,
    this.assignedToUserId,
    this.purchaseDate,
    this.purchasePrice,
    this.notes,
    this.photoUrls = const [],
    this.tags = const [],
    this.isLeasable = false,
    this.dailyRentalRate,
    this.weeklyRentalRate,
    this.monthlyRentalRate,
    this.replacementCost,
    this.areaId,
    this.positionX,
    this.positionY,
  });

  bool get isPlacedInRoom =>
      areaId != null && positionX != null && positionY != null;

  Asset copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? description,
    String? serialNumber,
    String? qrCode,
    String? status,
    String? category,
    String? location,
    String? assignedToProjectId,
    String? assignedToUserId,
    DateTime? purchaseDate,
    double? purchasePrice,
    String? notes,
    List<String>? photoUrls,
    List<String>? tags,
    bool? isLeasable,
    double? dailyRentalRate,
    double? weeklyRentalRate,
    double? monthlyRentalRate,
    double? replacementCost,
    String? areaId,
    double? positionX,
    double? positionY,
  }) {
    return Asset(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      description: description ?? this.description,
      serialNumber: serialNumber ?? this.serialNumber,
      qrCode: qrCode ?? this.qrCode,
      status: status ?? this.status,
      category: category ?? this.category,
      location: location ?? this.location,
      assignedToProjectId: assignedToProjectId ?? this.assignedToProjectId,
      assignedToUserId: assignedToUserId ?? this.assignedToUserId,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      notes: notes ?? this.notes,
      photoUrls: photoUrls ?? this.photoUrls,
      tags: tags ?? this.tags,
      isLeasable: isLeasable ?? this.isLeasable,
      dailyRentalRate: dailyRentalRate ?? this.dailyRentalRate,
      weeklyRentalRate: weeklyRentalRate ?? this.weeklyRentalRate,
      monthlyRentalRate: monthlyRentalRate ?? this.monthlyRentalRate,
      replacementCost: replacementCost ?? this.replacementCost,
      areaId: areaId ?? this.areaId,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
    );
  }
}
