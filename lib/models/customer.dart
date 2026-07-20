import 'package:cloud_firestore/cloud_firestore.dart';
import 'customer_contact.dart';
import 'customer_status.dart';
import 'customer_source.dart';

/// Parse DateTime from either Firestore Timestamp or ISO 8601 string (Supabase)
DateTime _parseDateTime(dynamic value) {
  if (value == null) {
    return DateTime.now();
  } else if (value is Timestamp) {
    return value.toDate();
  } else if (value is String) {
    return DateTime.parse(value);
  } else if (value is DateTime) {
    return value;
  }
  return DateTime.now();
}

class Customer {
  final String id;
  final String workspaceId;

  // Legacy fields (kept for backward compatibility during migration)
  final String? _legacyName;
  final String? _legacyEmail;
  final String? _legacyPhone;

  // New contacts array
  final List<CustomerContact> contacts;

  // Hierarchy support
  final String? parentCustomerId;

  // New Phase 1 fields
  final CustomerStatus status;
  final CustomerSource? source;
  final String? referrerName; // Used when source is referral
  final List<String> tagIds;
  final String? accountOwnerId;
  final String? logoUrl;

  final String? companyName;
  final String? businessPhone;
  final String? businessEmail;
  final String? website;
  final String? address;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;
  final String customerType;
  final bool taxExempt;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.workspaceId,
    List<CustomerContact>? contacts,
    String? legacyName,
    String? legacyEmail,
    String? legacyPhone,
    this.parentCustomerId,
    this.status = CustomerStatus.active,
    this.source,
    this.referrerName,
    List<String>? tagIds,
    this.accountOwnerId,
    this.logoUrl,
    this.companyName,
    this.businessPhone,
    this.businessEmail,
    this.website,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.customerType = 'Residential',
    this.taxExempt = false,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  }) : _legacyName = legacyName,
       _legacyEmail = legacyEmail,
       _legacyPhone = legacyPhone,
       contacts = contacts ?? [],
       tagIds = tagIds ?? [];

  // Computed properties for backward compatibility
  String get name {
    final primary = getPrimaryContact();
    return primary?.name ?? _legacyName ?? '';
  }

  String? get email {
    final primary = getPrimaryContact();
    return primary?.email ?? _legacyEmail;
  }

  String? get phone {
    final primary = getPrimaryContact();
    return primary?.phone ?? _legacyPhone;
  }

  // Helper methods for contact management
  CustomerContact? getPrimaryContact() {
    try {
      return contacts.firstWhere((c) => c.isPrimary && c.isActive);
    } catch (e) {
      // No primary contact, return first active contact
      try {
        return contacts.firstWhere((c) => c.isActive);
      } catch (e) {
        return null;
      }
    }
  }

  List<CustomerContact> getActiveContacts() {
    final activeContacts = contacts.where((c) => c.isActive).toList();
    // Sort with primary first
    activeContacts.sort((a, b) {
      if (a.isPrimary && !b.isPrimary) return -1;
      if (!a.isPrimary && b.isPrimary) return 1;
      return 0;
    });
    return activeContacts;
  }

  CustomerContact? findContactByEmail(String email) {
    try {
      return contacts.firstWhere(
        (c) => c.email?.toLowerCase() == email.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  factory Customer.fromJson(Map<String, dynamic> json, String id) {
    // Check if contacts array exists
    List<CustomerContact> contacts = [];
    if (json['contacts'] != null && json['contacts'] is List) {
      contacts = (json['contacts'] as List)
          .map((c) => CustomerContact.fromJson(c as Map<String, dynamic>))
          .toList();
    } else if (json['name'] != null) {
      // Legacy format - create contact from legacy fields
      contacts = [
        CustomerContact(
          name: json['name'] as String,
          email: json['email'] as String?,
          phone: json['phone'] as String?,
          isPrimary: true,
          isActive: true,
        ),
      ];
    }

    return Customer(
      id: id,
      workspaceId: json['workspaceId'] as String,
      contacts: contacts,
      legacyName: json['name'] as String?,
      legacyEmail: json['email'] as String?,
      legacyPhone: json['phone'] as String?,
      parentCustomerId: json['parentCustomerId'] as String?,
      status: json['status'] != null
          ? CustomerStatus.fromString(json['status'] as String)
          : CustomerStatus.active, // Default to active for existing customers
      source: json['source'] != null
          ? CustomerSource.fromString(json['source'] as String)
          : null,
      referrerName: json['referrerName'] as String?,
      tagIds: json['tagIds'] != null
          ? List<String>.from(json['tagIds'] as List)
          : [],
      accountOwnerId: json['accountOwnerId'] as String?,
      logoUrl: json['logoUrl'] as String?,
      companyName: json['companyName'] as String?,
      businessPhone: json['businessPhone'] as String?,
      businessEmail: json['businessEmail'] as String?,
      website: json['website'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zipCode: json['zipCode'] as String?,
      country: json['country'] as String?,
      customerType: json['customerType'] as String? ?? 'Residential',
      taxExempt: json['taxExempt'] as bool? ?? false,
      notes: json['notes'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    final primary = getPrimaryContact();
    return {
      'workspaceId': workspaceId,
      // Contacts array (new format)
      'contacts': contacts.map((c) => c.toJson()).toList(),
      // Legacy fields (for backward compatibility)
      'name': primary?.name ?? _legacyName ?? '',
      'email': primary?.email ?? _legacyEmail,
      'phone': primary?.phone ?? _legacyPhone,
      'parentCustomerId': parentCustomerId,
      // Phase 1 fields
      'status': status.name,
      'source': source?.toDbValue(),
      'referrerName': referrerName,
      'tagIds': tagIds,
      'accountOwnerId': accountOwnerId,
      'logoUrl': logoUrl,
      // Other fields
      'companyName': companyName,
      'businessPhone': businessPhone,
      'businessEmail': businessEmail,
      'website': website,
      'address': address,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'country': country,
      'customerType': customerType,
      'taxExempt': taxExempt,
      'notes': notes,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Customer copyWith({
    String? id,
    String? workspaceId,
    List<CustomerContact>? contacts,
    String? parentCustomerId,
    CustomerStatus? status,
    CustomerSource? source,
    String? referrerName,
    List<String>? tagIds,
    String? accountOwnerId,
    String? logoUrl,
    String? companyName,
    String? businessPhone,
    String? businessEmail,
    String? website,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    String? customerType,
    bool? taxExempt,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      contacts: contacts ?? this.contacts,
      legacyName: _legacyName,
      legacyEmail: _legacyEmail,
      legacyPhone: _legacyPhone,
      parentCustomerId: parentCustomerId ?? this.parentCustomerId,
      status: status ?? this.status,
      source: source ?? this.source,
      referrerName: referrerName ?? this.referrerName,
      tagIds: tagIds ?? this.tagIds,
      accountOwnerId: accountOwnerId ?? this.accountOwnerId,
      logoUrl: logoUrl ?? this.logoUrl,
      companyName: companyName ?? this.companyName,
      businessPhone: businessPhone ?? this.businessPhone,
      businessEmail: businessEmail ?? this.businessEmail,
      website: website ?? this.website,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      customerType: customerType ?? this.customerType,
      taxExempt: taxExempt ?? this.taxExempt,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool validate() {
    // Must have at least one contact
    if (contacts.isEmpty && _legacyName == null) {
      return false;
    }

    // Must have exactly one primary contact if using contacts
    if (contacts.isNotEmpty) {
      final primaryCount = contacts.where((c) => c.isPrimary).length;
      if (primaryCount != 1) {
        return false;
      }

      // Validate all contacts
      for (final contact in contacts) {
        if (contact.validate() != null) {
          return false;
        }
      }
    }

    return _validateFields();
  }

  bool _validateFields() {
    // Validate notes length if provided
    if (notes != null && notes!.length > 1000) {
      return false;
    }

    return true;
  }

  // Helper method to get full display name
  String get displayName {
    if (companyName != null && companyName!.isNotEmpty) {
      final contact = name.trim();
      if (contact.isEmpty || contact == companyName!.trim()) {
        return companyName!;
      }
      return '$companyName ($contact)';
    }
    return name;
  }

  String get businessDisplayName {
    final company = companyName?.trim();
    if (company != null && company.isNotEmpty) {
      return company;
    }
    return name;
  }

  // Helper method to get full address
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

  // Hierarchy helpers
  bool get hasParent => parentCustomerId != null;
  bool get isParent =>
      false; // Will be determined by checking if other customers reference this as parent

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Customer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
