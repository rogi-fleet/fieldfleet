class VehicleExpense {
  final String id;
  final String workspaceId;
  final String vehicleId;
  final DateTime date;
  final String category;
  final double amount;
  final String? description;
  final int? odometer;
  final String? vendor;
  final String? attachmentUrl;
  final DateTime? createdAt;

  VehicleExpense({
    required this.id,
    required this.workspaceId,
    required this.vehicleId,
    required this.date,
    required this.category,
    required this.amount,
    this.description,
    this.odometer,
    this.vendor,
    this.attachmentUrl,
    this.createdAt,
  });

  static const List<String> categories = [
    'fuel',
    'repair',
    'toll',
    'parking',
    'insurance',
    'registration',
    'wash',
    'other',
  ];

  static String categoryLabel(String category) {
    switch (category) {
      case 'fuel':
        return 'Fuel';
      case 'repair':
        return 'Repair';
      case 'toll':
        return 'Toll';
      case 'parking':
        return 'Parking';
      case 'insurance':
        return 'Insurance';
      case 'registration':
        return 'Registration';
      case 'wash':
        return 'Car Wash';
      case 'other':
      default:
        return 'Other';
    }
  }

  VehicleExpense copyWith({
    String? id,
    String? workspaceId,
    String? vehicleId,
    DateTime? date,
    String? category,
    double? amount,
    String? description,
    int? odometer,
    String? vendor,
    String? attachmentUrl,
    DateTime? createdAt,
  }) {
    return VehicleExpense(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      vehicleId: vehicleId ?? this.vehicleId,
      date: date ?? this.date,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      odometer: odometer ?? this.odometer,
      vendor: vendor ?? this.vendor,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
