import 'package:cloud_firestore/cloud_firestore.dart';
import 'payment_terms.dart';
import 'vendor_contact.dart';
import 'insurance_info.dart';
import 'license_info.dart';

class Vendor {
  final String id;
  final String workspaceId;

  // Company Information
  final String companyName;
  final String? dba; // "Doing Business As" name
  final String? businessPhone;
  final String? businessEmail;
  final List<VendorContact> contacts;
  final String? website;

  // Classification
  final String category;
  final String vendorType;
  final List<String> tags;

  // Business Details
  final String? taxId;
  final String? accountNumber; // Our account # with them
  final PaymentTerms? paymentTerms;
  final String? address;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;

  // Insurance & Licensing
  final InsuranceInfo? insurance;
  final List<LicenseInfo> licenses;

  // Relationship
  final bool isPreferred;
  final double? discountRate;
  final String? notes;
  final bool isActive;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  Vendor({
    required this.id,
    required this.workspaceId,
    required this.companyName,
    this.dba,
    this.businessPhone,
    this.businessEmail,
    List<VendorContact>? contacts,
    this.website,
    required this.category,
    required this.vendorType,
    List<String>? tags,
    this.taxId,
    this.accountNumber,
    this.paymentTerms,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.insurance,
    List<LicenseInfo>? licenses,
    this.isPreferred = false,
    this.discountRate,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  })  : contacts = contacts ?? [],
        tags = tags ?? [],
        licenses = licenses ?? [];

  factory Vendor.fromJson(Map<String, dynamic> json, String id) {
    // Parse contacts
    List<VendorContact> contacts = [];
    if (json['contacts'] != null && json['contacts'] is List) {
      contacts = (json['contacts'] as List)
          .map((c) => VendorContact.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    // Parse licenses
    List<LicenseInfo> licenses = [];
    if (json['licenses'] != null && json['licenses'] is List) {
      licenses = (json['licenses'] as List)
          .map((l) => LicenseInfo.fromJson(l as Map<String, dynamic>))
          .toList();
    }

    // Parse tags
    List<String> tags = [];
    if (json['tags'] != null && json['tags'] is List) {
      tags = (json['tags'] as List).cast<String>();
    }

    return Vendor(
      id: id,
      workspaceId: json['workspaceId'] as String,
      companyName: json['companyName'] as String,
      dba: json['dba'] as String?,
      businessPhone: json['businessPhone'] as String?,
      businessEmail: json['businessEmail'] as String?,
      contacts: contacts,
      website: json['website'] as String?,
      category: json['category'] as String? ?? 'Other',
      vendorType: json['vendorType'] as String? ?? 'Subcontractor',
      tags: tags,
      taxId: json['taxId'] as String?,
      accountNumber: json['accountNumber'] as String?,
      paymentTerms: json['paymentTerms'] != null
          ? PaymentTerms.fromString(json['paymentTerms'] as String)
          : null,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zipCode: json['zipCode'] as String?,
      country: json['country'] as String?,
      insurance: json['insurance'] != null
          ? InsuranceInfo.fromJson(json['insurance'] as Map<String, dynamic>)
          : null,
      licenses: licenses,
      isPreferred: json['isPreferred'] as bool? ?? false,
      discountRate: json['discountRate'] != null
          ? (json['discountRate'] as num).toDouble()
          : null,
      notes: json['notes'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      createdBy: json['createdBy'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'companyName': companyName,
      'dba': dba,
      'businessPhone': businessPhone,
      'businessEmail': businessEmail,
      'contacts': contacts.map((c) => c.toJson()).toList(),
      'website': website,
      'category': category,
      'vendorType': vendorType,
      'tags': tags,
      'taxId': taxId,
      'accountNumber': accountNumber,
      'paymentTerms': paymentTerms?.toDbValue(),
      'address': address,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'country': country,
      'insurance': insurance?.toJson(),
      'licenses': licenses.map((l) => l.toJson()).toList(),
      'isPreferred': isPreferred,
      'discountRate': discountRate,
      'notes': notes,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }

  // Helper methods for contact management
  VendorContact? getPrimaryContact() {
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

  List<VendorContact> getActiveContacts() {
    final activeContacts = contacts.where((c) => c.isActive).toList();
    // Sort with primary first
    activeContacts.sort((a, b) {
      if (a.isPrimary && !b.isPrimary) return -1;
      if (!a.isPrimary && b.isPrimary) return 1;
      return 0;
    });
    return activeContacts;
  }

  // Computed properties
  String get displayName {
    if (dba != null && dba!.isNotEmpty) {
      return '$companyName (DBA: $dba)';
    }
    return companyName;
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

  bool get hasValidInsurance {
    if (insurance == null) return false;
    return insurance!.isValid && !insurance!.isExpired;
  }

  bool get hasExpiredLicenses {
    return licenses.any((license) => license.isExpired);
  }

  bool get hasExpiringSoonInsuranceOrLicenses {
    if (insurance != null && insurance!.isExpiringSoon) return true;
    return licenses.any((license) => license.isExpiringSoon);
  }

  // Validation
  bool validate() {
    // Must have company name
    if (companyName.trim().isEmpty) {
      return false;
    }

    // Must have at least one contact
    if (contacts.isEmpty) {
      return false;
    }

    // Must have exactly one primary contact
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

    // Validate notes length if provided
    if (notes != null && notes!.length > 2000) {
      return false;
    }

    return true;
  }

  Vendor copyWith({
    String? id,
    String? workspaceId,
    String? companyName,
    String? dba,
    String? businessPhone,
    String? businessEmail,
    List<VendorContact>? contacts,
    String? website,
    String? category,
    String? vendorType,
    List<String>? tags,
    String? taxId,
    String? accountNumber,
    PaymentTerms? paymentTerms,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    InsuranceInfo? insurance,
    List<LicenseInfo>? licenses,
    bool? isPreferred,
    double? discountRate,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return Vendor(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      companyName: companyName ?? this.companyName,
      dba: dba ?? this.dba,
      businessPhone: businessPhone ?? this.businessPhone,
      businessEmail: businessEmail ?? this.businessEmail,
      contacts: contacts ?? this.contacts,
      website: website ?? this.website,
      category: category ?? this.category,
      vendorType: vendorType ?? this.vendorType,
      tags: tags ?? this.tags,
      taxId: taxId ?? this.taxId,
      accountNumber: accountNumber ?? this.accountNumber,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      insurance: insurance ?? this.insurance,
      licenses: licenses ?? this.licenses,
      isPreferred: isPreferred ?? this.isPreferred,
      discountRate: discountRate ?? this.discountRate,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
