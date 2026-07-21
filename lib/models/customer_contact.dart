class CustomerContact {
  final String? id; // UUID for linking to client_users
  final String name;
  final String? title;
  final String? phone;
  final String? mobilePhone;
  final String? email;
  final bool isPrimary;
  final bool isActive;
  /// Auth user linked to this contact as a portal customer, if any.
  final String? userId;
  /// When set, this contact is a "unit holder" scoped to exactly one
  /// property instead of the whole customer. Null = customer-wide (default).
  final String? restrictedPropertyId;

  const CustomerContact({
    this.id,
    required this.name,
    this.title,
    this.phone,
    this.mobilePhone,
    this.email,
    this.isPrimary = false,
    this.isActive = true,
    this.userId,
    this.restrictedPropertyId,
  });

  factory CustomerContact.fromJson(Map<String, dynamic> json) {
    return CustomerContact(
      id: json['id'] as String?,
      name: json['name'] as String,
      title: json['title'] as String?,
      phone: json['phone'] as String?,
      mobilePhone: (json['mobilePhone'] ?? json['mobile_phone']) as String?,
      email: json['email'] as String?,
      isPrimary:
          (json['isPrimary'] as bool?) ??
          (json['is_primary'] as bool?) ??
          false,
      isActive:
          (json['isActive'] as bool?) ?? (json['is_active'] as bool?) ?? true,
      userId: (json['userId'] ?? json['user_id']) as String?,
      restrictedPropertyId:
          (json['restrictedPropertyId'] ?? json['restricted_property_id'])
              as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': title,
      'phone': phone,
      'mobilePhone': mobilePhone,
      'email': email,
      'isPrimary': isPrimary,
      'isActive': isActive,
      'userId': userId,
      'restrictedPropertyId': restrictedPropertyId,
    };
  }

  CustomerContact copyWith({
    String? id,
    String? name,
    String? title,
    String? phone,
    String? mobilePhone,
    String? email,
    bool? isPrimary,
    bool? isActive,
    String? userId,
    bool clearUserId = false,
    String? restrictedPropertyId,
  }) {
    return CustomerContact(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      phone: phone ?? this.phone,
      mobilePhone: mobilePhone ?? this.mobilePhone,
      email: email ?? this.email,
      isPrimary: isPrimary ?? this.isPrimary,
      isActive: isActive ?? this.isActive,
      userId: clearUserId ? null : (userId ?? this.userId),
      restrictedPropertyId: restrictedPropertyId ?? this.restrictedPropertyId,
    );
  }

  /// True if this contact is scoped to a single property ("unit holder")
  /// rather than the whole customer.
  bool get isUnitHolder => restrictedPropertyId != null;

  // Validation
  String? validate() {
    if (name.trim().isEmpty) {
      return 'Name is required';
    }

    if (email != null && email!.isNotEmpty && !_isValidEmail(email!)) {
      return 'Invalid email format';
    }

    if (phone != null && phone!.isNotEmpty && !_isValidPhone(phone!)) {
      return 'Invalid phone format';
    }

    if (mobilePhone != null &&
        mobilePhone!.isNotEmpty &&
        !_isValidPhone(mobilePhone!)) {
      return 'Invalid cell phone format';
    }

    return null;
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    // Allow digits, spaces, dashes, parentheses, plus signs
    final phoneRegex = RegExp(r'^[0-9\s\-\(\)\+]+$');
    return phoneRegex.hasMatch(phone);
  }

  // Helper to check if contact has any contact information
  bool get hasContactInfo =>
      (phone != null && phone!.isNotEmpty) ||
      (mobilePhone != null && mobilePhone!.isNotEmpty) ||
      (email != null && email!.isNotEmpty);
}
