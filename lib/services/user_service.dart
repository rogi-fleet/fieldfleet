import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/user.dart';
import '../utils/app_logger.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Get a single user by ID
  Future<AppUser?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return AppUser.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to fetch user', error: e, metadata: {'userId': userId});
      return null;
    }
  }

  Stream<AppUser?> getUserStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromJson(doc.data()!, doc.id);
    });
  }

  // Get all users in a workspace
  Stream<List<AppUser>> getUsersByWorkspace(String workspaceId) {
    return _firestore
        .collection('users')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => AppUser.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Update user profile
  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    try {
      // Add updatedAt timestamp
      updates['updatedAt'] = Timestamp.now();

      await _firestore.collection('users').doc(userId).update(updates);
    } catch (e) {
      AppLogger.error('Failed to update user profile', error: e, metadata: {'userId': userId});
      throw Exception('Failed to update profile: $e');
    }
  }

  /// Get all users in a workspace as a map keyed by user ID
  /// Useful for efficient lookups when displaying user info on tasks
  Future<Map<String, AppUser>> getWorkspaceUsersMap(String workspaceId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();
      
      final Map<String, AppUser> usersMap = {};
      for (final doc in snapshot.docs) {
        usersMap[doc.id] = AppUser.fromJson(doc.data(), doc.id);
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
      final snapshot = await _firestore
          .collection('users')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      final lowerQuery = query.toLowerCase();
      return snapshot.docs
          .map((doc) => AppUser.fromJson(doc.data(), doc.id))
          .where((user) =>
              (user.displayName?.toLowerCase().contains(lowerQuery) ?? false) ||
              user.email.toLowerCase().contains(lowerQuery))
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
    // Basic phone validation - allows international formats
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

  // Profile Picture Upload - uses Uint8List for web compatibility
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

      // Delete existing profile picture if exists (don't fail upload if deletion fails)
      final user = await getUserById(userId);
      if (user?.profilePictureUrl != null && user!.profilePictureUrl!.contains('firebasestorage')) {
        try {
          final oldRef = _storage.refFromURL(user.profilePictureUrl!);
          // Just try to delete directly, catching any error
          await oldRef.delete().catchError((e) {
            AppLogger.info('Old profile picture could not be deleted (may not exist)', 
              metadata: {'userId': userId, 'error': e.toString()});
          });
        } catch (e) {
          AppLogger.warning('Error parsing old profile picture URL', metadata: {
            'userId': userId,
            'url': user.profilePictureUrl,
            'error': e.toString(),
          });
          // Continue with upload anyway
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
            'workspaces/$workspaceId/users/$userId/profile-picture.jpg',
          );

      await storageRef.putData(
        imageBytes,
        SettableMetadata(contentType: contentType),
      );
      final downloadUrl = await storageRef.getDownloadURL();

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
      // Extract storage path from URL and delete
      final ref = _storage.refFromURL(profilePictureUrl);

      // Check if file exists before attempting delete
      try {
        await ref.getMetadata();
        await ref.delete();
        AppLogger.info('Deleted profile picture from storage', metadata: {
          'userId': userId,
        });
      } catch (e) {
        // File doesn't exist or already deleted - that's okay
        AppLogger.info('Profile picture file not found in storage (already deleted)', metadata: {
          'userId': userId,
          'url': profilePictureUrl,
        });
      }

      // Update user document to clear the URL
      await updateProfile(userId, {'profilePictureUrl': null});
    } catch (e) {
      AppLogger.warning('Failed to delete profile picture', metadata: {
        'userId': userId,
        'error': e.toString(),
      });
      // Don't throw - allow profile update even if file deletion fails
      // Still try to clear the URL from the user document
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
}
