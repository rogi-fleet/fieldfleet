import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../models/workspace_invitation.dart';
import '../../models/user_role.dart';
import '../../utils/app_logger.dart';

class SupabaseInvitationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _tokenLength = 48;
  static const int _expirationDays = 7;

  /// Generate a cryptographically secure random token
  String _generateSecureToken() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      _tokenLength,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Invite a user to a workspace.
  ///
  /// Pass [portalCustomerContactId] or [portalVendorContactId] (exclusively —
  /// at most one) to bind the invitation to an external contact record. When
  /// the invitee accepts, accept_workspace_invitation will stamp their new
  /// auth user_id onto that contact so portal-scoped RLS knows which rows
  /// belong to them.
  Future<WorkspaceInvitation> inviteUser({
    required String workspaceId,
    required String email,
    required UserRole role,
    required String invitedBy,
    String interfaceMode = 'manager',
    String? roleTemplateId,
    String? portalCustomerContactId,
    String? portalVendorContactId,
  }) async {
    if (portalCustomerContactId != null && portalVendorContactId != null) {
      throw ArgumentError(
        'An invitation cannot be linked to both a customer and a vendor contact.',
      );
    }
    try {
      final normalizedEmail = email.trim().toLowerCase();

      // Check for existing pending invitation
      final existingInvitations = await _supabase
          .from('workspace_invitations')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('email', normalizedEmail)
          .eq('status', 'pending');

      if ((existingInvitations as List).isNotEmpty) {
        throw Exception('An invitation for this email already exists');
      }

      // Check if user with this email is already a member of the workspace
      final usersQuery = await _supabase
          .from('users')
          .select('id')
          .eq('email', normalizedEmail)
          .limit(1);

      if ((usersQuery as List).isNotEmpty) {
        final userId = usersQuery.first['id'] as String;

        final existingMember = await _supabase
            .from('workspace_members')
            .select('user_id')
            .eq('workspace_id', workspaceId)
            .eq('user_id', userId)
            .maybeSingle();

        if (existingMember != null) {
          throw Exception('This user is already a member of this workspace');
        }
      }

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(days: _expirationDays));

      final invitationData = {
        'workspace_id': workspaceId,
        'email': normalizedEmail,
        'role': _roleToString(role),
        if (roleTemplateId != null) 'role_template_id': roleTemplateId,
        'interface_mode': interfaceMode,
        'invited_by': invitedBy,
        'token': _generateSecureToken(),
        'status': 'pending',
        'expires_at': expiresAt.toIso8601String(),
        'created_at': now.toIso8601String(),
        if (portalCustomerContactId != null)
          'portal_customer_contact_id': portalCustomerContactId,
        if (portalVendorContactId != null)
          'portal_vendor_contact_id': portalVendorContactId,
      };

      final response = await _supabase
          .from('workspace_invitations')
          .insert(invitationData)
          .select()
          .single();

      AppLogger.info(
        'Invitation created',
        metadata: {
          'invitationId': response['id'],
          'workspaceId': workspaceId,
          'email': normalizedEmail,
        },
      );

      // Send invitation email via edge function
      await _sendInvitationEmail(
        email: normalizedEmail,
        workspaceId: workspaceId,
        invitedBy: invitedBy,
        token: response['token'] as String,
        role: _roleToString(role),
      );

      return WorkspaceInvitation.fromJson(
        _toFirestoreFormat(response),
        response['id'].toString(),
      );
    } catch (e) {
      AppLogger.error('Failed to create invitation', error: e);
      rethrow;
    }
  }

  /// Get all invitations for a workspace
  Stream<List<WorkspaceInvitation>> getWorkspaceInvitations(
    String workspaceId,
  ) {
    return _supabase
        .from('workspace_invitations')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .map(
          (data) => data
              .map(
                (row) => WorkspaceInvitation.fromJson(
                  _toFirestoreFormat(row),
                  row['id'].toString(),
                ),
              )
              .toList(),
        );
  }

  /// Get pending invitations for a user by email
  Future<List<WorkspaceInvitation>> getUserPendingInvitations(
    String email,
  ) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final response = await _supabase
          .from('workspace_invitations')
          .select()
          .eq('email', normalizedEmail)
          .eq('status', 'pending');

      return (response as List)
          .map(
            (row) => WorkspaceInvitation.fromJson(
              _toFirestoreFormat(row),
              row['id'].toString(),
            ),
          )
          .where((invitation) => !invitation.isExpired)
          .toList();
    } catch (e) {
      AppLogger.error('Failed to get pending invitations', error: e);
      return [];
    }
  }

  /// Accept an invitation
  Future<void> acceptInvitation({required String token}) async {
    try {
      final response = await _supabase.rpc(
        'accept_workspace_invitation',
        params: {'invite_token': token},
      );

      final metadata = response is Map
          ? Map<String, dynamic>.from(response)
          : null;
      AppLogger.info(
        'Invitation accepted',
        metadata: metadata ?? {'token': token},
      );
    } catch (e) {
      AppLogger.error('Failed to accept invitation', error: e);
      rethrow;
    }
  }

  /// Revoke an invitation
  Future<void> revokeInvitation(String invitationId) async {
    try {
      final response = await _supabase
          .from('workspace_invitations')
          .update({'status': 'revoked'})
          .eq('id', invitationId)
          .select('id')
          .maybeSingle();

      if (response == null) {
        throw Exception(
          'Invitation not found or you do not have permission to revoke it',
        );
      }

      AppLogger.info(
        'Invitation revoked',
        metadata: {'invitationId': invitationId},
      );
    } catch (e) {
      AppLogger.error('Failed to revoke invitation', error: e);
      rethrow;
    }
  }

  /// Resend an invitation (regenerate token and extend expiration)
  Future<void> resendInvitation(String invitationId) async {
    try {
      final now = DateTime.now();
      final newToken = _generateSecureToken();

      // Update the invitation with new token
      final response = await _supabase
          .from('workspace_invitations')
          .update({
            'token': newToken,
            'expires_at': now
                .add(const Duration(days: _expirationDays))
                .toIso8601String(),
            'status': 'pending',
          })
          .eq('id', invitationId)
          .select()
          .maybeSingle();

      if (response == null) {
        throw Exception(
          'Invitation not found or you do not have permission to resend it',
        );
      }

      // Send invitation email
      await _sendInvitationEmail(
        email: response['email'] as String,
        workspaceId: response['workspace_id'] as String,
        invitedBy: response['invited_by'] as String,
        token: newToken,
        role: response['role'] as String?,
      );

      AppLogger.info(
        'Invitation resent',
        metadata: {'invitationId': invitationId},
      );
    } catch (e) {
      AppLogger.error('Failed to resend invitation', error: e);
      rethrow;
    }
  }

  /// Clean up expired invitations
  Future<void> cleanupExpiredInvitations() async {
    try {
      final now = DateTime.now();
      final result = await _supabase
          .from('workspace_invitations')
          .update({'status': 'expired'})
          .eq('status', 'pending')
          .lt('expires_at', now.toIso8601String())
          .select();

      AppLogger.info(
        'Expired invitations cleaned up',
        metadata: {'count': (result as List).length},
      );
    } catch (e) {
      AppLogger.error('Failed to cleanup expired invitations', error: e);
    }
  }

  /// Check if a user with the given email already exists
  Future<bool> checkUserExistsByEmail(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final response = await _supabase
          .from('users')
          .select('id')
          .eq('email', normalizedEmail)
          .limit(1);

      return (response as List).isNotEmpty;
    } catch (e) {
      AppLogger.error('Failed to check if user exists', error: e);
      return false;
    }
  }

  /// Get invitation by token (for acceptance flow)
  Future<WorkspaceInvitation?> getInvitationByToken(String token) async {
    try {
      final response = await _supabase.rpc(
        'get_workspace_invitation_by_token',
        params: {'invite_token': token},
      );

      if (response == null || response is! Map) {
        return null;
      }

      final row = Map<String, dynamic>.from(response);
      return WorkspaceInvitation.fromJson(
        _toFirestoreFormat(row),
        row['id'].toString(),
      );
    } catch (e) {
      AppLogger.error('Failed to get invitation by token', error: e);
      return null;
    }
  }

  /// Send invitation email via Supabase Edge Function
  Future<void> _sendInvitationEmail({
    required String email,
    required String workspaceId,
    required String invitedBy,
    required String token,
    String? role,
  }) async {
    try {
      // Get workspace name
      final workspaceResponse = await _supabase
          .from('workspaces')
          .select('name')
          .eq('id', workspaceId)
          .maybeSingle();

      final workspaceName =
          workspaceResponse?['name'] as String? ?? 'Workspace';

      // Get inviter name
      final inviterResponse = await _supabase
          .from('users')
          .select('display_name, email')
          .eq('id', invitedBy)
          .maybeSingle();

      final inviterName =
          inviterResponse?['display_name'] as String? ??
          inviterResponse?['email'] as String? ??
          'A team member';

      // Call edge function
      final session = _supabase.auth.currentSession;
      if (session == null) {
        AppLogger.warning(
          'No active session found when sending invitation email',
        );
        // Try to refresh the session
        await _supabase.auth.refreshSession();
      }
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null) {
        throw Exception('User must be authenticated to send invitation emails');
      }

      final edgeFunctionUrl =
          '${SupabaseConfig.url}/functions/v1/send-invitation-email';

      final response = await http.post(
        Uri.parse(edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'email': email,
          'workspaceName': workspaceName,
          'inviterName': inviterName,
          'token': token,
          'role': role,
        }),
      );

      if (response.statusCode == 200) {
        AppLogger.info('Invitation email sent to $email');
      } else {
        AppLogger.warning(
          'Failed to send invitation email',
          metadata: {
            'statusCode': response.statusCode,
            'response': response.body,
          },
        );
        // Don't throw - invitation was created, email can be resent
      }
    } catch (e) {
      AppLogger.error('Error sending invitation email', error: e);
      // Don't throw - invitation was created, email can be resent later
    }
  }

  /// Invite a customer contact to the portal. Looks up the contact's email,
  /// resolves the workspace system Customer role template, and issues an
  /// invitation that will link this auth user to the contact on acceptance.
  Future<WorkspaceInvitation> inviteCustomerContactToPortal({
    required String customerContactId,
    required String invitedBy,
  }) async {
    final row = await _supabase
        .from('customer_contacts')
        .select('id, email, user_id, customer_id, customers!inner(workspace_id)')
        .eq('id', customerContactId)
        .maybeSingle();

    if (row == null) {
      throw Exception('Customer contact not found');
    }
    if (row['user_id'] != null) {
      throw Exception('This contact is already linked to a portal user.');
    }
    final email = (row['email'] as String?)?.trim();
    if (email == null || email.isEmpty) {
      throw Exception(
        'Customer contact has no email. Add an email before sending a portal invite.',
      );
    }
    final workspaceId =
        (row['customers'] as Map<String, dynamic>)['workspace_id'] as String;

    final templateId = await _findSystemRoleTemplateId(
      workspaceId: workspaceId,
      role: 'client',
    );

    return inviteUser(
      workspaceId: workspaceId,
      email: email,
      role: UserRole.client,
      invitedBy: invitedBy,
      roleTemplateId: templateId,
      portalCustomerContactId: customerContactId,
    );
  }

  /// Invite a vendor contact to the portal.
  Future<WorkspaceInvitation> inviteVendorContactToPortal({
    required String vendorContactId,
    required String invitedBy,
  }) async {
    final row = await _supabase
        .from('vendor_contacts')
        .select('id, email, user_id, vendor_id, vendors!inner(workspace_id)')
        .eq('id', vendorContactId)
        .maybeSingle();

    if (row == null) {
      throw Exception('Vendor contact not found');
    }
    if (row['user_id'] != null) {
      throw Exception('This contact is already linked to a portal user.');
    }
    final email = (row['email'] as String?)?.trim();
    if (email == null || email.isEmpty) {
      throw Exception(
        'Vendor contact has no email. Add an email before sending a portal invite.',
      );
    }
    final workspaceId =
        (row['vendors'] as Map<String, dynamic>)['workspace_id'] as String;

    final templateId = await _findSystemRoleTemplateId(
      workspaceId: workspaceId,
      role: 'vendor',
    );

    return inviteUser(
      workspaceId: workspaceId,
      email: email,
      role: UserRole.vendor,
      invitedBy: invitedBy,
      roleTemplateId: templateId,
      portalVendorContactId: vendorContactId,
    );
  }

  /// Revoke portal access from a linked contact. Unlinks the contact's
  /// user_id AND removes the auth user's workspace_members row in one atomic
  /// step via revoke_portal_contact_access.
  /// Returns the set of customer_contact ids that have a pending portal
  /// invitation in the given workspace. Used by the customer detail screen to
  /// render an "Invited" badge on pending contacts.
  Future<Set<String>> pendingPortalCustomerContactIds({
    required String workspaceId,
  }) async {
    final rows = await _supabase
        .from('workspace_invitations')
        .select('portal_customer_contact_id')
        .eq('workspace_id', workspaceId)
        .eq('status', 'pending')
        .not('portal_customer_contact_id', 'is', null);
    return (rows as List)
        .map(
          (r) =>
              (r as Map<String, dynamic>)['portal_customer_contact_id']
                  as String?,
        )
        .whereType<String>()
        .toSet();
  }

  Future<Set<String>> pendingPortalVendorContactIds({
    required String workspaceId,
  }) async {
    final rows = await _supabase
        .from('workspace_invitations')
        .select('portal_vendor_contact_id')
        .eq('workspace_id', workspaceId)
        .eq('status', 'pending')
        .not('portal_vendor_contact_id', 'is', null);
    return (rows as List)
        .map(
          (r) =>
              (r as Map<String, dynamic>)['portal_vendor_contact_id'] as String?,
        )
        .whereType<String>()
        .toSet();
  }

  /// Revoke a pending portal invitation by contact id. Use this when the
  /// admin wants to cancel an invite before the invitee accepts.
  Future<void> revokePendingPortalInvitationForCustomerContact({
    required String customerContactId,
  }) async {
    await _supabase
        .from('workspace_invitations')
        .update({'status': 'revoked'})
        .eq('portal_customer_contact_id', customerContactId)
        .eq('status', 'pending');
  }

  Future<void> revokePendingPortalInvitationForVendorContact({
    required String vendorContactId,
  }) async {
    await _supabase
        .from('workspace_invitations')
        .update({'status': 'revoked'})
        .eq('portal_vendor_contact_id', vendorContactId)
        .eq('status', 'pending');
  }

  Future<void> revokeCustomerPortalAccess({
    required String customerContactId,
  }) async {
    await _supabase.rpc(
      'revoke_portal_contact_access',
      params: {
        'contact_id': customerContactId,
        'contact_kind': 'customer',
      },
    );
  }

  Future<void> revokeVendorPortalAccess({
    required String vendorContactId,
  }) async {
    await _supabase.rpc(
      'revoke_portal_contact_access',
      params: {
        'contact_id': vendorContactId,
        'contact_kind': 'vendor',
      },
    );
  }

  Future<String?> _findSystemRoleTemplateId({
    required String workspaceId,
    required String role,
  }) async {
    final row = await _supabase
        .from('workspace_role_templates')
        .select('id')
        .eq('workspace_id', workspaceId)
        .eq('is_system', true)
        .eq('role', role)
        .maybeSingle();
    return row?['id'] as String?;
  }

  String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.masterAdmin:
        return 'master_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.projectManager:
        return 'project_manager';
      case UserRole.fieldTechnician:
        return 'field_technician';
      case UserRole.client:
        return 'client';
      case UserRole.vendor:
        return 'vendor';
    }
  }

  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'email': row['email'],
      'role': row['role'],
      'roleTemplateId': row['role_template_id'],
      'roleName': row['role_name'] ?? row['roleName'],
      'interfaceMode': row['interface_mode'],
      'invitedBy': row['invited_by'],
      'token': row['token'],
      'status': row['status'],
      'workspaceName': row['workspace_name'] ?? row['workspaceName'],
      'inviterName': row['inviter_name'] ?? row['inviterName'],
      'expiresAt': row['expires_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['expires_at']))
          : null,
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'acceptedAt': row['accepted_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['accepted_at']))
          : null,
      'acceptedBy': row['accepted_by'],
    };
  }
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
