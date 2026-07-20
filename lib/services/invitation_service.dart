import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workspace_invitation.dart';
import '../models/user_role.dart';
import '../utils/app_logger.dart';

class InvitationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int _tokenLength = 48;
  static const int _expirationDays = 7;

  /// Generate a cryptographically secure random token
  String _generateSecureToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(_tokenLength, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Invite a user to a workspace
  Future<WorkspaceInvitation> inviteUser({
    required String workspaceId,
    required String email,
    required UserRole role,
    required String invitedBy,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      // Check for existing pending invitation
      final existingInvitations = await _firestore
          .collection('workspace_invitations')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('email', isEqualTo: normalizedEmail)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingInvitations.docs.isNotEmpty) {
        throw Exception('An invitation for this email already exists');
      }

      // Check if user with this email is already a member of the workspace
      final usersQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (usersQuery.docs.isNotEmpty) {
        final userId = usersQuery.docs.first.id;
        final memberId = '${workspaceId}_$userId';
        
        final existingMember = await _firestore
            .collection('workspace_members')
            .doc(memberId)
            .get();

        if (existingMember.exists) {
          throw Exception('This user is already a member of this workspace');
        }
      }

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(days: _expirationDays));

      final invitation = WorkspaceInvitation(
        id: '', // Will be set by Firestore
        workspaceId: workspaceId,
        email: normalizedEmail,
        role: role,
        invitedBy: invitedBy,
        token: _generateSecureToken(),
        status: InvitationStatus.pending,
        expiresAt: expiresAt,
        createdAt: now,
      );

      // Validate invitation
      final validationError = invitation.validate();
      if (validationError != null) {
        throw Exception(validationError);
      }

      final docRef = await _firestore
          .collection('workspace_invitations')
          .add(invitation.toJson());

      AppLogger.info('Invitation created', metadata: {
        'invitationId': docRef.id,
        'workspaceId': workspaceId,
        'email': normalizedEmail,
      });

      return invitation.copyWith(id: docRef.id);
    } catch (e) {
      AppLogger.error('Failed to create invitation', error: e);
      rethrow;
    }
  }

  /// Get all invitations for a workspace
  Stream<List<WorkspaceInvitation>> getWorkspaceInvitations(String workspaceId) {
    return _firestore
        .collection('workspace_invitations')
        .where('workspaceId', isEqualTo: workspaceId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WorkspaceInvitation.fromJson(doc.data(), doc.id))
            .toList());
  }

  /// Get pending invitations for a user by email
  Future<List<WorkspaceInvitation>> getUserPendingInvitations(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final snapshot = await _firestore
          .collection('workspace_invitations')
          .where('email', isEqualTo: normalizedEmail)
          .where('status', isEqualTo: 'pending')
          .get();

      return snapshot.docs
          .map((doc) => WorkspaceInvitation.fromJson(doc.data(), doc.id))
          .where((invitation) => !invitation.isExpired)
          .toList();
    } catch (e) {
      AppLogger.error('Failed to get pending invitations', error: e);
      return [];
    }
  }

  /// Accept an invitation
  Future<void> acceptInvitation({
    required String token,
    required String userId,
  }) async {
    try {
      // Find invitation by token
      final snapshot = await _firestore
          .collection('workspace_invitations')
          .where('token', isEqualTo: token)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        throw Exception('Invitation not found');
      }

      final doc = snapshot.docs.first;
      final invitation = WorkspaceInvitation.fromJson(doc.data(), doc.id);

      // Validate invitation can be accepted
      if (!invitation.canAccept) {
        if (invitation.isExpired) {
          throw Exception('This invitation has expired');
        }
        throw Exception('This invitation cannot be accepted');
      }

      // Validate user email matches invitation email
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User not found');
      }
      
      final userEmail = (userDoc.data()!['email'] as String).toLowerCase().trim();
      final invitationEmail = invitation.email.toLowerCase().trim();
      if (userEmail != invitationEmail) {
        throw Exception('This invitation was sent to a different email address');
      }

      // Check if user is already a member of this workspace
      final memberId = '${invitation.workspaceId}_$userId';
      final existingMember = await _firestore
          .collection('workspace_members')
          .doc(memberId)
          .get();
      
      if (existingMember.exists) {
        throw Exception('You are already a member of this workspace');
      }

      // Create workspace member entry
      final now = DateTime.now();
      final member = {
        'workspaceId': invitation.workspaceId,
        'userId': userId,
        'role': invitation.role.toString(),
        'joinedAt': Timestamp.fromDate(now),
        'invitedBy': invitation.invitedBy,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      await _firestore
          .collection('workspace_members')
          .doc(memberId)
          .set(member);

      // Update user's active workspace
      await _firestore.collection('users').doc(userId).update({
        'activeWorkspaceId': invitation.workspaceId,
        'updatedAt': Timestamp.fromDate(now),
      });

      // Update invitation status
      await doc.reference.update({
        'status': InvitationStatus.accepted.name,
        'acceptedAt': Timestamp.now(),
        'acceptedBy': userId,
      });

      AppLogger.info('Invitation accepted and workspace member created', metadata: {
        'invitationId': doc.id,
        'userId': userId,
        'workspaceId': invitation.workspaceId,
        'role': invitation.role.toString(),
      });
    } catch (e) {
      AppLogger.error('Failed to accept invitation', error: e);
      rethrow;
    }
  }

  /// Revoke an invitation
  Future<void> revokeInvitation(String invitationId) async {
    try {
      await _firestore
          .collection('workspace_invitations')
          .doc(invitationId)
          .update({
        'status': InvitationStatus.revoked.name,
      });

      AppLogger.info('Invitation revoked', metadata: {'invitationId': invitationId});
    } catch (e) {
      AppLogger.error('Failed to revoke invitation', error: e);
      rethrow;
    }
  }

  /// Resend an invitation (regenerate token and extend expiration)
  Future<void> resendInvitation(String invitationId) async {
    try {
      final doc = await _firestore
          .collection('workspace_invitations')
          .doc(invitationId)
          .get();

      if (!doc.exists) {
        throw Exception('Invitation not found');
      }

      final now = DateTime.now();
      await doc.reference.update({
        'token': _generateSecureToken(),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: _expirationDays))),
        'status': InvitationStatus.pending.name,
      });

      AppLogger.info('Invitation resent', metadata: {'invitationId': invitationId});
    } catch (e) {
      AppLogger.error('Failed to resend invitation', error: e);
      rethrow;
    }
  }

  /// Clean up expired invitations (should be run periodically)
  Future<void> cleanupExpiredInvitations() async {
    try {
      final snapshot = await _firestore
          .collection('workspace_invitations')
          .where('status', isEqualTo: 'pending')
          .where('expiresAt', isLessThan: Timestamp.now())
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'status': InvitationStatus.expired.name});
      }

      await batch.commit();

      AppLogger.info('Expired invitations cleaned up', metadata: {
        'count': snapshot.docs.length,
      });
    } catch (e) {
      AppLogger.error('Failed to cleanup expired invitations', error: e);
    }
  }

  /// Check if a user with the given email already exists
  Future<bool> checkUserExistsByEmail(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final usersQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      return usersQuery.docs.isNotEmpty;
    } catch (e) {
      AppLogger.error('Failed to check if user exists', error: e);
      return false;
    }
  }

  /// Get invitation by token (for acceptance flow)
  Future<WorkspaceInvitation?> getInvitationByToken(String token) async {
    try {
      final snapshot = await _firestore
          .collection('workspace_invitations')
          .where('token', isEqualTo: token)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return WorkspaceInvitation.fromJson(
        snapshot.docs.first.data(),
        snapshot.docs.first.id,
      );
    } catch (e) {
      AppLogger.error('Failed to get invitation by token', error: e);
      return null;
    }
  }
}
