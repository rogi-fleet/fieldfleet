class VendorContact {
  final String? id;
  final String name;
  final String? title;
  final String? email;
  final String? phone;
  final String? mobilePhone;
  final bool isPrimary;
  final bool isActive;
  final String? notes;
  /// Auth user linked to this contact as a portal vendor, if any.
  final String? userId;

  VendorContact({
    this.id,
    required this.name,
    this.title,
    this.email,
    this.phone,
    this.mobilePhone,
    this.isPrimary = false,
    this.isActive = true,
    this.notes,
    this.userId,
  });

  factory VendorContact.fromJson(Map<String, dynamic> json) {
    return VendorContact(
      id: json['id'] as String?,
      name: json['name'] as String,
      title: json['title'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      mobilePhone: (json['mobilePhone'] ?? json['mobile_phone']) as String?,
      isPrimary: (json['isPrimary'] ?? json['is_primary']) as bool? ?? false,
      isActive: (json['isActive'] ?? json['is_active']) as bool? ?? true,
      notes: json['notes'] as String?,
      userId: (json['userId'] ?? json['user_id']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'title': title,
      'email': email,
      'phone': phone,
      'mobilePhone': mobilePhone,
      'isPrimary': isPrimary,
      'isActive': isActive,
      'notes': notes,
      'userId': userId,
    };
  }

  String? validate() {
    if (name.trim().isEmpty) {
      return 'Contact name is required';
    }
    if (name.length > 100) {
      return 'Contact name cannot exceed 100 characters';
    }
    if (email != null && email!.isNotEmpty) {
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      if (!emailRegex.hasMatch(email!)) {
        return 'Invalid email format';
      }
    }
    if (notes != null && notes!.length > 500) {
      return 'Contact notes cannot exceed 500 characters';
    }
    return null;
  }

  VendorContact copyWith({
    String? id,
    String? name,
    String? title,
    String? email,
    String? phone,
    String? mobilePhone,
    bool? isPrimary,
    bool? isActive,
    String? notes,
    String? userId,
    bool clearUserId = false,
  }) {
    return VendorContact(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      mobilePhone: mobilePhone ?? this.mobilePhone,
      isPrimary: isPrimary ?? this.isPrimary,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      userId: clearUserId ? null : (userId ?? this.userId),
    );
  }
}
