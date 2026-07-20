import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/company_type.dart';
import '../models/workspace_member.dart';
import '../models/user_role.dart';
import '../utils/app_logger.dart';
import '../utils/timezone_options.dart';

class WorkspaceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> createWorkspace({
    required String name,
    required String ownerId,
    required CompanyType companyType,
    String? projectTerminology,
    int? startingProjectSerialNumber,
    List<String>? enabledProjectTabs,
    String? companyAddress,
    String? companyCity,
    String? companyState,
    String? companyZipCode,
    String? companyCountry,
    String currencyCode = 'USD',
    String timezone = TimezoneOptions.defaultTimezone,
    double? hourlyRate,
    double? weeklyWage,
    bool defaultTaxEnabled = true,
    String defaultTaxName = 'Tax',
    double? defaultTaxRate,
  }) async {
    try {
      // Apply smart defaults based on company type
      final effectiveProjectTerminology =
          projectTerminology ?? companyType.defaultProjectTerminology;
      final effectiveEnabledTabs =
          enabledProjectTabs ?? companyType.defaultEnabledTabs;

      // 1. Create workspace document
      final workspaceRef = _firestore.collection('workspaces').doc();
      final workspaceId = workspaceRef.id;

      final now = DateTime.now();

      await workspaceRef.set({
        'id': workspaceId,
        'name': name,
        'ownerId': ownerId,
        'companyType': companyType.name,
        'projectTerminology': effectiveProjectTerminology,
        if (startingProjectSerialNumber != null)
          'startingProjectSerialNumber': startingProjectSerialNumber,
        if (effectiveEnabledTabs.isNotEmpty)
          'enabledProjectTabs': effectiveEnabledTabs,
        if (companyAddress != null) 'companyAddress': companyAddress,
        if (companyCity != null) 'companyCity': companyCity,
        if (companyState != null) 'companyState': companyState,
        if (companyZipCode != null) 'companyZipCode': companyZipCode,
        if (companyCountry != null) 'companyCountry': companyCountry,
        'currencyCode': currencyCode,
        'timezone': timezone,
        if (hourlyRate != null) 'hourlyRate': hourlyRate,
        if (weeklyWage != null) 'weeklyWage': weeklyWage,
        'defaultTaxEnabled': defaultTaxEnabled,
        'defaultTaxName': defaultTaxName,
        if (defaultTaxRate != null) 'defaultTaxRate': defaultTaxRate,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      // 2. Add owner as admin member
      final memberId = WorkspaceMember.generateId(workspaceId, ownerId);
      final member = WorkspaceMember(
        id: memberId,
        workspaceId: workspaceId,
        userId: ownerId,
        role: UserRole.admin,
        joinedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await _firestore
          .collection('workspace_members')
          .doc(memberId)
          .set(member.toJson());

      AppLogger.info(
        'Workspace created',
        metadata: {
          'workspaceId': workspaceId,
          'name': name,
          'ownerId': ownerId,
        },
      );

      return workspaceId;
    } catch (e) {
      AppLogger.error('Failed to create workspace', error: e);
      rethrow;
    }
  }

  Future<void> updateWorkspace({
    required String workspaceId,
    required String name,
    CompanyType? companyType,
    String? projectTerminology,
    int? startingProjectSerialNumber,
    List<String>? enabledProjectTabs,
    List<String>? enabledNavigationTabs,
    bool? showBusinessDaysOnly,
    String? companyAddress,
    String? companyCity,
    String? companyState,
    String? companyZipCode,
    String? companyCountry,
    String? currencyCode,
    String? timezone,
    double? hourlyRate,
    double? weeklyWage,
    bool? defaultTaxEnabled,
    String? defaultTaxName,
    double? defaultTaxRate,
    String? aiPersonaName,
    String? aiPersonaAvatar,
    String? aiPersonaStyle,
    String? aiPersonaContext,
    List<String>? goals,
    int? teamSize,
    Set<String>? touchedFields,
  }) async {
    try {
      final now = DateTime.now();

      final updates = <String, dynamic>{'updatedAt': Timestamp.fromDate(now)};

      bool shouldUpdate(String field) {
        return touchedFields == null || touchedFields.contains(field);
      }

      if (shouldUpdate('name')) {
        updates['name'] = name;
      }

      if (shouldUpdate('companyType') && companyType != null) {
        updates['companyType'] = companyType.name;
      }

      if (shouldUpdate('projectTerminology')) {
        updates['projectTerminology'] = projectTerminology;
      } else if (projectTerminology != null) {
        updates['projectTerminology'] = projectTerminology;
      }

      if (shouldUpdate('startingProjectSerialNumber')) {
        updates['startingProjectSerialNumber'] = startingProjectSerialNumber;
      } else if (startingProjectSerialNumber != null) {
        updates['startingProjectSerialNumber'] = startingProjectSerialNumber;
      }

      if (shouldUpdate('enabledProjectTabs')) {
        updates['enabledProjectTabs'] = enabledProjectTabs ?? [];
      } else if (touchedFields == null) {
        updates['enabledProjectTabs'] = enabledProjectTabs ?? [];
      }
      if (shouldUpdate('enabledNavigationTabs')) {
        updates['enabledNavigationTabs'] = enabledNavigationTabs ?? [];
      } else if (touchedFields == null) {
        updates['enabledNavigationTabs'] = enabledNavigationTabs ?? [];
      }

      if (shouldUpdate('showBusinessDaysOnly') &&
          showBusinessDaysOnly != null) {
        updates['showBusinessDaysOnly'] = showBusinessDaysOnly;
      } else if (showBusinessDaysOnly != null) {
        updates['showBusinessDaysOnly'] = showBusinessDaysOnly;
      }

      if (shouldUpdate('companyAddress')) {
        updates['companyAddress'] = companyAddress;
      } else if (touchedFields == null) {
        updates['companyAddress'] = companyAddress;
      }
      if (shouldUpdate('companyCity')) {
        updates['companyCity'] = companyCity;
      } else if (touchedFields == null) {
        updates['companyCity'] = companyCity;
      }
      if (shouldUpdate('companyState')) {
        updates['companyState'] = companyState;
      } else if (touchedFields == null) {
        updates['companyState'] = companyState;
      }
      if (shouldUpdate('companyZipCode')) {
        updates['companyZipCode'] = companyZipCode;
      } else if (touchedFields == null) {
        updates['companyZipCode'] = companyZipCode;
      }
      if (shouldUpdate('companyCountry')) {
        updates['companyCountry'] = companyCountry;
      } else if (touchedFields == null) {
        updates['companyCountry'] = companyCountry;
      }

      if (shouldUpdate('currencyCode') && currencyCode != null) {
        updates['currencyCode'] = currencyCode;
      } else if (currencyCode != null) {
        updates['currencyCode'] = currencyCode;
      }
      if (shouldUpdate('timezone') && timezone != null) {
        updates['timezone'] = timezone;
      } else if (timezone != null) {
        updates['timezone'] = timezone;
      }
      if (shouldUpdate('hourlyRate')) {
        updates['hourlyRate'] = hourlyRate;
      } else if (hourlyRate != null) {
        updates['hourlyRate'] = hourlyRate;
      }
      if (shouldUpdate('weeklyWage')) {
        updates['weeklyWage'] = weeklyWage;
      } else if (weeklyWage != null) {
        updates['weeklyWage'] = weeklyWage;
      }

      if (shouldUpdate('defaultTaxEnabled') && defaultTaxEnabled != null) {
        updates['defaultTaxEnabled'] = defaultTaxEnabled;
      }
      if (shouldUpdate('defaultTaxName')) {
        updates['defaultTaxName'] = defaultTaxName;
      } else if (defaultTaxName != null) {
        updates['defaultTaxName'] = defaultTaxName;
      }
      if (shouldUpdate('defaultTaxRate')) {
        updates['defaultTaxRate'] = defaultTaxRate;
      } else if (defaultTaxRate != null) {
        updates['defaultTaxRate'] = defaultTaxRate;
      }

      if (shouldUpdate('aiPersonaName')) {
        updates['aiPersonaName'] = aiPersonaName;
      } else if (aiPersonaName != null) {
        updates['aiPersonaName'] = aiPersonaName;
      }
      if (shouldUpdate('aiPersonaAvatar') && aiPersonaAvatar != null) {
        updates['aiPersonaAvatar'] = aiPersonaAvatar;
      } else if (aiPersonaAvatar != null) {
        updates['aiPersonaAvatar'] = aiPersonaAvatar;
      }
      if (shouldUpdate('aiPersonaStyle') && aiPersonaStyle != null) {
        updates['aiPersonaStyle'] = aiPersonaStyle;
      } else if (aiPersonaStyle != null) {
        updates['aiPersonaStyle'] = aiPersonaStyle;
      }
      if (shouldUpdate('aiPersonaContext')) {
        updates['aiPersonaContext'] = aiPersonaContext;
      } else if (aiPersonaContext != null) {
        updates['aiPersonaContext'] = aiPersonaContext;
      }

      if (shouldUpdate('goals') && goals != null) {
        updates['goals'] = goals;
      } else if (goals != null) {
        updates['goals'] = goals;
      }
      if (shouldUpdate('teamSize') && teamSize != null) {
        updates['teamSize'] = teamSize;
      } else if (teamSize != null) {
        updates['teamSize'] = teamSize;
      }

      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .update(updates);

      AppLogger.info(
        'Workspace updated',
        metadata: {'workspaceId': workspaceId, 'name': name},
      );
    } catch (e) {
      AppLogger.error('Failed to update workspace', error: e);
      rethrow;
    }
  }

  Stream<Map<String, dynamic>?> getWorkspace(String workspaceId) {
    return _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// Upload workspace avatar image
  Future<String> uploadWorkspaceAvatar(
    String workspaceId,
    Uint8List imageBytes,
    String fileName,
  ) async {
    try {
      // Validate file size (max 5MB)
      if (imageBytes.length > 5 * 1024 * 1024) {
        throw Exception('Image must be less than 5MB');
      }

      // Validate file type
      final lowerFileName = fileName.toLowerCase();
      if (!lowerFileName.endsWith('.jpg') &&
          !lowerFileName.endsWith('.jpeg') &&
          !lowerFileName.endsWith('.png') &&
          !lowerFileName.endsWith('.heic') &&
          !lowerFileName.endsWith('.webp')) {
        throw Exception('Only JPEG, PNG, HEIC, and WebP images are allowed');
      }

      // Delete existing avatar if exists
      final workspaceDoc = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .get();

      final existingAvatarUrl = workspaceDoc.data()?['avatarUrl'] as String?;
      if (existingAvatarUrl != null) {
        try {
          final oldRef = _storage.refFromURL(existingAvatarUrl);
          try {
            await oldRef.getMetadata();
            await oldRef.delete();
            AppLogger.info(
              'Deleted old workspace avatar',
              metadata: {'workspaceId': workspaceId},
            );
          } catch (e) {
            AppLogger.info(
              'Old workspace avatar not found (already deleted)',
              metadata: {'workspaceId': workspaceId, 'url': existingAvatarUrl},
            );
          }
        } catch (e) {
          AppLogger.warning(
            'Error checking/deleting old workspace avatar',
            metadata: {'workspaceId': workspaceId, 'error': e.toString()},
          );
        }
      }

      // Determine content type
      String contentType = 'image/jpeg';
      if (lowerFileName.endsWith('.png')) {
        contentType = 'image/png';
      } else if (lowerFileName.endsWith('.webp')) {
        contentType = 'image/webp';
      } else if (lowerFileName.endsWith('.heic')) {
        contentType = 'image/heic';
      }

      // Upload to Firebase Storage
      final storageRef = _storage.ref().child(
        'workspaces/$workspaceId/avatar.jpg',
      );

      await storageRef.putData(
        imageBytes,
        SettableMetadata(contentType: contentType),
      );
      final downloadUrl = await storageRef.getDownloadURL();

      // Update workspace document with new avatar URL
      await _firestore.collection('workspaces').doc(workspaceId).update({
        'avatarUrl': downloadUrl,
        'updatedAt': Timestamp.now(),
      });

      AppLogger.info(
        'Workspace avatar uploaded',
        metadata: {'workspaceId': workspaceId},
      );

      return downloadUrl;
    } catch (e) {
      AppLogger.error(
        'Failed to upload workspace avatar',
        error: e,
        metadata: {'workspaceId': workspaceId},
      );
      throw Exception('Failed to upload workspace avatar: $e');
    }
  }

  /// Delete workspace avatar
  Future<void> deleteWorkspaceAvatar(
    String workspaceId,
    String avatarUrl,
  ) async {
    try {
      // Extract storage path from URL and delete
      final ref = _storage.refFromURL(avatarUrl);

      try {
        await ref.getMetadata();
        await ref.delete();
        AppLogger.info(
          'Deleted workspace avatar from storage',
          metadata: {'workspaceId': workspaceId},
        );
      } catch (e) {
        AppLogger.info(
          'Workspace avatar file not found in storage (already deleted)',
          metadata: {'workspaceId': workspaceId, 'url': avatarUrl},
        );
      }

      // Update workspace document to clear the URL
      await _firestore.collection('workspaces').doc(workspaceId).update({
        'avatarUrl': FieldValue.delete(),
        'updatedAt': Timestamp.now(),
      });

      AppLogger.info(
        'Workspace avatar removed',
        metadata: {'workspaceId': workspaceId},
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to delete workspace avatar',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
      // Still try to clear the URL from the workspace document
      try {
        await _firestore.collection('workspaces').doc(workspaceId).update({
          'avatarUrl': FieldValue.delete(),
          'updatedAt': Timestamp.now(),
        });
      } catch (updateError) {
        AppLogger.error(
          'Failed to update workspace after avatar deletion error',
          error: updateError,
          metadata: {'workspaceId': workspaceId},
        );
      }
    }
  }
}
