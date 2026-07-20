import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../models/vendor_contact.dart';
import '../../models/insurance_info.dart';
import '../../models/license_info.dart';
import '../../models/payment_terms.dart';

/// Supabase implementation of VendorService
class SupabaseVendorService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all vendors for a workspace
  Stream<List<Vendor>> getVendors(String workspaceId) {
    return _supabase
        .from('vendors')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((data) async {
          final filtered = data
              .where((row) => row['is_active'] == true)
              .toList();

          if (filtered.isEmpty) return <Vendor>[];

          final contactsByVendor = await _fetchContactsForVendors(
            filtered.map((r) => r['id'] as String).toList(),
          );

          final vendors = filtered.map((row) {
            final vendorId = row['id'] as String;
            return _toVendor(row, contacts: contactsByVendor[vendorId]);
          }).toList();
          vendors.sort((a, b) => a.companyName.compareTo(b.companyName));
          return vendors;
        });
  }

  /// Get single vendor
  Future<Vendor?> getVendor(String vendorId) async {
    final response = await _supabase
        .from('vendors')
        .select('*, vendor_contacts(*)')
        .eq('id', vendorId)
        .maybeSingle();

    if (response == null) return null;
    return _toVendor(response);
  }

  /// Create vendor
  Future<String> createVendor(Vendor vendor) async {
    final validationError = _getValidationError(vendor);
    if (validationError != null) {
      debugPrint('Vendor validation failed: $validationError');
      throw Exception('Invalid vendor data: $validationError');
    }

    final now = DateTime.now();
    final vendorData = _toDbFormat(vendor);
    vendorData['created_at'] = now.toIso8601String();
    vendorData['updated_at'] = now.toIso8601String();

    final response = await _insertVendor(vendorData);

    final vendorId = response['id'] as String;
    await _syncContacts(vendorId, vendor.contacts);
    await _touchVendor(vendorId);
    return vendorId;
  }

  /// Update vendor
  Future<void> updateVendor(Vendor vendor) async {
    final validationError = _getValidationError(vendor);
    if (validationError != null) {
      debugPrint('Vendor validation failed: $validationError');
      throw Exception('Invalid vendor data: $validationError');
    }

    final vendorData = _toDbFormat(vendor);
    vendorData['updated_at'] = DateTime.now().toIso8601String();

    await _updateVendor(vendor.id, vendorData);

    await _syncContacts(vendor.id, vendor.contacts);
    await _touchVendor(vendor.id);
  }

  /// Delete vendor
  Future<void> deleteVendor(String vendorId) async {
    await _supabase.from('vendors').delete().eq('id', vendorId);
  }

  /// Archive vendor (soft delete)
  Future<void> archiveVendor(String vendorId) async {
    await _supabase
        .from('vendors')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', vendorId);
  }

  /// Restore vendor
  Future<void> restoreVendor(String vendorId) async {
    await _supabase
        .from('vendors')
        .update({
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', vendorId);
  }

  /// Filter by category
  Stream<List<Vendor>> getVendorsByCategory(
    String workspaceId,
    String category,
  ) {
    return _supabase
        .from('vendors')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((data) async {
          final filtered = data
              .where((row) => row['is_active'] == true)
              .toList();

          if (filtered.isEmpty) return <Vendor>[];

          final contactsByVendor = await _fetchContactsForVendors(
            filtered.map((r) => r['id'] as String).toList(),
          );

          final vendors = filtered
              .map((row) {
                final vendorId = row['id'] as String;
                return _toVendor(row, contacts: contactsByVendor[vendorId]);
              })
              .where((vendor) => vendor.category == category)
              .toList();
          vendors.sort((a, b) => a.companyName.compareTo(b.companyName));
          return vendors;
        });
  }

  /// Filter by type
  Stream<List<Vendor>> getVendorsByType(String workspaceId, String type) {
    return _supabase
        .from('vendors')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((data) async {
          final filtered = data
              .where((row) => row['is_active'] == true)
              .toList();

          if (filtered.isEmpty) return <Vendor>[];

          final contactsByVendor = await _fetchContactsForVendors(
            filtered.map((r) => r['id'] as String).toList(),
          );

          final vendors = filtered
              .map((row) {
                final vendorId = row['id'] as String;
                return _toVendor(row, contacts: contactsByVendor[vendorId]);
              })
              .where((vendor) => vendor.vendorType == type)
              .toList();
          vendors.sort((a, b) => a.companyName.compareTo(b.companyName));
          return vendors;
        });
  }

  /// Get preferred vendors
  Stream<List<Vendor>> getPreferredVendors(String workspaceId) {
    return _supabase
        .from('vendors')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((data) async {
          final filtered = data
              .where(
                (row) =>
                    row['is_active'] == true && row['is_preferred'] == true,
              )
              .toList();

          if (filtered.isEmpty) return <Vendor>[];

          final contactsByVendor = await _fetchContactsForVendors(
            filtered.map((r) => r['id'] as String).toList(),
          );

          final vendors = filtered.map((row) {
            final vendorId = row['id'] as String;
            return _toVendor(row, contacts: contactsByVendor[vendorId]);
          }).toList();
          vendors.sort((a, b) => a.companyName.compareTo(b.companyName));
          return vendors;
        });
  }

  /// Get archived vendors
  Stream<List<Vendor>> getArchivedVendors(String workspaceId) {
    return _supabase
        .from('vendors')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((data) async {
          final filtered = data
              .where((row) => row['is_active'] == false)
              .toList();

          if (filtered.isEmpty) return <Vendor>[];

          final contactsByVendor = await _fetchContactsForVendors(
            filtered.map((r) => r['id'] as String).toList(),
          );

          final vendors = filtered.map((row) {
            final vendorId = row['id'] as String;
            return _toVendor(row, contacts: contactsByVendor[vendorId]);
          }).toList();
          vendors.sort((a, b) => a.companyName.compareTo(b.companyName));
          return vendors;
        });
  }

  /// Search vendors
  Future<List<Vendor>> searchVendors(String workspaceId, String query) async {
    final response = await _supabase
        .from('vendors')
        .select('*, vendor_contacts(*)')
        .eq('workspace_id', workspaceId)
        .eq('is_active', true)
        .ilike('company_name', '%$query%');

    return response.map((row) => _toVendor(row)).toList();
  }

  /// Calculate total spending for a vendor (sum of all bills)
  Future<double> calculateVendorSpending(String vendorId) async {
    try {
      final bills = await _supabase
          .from('generated_documents')
          .select('total_amount')
          .eq('vendor_id', vendorId)
          .eq('document_type', 'bill');

      double total = 0.0;
      for (final bill in bills) {
        total += (bill['total_amount'] as num?)?.toDouble() ?? 0.0;
      }
      return total;
    } catch (_) {
      return 0.0;
    }
  }

  /// Get last activity date for a vendor (most recent linked project update)
  Future<DateTime?> getVendorLastActivityDate(String vendorId) async {
    try {
      final projects = await getVendorProjects(vendorId);
      if (projects.isEmpty) return null;
      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return projects.first.updatedAt;
    } catch (_) {
      return null;
    }
  }

  /// Get all projects associated with a vendor (via bills, purchase orders, or bid requests)
  Future<List<Project>> getVendorProjects(String vendorId) async {
    final projectIds = <String>{};

    final bills = await _supabase
        .from('bills')
        .select('project_id')
        .eq('vendor_id', vendorId);
    for (final row in bills) {
      if (row['project_id'] != null) projectIds.add(row['project_id']);
    }

    final pos = await _supabase
        .from('purchase_orders')
        .select('project_id')
        .eq('vendor_id', vendorId);
    for (final row in pos) {
      if (row['project_id'] != null) projectIds.add(row['project_id']);
    }

    final bids = await _supabase
        .from('bid_requests')
        .select('project_id')
        .eq('vendor_id', vendorId);
    for (final row in bids) {
      if (row['project_id'] != null) projectIds.add(row['project_id']);
    }

    if (projectIds.isEmpty) return [];

    final projects = await _supabase
        .from('projects')
        .select('*, project_team_members(user_id)')
        .inFilter('id', projectIds.toList())
        .order('updated_at', ascending: false);

    return projects.map((row) => _projectFromRow(row)).toList();
  }

  Project _projectFromRow(Map<String, dynamic> row) {
    return Project.fromJson({
      'id': row['id'],
      'workspaceId': row['workspace_id'],
      'name': row['name'],
      'address': row['address'],
      'status': row['status'],
      'clientId': row['client_id'],
      'estimatedBudget': row['estimated_budget'],
      'materialMarkupPercent': row['material_markup_percent'],
      'laborMarkupPercent': row['labor_markup_percent'],
      'startDate': _toTimestamp(row['start_date']),
      'targetCompletionDate': _toTimestamp(row['target_completion_date']),
      'createdAt': _toTimestamp(row['created_at']),
      'updatedAt': _toTimestamp(row['updated_at']),
      'priceType': row['price_type'],
      'contractAmount': row['contract_amount'],
      'costPlusType': row['cost_plus_type'],
      'costPlusValue': row['cost_plus_value'],
      'description': row['description'],
      'projectManagerId': row['project_manager_id'],
      'latitude': row['latitude'],
      'longitude': row['longitude'],
      'photoUrl': row['photo_url'],
      'jobType': row['job_type'],
      'purchaseOrderNumber': row['purchase_order_number'],
      'dateRequestReceived': _toTimestamp(row['date_request_received']),
      'locationDetails': row['location_details'],
      'salespersonId': row['salesperson_id'],
      'supervisorId': row['supervisor_id'],
      'primaryContactName': row['primary_contact_name'],
      'customerName': row['customer_name'],
      'primaryContactRole': row['primary_contact_role'],
      'primaryContactPhone': row['primary_contact_phone'],
      'primaryContactEmail': row['primary_contact_email'],
      'serialNumber': row['serial_number'],
      'teamMemberIds': row['project_team_members'] is List
          ? (row['project_team_members'] as List)
                .map((e) => e['user_id'] as String)
                .toList()
          : (row['team_member_ids'] as List?)?.cast<String>() ?? [],
      'geofenceRadiusMeters': row['geofence_radius_meters'],
      'requireGeofenceValidation': row['require_geofence_validation'],
      'allowClockInOutsideGeofence': row['allow_clock_in_outside_geofence'],
    }, row['id']);
  }

  Timestamp? _toTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is String) {
      return Timestamp.fromDate(DateTime.parse(value));
    }
    return null;
  }

  /// Batch-fetch contacts for a list of vendor IDs, grouped by vendor
  Future<Map<String, List<Map<String, dynamic>>>> _fetchContactsForVendors(
    List<String> vendorIds,
  ) async {
    if (vendorIds.isEmpty) return {};
    final response = await _supabase
        .from('vendor_contacts')
        .select()
        .inFilter('vendor_id', vendorIds);

    final contactsByVendor = <String, List<Map<String, dynamic>>>{};
    for (final contact in response) {
      final vendorId = contact['vendor_id'] as String;
      contactsByVendor.putIfAbsent(vendorId, () => []).add(contact);
    }
    return contactsByVendor;
  }

  /// Sync contacts: upsert existing rows by id, insert new ones, delete rows
  /// no longer in the list. Must not delete-and-re-insert existing rows —
  /// that would blow away customer_contacts.user_id (portal linkage) and
  /// churn UUIDs that outside tables reference.
  Future<void> _syncContacts(
    String vendorId,
    List<VendorContact> contacts,
  ) async {
    final existing = await _supabase
        .from('vendor_contacts')
        .select('id')
        .eq('vendor_id', vendorId);
    final existingIds = (existing as List)
        .map((r) => (r as Map<String, dynamic>)['id'] as String)
        .toSet();
    final keepIds = contacts
        .map((c) => c.id)
        .whereType<String>()
        .toSet();
    final toDelete = existingIds.difference(keepIds).toList();
    if (toDelete.isNotEmpty) {
      await _supabase
          .from('vendor_contacts')
          .delete()
          .inFilter('id', toDelete);
    }

    Map<String, dynamic> payload(VendorContact c) => {
      'vendor_id': vendorId,
      'name': c.name,
      'title': c.title,
      'phone': c.phone,
      'email': c.email,
      'mobile_phone': c.mobilePhone,
      'notes': c.notes,
      'is_primary': c.isPrimary,
      'is_active': c.isActive,
    };

    final updates = contacts.where((c) => c.id != null).toList();
    final inserts = contacts.where((c) => c.id == null).toList();

    if (updates.isNotEmpty) {
      await _supabase
          .from('vendor_contacts')
          .upsert(
            updates.map((c) => {'id': c.id, ...payload(c)}).toList(),
            onConflict: 'id',
          );
    }
    if (inserts.isNotEmpty) {
      await _supabase
          .from('vendor_contacts')
          .insert(inserts.map(payload).toList());
    }
  }

  Future<Map<String, dynamic>> _insertVendor(
    Map<String, dynamic> vendorData,
  ) async {
    return await _supabase
        .from('vendors')
        .insert(vendorData)
        .select('id')
        .single();
  }

  Future<void> _updateVendor(
    String vendorId,
    Map<String, dynamic> vendorData,
  ) async {
    await _supabase.from('vendors').update(vendorData).eq('id', vendorId);
  }

  Future<void> _touchVendor(String vendorId) async {
    await _supabase
        .from('vendors')
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('id', vendorId);
  }

  /// Convert database row to Vendor model
  Vendor _toVendor(
    Map<String, dynamic> row, {
    List<Map<String, dynamic>>? contacts,
  }) {
    // Parse contacts from explicit param, join key, or empty
    List<VendorContact> vendorContacts = [];
    final contactRows = contacts ?? row['vendor_contacts'];
    if (contactRows != null && contactRows is List) {
      vendorContacts = contactRows
          .map(
            (c) => VendorContact(
              id: c['id'] as String?,
              name: c['name'] as String,
              title: c['title'] as String?,
              email: c['email'] as String?,
              phone: c['phone'] as String?,
              mobilePhone: c['mobile_phone'] as String?,
              notes: c['notes'] as String?,
              isPrimary: c['is_primary'] as bool? ?? false,
              isActive: c['is_active'] as bool? ?? true,
            ),
          )
          .toList();
    }

    // Parse licenses from JSONB
    List<LicenseInfo> licenses = [];
    if (row['licenses'] != null && row['licenses'] is List) {
      licenses = (row['licenses'] as List)
          .map((l) => LicenseInfo.fromJson(l as Map<String, dynamic>))
          .toList();
    }

    // Parse tags
    List<String> tags = [];
    if (row['tags'] != null && row['tags'] is List) {
      tags = (row['tags'] as List).cast<String>();
    }

    return Vendor(
      id: row['id'],
      workspaceId: row['workspace_id'],
      companyName: row['company_name'],
      dba: row['dba'],
      contacts: vendorContacts,
      website: row['website'],
      businessPhone: row['business_phone'] as String?,
      businessEmail: row['business_email'] as String?,
      category: row['category'] as String? ?? 'Other',
      vendorType: row['vendor_type'] as String? ?? 'Subcontractor',
      tags: tags,
      taxId: row['tax_id'],
      accountNumber: row['account_number'],
      paymentTerms: row['payment_terms'] != null
          ? PaymentTerms.fromString(row['payment_terms'])
          : null,
      address: row['address'],
      city: row['city'],
      state: row['state'],
      zipCode: row['zip_code'],
      country: row['country'],
      insurance: row['insurance'] != null
          ? InsuranceInfo.fromJson(row['insurance'] as Map<String, dynamic>)
          : null,
      licenses: licenses,
      isPreferred: row['is_preferred'] ?? false,
      discountRate: row['discount_rate']?.toDouble(),
      notes: row['notes'],
      isActive: row['is_active'] ?? true,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
      createdBy: row['created_by'] ?? '',
    );
  }

  /// Get specific validation error for better debugging
  String? _getValidationError(Vendor vendor) {
    if (vendor.companyName.trim().isEmpty) {
      return 'Company name is required';
    }
    if (vendor.contacts.isEmpty) {
      return 'At least one contact is required';
    }
    final primaryCount = vendor.contacts.where((c) => c.isPrimary).length;
    if (primaryCount == 0) {
      return 'A primary contact is required';
    }
    if (primaryCount > 1) {
      return 'Only one primary contact is allowed (found $primaryCount)';
    }
    for (int i = 0; i < vendor.contacts.length; i++) {
      final contactError = vendor.contacts[i].validate();
      if (contactError != null) {
        return 'Contact ${i + 1}: $contactError';
      }
    }
    if (vendor.notes != null && vendor.notes!.length > 2000) {
      return 'Notes cannot exceed 2000 characters';
    }
    return null;
  }

  /// Convert Vendor model to database format
  Map<String, dynamic> _toDbFormat(Vendor vendor) {
    return {
      'workspace_id': vendor.workspaceId,
      'company_name': vendor.companyName,
      'dba': vendor.dba,
      'website': vendor.website,
      'category': vendor.category,
      'vendor_type': vendor.vendorType,
      'tags': vendor.tags,
      'tax_id': vendor.taxId,
      'account_number': vendor.accountNumber,
      'payment_terms': vendor.paymentTerms?.toDbValue(),
      'address': vendor.address,
      'city': vendor.city,
      'state': vendor.state,
      'zip_code': vendor.zipCode,
      'country': vendor.country,
      'insurance': vendor.insurance?.toJson(),
      'licenses': vendor.licenses.map((l) => l.toJson()).toList(),
      'is_preferred': vendor.isPreferred,
      'discount_rate': vendor.discountRate,
      'business_phone': vendor.businessPhone,
      'business_email': vendor.businessEmail,
      'notes': vendor.notes,
      'is_active': vendor.isActive,
      'created_by': vendor.createdBy,
    };
  }
}
