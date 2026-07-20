import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user.dart';
import '../../utils/app_logger.dart';

class SupabaseUserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get a single user by ID
  Future<AppUser?> getUserById(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        return AppUser.fromJson(_toFirestoreFormat(response), userId);
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to fetch user', error: e, metadata: {'userId': userId});
      return null;
    }
  }

  Stream<AppUser?> getUserStream(String userId) {
    return _supabase
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) {
          if (data.isEmpty) return null;
          return AppUser.fromJson(_toFirestoreFormat(data.first), userId);
        });
  }

  // Get all users in a workspace
  Stream<List<AppUser>> getUsersByWorkspace(String workspaceId) {
    return _supabase
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('active_workspace_id', workspaceId)
        .map((data) => data
            .map((row) => AppUser.fromJson(_toFirestoreFormat(row), row['id']))
            .toList());
  }

  /// Fetch a specific set of users by their IDs in a single query.
  Future<List<AppUser>> getUsersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final response = await _supabase
          .from('users')
          .select()
          .inFilter('id', ids);
      return response
          .map((row) => AppUser.fromJson(_toFirestoreFormat(row), row['id']))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to fetch users by ids', error: e);
      return [];
    }
  }

  // Update user profile
  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    try {
      // Convert camelCase to snake_case for Supabase
      final supabaseUpdates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      updates.forEach((key, value) {
        supabaseUpdates[_toSnakeCase(key)] = value;
      });

      await _supabase.from('users').update(supabaseUpdates).eq('id', userId);
    } catch (e) {
      AppLogger.error('Failed to update user profile', error: e, metadata: {'userId': userId});
      throw Exception('Failed to update profile: $e');
    }
  }

  /// Get all users in a workspace as a map keyed by user ID
  Future<Map<String, AppUser>> getWorkspaceUsersMap(String workspaceId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('active_workspace_id', workspaceId);

      final Map<String, AppUser> usersMap = {};
      for (final row in response as List) {
        final userId = row['id'] as String;
        usersMap[userId] = AppUser.fromJson(_toFirestoreFormat(row), userId);
      }
      return usersMap;
    } catch (e) {
      AppLogger.error('Failed to fetch workspace users map', error: e, metadata: {
        'workspaceId': workspaceId,
      });
      return {};
    }
  }

  // Search users by name or email
  Future<List<AppUser>> searchUsers(String workspaceId, String query) async {
    try {
      final lowerQuery = query.toLowerCase();
      final response = await _supabase
          .from('users')
          .select()
          .eq('active_workspace_id', workspaceId)
          .or('display_name.ilike.%$lowerQuery%,email.ilike.%$lowerQuery%');

      return (response as List)
          .map((row) => AppUser.fromJson(_toFirestoreFormat(row), row['id']))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to search users', error: e, metadata: {
        'workspaceId': workspaceId,
        'query': query,
      });
      return [];
    }
  }

  // Validation helpers
  bool isValidPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return true;
    final phoneRegex = RegExp(r'^\+?[\d\s\-\(\)]{7,20}$');
    return phoneRegex.hasMatch(phone);
  }

  bool isValidBio(String? bio) {
    if (bio == null) return true;
    return bio.length <= 500;
  }

  bool isValidJobTitle(String? title) {
    if (title == null) return true;
    return title.length <= 100;
  }

  bool isValidCompanyName(String? name) {
    if (name == null) return true;
    return name.length <= 100;
  }

  // Profile Picture Upload
  Future<String> uploadProfilePicture(
    String userId,
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

      // Delete existing profile picture if exists
      final user = await getUserById(userId);
      if (user?.profilePictureUrl != null) {
        try {
          final oldPath = _extractStoragePath(user!.profilePictureUrl!);
          if (oldPath != null) {
            await _supabase.storage.from('avatars').remove([oldPath]);
            AppLogger.info('Deleted old profile picture', metadata: {'userId': userId});
          }
        } catch (e) {
          AppLogger.warning('Error deleting old profile picture', metadata: {
            'userId': userId,
            'error': e.toString(),
          });
        }
      }

      // Upload to Supabase Storage (unique path per upload for cache-busting)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'users/$userId/profile-picture_$timestamp.jpg';
      await _supabase.storage.from('avatars').uploadBinary(
        storagePath,
        imageBytes,
        fileOptions: FileOptions(
          contentType: _getContentType(lowerFileName),
          cacheControl: '31536000',
        ),
      );

      final downloadUrl = _supabase.storage.from('avatars').getPublicUrl(storagePath);

      // Update user document with new profile picture URL
      await updateProfile(userId, {'profilePictureUrl': downloadUrl});

      return downloadUrl;
    } catch (e) {
      AppLogger.error('Failed to upload profile picture', error: e, metadata: {
        'userId': userId,
        'workspaceId': workspaceId,
      });
      throw Exception('Failed to upload profile picture: $e');
    }
  }

  // Delete Profile Picture
  Future<void> deleteProfilePicture(
    String userId,
    String profilePictureUrl,
  ) async {
    try {
      final path = _extractStoragePath(profilePictureUrl);
      if (path != null) {
        await _supabase.storage.from('avatars').remove([path]);
        AppLogger.info('Deleted profile picture from storage', metadata: {
          'userId': userId,
        });
      }

      await updateProfile(userId, {'profilePictureUrl': null});
    } catch (e) {
      AppLogger.warning('Failed to delete profile picture', metadata: {
        'userId': userId,
        'error': e.toString(),
      });
      try {
        await updateProfile(userId, {'profilePictureUrl': null});
      } catch (updateError) {
        AppLogger.error('Failed to update user profile after picture deletion error',
          error: updateError,
          metadata: {'userId': userId},
        );
      }
    }
  }

  String? _extractStoragePath(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf('avatars');
      if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
        return pathSegments.sublist(bucketIndex + 1).join('/');
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _getContentType(String fileName) {
    if (fileName.endsWith('.png')) return 'image/png';
    if (fileName.endsWith('.webp')) return 'image/webp';
    if (fileName.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  /// Helper class for Timestamp compatibility
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'email': row['email'],
      'displayName': row['display_name'],
      'workspaceId': row['active_workspace_id'],
      'activeWorkspaceId': row['active_workspace_id'],
      'defaultWorkspaceId': row['default_workspace_id'],
      'role': row['role'],
      'emailVerified': row['email_verified'],
      'emailVerifiedAt': row['email_verified_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['email_verified_at']))
          : null,
      'profilePictureUrl': row['profile_picture_url'],
      'phoneNumber': row['phone_number'],
      'jobTitle': row['job_title'],
      'bio': row['bio'],
      'companyName': row['company_name'],
      'timezone': row['timezone'],
      'hourlyRate': row['hourly_rate'],
      'notificationPreferences': row['notification_preferences'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : _FakeTimestamp(DateTime.now()),
    };
  }
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
