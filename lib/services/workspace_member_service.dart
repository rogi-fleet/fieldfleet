import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workspace_member.dart';
import '../models/workspace_membership.dart';
import '../models/user_role.dart';
import '../utils/app_logger.dart';

class WorkspaceMemberService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add a member to a workspace
  Future<void> addMember({
    required String workspaceId,
    required String userId,
    required UserRole role,
    String? invitedBy,
  }) async {
    try {
      // Check if member already exists
      final existingMember = await isMember(workspaceId, userId);
      if (existingMember) {
        throw Exception('User is already a member of this workspace');
      }

      final now = DateTime.now();
      double? defaultHourlyRate;
      double? defaultWeeklyWage;
      try {
        final workspaceDoc = await _firestore.collection('workspaces').doc(workspaceId).get();
        final workspaceData = workspaceDoc.data();
        if (workspaceData != null) {
          defaultHourlyRate = (workspaceData['hourlyRate'] as num?)?.toDouble();
          defaultWeeklyWage = (workspaceData['weeklyWage'] as num?)?.toDouble();
        }
      } catch (e) {
        AppLogger.warning('Failed to load workspace default wages', metadata: {
          'workspaceId': workspaceId,
          'error': e.toString(),
        });
      }
      final member = WorkspaceMember(
        id: WorkspaceMember.generateId(workspaceId, userId),
        workspaceId: workspaceId,
        userId: userId,
        role: role,
        hourlyRate: defaultHourlyRate,
        weeklyWage: defaultWeeklyWage,
        joinedAt: now,
        invitedBy: invitedBy,
        createdAt: now,
        updatedAt: now,
      );

      await _firestore
          .collection('workspace_members')
          .doc(member.id)
          .set(member.toJson());

      AppLogger.info('Member added to workspace', metadata: {
        'workspaceId': workspaceId,
        'userId': userId,
        'role': role.toString(),
      });
    } catch (e) {
      AppLogger.error('Failed to add member', error: e);
      rethrow;
    }
  }

  /// Remove a member from a workspace
  Future<void> removeMember({
    required String workspaceId,
    required String userId,
  }) async {
    try {
      // Check if this is the last admin
      final isLastAdmin = await _isLastAdmin(workspaceId, userId);
      if (isLastAdmin) {
        throw Exception('Cannot remove the last admin from a workspace');
      }

      final memberId = WorkspaceMember.generateId(workspaceId, userId);
      await _firestore.collection('workspace_members').doc(memberId).delete();

      AppLogger.info('Member removed from workspace', metadata: {
        'workspaceId': workspaceId,
        'userId': userId,
      });
    } catch (e) {
      AppLogger.error('Failed to remove member', error: e);
      rethrow;
    }
  }

  /// Update a member's role in a workspace
  Future<void> updateMemberRole({
    required String workspaceId,
    required String userId,
    required UserRole newRole,
  }) async {
    try {
      // If demoting from admin, check if this is the last admin
      final currentRole = await getUserRole(workspaceId, userId);
      if (currentRole == UserRole.admin && newRole != UserRole.admin) {
        final isLastAdmin = await _isLastAdmin(workspaceId, userId);
        if (isLastAdmin) {
          throw Exception('Cannot demote the last admin');
        }
      }

      final memberId = WorkspaceMember.generateId(workspaceId, userId);
      await _firestore.collection('workspace_members').doc(memberId).update({
        'role': newRole.toString(),
        'updatedAt': Timestamp.now(),
      });

      AppLogger.info('Member role updated', metadata: {
        'workspaceId': workspaceId,
        'userId': userId,
        'newRole': newRole.toString(),
      });
    } catch (e) {
      AppLogger.error('Failed to update member role', error: e);
      rethrow;
    }
  }

  /// Get all members of a workspace
  Stream<List<WorkspaceMember>> getWorkspaceMembers(String workspaceId) {
    return _firestore
        .collection('workspace_members')
        .where('workspaceId', isEqualTo: workspaceId)
        .orderBy('joinedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WorkspaceMember.fromJson(doc.data(), doc.id))
            .toList());
  }

  /// Get all workspaces a user belongs to
  Future<List<WorkspaceMembership>> getUserWorkspaces(String userId) async {
    try {
      print('getUserWorkspaces: Querying for userId=$userId');
      
      // Query workspace_members collection for this user
      final membershipSnapshot = await _firestore
          .collection('workspace_members')
          .where('userId', isEqualTo: userId)
          .orderBy('joinedAt', descending: true)
          .get();

      print('getUserWorkspaces: Found ${membershipSnapshot.docs.length} membership documents');
      
      final workspaces = <WorkspaceMembership>[];

      for (final doc in membershipSnapshot.docs) {
        print('getUserWorkspaces: Processing doc ${doc.id}');
        print('getUserWorkspaces: Doc data: ${doc.data()}');
        
        final member = WorkspaceMember.fromJson(doc.data(), doc.id);

        // Fetch workspace details
        final workspaceDoc = await _firestore
            .collection('workspaces')
            .doc(member.workspaceId)
            .get();

        print('getUserWorkspaces: Workspace ${member.workspaceId} exists: ${workspaceDoc.exists}');
        
        if (workspaceDoc.exists) {
          final workspaceData = workspaceDoc.data()!;
          print('getUserWorkspaces: Workspace data: $workspaceData');
          
          workspaces.add(WorkspaceMembership(
            membershipId: member.id,
            workspaceId: member.workspaceId,
            workspaceName: workspaceData['name'] as String? ?? 'Unnamed Workspace',
            avatarUrl: workspaceData['avatarUrl'] as String?,
            role: member.role,
            joinedAt: member.joinedAt,
            projectTerminology: workspaceData['projectTerminology'] as String?,
            enabledNavigationTabs: workspaceData['enabledNavigationTabs'] != null
                ? List<String>.from(workspaceData['enabledNavigationTabs'] as List)
                : const [],
            showBusinessDaysOnly: workspaceData['showBusinessDaysOnly'] as bool? ?? false,
            currencyCode: workspaceData['currencyCode'] as String? ?? 'USD',
            hourlyRate: member.hourlyRate,
            defaultHourlyRate: (workspaceData['hourlyRate'] as num?)?.toDouble(),
            weeklyWage: member.weeklyWage,
            defaultWeeklyWage: (workspaceData['weeklyWage'] as num?)?.toDouble(),
            modulePermissions: member.modulePermissions,
          ));
        }
      }

      print('getUserWorkspaces: Returning ${workspaces.length} workspaces');
      return workspaces;
    } catch (e) {
      print('getUserWorkspaces: Error - $e');
      AppLogger.error('Failed to get user workspaces', error: e);
      return [];
    }
  }

  /// Check if a user is a member of a workspace
  Future<bool> isMember(String workspaceId, String userId) async {
    try {
      final memberId = WorkspaceMember.generateId(workspaceId, userId);
      final doc = await _firestore
          .collection('workspace_members')
          .doc(memberId)
          .get();

      return doc.exists;
    } catch (e) {
      AppLogger.error('Failed to check membership', error: e);
      return false;
    }
  }

  /// Get a user's role in a workspace
  Future<UserRole?> getUserRole(String workspaceId, String userId) async {
    try {
      final memberId = WorkspaceMember.generateId(workspaceId, userId);
      final doc = await _firestore
          .collection('workspace_members')
          .doc(memberId)
          .get();

      if (!doc.exists) {
        return null;
      }

      final member = WorkspaceMember.fromJson(doc.data()!, doc.id);
      return member.role;
    } catch (e) {
      AppLogger.error('Failed to get user role', error: e);
      return null;
    }
  }

  /// Check if a user is the last admin in a workspace
  Future<bool> _isLastAdmin(String workspaceId, String userId) async {
    try {
      final userRole = await getUserRole(workspaceId, userId);
      if (userRole != UserRole.admin) {
        return false;
      }

      final adminsSnapshot = await _firestore
          .collection('workspace_members')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('role', isEqualTo: 'admin')
          .get();

      return adminsSnapshot.docs.length == 1;
    } catch (e) {
      AppLogger.error('Failed to check if last admin', error: e);
      return false;
    }
  }

  /// Get member count for a workspace
  Future<int> getMemberCount(String workspaceId) async {
    try {
      final snapshot = await _firestore
          .collection('workspace_members')
          .where('workspaceId', isEqualTo: workspaceId)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      AppLogger.error('Failed to get member count', error: e);
      return 0;
    }
  }

  /// Update a member's skills
  Future<void> updateMemberSkills({
    required String workspaceId,
    required String userId,
    required List<String> skillIds,
  }) async {
    try {
      final memberId = WorkspaceMember.generateId(workspaceId, userId);
      await _firestore.collection('workspace_members').doc(memberId).update({
        'skillIds': skillIds,
        'updatedAt': Timestamp.now(),
      });

      AppLogger.info('Member skills updated', metadata: {
        'workspaceId': workspaceId,
        'userId': userId,
        'skillCount': skillIds.length,
      });
    } catch (e) {
      AppLogger.error('Failed to update member skills', error: e);
      rethrow;
    }
  }

  /// Get a member's interface mode (Firebase stub always returns 'manager')
  Future<String> getMemberInterfaceMode(String workspaceId, String userId) {
    return Future.value('manager');
  }

  /// Update a member's settings (hourly rate, weekly wage, module permissions, and interface mode)
  Future<void> updateMemberSettings({
    required String workspaceId,
    required String userId,
    double? hourlyRate,
    double? weeklyWage,
    Map<String, String>? modulePermissions,
    String? interfaceMode,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': Timestamp.now(),
      };

      if (hourlyRate != null) {
        updates['hourlyRate'] = hourlyRate;
      }

      if (weeklyWage != null) {
        updates['weeklyWage'] = weeklyWage;
      }

      if (modulePermissions != null) {
        updates['modulePermissions'] = modulePermissions;
      }

      final memberId = WorkspaceMember.generateId(workspaceId, userId);
      await _firestore.collection('workspace_members').doc(memberId).update(updates);

      AppLogger.info('Member settings updated', metadata: {
        'workspaceId': workspaceId,
        'userId': userId,
        'hasHourlyRate': hourlyRate != null,
        'hasWeeklyWage': weeklyWage != null,
        'hasPermissions': modulePermissions != null,
      });
    } catch (e) {
      AppLogger.error('Failed to update member settings', error: e);
      rethrow;
    }
  }
}
