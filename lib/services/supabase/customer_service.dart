import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/customer.dart';
import '../../models/project.dart';
import '../../utils/app_logger.dart';
import 'project_service.dart';

/// Supabase implementation of CustomerService
class SupabaseCustomerService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Cache for customer data
  static final Map<String, ({Customer customer, DateTime cachedAt})>
  _customerCache = {};
  static const _cacheDuration = Duration(minutes: 5);

  /// Get all active customers for a workspace (one-time)
  Future<List<Customer>> getCustomersOnce(String workspaceId) async {
    try {
      final response = await _supabase
          .from('customers')
          .select('''
            *,
            customer_contacts(*),
            customer_tag_assignments(tag_id)
          ''')
          .eq('workspace_id', workspaceId)
          .eq('is_active', true)
          .order('updated_at', ascending: false);

      return response.map((row) => _toCustomer(row)).toList();
    } catch (e) {
      AppLogger.error('Error fetching customers', error: e);
      return [];
    }
  }

  /// Get active customers (realtime stream)
  /// Note: Stream doesn't include contacts/tags for performance. Use getCustomer() for full data.
  Stream<List<Customer>> getCustomers(String workspaceId) {
    AppLogger.debug(
      'Fetching customers',
      metadata: {'workspaceId': workspaceId},
    );
    return _supabase
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .asyncMap((data) async {
          final activeRows = data
              .where((row) => row['is_active'] == true)
              .toList();

          // Fetch contacts and tags for all customers in batch
          if (activeRows.isEmpty) return <Customer>[];

          final customerIds = activeRows.map((r) => r['id'] as String).toList();

          // Fetch all contacts for these customers
          final contactsResponse = await _supabase
              .from('customer_contacts')
              .select()
              .inFilter('customer_id', customerIds);

          // Fetch all tag assignments for these customers
          final tagsResponse = await _supabase
              .from('customer_tag_assignments')
              .select('customer_id, tag_id')
              .inFilter('customer_id', customerIds);

          // Group contacts by customer_id
          final contactsByCustomer = <String, List<Map<String, dynamic>>>{};
          for (final contact in contactsResponse) {
            final customerId = contact['customer_id'] as String;
            contactsByCustomer.putIfAbsent(customerId, () => []).add(contact);
          }

          // Group tags by customer_id
          final tagsByCustomer = <String, List<String>>{};
          for (final tag in tagsResponse) {
            final customerId = tag['customer_id'] as String;
            tagsByCustomer
                .putIfAbsent(customerId, () => [])
                .add(tag['tag_id'] as String);
          }

          return activeRows.map((row) {
            final customerId = row['id'] as String;
            return _toCustomer(
              row,
              contacts: contactsByCustomer[customerId],
              tagIds: tagsByCustomer[customerId],
            );
          }).toList();
        });
  }

  /// Get a single customer by ID (with caching)
  Future<Customer?> getCustomer(String customerId) async {
    try {
      // Check cache first
      final cached = _customerCache[customerId];
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < _cacheDuration) {
          return cached.customer;
        } else {
          _customerCache.remove(customerId);
        }
      }

      // Fetch customer with contacts and tag assignments
      final response = await _supabase
          .from('customers')
          .select('''
            *,
            customer_contacts(*),
            customer_tag_assignments(tag_id)
          ''')
          .eq('id', customerId)
          .maybeSingle();

      if (response != null) {
        final customer = _toCustomer(response);
        _customerCache[customerId] = (
          customer: customer,
          cachedAt: DateTime.now(),
        );
        return customer;
      }
      return null;
    } catch (e) {
      AppLogger.error(
        'Failed to fetch customer',
        error: e,
        metadata: {'customerId': customerId},
      );
      throw Exception('Error fetching customer: $e');
    }
  }

  /// Stream a single customer with real-time updates, including contacts.
  Stream<Customer?> watchCustomer(String customerId) {
    return _supabase
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('id', customerId)
        .asyncMap((data) async {
          if (data.isEmpty) return null;
          final row = data.first;
          final contactsResponse = await _supabase
              .from('customer_contacts')
              .select()
              .eq('customer_id', customerId);
          return _toCustomer(
            row,
            contacts: List<Map<String, dynamic>>.from(contactsResponse),
          );
        });
  }

  /// Clear cache
  static void clearCache() {
    _customerCache.clear();
  }

  /// Clear specific customer from cache
  static void clearCustomerCache(String customerId) {
    _customerCache.remove(customerId);
  }

  Future<void> _touchCustomer(String customerId) async {
    await _supabase
        .from('customers')
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('id', customerId);
  }

  /// Create a new customer with contacts
  Future<Customer> createCustomerWithContacts(
    String workspaceId,
    Customer customer,
  ) async {
    try {
      final now = DateTime.now();
      final customerData = _toDbFormat(customer);
      customerData['workspace_id'] = workspaceId;
      customerData['is_active'] = true;
      customerData['created_at'] = now.toIso8601String();
      customerData['updated_at'] = now.toIso8601String();

      final response = await _supabase
          .from('customers')
          .insert(customerData)
          .select()
          .single();

      final customerId = response['id'] as String;

      // Insert contacts into customer_contacts table
      if (customer.contacts.isNotEmpty) {
        final contactsData = customer.contacts
            .map(
              (contact) => {
                'customer_id': customerId,
                'name': contact.name,
                'title': contact.title,
                'phone': contact.phone,
                'mobile_phone': contact.mobilePhone,
                'email': contact.email,
                'is_primary': contact.isPrimary,
                'is_active': contact.isActive,
                'created_at': now.toIso8601String(),
              },
            )
            .toList();

        await _supabase.from('customer_contacts').insert(contactsData);
      }

      // Insert tag assignments
      if (customer.tagIds.isNotEmpty) {
        final tagAssignments = customer.tagIds
            .map((tagId) => {'customer_id': customerId, 'tag_id': tagId})
            .toList();

        await _supabase.from('customer_tag_assignments').insert(tagAssignments);
      }

      await _touchCustomer(customerId);

      AppLogger.info(
        'Customer created successfully',
        metadata: {'customerId': customerId},
      );

      // Fetch the complete customer with contacts
      return await getCustomer(customerId) ?? _toCustomer(response);
    } catch (e) {
      AppLogger.error('Failed to create customer', error: e);
      throw Exception('Error creating customer: $e');
    }
  }

  /// Create a new customer (legacy format)
  Future<Customer> createCustomer({
    required String workspaceId,
    required String name,
    String? companyName,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String customerType = 'Residential',
    bool taxExempt = false,
    String? notes,
  }) async {
    try {
      final now = DateTime.now();
      final customerData = {
        'workspace_id': workspaceId,
        'company_name': companyName,
        'address': address,
        'city': city,
        'state': state,
        'zip_code': zipCode,
        'customer_type': customerType,
        'tax_exempt': taxExempt,
        'notes': notes,
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('customers')
          .insert(customerData)
          .select()
          .single();

      final customerId = response['id'] as String;

      // Legacy create path: map name/email/phone to a primary contact record.
      await _supabase.from('customer_contacts').insert({
        'customer_id': customerId,
        'name': name,
        'phone': phone,
        'email': email,
        'is_primary': true,
        'is_active': true,
        'created_at': now.toIso8601String(),
      });

      await _touchCustomer(customerId);

      AppLogger.info(
        'Customer created successfully',
        metadata: {'customerId': response['id'], 'name': name},
      );
      return await getCustomer(customerId) ?? _toCustomer(response);
    } catch (e) {
      AppLogger.error(
        'Failed to create customer',
        error: e,
        metadata: {'name': name},
      );
      throw Exception('Error creating customer: $e');
    }
  }

  /// Update an existing customer
  Future<void> updateCustomer(
    String customerId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final dbUpdates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      List<Map<String, dynamic>>? contacts;
      List<String>? tagIds;

      updates.forEach((key, value) {
        switch (key) {
          case 'contacts':
            contacts = _normalizeContacts(value);
            break;
          case 'tagIds':
            tagIds = _normalizeTagIds(value);
            break;
          case 'name':
          case 'email':
          case 'phone':
            // Legacy fields are derived from the primary contact in Supabase.
            break;
          default:
            final dbKey = _toSnakeCase(key);
            if (_customerColumns.contains(dbKey)) {
              dbUpdates[dbKey] = value;
            }
        }
      });

      await _supabase.from('customers').update(dbUpdates).eq('id', customerId);

      if (contacts != null) {
        // Diff-based sync: preserve ids (and their customer_contacts.user_id
        // portal linkage) for rows the caller still references. Only rows
        // dropped from the input get deleted.
        final existing = await _supabase
            .from('customer_contacts')
            .select('id')
            .eq('customer_id', customerId);
        final existingIds = (existing as List)
            .map((r) => (r as Map<String, dynamic>)['id'] as String)
            .toSet();
        final keepIds = contacts!
            .map((c) => (c['id'] ?? c['Id']) as String?)
            .whereType<String>()
            .toSet();
        final toDelete = existingIds.difference(keepIds).toList();
        if (toDelete.isNotEmpty) {
          await _supabase
              .from('customer_contacts')
              .delete()
              .inFilter('id', toDelete);
        }

        if (contacts!.isNotEmpty) {
          final now = DateTime.now().toIso8601String();
          Map<String, dynamic> payload(Map<String, dynamic> contact) => {
            'customer_id': customerId,
            'name': contact['name'],
            'title': contact['title'],
            'phone': contact['phone'],
            'mobile_phone':
                contact['mobile_phone'] ?? contact['mobilePhone'],
            'email': contact['email'],
            'is_primary': contact['is_primary'] ?? false,
            'is_active': contact['is_active'] ?? true,
          };

          final updates = contacts!
              .where((c) => (c['id'] ?? c['Id']) is String)
              .toList();
          final inserts = contacts!
              .where((c) => (c['id'] ?? c['Id']) is! String)
              .toList();

          if (updates.isNotEmpty) {
            await _supabase
                .from('customer_contacts')
                .upsert(
                  updates
                      .map(
                        (c) => {
                          'id': (c['id'] ?? c['Id']) as String,
                          ...payload(c),
                        },
                      )
                      .toList(),
                  onConflict: 'id',
                );
          }
          if (inserts.isNotEmpty) {
            await _supabase
                .from('customer_contacts')
                .insert(
                  inserts
                      .map((c) => {...payload(c), 'created_at': now})
                      .toList(),
                );
          }
        }
      }

      if (tagIds != null) {
        await _supabase
            .from('customer_tag_assignments')
            .delete()
            .eq('customer_id', customerId);

        if (tagIds!.isNotEmpty) {
          final tagAssignments = tagIds!
              .toSet()
              .map((tagId) => {'customer_id': customerId, 'tag_id': tagId})
              .toList();

          await _supabase
              .from('customer_tag_assignments')
              .insert(tagAssignments);
        }
      }

      await _touchCustomer(customerId);

      clearCustomerCache(customerId);
    } catch (e) {
      AppLogger.error(
        'Failed to update customer',
        error: e,
        metadata: {'customerId': customerId},
      );
      throw Exception('Error updating customer: $e');
    }
  }

  /// Archive a customer (soft delete)
  Future<void> archiveCustomer(String customerId) async {
    try {
      await _supabase
          .from('customers')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', customerId);

      clearCustomerCache(customerId);
    } catch (e) {
      AppLogger.error(
        'Failed to archive customer',
        error: e,
        metadata: {'customerId': customerId},
      );
      throw Exception('Error archiving customer: $e');
    }
  }

  /// Restore an archived customer
  Future<void> restoreCustomer(String customerId) async {
    try {
      await _supabase
          .from('customers')
          .update({
            'is_active': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', customerId);

      clearCustomerCache(customerId);
    } catch (e) {
      AppLogger.error(
        'Failed to restore customer',
        error: e,
        metadata: {'customerId': customerId},
      );
      throw Exception('Error restoring customer: $e');
    }
  }

  /// Search customers
  Stream<List<Customer>> searchCustomers(String workspaceId, String query) {
    return getCustomers(workspaceId).map((customers) {
      final lowerQuery = query.toLowerCase();
      return customers.where((customer) {
        return customer.name.toLowerCase().contains(lowerQuery) ||
            (customer.companyName?.toLowerCase().contains(lowerQuery) ??
                false) ||
            (customer.email?.toLowerCase().contains(lowerQuery) ?? false) ||
            (customer.phone?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    });
  }

  /// Get customers by type
  Stream<List<Customer>> getCustomersByType(String workspaceId, String type) {
    return _supabase
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((data) async {
          final filtered = data
              .where(
                (row) =>
                    row['customer_type'] == type && row['is_active'] == true,
              )
              .toList();

          if (filtered.isEmpty) return <Customer>[];

          final customerIds = filtered.map((r) => r['id'] as String).toList();
          final contactsResponse = await _supabase
              .from('customer_contacts')
              .select()
              .inFilter('customer_id', customerIds);

          final contactsByCustomer = <String, List<Map<String, dynamic>>>{};
          for (final contact in contactsResponse) {
            final customerId = contact['customer_id'] as String;
            contactsByCustomer.putIfAbsent(customerId, () => []).add(contact);
          }

          final customers = filtered.map((row) {
            final customerId = row['id'] as String;
            return _toCustomer(row, contacts: contactsByCustomer[customerId]);
          }).toList();

          customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return customers;
        });
  }

  /// Get archived customers
  Stream<List<Customer>> getArchivedCustomers(String workspaceId) {
    return _supabase
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((data) async {
          final filtered = data
              .where((row) => row['is_active'] == false)
              .toList();

          if (filtered.isEmpty) return <Customer>[];

          final customerIds = filtered.map((r) => r['id'] as String).toList();
          final contactsResponse = await _supabase
              .from('customer_contacts')
              .select()
              .inFilter('customer_id', customerIds);

          final contactsByCustomer = <String, List<Map<String, dynamic>>>{};
          for (final contact in contactsResponse) {
            final customerId = contact['customer_id'] as String;
            contactsByCustomer.putIfAbsent(customerId, () => []).add(contact);
          }

          final customers = filtered.map((row) {
            final customerId = row['id'] as String;
            return _toCustomer(row, contacts: contactsByCustomer[customerId]);
          }).toList();

          customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return customers;
        });
  }

  /// Get all projects for a customer
  Stream<List<Project>> getCustomerProjects(String customerId) {
    return _supabase
        .from('projects')
        .stream(primaryKey: ['id'])
        .eq('client_id', customerId)
        .order('updated_at', ascending: false)
        .asyncMap((data) async {
          final projectIds = data.map((row) => row['id'] as String).toList();
          final teamMap = await _fetchTeamMemberMap(projectIds);
          return data.map((row) {
            row['team_member_ids'] = teamMap[row['id']] ?? [];
            return _projectFromRow(row);
          }).toList();
        });
  }

  /// Calculate total revenue from a customer
  Future<double> calculateCustomerRevenue(String customerId) async {
    try {
      final projects = await _supabase
          .from('projects')
          .select('id')
          .eq('client_id', customerId);

      if (projects.isEmpty) return 0.0;

      final projectIds = projects.map((p) => p['id'] as String).toList();

      final invoices = await _supabase
          .from('generated_documents')
          .select('total_amount, amount_paid, paid_date')
          .eq('document_type', 'invoice')
          .inFilter('project_id', projectIds)
          // Fully-paid invoices OR open invoices carrying partial payments.
          .or('paid_date.not.is.null,amount_paid.gt.0');

      return SupabaseProjectService.sumCollectedRevenueFromRows(invoices);
    } catch (e) {
      AppLogger.error(
        'Failed to calculate customer revenue',
        error: e,
        metadata: {'customerId': customerId},
      );
      return 0.0;
    }
  }

  /// Aggregated stats for a single customer card / table row.
  /// Open jobs = ProjectStatus.isOpen (active, on hold, awarded).
  /// Closed jobs = ProjectStatus.isClosed (complete, lost, canceled).
  /// Pipeline stages (lead, bidding, proposal sent) are excluded from both.
  Future<CustomerStats> getCustomerStats(String customerId) async {
    try {
      final Future<List<Map<String, dynamic>>> projectsFuture = _supabase
          .from('projects')
          .select('id, status')
          .eq('client_id', customerId);
      final lastActivityFuture = getLastActivityDate(customerId);
      final results = await Future.wait<Object?>(
          [projectsFuture, lastActivityFuture]);
      final projects = results[0] as List<dynamic>;
      final lastActivity = results[1] as DateTime?;

      int openJobs = 0;
      int closedJobs = 0;
      final projectIds = <String>[];
      for (final row in projects) {
        final map = row as Map<String, dynamic>;
        projectIds.add(map['id'] as String);
        final statusRaw = map['status'] as String?;
        if (statusRaw == null) continue;
        try {
          final status = ProjectStatus.fromString(statusRaw);
          if (status.isOpen) openJobs++;
          if (status.isClosed) closedJobs++;
        } catch (_) {
          // Unknown status — skip rather than throw.
        }
      }

      double collectedRevenue = 0.0;
      if (projectIds.isNotEmpty) {
        final invoices = await _supabase
            .from('generated_documents')
            .select('total_amount, amount_paid, paid_date')
            .eq('document_type', 'invoice')
            .inFilter('project_id', projectIds)
            .or('paid_date.not.is.null,amount_paid.gt.0');
        collectedRevenue =
            SupabaseProjectService.sumCollectedRevenueFromRows(invoices);
      }

      return CustomerStats(
        openJobs: openJobs,
        closedJobs: closedJobs,
        totalProjects: projects.length,
        collectedRevenue: collectedRevenue,
        lastActivity: lastActivity,
      );
    } catch (e) {
      AppLogger.error(
        'Failed to get customer stats',
        error: e,
        metadata: {'customerId': customerId},
      );
      return const CustomerStats.empty();
    }
  }

  /// Get last activity date for a customer (most recent project update)
  Future<DateTime?> getLastActivityDate(String customerId) async {
    try {
      final response = await _supabase
          .from('projects')
          .select('updated_at')
          .eq('client_id', customerId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      final updatedAt = response['updated_at'];
      if (updatedAt is String) {
        return DateTime.parse(updatedAt);
      }
      return null;
    } catch (e) {
      AppLogger.error(
        'Failed to get last activity date',
        error: e,
        metadata: {'customerId': customerId},
      );
      return null;
    }
  }

  /// Get child customers
  Future<List<Customer>> getChildCustomers(
    String parentCustomerId,
    String workspaceId,
  ) async {
    try {
      final response = await _supabase
          .from('customers')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('parent_customer_id', parentCustomerId)
          .eq('is_active', true);

      return response.map((row) => _toCustomer(row)).toList();
    } catch (e) {
      AppLogger.error('Failed to get child customers', error: e);
      throw Exception('Error fetching child customers: $e');
    }
  }

  /// Add tag to customer
  Future<void> addTagToCustomer(String customerId, String tagId) async {
    try {
      // Insert into junction table (will fail silently if already exists due to primary key)
      await _supabase.from('customer_tag_assignments').upsert({
        'customer_id': customerId,
        'tag_id': tagId,
      });

      // Update customer's updated_at timestamp
      await _supabase
          .from('customers')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', customerId);

      clearCustomerCache(customerId);
    } catch (e) {
      AppLogger.error('Failed to add tag to customer', error: e);
      rethrow;
    }
  }

  /// Remove tag from customer
  Future<void> removeTagFromCustomer(String customerId, String tagId) async {
    try {
      await _supabase
          .from('customer_tag_assignments')
          .delete()
          .eq('customer_id', customerId)
          .eq('tag_id', tagId);

      // Update customer's updated_at timestamp
      await _supabase
          .from('customers')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', customerId);

      clearCustomerCache(customerId);
    } catch (e) {
      AppLogger.error('Failed to remove tag from customer', error: e);
      rethrow;
    }
  }

  /// Convert database row to Customer model
  /// Contacts and tags should be fetched separately or via join
  Customer _toCustomer(
    Map<String, dynamic> row, {
    List<Map<String, dynamic>>? contacts,
    List<String>? tagIds,
  }) {
    // Convert contacts from customer_contacts table format
    List<Map<String, dynamic>> contactsList = [];
    if (contacts != null) {
      contactsList = contacts;
    } else if (row['customer_contacts'] != null) {
      // Handle joined data
      contactsList = List<Map<String, dynamic>>.from(row['customer_contacts']);
    }

    // Get tag IDs from junction table if available
    List<String> tags = tagIds ?? [];
    if (row['customer_tag_assignments'] != null) {
      tags = (row['customer_tag_assignments'] as List)
          .map((t) => t['tag_id'] as String)
          .toList();
    }

    return Customer.fromJson({
      'id': row['id'],
      'workspaceId': row['workspace_id'],
      'companyName': row['company_name'],
      'address': row['address'],
      'city': row['city'],
      'state': row['state'],
      'zipCode': row['zip_code'],
      'country': row['country'],
      'customerType': row['customer_type'],
      'taxExempt': row['tax_exempt'] ?? false,
      'notes': row['notes'],
      'isActive': row['is_active'] ?? true,
      'parentCustomerId': row['parent_customer_id'],
      'contacts': contactsList,
      'tagIds': tags,
      'accountOwnerId': row['account_owner_id'],
      'status': row['status'],
      'source': row['source'],
      'referrerName': row['referrer_name'],
      'businessPhone': row['business_phone'],
      'businessEmail': row['business_email'],
      'website': row['website'],
      'logoUrl': row['logo_url'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
    }, row['id']);
  }

  /// Convert Customer model to database format
  /// Note: contacts are stored in separate customer_contacts table
  /// Note: tags are stored in customer_tag_assignments junction table
  Map<String, dynamic> _toDbFormat(Customer customer) {
    return {
      'company_name': customer.companyName,
      'address': customer.address,
      'city': customer.city,
      'state': customer.state,
      'zip_code': customer.zipCode,
      'country': customer.country,
      'customer_type': customer.customerType,
      'tax_exempt': customer.taxExempt,
      'notes': customer.notes,
      'is_active': customer.isActive,
      'parent_customer_id': customer.parentCustomerId,
      'status': customer.status.name,
      'source': customer.source?.toDbValue(),
      'referrer_name': customer.referrerName,
      'account_owner_id': customer.accountOwnerId,
      'business_phone': customer.businessPhone,
      'business_email': customer.businessEmail,
      'website': customer.website,
      'logo_url': customer.logoUrl,
    };
  }

  List<Map<String, dynamic>> _normalizeContacts(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map(
          (contact) => {
            'name': contact['name'],
            'title': contact['title'],
            'phone': contact['phone'],
            'mobile_phone': contact['mobile_phone'] ?? contact['mobilePhone'],
            'email': contact['email'],
            'is_primary': contact['is_primary'] ?? contact['isPrimary'],
            'is_active': contact['is_active'] ?? contact['isActive'],
          },
        )
        .where(
          (contact) => (contact['name'] as String?)?.trim().isNotEmpty == true,
        )
        .toList();
  }

  List<String> _normalizeTagIds(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }

  /// Convert camelCase to snake_case
  String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  static const Set<String> _customerColumns = {
    'parent_customer_id',
    'company_name',
    'business_phone',
    'business_email',
    'website',
    'status',
    'source',
    'referrer_name',
    'account_owner_id',
    'logo_url',
    'address',
    'city',
    'state',
    'zip_code',
    'country',
    'customer_type',
    'tax_exempt',
    'notes',
    'is_active',
    'updated_at',
  };

  /// Convert project row to Project model
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

  Future<Map<String, List<String>>> _fetchTeamMemberMap(
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) return {};
    final teamRows = await _supabase
        .from('project_team_members')
        .select('project_id, user_id')
        .inFilter('project_id', projectIds);
    final map = <String, List<String>>{};
    for (final row in teamRows) {
      final pid = row['project_id'] as String;
      map.putIfAbsent(pid, () => []).add(row['user_id'] as String);
    }
    return map;
  }

  Timestamp? _toTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is String) {
      return Timestamp.fromDate(DateTime.parse(value));
    }
    return null;
  }
}

class CustomerStats {
  final int openJobs;
  final int closedJobs;
  final int totalProjects;
  final double collectedRevenue;
  final DateTime? lastActivity;

  const CustomerStats({
    required this.openJobs,
    required this.closedJobs,
    required this.totalProjects,
    required this.collectedRevenue,
    required this.lastActivity,
  });

  const CustomerStats.empty()
      : openJobs = 0,
        closedJobs = 0,
        totalProjects = 0,
        collectedRevenue = 0,
        lastActivity = null;
}
