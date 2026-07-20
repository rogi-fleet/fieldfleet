class VendorSubdivision {
  final String id;
  final String workspaceId;
  final String vendorId;
  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? contactId;
  final String? accessDetails;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VendorSubdivision({
    required this.id,
    required this.workspaceId,
    required this.vendorId,
    required this.name,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.latitude,
    this.longitude,
    this.contactId,
    this.accessDetails,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VendorSubdivision.fromJson(Map<String, dynamic> json) {
    return VendorSubdivision(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      vendorId: json['vendor_id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zipCode: json['zip_code'] as String?,
      country: json['country'] as String?,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      contactId: json['contact_id'] as String?,
      accessDetails: json['access_details'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspace_id': workspaceId,
      'vendor_id': vendorId,
      'name': name,
      'address': address,
      'city': city,
      'state': state,
      'zip_code': zipCode,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'contact_id': contactId,
      'access_details': accessDetails,
      'notes': notes,
      'is_active': isActive,
    };
  }

  VendorSubdivision copyWith({
    String? id,
    String? workspaceId,
    String? vendorId,
    String? name,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    double? latitude,
    double? longitude,
    String? contactId,
    String? accessDetails,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VendorSubdivision(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      vendorId: vendorId ?? this.vendorId,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      contactId: contactId ?? this.contactId,
      accessDetails: accessDetails ?? this.accessDetails,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String? get fullAddress {
    if (address == null) return null;

    final parts = <String>[];
    parts.add(address!);
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (zipCode != null) parts.add(zipCode!);
    if (country != null) parts.add(country!);

    return parts.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VendorSubdivision &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
