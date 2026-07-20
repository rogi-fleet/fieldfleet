import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/customer.dart';
import '../models/project.dart';
import '../utils/app_logger.dart';
import 'analytics_service.dart';

class CustomerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AnalyticsService _analytics = AnalyticsService();

  // Cache for customer data
  static final Map<String, ({Customer customer, DateTime cachedAt})> _customerCache = {};
  static const _cacheDuration = Duration(minutes: 5);

  // Get all active customers for a workspace (one-time)
  Future<List<Customer>> getCustomersOnce(String workspaceId) async {
    try {
      final snapshot = await _firestore
          .collection('clients')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      final customers = snapshot.docs
          .map((doc) => Customer.fromJson(doc.data(), doc.id))
          .where((customer) => customer.isActive)
          .toList();

      customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return customers;
    } catch (e) {
      return [];
    }
  }

  // Get active customers
  Stream<List<Customer>> getCustomers(String workspaceId) {
    AppLogger.debug('Fetching customers', metadata: {'workspaceId': workspaceId});
    return _firestore
        .collection('clients') // Keep collection name for backward compatibility
        .where('workspaceId', isEqualTo: workspaceId)
        // Temporarily remove orderBy while index is building
        // .orderBy('updatedAt', descending: true)
        .snapshots()
        .handleError((error) {
      AppLogger.error('Error in getCustomers stream', error: error, metadata: {'workspaceId': workspaceId});
      throw error;
    }).map((snapshot) {
      AppLogger.debug('Received customer documents', metadata: {
        'workspaceId': workspaceId,
        'documentCount': snapshot.docs.length,
      });
      try {
        final customers = snapshot.docs
            .map((doc) {
          try {
            return Customer.fromJson(doc.data(), doc.id);
          } catch (e) {
            AppLogger.error('Error parsing customer document', error: e, metadata: {
              'customerId': doc.id,
              'workspaceId': workspaceId,
            });
            rethrow;
          }
        })
            .where((customer) => customer.isActive) // Filter in-memory for backward compatibility
            .toList();

        // Sort in-memory while index is building
        customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        AppLogger.debug('Returning active customers', metadata: {
          'workspaceId': workspaceId,
          'customerCount': customers.length,
        });
        return customers;
      } catch (e) {
        AppLogger.error('Error mapping customers', error: e, metadata: {'workspaceId': workspaceId});
        rethrow;
      }
    });
  }

  // Get a single customer by ID (with caching)
  Future<Customer?> getCustomer(String customerId) async {
    try {
      // Check cache first
      final cached = _customerCache[customerId];
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < _cacheDuration) {
          return cached.customer;
        } else {
          // Remove stale cache entry
          _customerCache.remove(customerId);
        }
      }

      // Fetch from Firestore
      final doc = await _firestore.collection('clients').doc(customerId).get();
      if (doc.exists) {
        final customer = Customer.fromJson(doc.data()!, doc.id);

        // Update cache
        _customerCache[customerId] = (customer: customer, cachedAt: DateTime.now());

        return customer;
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to fetch customer', error: e, metadata: {'customerId': customerId});
      throw Exception('Error fetching customer: $e');
    }
  }

  // Clear cache (useful for testing or after updates)
  static void clearCache() {
    _customerCache.clear();
  }

  // Clear specific customer from cache
  static void clearCustomerCache(String customerId) {
    _customerCache.remove(customerId);
  }

  // Create a new customer with contacts (new format)
  Future<Customer> createCustomerWithContacts(
    String workspaceId,
    Customer customer,
  ) async {
    try {
      final customerData = customer.toJson();
      customerData['workspaceId'] = workspaceId;
      customerData['isActive'] = true;
      customerData['createdAt'] = Timestamp.fromDate(DateTime.now());
      customerData['updatedAt'] = Timestamp.fromDate(DateTime.now());

      final docRef = await _firestore.collection('clients').add(customerData);
      AppLogger.info('Customer created successfully', metadata: {'customerId': docRef.id});

      // Track customer creation in Analytics
      await _analytics.logCustomerCreated(
        customerId: docRef.id,
        customerType: customer.customerType,
      );

      return Customer.fromJson(customerData, docRef.id);
    } catch (e) {
      AppLogger.error('Failed to create customer', error: e);
      throw Exception('Error creating customer: $e');
    }
  }

  // Create a new customer (legacy format - for backward compatibility)
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
        'workspaceId': workspaceId,
        'name': name,
        'companyName': companyName,
        'email': email,
        'phone': phone,
        'address': address,
        'city': city,
        'state': state,
        'zipCode': zipCode,
        'customerType': customerType,
        'taxExempt': taxExempt,
        'notes': notes,
        'isActive': true,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      final docRef = await _firestore.collection('clients').add(customerData);
      AppLogger.info('Customer created successfully (legacy format)', metadata: {'customerId': docRef.id, 'name': name});

      // Track customer creation in Analytics
      await _analytics.logCustomerCreated(
        customerId: docRef.id,
        customerType: customerType,
      );

      return Customer.fromJson(customerData, docRef.id);
    } catch (e) {
      AppLogger.error('Failed to create customer (legacy format)', error: e, metadata: {'name': name});
      throw Exception('Error creating customer: $e');
    }
  }

  // Update an existing customer
  Future<void> updateCustomer(
    String customerId,
    Map<String, dynamic> updates,
  ) async {
    try {
      updates['updatedAt'] = Timestamp.fromDate(DateTime.now());
      await _firestore.collection('clients').doc(customerId).update(updates);

      // Clear cache for this customer
      clearCustomerCache(customerId);
    } catch (e) {
      AppLogger.error('Failed to update customer', error: e, metadata: {'customerId': customerId});
      throw Exception('Error updating customer: $e');
    }
  }

  // Archive a customer (soft delete)
  Future<void> archiveCustomer(String customerId) async {
    try {
      await _firestore.collection('clients').doc(customerId).update({
        'isActive': false,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Clear cache for this customer
      clearCustomerCache(customerId);
    } catch (e) {
      AppLogger.error('Failed to archive customer', error: e, metadata: {'customerId': customerId});
      throw Exception('Error archiving customer: $e');
    }
  }

  // Restore an archived customer
  Future<void> restoreCustomer(String customerId) async {
    try {
      await _firestore.collection('clients').doc(customerId).update({
        'isActive': true,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      AppLogger.error('Failed to restore customer', error: e, metadata: {'customerId': customerId});
      throw Exception('Error restoring customer: $e');
    }
  }

  // Search customers by name, company, email, or phone
  Stream<List<Customer>> searchCustomers(
    String workspaceId,
    String query,
  ) {
    // Get all customers and filter client-side for now
    // For production, consider using Algolia or Firestore's full-text search
    return getCustomers(workspaceId).map((customers) {
      final lowerQuery = query.toLowerCase();
      return customers.where((customer) {
        return customer.name.toLowerCase().contains(lowerQuery) ||
            (customer.companyName?.toLowerCase().contains(lowerQuery) ?? false) ||
            (customer.email?.toLowerCase().contains(lowerQuery) ?? false) ||
            (customer.phone?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    });
  }

  // Get customers by type
  Stream<List<Customer>> getCustomersByType(
    String workspaceId,
    String type,
  ) {
    return _firestore
        .collection('clients')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots()
        .map((snapshot) {
      final customers = snapshot.docs
          .map((doc) => Customer.fromJson(doc.data(), doc.id))
          .where((customer) => customer.customerType == type && customer.isActive)
          .toList();

      customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return customers;
    });
  }

  // Get active customers
  Stream<List<Customer>> getActiveCustomers(String workspaceId) {
    return getCustomers(workspaceId);
  }

  // Get archived customers
  Stream<List<Customer>> getArchivedCustomers(String workspaceId) {
    return _firestore
        .collection('clients')
        .where('workspaceId', isEqualTo: workspaceId)
        // Temporarily remove orderBy while index is building
        // .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final customers = snapshot.docs
          .map((doc) => Customer.fromJson(doc.data(), doc.id))
          .where((customer) => !customer.isActive) // Filter in-memory
          .toList();

      // Sort in-memory while index is building
      customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return customers;
    });
  }

  // Get all projects for a customer
  Stream<List<Project>> getCustomerProjects(String customerId) {
    return _firestore
        .collection('projects')
        .where('clientId', isEqualTo: customerId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Project.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Calculate total revenue from a customer (sum of paid invoices)
  Future<double> calculateCustomerRevenue(String customerId) async {
    try {
      // Get all projects for this customer
      final projectsSnapshot = await _firestore
          .collection('projects')
          .where('clientId', isEqualTo: customerId)
          .get();

      if (projectsSnapshot.docs.isEmpty) {
        return 0.0;
      }

      final projectIds = projectsSnapshot.docs.map((doc) => doc.id).toList();

      // Get all paid invoices for these projects
      double totalRevenue = 0.0;
      for (final projectId in projectIds) {
        final invoicesSnapshot = await _firestore
            .collection('invoices')
            .where('projectId', isEqualTo: projectId)
            .where('status', isEqualTo: 'paid')
            .get();

        for (final doc in invoicesSnapshot.docs) {
          final data = doc.data();
          totalRevenue += (data['total'] as num?)?.toDouble() ?? 0.0;
        }
      }

      return totalRevenue;
    } catch (e) {
      AppLogger.error('Failed to calculate customer revenue', error: e, metadata: {'customerId': customerId});
      return 0.0;
    }
  }

  // Get last activity date for a customer (most recent project update)
  Future<DateTime?> getLastActivityDate(String customerId) async {
    try {
      final projectsSnapshot = await _firestore
          .collection('projects')
          .where('clientId', isEqualTo: customerId)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();

      if (projectsSnapshot.docs.isEmpty) {
        return null;
      }

      final project = Project.fromJson(
        projectsSnapshot.docs.first.data(),
        projectsSnapshot.docs.first.id,
      );
      return project.updatedAt;
    } catch (e) {
      AppLogger.error('Failed to get last activity date', error: e, metadata: {'customerId': customerId});
      return null;
    }
  }

  // Get project counts by status for a customer
  Future<Map<ProjectStatus, int>> getProjectCounts(String customerId) async {
    try {
      final projectsSnapshot = await _firestore
          .collection('projects')
          .where('clientId', isEqualTo: customerId)
          .get();

      final counts = <ProjectStatus, int>{
        for (final s in ProjectStatus.values) s: 0,
      };

      for (final doc in projectsSnapshot.docs) {
        final project = Project.fromJson(doc.data(), doc.id);
        counts[project.status] = (counts[project.status] ?? 0) + 1;
      }

      return counts;
    } catch (e) {
      AppLogger.error('Failed to get project counts', error: e, metadata: {'customerId': customerId});
      return {};
    }
  }

  // ============================================================================
  // Hierarchy Operations
  // ============================================================================

  /// Get all child customers for a parent customer
  Future<List<Customer>> getChildCustomers(String parentCustomerId, String workspaceId) async {
    try {
      final snapshot = await _firestore
          .collection('clients')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('parentCustomerId', isEqualTo: parentCustomerId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => Customer.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to get child customers', error: e, metadata: {'parentCustomerId': parentCustomerId, 'workspaceId': workspaceId});
      throw Exception('Error fetching child customers: $e');
    }
  }

  /// Get parent customer
  Future<Customer?> getParentCustomer(String parentCustomerId) async {
    return await getCustomer(parentCustomerId);
  }

  /// Get only parent customers (customers with no parent and have children)
  Stream<List<Customer>> getParentCustomers(String workspaceId) {
    return _firestore
        .collection('clients')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .asyncMap((snapshot) async {
      // Get all customers
      final allCustomers = snapshot.docs
          .map((doc) => Customer.fromJson(doc.data(), doc.id))
          .toList();

      // Filter to only those without parents
      final potentialParents = allCustomers.where((c) => !c.hasParent).toList();

      // Check which ones actually have children
      final parents = <Customer>[];
      for (final customer in potentialParents) {
        final children = await getChildCustomers(customer.id, workspaceId);
        if (children.isNotEmpty) {
          parents.add(customer);
        }
      }

      return parents;
    });
  }

  /// Get all projects for a parent and its children
  Future<List<Project>> getProjectsForCustomerHierarchy(String customerId) async {
    try {
      // Get the customer to access its workspaceId
      final customer = await getCustomer(customerId);
      if (customer == null) {
        throw Exception('Customer not found');
      }

      // Get projects for this customer
      final customerProjects = await _firestore
          .collection('projects')
          .where('clientId', isEqualTo: customerId)
          .get();

      final projects = customerProjects.docs
          .map((doc) => Project.fromJson(doc.data(), doc.id))
          .toList();

      // Get child customers
      final children = await getChildCustomers(customerId, customer.workspaceId);

      // Get projects for each child
      for (final child in children) {
        final childProjects = await _firestore
            .collection('projects')
            .where('clientId', isEqualTo: child.id)
            .get();

        projects.addAll(
          childProjects.docs.map((doc) => Project.fromJson(doc.data(), doc.id)),
        );
      }

      return projects;
    } catch (e) {
      AppLogger.error('Failed to get hierarchy projects', error: e, metadata: {'customerId': customerId});
      throw Exception('Error fetching hierarchy projects: $e');
    }
  }

  /// Check if a customer can be set as parent (prevent circular references)
  Future<bool> canSetAsParent(String customerId, String potentialParentId) async {
    if (customerId == potentialParentId) return false;
    if (potentialParentId.isEmpty) return true;

    try {
      final potentialParent = await getCustomer(potentialParentId);
      if (potentialParent == null) return false;

      if (potentialParent.parentCustomerId == customerId) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  // ===========================================================================
  // Phase 1: New Filtering and Management Methods
  // ===========================================================================

  /// Get customers by status
  Stream<List<Customer>> getCustomersByStatus(
    String workspaceId,
    String status,
  ) {
    return _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('customers')
        .where('status', isEqualTo: status)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Customer.fromJson(doc.data(), doc.id))
            .toList());
  }

  /// Get customers by account owner
  Stream<List<Customer>> getCustomersByOwner(
    String workspaceId,
    String ownerId,
  ) {
    return _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('customers')
        .where('accountOwnerId', isEqualTo: ownerId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Customer.fromJson(doc.data(), doc.id))
            .toList());
  }

  /// Get customers by tag
  Stream<List<Customer>> getCustomersByTag(
    String workspaceId,
    String tagId,
  ) {
    return _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('customers')
        .where('tagIds', arrayContains: tagId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Customer.fromJson(doc.data(), doc.id))
            .toList());
  }

  /// Get customers by source
  Stream<List<Customer>> getCustomersBySource(
    String workspaceId,
    String source,
  ) {
    return _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('customers')
        .where('source', isEqualTo: source)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Customer.fromJson(doc.data(), doc.id))
            .toList());
  }

  /// Update customer status
  Future<void> updateCustomerStatus(String customerId, String status) async {
    try {
      await _firestore.collection('customers').doc(customerId).update({
        'status': status,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      clearCustomerCache(customerId);

      AppLogger.info('Updated customer status', metadata: {
        'customerId': customerId,
        'status': status,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update customer status',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Assign account owner to customer
  Future<void> assignAccountOwner(String customerId, String? ownerId) async {
    try {
      await _firestore.collection('customers').doc(customerId).update({
        'accountOwnerId': ownerId,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      clearCustomerCache(customerId);

      AppLogger.info('Assigned account owner', metadata: {
        'customerId': customerId,
        'ownerId': ownerId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to assign account owner',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Add tag to customer
  Future<void> addTagToCustomer(String customerId, String tagId) async {
    try {
      await _firestore.collection('customers').doc(customerId).update({
        'tagIds': FieldValue.arrayUnion([tagId]),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      clearCustomerCache(customerId);

      AppLogger.info('Added tag to customer', metadata: {
        'customerId': customerId,
        'tagId': tagId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add tag to customer',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Remove tag from customer
  Future<void> removeTagFromCustomer(String customerId, String tagId) async {
    try {
      await _firestore.collection('customers').doc(customerId).update({
        'tagIds': FieldValue.arrayRemove([tagId]),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      clearCustomerCache(customerId);

      AppLogger.info('Removed tag from customer', metadata: {
        'customerId': customerId,
        'tagId': tagId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to remove tag from customer',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
