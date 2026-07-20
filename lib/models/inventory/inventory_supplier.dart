/// A supplier / vendor that the workspace purchases inventory from.
class InventorySupplier {
  final String id;
  final String workspaceId;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? website;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventorySupplier({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.website,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventorySupplier.fromRow(Map<String, dynamic> r) => InventorySupplier(
        id: r['id'],
        workspaceId: r['workspace_id'],
        name: r['name'] ?? '',
        contactName: r['contact_name'],
        email: r['email'],
        phone: r['phone'],
        address: r['address'],
        website: r['website'],
        notes: r['notes'],
        isActive: r['is_active'] ?? true,
        createdAt: r['created_at'] != null
            ? DateTime.parse(r['created_at'])
            : DateTime.now(),
        updatedAt: r['updated_at'] != null
            ? DateTime.parse(r['updated_at'])
            : DateTime.now(),
      );

  Map<String, dynamic> toDb() => {
        'workspace_id': workspaceId,
        'name': name,
        'contact_name': contactName,
        'email': email,
        'phone': phone,
        'address': address,
        'website': website,
        'notes': notes,
        'is_active': isActive,
      };

  InventorySupplier copyWith({
    String? name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    String? website,
    String? notes,
    bool? isActive,
  }) =>
      InventorySupplier(
        id: id,
        workspaceId: workspaceId,
        name: name ?? this.name,
        contactName: contactName ?? this.contactName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        website: website ?? this.website,
        notes: notes ?? this.notes,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
