import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../models/client_user.dart';
import '../../models/customer.dart';
import '../../models/document_activity.dart';
import '../../models/document_line_item.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/portal_invoice_summary.dart';
import '../../models/project.dart';
import '../../models/selection.dart';
import '../../utils/app_logger.dart';
import '../../utils/storage_path_utils.dart';
import 'storage_service.dart';

/// Supabase implementation of ClientPortalService
/// Clients authenticate via magic link and access data based on their email
class SupabaseClientPortalService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseStorageService _storageService = SupabaseStorageService();

  Future<Map<String, dynamic>> _resolveDocumentAssetUrls(
    Map<String, dynamic> row,
  ) async {
    final resolved = Map<String, dynamic>.from(row);
    resolved['signature_url'] = await _storageService.resolveStorageUrl(
      row['signature_url'] as String?,
    );
    return resolved;
  }

  // ============================================================================
  // Magic Link Authentication
  // ============================================================================

  /// Request a magic link for the given email.
  /// Returns true if email has portal access, false otherwise.
  Future<bool> requestMagicLink(
    String email, {
    String? workspaceId,
    String? customerId,
    String? sentBy,
  }) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();

      final canAccess = await _supabase.rpc(
        'portal_can_request_access',
        params: {'portal_email': normalizedEmail},
      );

      if (canAccess != true) {
        AppLogger.warning('Magic link requested for unknown email: $email');
        return false;
      }

      // Pick the right redirect for the platform: the mobile deep link only
      // resolves inside the installed app, so web magic-link users would land
      // on a page their browser can't open. On web, send them back to the
      // portal entry route. The supabase_flutter SDK auto-consumes auth
      // tokens from the URL fragment on init, then go_router navigates to
      // /portal which redirects to /portal/dashboard for authed users.
      final redirect = kIsWeb
          ? '${SupabaseConfig.siteUrl}/#/portal'
          : 'io.supabase.taskfleet://client-portal-callback/';
      await _supabase.auth.signInWithOtp(
        email: normalizedEmail,
        emailRedirectTo: redirect,
      );

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

  /// Validate a magic link token (called after user clicks link)
  /// Returns the client context if valid, null otherwise
  Future<ClientPortalContext?> validateMagicLink(String token) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        token: token,
        type: OtpType.magiclink,
      );

      if (response.session == null || response.user == null) {
        return null;
      }

      final email = response.user!.email;
      if (email == null || email.trim().isEmpty) return null;

      // Keep portal invite/login history accurate.
      try {
        await getOrCreateClientUser(email);
      } catch (e) {
        AppLogger.warning(
          'Failed to upsert client user during magic link validation',
          metadata: {'email': email, 'error': e.toString()},
        );
      }

      final projects = await getPortalProjects();
      final customerIds = projects
          .map((project) => project.clientId)
          .whereType<String>()
          .toSet()
          .toList();

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

  /// Sign out from client portal
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Returns the authenticated portal email, if available.
  String? getPortalEmail() {
    final email = _supabase.auth.currentUser?.email;
    final normalized = email?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  // ============================================================================
  // Portal Access (secure RPC-backed)
  // ============================================================================

  Future<List<Project>> getPortalProjects({String? previewCustomerId}) async {
    try {
      final params = <String, dynamic>{};
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = params.isEmpty
          ? await _supabase.rpc('portal_get_projects')
          : await _supabase.rpc('portal_get_projects', params: params);
      if (raw is! List) return [];
      return raw
          .map((row) => _toProjectFromPortalRow(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal projects',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<Project?> getPortalProject(
    String projectId, {
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{'project_id': projectId};
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = await _supabase.rpc('portal_get_project', params: params);

      if (raw is! List || raw.isEmpty) return null;
      return _toProjectFromPortalRow(Map<String, dynamic>.from(raw.first));
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal project',
        error: e,
        stackTrace: stackTrace,
        metadata: {'projectId': projectId},
      );
      rethrow;
    }
  }

  Future<List<PortalInvoiceSummary>> getPortalInvoices({
    String? projectId,
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (projectId != null) params['p_project_id'] = projectId;
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final dynamic raw = params.isEmpty
          ? await _supabase.rpc('portal_get_invoices')
          : await _supabase.rpc('portal_get_invoices', params: params);

      if (raw is! List) return [];
      return raw.map((row) {
        final map = Map<String, dynamic>.from(row);
        return PortalInvoiceSummary(
          invoice: _toPortalDocument(map),
          projectName: map['project_name'] as String?,
        );
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal invoices',
        error: e,
        stackTrace: stackTrace,
        metadata: {'projectId': projectId},
      );
      rethrow;
    }
  }

  Future<GeneratedDocument?> getPortalInvoice(
    String invoiceId, {
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{'invoice_id': invoiceId};
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = await _supabase.rpc('portal_get_invoice', params: params);

      if (raw is! List || raw.isEmpty) return null;
      return _toPortalDocument(Map<String, dynamic>.from(raw.first));
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal invoice',
        error: e,
        stackTrace: stackTrace,
        metadata: {'invoiceId': invoiceId},
      );
      rethrow;
    }
  }

  Future<String> ensurePortalPaymentLink(String invoiceId) async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.post(
        Uri.parse(
          '${SupabaseConfig.url}/functions/v1/generate-invoice-payment-link',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: jsonEncode({'invoiceId': invoiceId}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        final url = data['url'] as String?;
        if (data['success'] == true && url != null && url.isNotEmpty) {
          return url;
        }
      }

      if (data is Map<String, dynamic>) {
        throw Exception(data['error'] ?? 'Failed to generate payment link');
      }

      throw Exception('Failed to generate payment link');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error ensuring portal payment link: $e');
      }
      rethrow;
    }
  }

  // ============================================================================
  // Portal Document Actions
  // ============================================================================

  /// Deny a document from the portal.
  Future<void> denyDocument(
    String documentId,
    String reason, {
    String? actorName,
  }) async {
    try {
      await _supabase.rpc(
        'portal_deny_document',
        params: {
          'p_document_id': documentId,
          'p_reason': reason,
          'p_actor_name': actorName,
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to deny document',
        error: e,
        stackTrace: stackTrace,
        metadata: {'documentId': documentId},
      );
      rethrow;
    }
  }

  /// Request changes on a document from the portal.
  Future<void> requestDocumentChanges(
    String documentId,
    String reason, {
    String? actorName,
  }) async {
    try {
      await _supabase.rpc(
        'portal_request_document_changes',
        params: {
          'p_document_id': documentId,
          'p_reason': reason,
          'p_actor_name': actorName,
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to request document changes',
        error: e,
        stackTrace: stackTrace,
        metadata: {'documentId': documentId},
      );
      rethrow;
    }
  }

  /// Get a single document visible to the portal user.
  Future<GeneratedDocument?> getPortalDocument(
    String documentId, {
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{'p_document_id': documentId};
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = await _supabase.rpc('portal_get_document', params: params);

      if (raw is! List || raw.isEmpty) return null;
      final resolvedRow = await _resolveDocumentAssetUrls(
        Map<String, dynamic>.from(raw.first),
      );
      return _toPortalDocumentFull(resolvedRow);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal document',
        error: e,
        stackTrace: stackTrace,
        metadata: {'documentId': documentId},
      );
      rethrow;
    }
  }

  /// Get activity log for a document.
  Future<List<DocumentActivity>> getPortalDocumentActivity(
    String documentId, {
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{'p_document_id': documentId};
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = await _supabase.rpc(
        'portal_get_document_activity',
        params: params,
      );

      if (raw is! List) return [];
      return raw
          .map(
            (row) => DocumentActivity.fromRow(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal document activity',
        error: e,
        stackTrace: stackTrace,
        metadata: {'documentId': documentId},
      );
      return [];
    }
  }

  /// Get a chronological activity feed for a project (documents, invoices,
  /// selections, change orders). Server-side authz mirrors [getPortalProject].
  Future<List<Map<String, dynamic>>> getPortalProjectActivity(
    String projectId, {
    int limit = 100,
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_project_id': projectId,
        'p_limit': limit,
      };
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = await _supabase.rpc(
        'portal_get_project_activity',
        params: params,
      );
      if (raw is! List) return [];
      return raw
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal project activity',
        error: e,
        stackTrace: stackTrace,
        metadata: {'projectId': projectId},
      );
      return [];
    }
  }

  /// Get customer-facing documents for a project.
  Future<List<GeneratedDocument>> getPortalProjectDocuments(
    String projectId, {
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{'p_project_id': projectId};
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = await _supabase.rpc(
        'portal_get_project_documents',
        params: params,
      );

      if (raw is! List) return [];
      return raw
          .map(
            (row) => _toPortalDocumentSummary(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load portal project documents',
        error: e,
        stackTrace: stackTrace,
        metadata: {'projectId': projectId},
      );
      rethrow;
    }
  }

  /// Get or create a signing link for the portal user.
  Future<Map<String, dynamic>> getOrCreateSignLink(String documentId) async {
    try {
      final raw = await _supabase.rpc(
        'portal_get_or_create_sign_link',
        params: {'p_document_id': documentId},
      );

      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      throw Exception('Unexpected response from sign link RPC');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get/create sign link',
        error: e,
        stackTrace: stackTrace,
        metadata: {'documentId': documentId},
      );
      rethrow;
    }
  }

  // ============================================================================
  // Legacy Customer & Project Access (used by non-portal flows)
  // ============================================================================

  /// Get all customers where the given email is an active contact.
  Future<List<Customer>> getAccessibleCustomers(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      final contacts = await _supabase
          .from('customer_contacts')
          .select(
            'customer_id, name, title, phone, email, is_primary, is_active',
          )
          .eq('is_active', true)
          .ilike('email', normalizedEmail);

      if (contacts.isEmpty) return [];

      final customerIds = contacts
          .map((row) => row['customer_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      if (customerIds.isEmpty) return [];

      final contactsByCustomer = <String, List<Map<String, dynamic>>>{};
      for (final row in contacts) {
        final customerId = row['customer_id'] as String?;
        if (customerId == null) continue;
        contactsByCustomer
            .putIfAbsent(customerId, () => [])
            .add(Map<String, dynamic>.from(row));
      }

      final rows = await _supabase
          .from('customers')
          .select()
          .inFilter('id', customerIds)
          .order('updated_at', ascending: false);

      return rows.map((row) {
        final customerId = row['id'] as String?;
        return _toCustomer(
          row,
          contacts: customerId != null ? contactsByCustomer[customerId] : null,
        );
      }).toList();
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
      final response = await _supabase
          .from('projects')
          .select()
          .inFilter('client_id', customerIds)
          .order('updated_at', ascending: false);

      return response.map((row) => _toProject(row)).toList();
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

      final response = await _supabase
          .from('projects')
          .select()
          .eq('id', projectId)
          .maybeSingle();

      if (response == null) return null;

      final project = _toProject(response);
      if (project.clientId != null && customerIds.contains(project.clientId)) {
        return project;
      }

      return null;
    } catch (e) {
      AppLogger.error('Failed to get project', error: e);
      return null;
    }
  }

  // ============================================================================
  // Client User Management
  // ============================================================================

  /// Get or create a client user by email
  Future<ClientUser> getOrCreateClientUser(String email) async {
    final normalizedEmail = email.toLowerCase().trim();

    try {
      final response = await _supabase
          .from('client_users')
          .select()
          .eq('email', normalizedEmail)
          .maybeSingle();

      if (response != null) {
        await _supabase
            .from('client_users')
            .update({
              'last_login_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', response['id']);

        return _toClientUser(response);
      }

      final now = DateTime.now();
      final newUserData = {
        'email': normalizedEmail,
        'last_login_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final newResponse = await _supabase
          .from('client_users')
          .insert(newUserData)
          .select()
          .single();

      return _toClientUser(newResponse);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get/create client user',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get client user by ID
  Future<ClientUser?> getClientUser(String userId) async {
    try {
      final response = await _supabase
          .from('client_users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return null;
      return _toClientUser(response);
    } catch (e) {
      return null;
    }
  }

  /// Get recent portal invite history for a customer.
  Future<List<Map<String, dynamic>>> getCustomerPortalInviteHistory({
    required String workspaceId,
    required String customerId,
    int limit = 25,
  }) async {
    try {
      final response = await _supabase
          .from('client_portal_invites')
          .select('email, sent_at, sent_by')
          .eq('workspace_id', workspaceId)
          .eq('customer_id', customerId)
          .order('sent_at', ascending: false)
          .limit(limit);

      final inviteRows = List<Map<String, dynamic>>.from(response);
      if (inviteRows.isEmpty) return [];

      final emails = inviteRows
          .map((row) => row['email'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final senderIds = inviteRows
          .map((row) => row['sent_by'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, DateTime?> emailToLastLogin = {};
      if (emails.isNotEmpty) {
        final usersResponse = await _supabase
            .from('client_users')
            .select('email, last_login_at')
            .inFilter('email', emails);
        for (final row in usersResponse) {
          final email = row['email'] as String?;
          if (email == null) continue;
          emailToLastLogin[email] = _parseNullableDateTime(
            row['last_login_at'],
          );
        }
      }

      final Map<String, String> senderNames = {};
      if (senderIds.isNotEmpty) {
        final sendersResponse = await _supabase
            .from('users')
            .select('id, display_name, email')
            .inFilter('id', senderIds);
        for (final row in sendersResponse) {
          final id = row['id'] as String?;
          if (id == null) continue;
          senderNames[id] =
              (row['display_name'] as String?) ??
              (row['email'] as String?) ??
              'Unknown user';
        }
      }

      return inviteRows.map((row) {
        final email = row['email'] as String? ?? '';
        final sentBy = row['sent_by'] as String?;
        return {
          'email': email,
          'sentAt': _parseNullableDateTime(row['sent_at']),
          'sentBy': sentBy,
          'sentByName': sentBy != null ? senderNames[sentBy] : null,
          'lastLoginAt': emailToLastLogin[email],
        };
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Failed to load portal invite history',
        metadata: {
          'workspaceId': workspaceId,
          'customerId': customerId,
          'error': e.toString(),
        },
      );
      AppLogger.error(
        'Portal invite history query failed',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  Future<void> _recordPortalInviteSend({
    required String workspaceId,
    required String customerId,
    required String email,
    String? sentBy,
  }) async {
    try {
      final effectiveSentBy = sentBy ?? _supabase.auth.currentUser?.id;
      await _supabase.from('client_portal_invites').insert({
        'workspace_id': workspaceId,
        'customer_id': customerId,
        'email': email,
        'sent_by': effectiveSentBy,
      });
    } catch (e) {
      AppLogger.warning(
        'Failed to record portal invite send',
        metadata: {
          'workspaceId': workspaceId,
          'customerId': customerId,
          'email': email,
          'error': e.toString(),
        },
      );
    }
  }

  /// Generate a secure random token for magic links
  static String generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Customer _toCustomer(
    Map<String, dynamic> row, {
    List<Map<String, dynamic>>? contacts,
  }) {
    final contactsList =
        contacts ??
        (row['contacts'] as List?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    return Customer.fromJson({
      'id': row['id'],
      'workspaceId': row['workspace_id'],
      'name': row['name'],
      'companyName': row['company_name'],
      'email': row['email'],
      'phone': row['phone'],
      'contacts': contactsList,
      'isActive': row['is_active'] ?? true,
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
    }, row['id'] as String);
  }

  Project _toProject(Map<String, dynamic> row) {
    return _toProjectFromPortalRow(row);
  }

  Project _toProjectFromPortalRow(Map<String, dynamic> row) {
    return Project(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: (row['name'] as String?) ?? 'Project',
      address: (row['address'] as String?) ?? '',
      status: _parseProjectStatus(row['status'] as String?),
      clientId: row['client_id'] as String?,
      description: row['description'] as String?,
      startDate: _parseNullableDateTime(row['start_date']),
      targetCompletionDate: _parseNullableDateTime(
        row['target_completion_date'],
      ),
      createdAt: _parseDateTime(row['created_at']),
      updatedAt: _parseDateTime(row['updated_at']),
    );
  }

  GeneratedDocument _toPortalDocumentFull(Map<String, dynamic> row) {
    final lineItemsList =
        (row['line_items'] as List?)
            ?.map(
              (item) =>
                  DocumentLineItem.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        [];

    final metadataRaw = row['metadata'];
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : const <String, dynamic>{};

    return GeneratedDocument(
      id: row['id'] as String,
      workspaceId: (row['workspace_id'] as String?) ?? '',
      projectId: row['project_id'] as String?,
      customerId: row['customer_id'] as String?,
      templateId: '',
      templateName: (row['template_name'] as String?) ?? 'Document',
      documentType: DocumentTypeExtension.fromStoredValue(
        row['document_type'] as String?,
      ),
      renderedContent: (row['rendered_content'] as String?) ?? '',
      status: DocumentStatusExtension.fromDbValue(row['status'] as String?),
      createdBy: (row['created_by'] as String?) ?? '',
      createdAt: _parseDateTime(row['created_at']),
      lineItems: lineItemsList,
      lineItemVisibility: LineItemVisibility.fromString(
        row['line_item_visibility'] as String?,
      ),
      totalAmount: _toDouble(row['total_amount']),
      collectTax: row['collect_tax'] as bool? ?? false,
      taxRate: _toDouble(row['tax_rate']),
      taxName: row['tax_name'] as String?,
      documentNumber: row['document_number'] as String?,
      dueDate: _parseNullableDateTime(row['due_date']),
      paidDate: _parseNullableDateTime(row['paid_date']),
      metadata: metadata,
      preparedBy: row['prepared_by'] != null
          ? DocumentContactInfo.fromJson(row['prepared_by'])
          : null,
      preparedFor: row['prepared_for'] != null
          ? DocumentContactInfo.fromJson(row['prepared_for'])
          : null,
      footerContent: row['footer_content'] as String?,
      signedByName: row['signed_by_name'] as String?,
      signedByEmail: row['signed_by_email'] as String?,
      signedAt: _parseNullableDateTime(row['signed_at']),
      signatureUrl: row['signature_url'] as String?,
      deniedAt: _parseNullableDateTime(row['denied_at']),
      deniedByName: row['denied_by_name'] as String?,
      deniedByEmail: row['denied_by_email'] as String?,
      denialReason: row['denial_reason'] as String?,
    );
  }

  GeneratedDocument _toPortalDocumentSummary(Map<String, dynamic> row) {
    final metadataRaw = row['metadata'];
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : const <String, dynamic>{};

    return GeneratedDocument(
      id: row['id'] as String,
      workspaceId: (row['workspace_id'] as String?) ?? '',
      projectId: row['project_id'] as String?,
      customerId: row['customer_id'] as String?,
      templateId: '',
      templateName: (row['template_name'] as String?) ?? 'Document',
      documentType: DocumentTypeExtension.fromStoredValue(
        row['document_type'] as String?,
      ),
      renderedContent: '',
      status: DocumentStatusExtension.fromDbValue(row['status'] as String?),
      createdBy: (row['created_by'] as String?) ?? '',
      createdAt: _parseDateTime(row['created_at']),
      totalAmount: _toDouble(row['total_amount']),
      documentNumber: row['document_number'] as String?,
      dueDate: _parseNullableDateTime(row['due_date']),
      paidDate: _parseNullableDateTime(row['paid_date']),
      metadata: metadata,
      deniedAt: _parseNullableDateTime(row['denied_at']),
      deniedByName: row['denied_by_name'] as String?,
      denialReason: row['denial_reason'] as String?,
      signedByName: row['signed_by_name'] as String?,
      signedAt: _parseNullableDateTime(row['signed_at']),
    );
  }

  GeneratedDocument _toPortalDocument(Map<String, dynamic> row) {
    final lineItemsList =
        (row['line_items'] as List?)
            ?.map(
              (item) =>
                  DocumentLineItem.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        [];

    final metadataRaw = row['metadata'];
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : const <String, dynamic>{};

    return GeneratedDocument(
      id: row['id'] as String,
      workspaceId: (row['workspace_id'] as String?) ?? '',
      projectId: row['project_id'] as String?,
      customerId: row['customer_id'] as String?,
      templateId: '',
      templateName: 'Invoice',
      documentType: DocumentTypeExtension.fromStoredValue(
        row['document_type'] as String?,
      ),
      renderedContent: (row['rendered_content'] as String?) ?? '',
      status: DocumentStatusExtension.fromDbValue(row['status'] as String?),
      createdBy: (row['created_by'] as String?) ?? '',
      createdAt: _parseDateTime(row['created_at']),
      lineItems: lineItemsList,
      totalAmount: _toDouble(row['total_amount']),
      amountPaid: _toDouble(row['amount_paid']),
      discountAmount: _toDouble(row['discount_amount']),
      collectTax: row['collect_tax'] as bool? ?? false,
      taxRate: _toDouble(row['tax_rate']),
      documentNumber: row['document_number'] as String?,
      dueDate: _parseNullableDateTime(row['due_date']),
      paidDate: _parseNullableDateTime(row['paid_date']),
      metadata: metadata,
    );
  }

  ClientUser _toClientUser(Map<String, dynamic> row) {
    return ClientUser(
      id: row['id'] as String,
      email: row['email'] as String,
      displayName: row['display_name'] as String?,
      lastLoginAt: _parseNullableDateTime(row['last_login_at']),
      createdAt: _parseDateTime(row['created_at']),
      updatedAt: _parseDateTime(row['updated_at']),
    );
  }

  DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  DateTime? _parseNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // ============================================================================
  // Portal Selections
  // ============================================================================

  /// List selections visible to the portal user for a project. Returns
  /// awaiting_client, approved and declined items only.
  Future<List<Selection>> getPortalProjectSelections(
    String projectId, {
    String? previewCustomerId,
  }) async {
    try {
      final params = <String, dynamic>{'p_project_id': projectId};
      if (previewCustomerId != null) {
        params['p_preview_customer_id'] = previewCustomerId;
      }
      final raw = await _supabase.rpc(
        'portal_get_project_selections',
        params: params,
      );
      if (raw is! List) return [];
      return raw.map((row) {
        final m = Map<String, dynamic>.from(row as Map);
        final optsRaw = m['options'];
        final options = <SelectionOption>[];
        if (optsRaw is List) {
          for (final o in optsRaw) {
            final opt = Map<String, dynamic>.from(o as Map);
            opt['selection_id'] = m['id'];
            options.add(SelectionOption.fromRow(opt));
          }
        }
        return Selection.fromRow(m, options: options);
      }).toList();
    } catch (e, st) {
      AppLogger.error('Failed to load portal selections',
          error: e, stackTrace: st, metadata: {'projectId': projectId});
      rethrow;
    }
  }

  Future<void> approvePortalSelection(
    String selectionId,
    String optionId, {
    String? actorName,
  }) async {
    try {
      await _supabase.rpc('portal_approve_selection', params: {
        'p_selection_id': selectionId,
        'p_option_id': optionId,
        'p_actor_name': actorName,
      });
    } catch (e, st) {
      AppLogger.error('Failed to approve selection',
          error: e, stackTrace: st, metadata: {'selectionId': selectionId});
      rethrow;
    }
  }

  /// List the message thread for a selection (client view).
  Future<List<SelectionComment>> getSelectionComments(
      String selectionId) async {
    try {
      final raw = await _supabase.rpc('portal_list_selection_comments',
          params: {'p_selection_id': selectionId});
      if (raw is! List) return [];
      return raw
          .map((row) =>
              SelectionComment.fromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e, st) {
      AppLogger.error('Failed to load selection comments',
          error: e, stackTrace: st, metadata: {'selectionId': selectionId});
      rethrow;
    }
  }

  /// Client proposes ("writes in") their own option on a selection.
  Future<void> suggestSelectionOption(
      String selectionId, String name, String? note) async {
    try {
      await _supabase.rpc('portal_suggest_selection_option', params: {
        'p_selection_id': selectionId,
        'p_name': name,
        'p_note': note,
      });
    } catch (e, st) {
      AppLogger.error('Failed to suggest selection option',
          error: e, stackTrace: st, metadata: {'selectionId': selectionId});
      rethrow;
    }
  }

  /// Post a message on a selection (from the client).
  Future<void> addSelectionComment(String selectionId, String body) async {
    try {
      await _supabase.rpc('portal_add_selection_comment',
          params: {'p_selection_id': selectionId, 'p_body': body});
    } catch (e, st) {
      AppLogger.error('Failed to post selection comment',
          error: e, stackTrace: st, metadata: {'selectionId': selectionId});
      rethrow;
    }
  }

  /// Record an additional e-signature on a selection (multi-signer support).
  Future<void> addSelectionSignatureRecord(
      String selectionId, String? name, String? email, String url) async {
    try {
      await _supabase.rpc('portal_add_selection_signature', params: {
        'p_selection_id': selectionId,
        'p_signer_name': name,
        'p_signer_email': email,
        'p_signature_url': url,
      });
    } catch (e, st) {
      AppLogger.error('Failed to record selection signature',
          error: e, stackTrace: st, metadata: {'selectionId': selectionId});
      rethrow;
    }
  }

  /// Attach a captured e-signature URL to an approved selection.
  Future<void> setSelectionSignature(
      String selectionId, String signatureUrl) async {
    try {
      await _supabase.rpc('portal_set_selection_signature', params: {
        'p_selection_id': selectionId,
        'p_signature_url': signatureUrl,
      });
    } catch (e, st) {
      AppLogger.error('Failed to attach selection signature',
          error: e, stackTrace: st, metadata: {'selectionId': selectionId});
      rethrow;
    }
  }

  Future<void> declinePortalSelection(
    String selectionId,
    String reason, {
    String? actorName,
  }) async {
    try {
      await _supabase.rpc('portal_decline_selection', params: {
        'p_selection_id': selectionId,
        'p_reason': reason,
        'p_actor_name': actorName,
      });
    } catch (e, st) {
      AppLogger.error('Failed to decline selection',
          error: e, stackTrace: st, metadata: {'selectionId': selectionId});
      rethrow;
    }
  }

  // ============================================================================
  // Portal Messaging
  // ============================================================================

  /// Returns (or lazily creates) the portal-visible conversation thread for a
  /// project. Caller must have portal access to the project (real or preview).
  Future<Map<String, dynamic>> getOrCreateProjectThread({
    required String projectId,
    String? previewCustomerId,
  }) async {
    try {
      final result = await _supabase.rpc(
        'portal_get_or_create_project_thread',
        params: {
          'p_project_id': projectId,
          if (previewCustomerId != null)
            'p_preview_customer_id': previewCustomerId,
        },
      );
      if (result is List && result.isNotEmpty) {
        return Map<String, dynamic>.from(result.first as Map);
      }
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      throw Exception('Unexpected thread response');
    } catch (e, st) {
      AppLogger.error('Failed to load portal thread',
          error: e, stackTrace: st, metadata: {'projectId': projectId});
      rethrow;
    }
  }

  /// Reads messages from a portal-visible thread, newest-first.
  Future<List<Map<String, dynamic>>> getThreadMessages({
    required String conversationId,
    String? previewCustomerId,
    int limit = 100,
    DateTime? before,
  }) async {
    try {
      final result = await _supabase.rpc(
        'portal_get_thread_messages',
        params: {
          'p_conversation_id': conversationId,
          if (previewCustomerId != null)
            'p_preview_customer_id': previewCustomerId,
          'p_limit': limit,
          if (before != null) 'p_before': before.toUtc().toIso8601String(),
        },
      );
      if (result is List) {
        return result
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return const [];
    } catch (e, st) {
      AppLogger.error('Failed to load thread messages',
          error: e, stackTrace: st,
          metadata: {'conversationId': conversationId});
      rethrow;
    }
  }

  /// Sends a message into a portal-visible thread. Not allowed in preview.
  Future<String> sendThreadMessage({
    required String conversationId,
    required String content,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    try {
      final id = await _supabase.rpc('portal_send_message', params: {
        'p_conversation_id': conversationId,
        'p_content': content,
        'p_attachments': attachments,
      });
      return id as String;
    } catch (e, st) {
      AppLogger.error('Failed to send portal message',
          error: e, stackTrace: st,
          metadata: {'conversationId': conversationId});
      rethrow;
    }
  }

  /// Stream of newly-inserted messages on a portal-visible thread. Each
  /// emission is a single new row. Backed by Supabase realtime
  /// postgres-changes on `public.messages` (INSERT, filtered to the given
  /// conversation_id). The `messages_select_portal` RLS policy
  /// (20260524010001) authorizes portal-authenticated customers; staff hit
  /// the default `messages_select` policy.
  ///
  /// Designed to coexist with paginated historical loads via
  /// [getThreadMessages] — this stream only delivers events newer than the
  /// subscription start, so it doesn't fight the pagination cursor.
  ///
  /// Not safe to call in preview mode: preview impersonators aren't in
  /// `customer_contacts` and won't pass the portal RLS policy.
  Stream<Map<String, dynamic>> watchThreadInserts({
    required String conversationId,
  }) {
    late RealtimeChannel channel;
    final controller = StreamController<Map<String, dynamic>>();
    controller.onListen = () {
      channel = _supabase
          .channel('portal_thread_$conversationId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: (payload) {
              if (controller.isClosed) return;
              controller.add(Map<String, dynamic>.from(payload.newRecord));
            },
          )
          .subscribe();
    };
    controller.onCancel = () async {
      await channel.unsubscribe();
      await controller.close();
    };
    return controller.stream;
  }

  /// Uploads a portal attachment into the `project-files` bucket under
  /// `{workspace_id}/conversations/{conversation_id}/...` and returns an
  /// attachment dict suitable for inclusion in `sendThreadMessage(attachments:)`.
  ///
  /// The `fileUrl` field is a private storage reference
  /// (`supabase://project-files/<path>`) — resolve it via
  /// [resolvePortalAttachmentUrl] before display.
  Future<Map<String, dynamic>> uploadPortalAttachment({
    required String conversationId,
    required String workspaceId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final fileId = const Uuid().v4();
    final safeName = sanitizeStoragePathSegment(fileName);
    final path =
        '$workspaceId/conversations/$conversationId/$fileId-$safeName';
    await _supabase.storage
        .from(SupabaseConfig.projectFilesBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            cacheControl: '31536000',
          ),
        );
    return {
      'id': fileId,
      'fileName': fileName,
      'fileUrl': 'supabase://${SupabaseConfig.projectFilesBucket}/$path',
      'fileSize': bytes.length,
      'mimeType': mimeType,
    };
  }

  /// Resolve a `supabase://bucket/path` reference produced by
  /// [uploadPortalAttachment] into a short-lived signed URL safe to launch
  /// from a portal user's session.
  Future<String?> resolvePortalAttachmentUrl(
    String? fileUrl, {
    int expiresIn = 3600,
  }) async {
    return _storageService.resolveStorageUrl(fileUrl, expiresIn: expiresIn);
  }

  /// Resets the calling portal user's unread count on a thread.
  Future<void> markThreadRead(String conversationId) async {
    try {
      await _supabase.rpc('portal_mark_thread_read', params: {
        'p_conversation_id': conversationId,
      });
    } catch (e, st) {
      AppLogger.error('Failed to mark portal thread read',
          error: e, stackTrace: st,
          metadata: {'conversationId': conversationId});
      // Non-fatal.
    }
  }

  ProjectStatus _parseProjectStatus(String? value) {
    if (value == null) return ProjectStatus.active;
    try {
      return ProjectStatus.fromString(value);
    } catch (_) {
      return ProjectStatus.active;
    }
  }
}

/// Context returned after successful magic link validation
class ClientPortalContext {
  final String email;
  final List<String> customerIds;

  ClientPortalContext({required this.email, required this.customerIds});
}
