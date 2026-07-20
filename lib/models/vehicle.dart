class Vehicle {
  final String id;
  final String workspaceId;
  final String name;
  final String make;
  final String model;
  final int year;
  final String licensePlate;
  final String? vin;
  final int currentMileage;
  /// Primary driver — the team member this vehicle is long-term registered to.
  final String? assignedToUserId;
  /// Whoever currently has the keys. Set on check-out, cleared on check-in.
  final String? currentDriverId;
  /// Project the vehicle is committed to right now (for utilisation / budget rollup).
  final String? assignedToProjectId;
  final String status; // 'active', 'maintenance', 'retired'
  final String? qrCode;
  final String? imageUrl;
  final DateTime? insuranceExpiry;
  final DateTime? registrationExpiry;

  Vehicle({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.make,
    required this.model,
    required this.year,
    required this.licensePlate,
    this.vin,
    required this.currentMileage,
    this.assignedToUserId,
    this.currentDriverId,
    this.assignedToProjectId,
    this.status = 'active',
    this.qrCode,
    this.imageUrl,
    this.insuranceExpiry,
    this.registrationExpiry,
  });

  Vehicle copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? make,
    String? model,
    int? year,
    String? licensePlate,
    String? vin,
    int? currentMileage,
    String? assignedToUserId,
    String? currentDriverId,
    String? assignedToProjectId,
    String? status,
    String? qrCode,
    String? imageUrl,
    DateTime? insuranceExpiry,
    DateTime? registrationExpiry,
  }) {
    return Vehicle(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      licensePlate: licensePlate ?? this.licensePlate,
      vin: vin ?? this.vin,
      currentMileage: currentMileage ?? this.currentMileage,
      assignedToUserId: assignedToUserId ?? this.assignedToUserId,
      currentDriverId: currentDriverId ?? this.currentDriverId,
      assignedToProjectId: assignedToProjectId ?? this.assignedToProjectId,
      status: status ?? this.status,
      qrCode: qrCode ?? this.qrCode,
      imageUrl: imageUrl ?? this.imageUrl,
      insuranceExpiry: insuranceExpiry ?? this.insuranceExpiry,
      registrationExpiry: registrationExpiry ?? this.registrationExpiry,
    );
  }
}
