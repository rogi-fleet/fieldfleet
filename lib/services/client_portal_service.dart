import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/client_user.dart';
import '../models/customer.dart';
import '../models/document_type.dart';
import '../models/generated_document.dart';
import '../models/portal_invoice_summary.dart';
import '../models/project.dart';
import '../utils/app_logger.dart';

/// Service for client portal authentication and data access
/// Clients authenticate via magic link and access data based on their email
class ClientPortalService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Collections
  CollectionReference get _clientUsersRef =>
      _firestore.collection('client_users');
  // ignore: unused_element
  CollectionReference get _clientSessionsRef =>
      _firestore.collection('client_sessions');
  CollectionReference get _clientPortalInvitesRef =>
      _firestore.collection('client_portal_invites');
  CollectionReference get _customersRef => _firestore.collection('customers');
  CollectionReference get _projectsRef => _firestore.collection('projects');
  CollectionReference get _generatedDocumentsRef =>
      _firestore.collection('generated_documents');

  // ============================================================================
  // Magic Link Authentication
  // ============================================================================

  /// Request a magic link for the given email
  /// Returns true if email was sent, false if email not found in any customer
  Future<bool> requestMagicLink(
    String email, {
    String? workspaceId,
    String? customerId,
    String? sentBy,
  }) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();

      // Check if email exists in any customer contact
      final hasAccess = await _emailHasAccess(normalizedEmail);
      if (!hasAccess) {
        AppLogger.warning('Magic link requested for unknown email: $email');
        return false;
      }

      // Call Cloud Function to send magic link
      final callable = _functions.httpsCallable('sendClientMagicLink');
      await callable.call({'email': normalizedEmail});

      if (workspaceId != null && customerId != null) {
        await _recordPortalInviteSend(
          workspaceId: workspaceId,
          customerId: customerId,
          email: normalizedEmail,
          sentBy: sentBy,
        );
      }

      AppLogger.info('Magic link sent to: $email');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to send magic link',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Validate a magic link token
  /// Returns the client context if valid, null otherwise
  Future<ClientPortalContext?> validateMagicLink(String token) async {
    try {
      // Call Cloud Function to validate
      final callable = _functions.httpsCallable('validateClientMagicLink');
      final result = await callable.call({'token': token});

      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) {
        return null;
      }

      final email = data['email'] as String;
      final customerIds = List<String>.from(data['customerIds'] ?? []);

      return ClientPortalContext(email: email, customerIds: customerIds);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to validate magic link',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Sign out from client portal.
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  // ============================================================================
  // Customer & Project Access
  // ============================================================================

  /// Get all customers where the given email is a contact
  Future<List<Customer>> getAccessibleCustomers(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();

      // Query all customers and filter by contacts
      // Note: Firestore doesn't support querying array of objects by field,
      // so we fetch all and filter client-side (consider denormalization for scale)
      final snapshot = await _customersRef.get();

      final customers = <Customer>[];
      for (final doc in snapshot.docs) {
        final customer = Customer.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );

        // Check if email matches any contact
        final hasContact = customer.contacts.any(
          (c) => c.email?.toLowerCase() == normalizedEmail && c.isActive,
        );

        if (hasContact) {
          customers.add(customer);
        }
      }

      return customers;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get accessible customers',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get all projects for the given customer IDs
  Future<List<Project>> getClientProjects(List<String> customerIds) async {
    if (customerIds.isEmpty) return [];

    try {
      final projects = <Project>[];

      // Firestore whereIn has a limit of 10, so batch if needed
      for (var i = 0; i < customerIds.length; i += 10) {
        final batch = customerIds.skip(i).take(10).toList();
        final snapshot = await _projectsRef
            .where('clientId', whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          projects.add(
            Project.fromJson(doc.data() as Map<String, dynamic>, doc.id),
          );
        }
      }

      // Sort by updatedAt descending
      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return projects;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get client projects',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get projects accessible by a specific email
  Future<List<Project>> getProjectsForEmail(String email) async {
    final customers = await getAccessibleCustomers(email);
    final customerIds = customers.map((c) => c.id).toList();
    return getClientProjects(customerIds);
  }

  /// Get a single project by ID (with access check)
  Future<Project?> getProject(String projectId, String email) async {
    try {
      final customers = await getAccessibleCustomers(email);
      final customerIds = customers.map((c) => c.id).toSet();

      final doc = await _projectsRef.doc(projectId).get();
      if (!doc.exists || doc.data() == null) return null;

      final project = Project.fromJson(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
      if (project.clientId != null && customerIds.contains(project.clientId)) {
        return project;
      }

      return null;
    } catch (e) {
      AppLogger.error('Failed to get project', error: e);
      return null;
    }
  }

  /// Returns the authenticated portal email, if available.
  String? getPortalEmail() {
    final email = FirebaseAuth.instance.currentUser?.email;
    final normalized = email?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  /// Secure project list for current portal user.
  Future<List<Project>> getPortalProjects() async {
    final email = getPortalEmail();
    if (email == null) return [];
    return getProjectsForEmail(email);
  }

  /// Secure single project fetch for current portal user.
  Future<Project?> getPortalProject(String projectId) async {
    final email = getPortalEmail();
    if (email == null) return null;
    return getProject(projectId, email);
  }

  /// Secure invoice list for current portal user.
  Future<List<PortalInvoiceSummary>> getPortalInvoices({
    String? projectId,
  }) async {
    final projects = await getPortalProjects();
    if (projects.isEmpty) return [];

    final projectById = {for (final project in projects) project.id: project};
    final accessibleProjectIds = projectById.keys.toSet();
    if (accessibleProjectIds.isEmpty) return [];

    final targetProjectIds = projectId == null
        ? accessibleProjectIds.toList()
        : (accessibleProjectIds.contains(projectId) ? [projectId] : <String>[]);

    if (targetProjectIds.isEmpty) return [];

    final rows = <QueryDocumentSnapshot>[];
    for (final batch in _chunk(targetProjectIds, 10)) {
      final snapshot = await _generatedDocumentsRef
          .where('projectId', whereIn: batch)
          .where('documentType', isEqualTo: 'invoice')
          .get();
      rows.addAll(snapshot.docs);
    }

    final summaries = rows.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final document = GeneratedDocument.fromJson(data, doc.id);
      return PortalInvoiceSummary(
        invoice: document,
        projectName: projectById[document.projectId]?.name,
      );
    }).toList();

    summaries.sort((a, b) {
      final aDue = a.invoice.dueDate ?? a.invoice.createdAt;
      final bDue = b.invoice.dueDate ?? b.invoice.createdAt;
      return bDue.compareTo(aDue);
    });
    return summaries;
  }

  /// Secure single invoice fetch for current portal user.
  Future<GeneratedDocument?> getPortalInvoice(String invoiceId) async {
    final invoiceDoc = await _generatedDocumentsRef.doc(invoiceId).get();
    if (!invoiceDoc.exists || invoiceDoc.data() == null) return null;

    final document = GeneratedDocument.fromJson(
      invoiceDoc.data() as Map<String, dynamic>,
      invoiceDoc.id,
    );
    if (document.documentType != DocumentType.invoice) return null;

    final projects = await getPortalProjects();
    final accessibleProjectIds = projects.map((project) => project.id).toSet();
    if (!accessibleProjectIds.contains(document.projectId)) {
      return null;
    }
    return document;
  }

  /// Firebase fallback for portal pay-now.
  Future<String> ensurePortalPaymentLink(String invoiceId) async {
    final document = await getPortalInvoice(invoiceId);
    final url = document?.metadata['stripePaymentLinkUrl'] as String?;
    if (url != null && url.isNotEmpty) return url;
    throw Exception(
      'Payment link unavailable for this invoice in Firebase portal mode.',
    );
  }

  // ============================================================================
  // Client User Management
  // ============================================================================

  /// Get or create a client user by email
  Future<ClientUser> getOrCreateClientUser(String email) async {
    final normalizedEmail = email.toLowerCase().trim();

    try {
      // Check if user exists
      final snapshot = await _clientUsersRef
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        // Update last login
        await doc.reference.update({
          'lastLoginAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return ClientUser.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }

      // Create new user
      final now = DateTime.now();
      final newUser = ClientUser(
        id: '',
        email: normalizedEmail,
        lastLoginAt: now,
        createdAt: now,
        updatedAt: now,
      );

      final docRef = await _clientUsersRef.add(newUser.toJson());
      return newUser.copyWith(id: docRef.id);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get/create client user',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get recent portal invite history for a customer.
  Future<List<Map<String, dynamic>>> getCustomerPortalInviteHistory({
    required String workspaceId,
    required String customerId,
    int limit = 25,
  }) async {
    try {
      final invitesSnapshot = await _clientPortalInvitesRef
          .where('workspaceId', isEqualTo: workspaceId)
          .where('customerId', isEqualTo: customerId)
          .orderBy('sentAt', descending: true)
          .limit(limit)
          .get();

      if (invitesSnapshot.docs.isEmpty) return [];

      final inviteRows = invitesSnapshot.docs
          .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
          .toList();
      final emails = inviteRows
          .map((row) => row['email'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final senderIds = inviteRows
          .map((row) => row['sentBy'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, DateTime?> emailToLastLogin = {};
      for (final email in emails) {
        final snapshot = await _clientUsersRef
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) continue;
        final row = snapshot.docs.first.data() as Map<String, dynamic>;
        final raw = row['lastLoginAt'];
        if (raw is Timestamp) {
          emailToLastLogin[email] = raw.toDate();
        } else {
          emailToLastLogin[email] = null;
        }
      }

      final Map<String, String> senderNames = {};
      for (final senderId in senderIds) {
        final doc = await _firestore.collection('users').doc(senderId).get();
        if (!doc.exists) continue;
        final data = doc.data();
        if (data == null) continue;
        senderNames[senderId] =
            (data['displayName'] as String?) ??
            (data['email'] as String?) ??
            'Unknown user';
      }

      return inviteRows.map((row) {
        final email = row['email'] as String? ?? '';
        final sentBy = row['sentBy'] as String?;
        final sentAtRaw = row['sentAt'];
        DateTime? sentAt;
        if (sentAtRaw is Timestamp) {
          sentAt = sentAtRaw.toDate();
        }

        return {
          'email': email,
          'sentAt': sentAt,
          'sentBy': sentBy,
          'sentByName': sentBy != null ? senderNames[sentBy] : null,
          'lastLoginAt': emailToLastLogin[email],
        };
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal invite history',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /// Check if an email has access to any customer
  Future<bool> _emailHasAccess(String email) async {
    final customers = await getAccessibleCustomers(email);
    return customers.isNotEmpty;
  }

  Future<void> _recordPortalInviteSend({
    required String workspaceId,
    required String customerId,
    required String email,
    String? sentBy,
  }) async {
    try {
      final effectiveSentBy = sentBy ?? FirebaseAuth.instance.currentUser?.uid;
      await _clientPortalInvitesRef.add({
        'workspaceId': workspaceId,
        'customerId': customerId,
        'email': email,
        'sentBy': effectiveSentBy,
        'sentAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to record portal invite send',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Generate a secure random token for magic links
  static String generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Iterable<List<String>> _chunk(List<String> values, int size) sync* {
    for (var i = 0; i < values.length; i += size) {
      yield values.skip(i).take(size).toList();
    }
  }
}

/// Context returned after successful magic link validation
class ClientPortalContext {
  final String email;
  final List<String> customerIds;

  ClientPortalContext({required this.email, required this.customerIds});
}
