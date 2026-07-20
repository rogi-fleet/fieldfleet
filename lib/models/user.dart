import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';

/// Email delivery cadence. `immediate` keeps the legacy behavior (one
/// email per event); `hourly` / `daily` route eligible emails through
/// `email_notification_queue` for the digest runner to roll up.
enum EmailDigestMode { immediate, hourly, daily }

EmailDigestMode _digestModeFromString(String? raw) {
  switch (raw) {
    case 'hourly':
      return EmailDigestMode.hourly;
    case 'daily':
      return EmailDigestMode.daily;
    case 'immediate':
    case null:
    case '':
    default:
      return EmailDigestMode.immediate;
  }
}

String _digestModeToString(EmailDigestMode mode) {
  switch (mode) {
    case EmailDigestMode.hourly:
      return 'hourly';
    case EmailDigestMode.daily:
      return 'daily';
    case EmailDigestMode.immediate:
      return 'immediate';
  }
}

class NotificationPreferences {
  final bool taskAssignmentsEmail;
  final bool taskAssignmentsPush;
  final bool taskCompletionsEmail;
  final bool taskCompletionsPush;
  final bool projectUpdatesEmail;
  final bool projectUpdatesPush;
  final bool mentionsEmail;
  final bool mentionsPush;
  final bool messagesPush;
  final EmailDigestMode digestMode;

  const NotificationPreferences({
    this.taskAssignmentsEmail = true,
    this.taskAssignmentsPush = true,
    this.taskCompletionsEmail = true,
    this.taskCompletionsPush = true,
    this.projectUpdatesEmail = true,
    this.projectUpdatesPush = true,
    this.mentionsEmail = true,
    this.mentionsPush = true,
    this.messagesPush = true,
    this.digestMode = EmailDigestMode.immediate,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NotificationPreferences();
    return NotificationPreferences(
      taskAssignmentsEmail: json['taskAssignmentsEmail'] as bool? ?? true,
      taskAssignmentsPush: json['taskAssignmentsPush'] as bool? ?? true,
      taskCompletionsEmail: json['taskCompletionsEmail'] as bool? ?? true,
      taskCompletionsPush: json['taskCompletionsPush'] as bool? ?? true,
      projectUpdatesEmail: json['projectUpdatesEmail'] as bool? ?? true,
      projectUpdatesPush: json['projectUpdatesPush'] as bool? ?? true,
      mentionsEmail: json['mentionsEmail'] as bool? ?? true,
      mentionsPush: json['mentionsPush'] as bool? ?? true,
      messagesPush: json['messagesPush'] as bool? ?? true,
      digestMode: _digestModeFromString(json['digestMode'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskAssignmentsEmail': taskAssignmentsEmail,
      'taskAssignmentsPush': taskAssignmentsPush,
      'taskCompletionsEmail': taskCompletionsEmail,
      'taskCompletionsPush': taskCompletionsPush,
      'projectUpdatesEmail': projectUpdatesEmail,
      'projectUpdatesPush': projectUpdatesPush,
      'mentionsEmail': mentionsEmail,
      'mentionsPush': mentionsPush,
      'messagesPush': messagesPush,
      'digestMode': _digestModeToString(digestMode),
    };
  }

  NotificationPreferences copyWith({
    bool? taskAssignmentsEmail,
    bool? taskAssignmentsPush,
    bool? taskCompletionsEmail,
    bool? taskCompletionsPush,
    bool? projectUpdatesEmail,
    bool? projectUpdatesPush,
    bool? mentionsEmail,
    bool? mentionsPush,
    bool? messagesPush,
    EmailDigestMode? digestMode,
  }) {
    return NotificationPreferences(
      taskAssignmentsEmail: taskAssignmentsEmail ?? this.taskAssignmentsEmail,
      taskAssignmentsPush: taskAssignmentsPush ?? this.taskAssignmentsPush,
      taskCompletionsEmail: taskCompletionsEmail ?? this.taskCompletionsEmail,
      taskCompletionsPush: taskCompletionsPush ?? this.taskCompletionsPush,
      projectUpdatesEmail: projectUpdatesEmail ?? this.projectUpdatesEmail,
      projectUpdatesPush: projectUpdatesPush ?? this.projectUpdatesPush,
      mentionsEmail: mentionsEmail ?? this.mentionsEmail,
      mentionsPush: mentionsPush ?? this.mentionsPush,
      messagesPush: messagesPush ?? this.messagesPush,
      digestMode: digestMode ?? this.digestMode,
    );
  }
}

class AppUser {
  final String id;
  final String email;
  final String workspaceId; // Legacy field, will be removed after migration
  final String? activeWorkspaceId; // Currently selected workspace
  final String? defaultWorkspaceId; // Workspace created during signup
  final String? displayName;
  final UserRole role; // Legacy field, will be removed (moved to workspace_members)
  final DateTime createdAt;
  final DateTime updatedAt;

  // Email verification
  final bool emailVerified;
  final DateTime? emailVerifiedAt;

  // Profile fields
  final String? profilePictureUrl;
  final String? phoneNumber;
  final String? jobTitle;
  final String? bio;
  final String? companyName;
  final String? timezone;
  final NotificationPreferences notificationPreferences;

  // Time tracking fields
  final double? hourlyRate; // Base hourly rate for time tracking and costs

  // Helper to get the effective workspace ID (active or legacy)
  String get currentWorkspaceId => activeWorkspaceId ?? workspaceId;

  AppUser({
    required this.id,
    required this.email,
    required this.workspaceId,
    this.activeWorkspaceId,
    this.defaultWorkspaceId,
    this.displayName,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.emailVerified = false,
    this.emailVerifiedAt,
    this.profilePictureUrl,
    this.phoneNumber,
    this.jobTitle,
    this.bio,
    this.companyName,
    this.timezone,
    NotificationPreferences? notificationPreferences,
    this.hourlyRate,
  }) : notificationPreferences = notificationPreferences ?? const NotificationPreferences();

  factory AppUser.fromJson(Map<String, dynamic> json, String id) {
    return AppUser(
      id: id,
      email: json['email'] as String,
      workspaceId: json['workspaceId'] as String? ?? '',
      activeWorkspaceId: json['activeWorkspaceId'] as String?,
      defaultWorkspaceId: json['defaultWorkspaceId'] as String?,
      displayName: json['displayName'] as String?,
      role: UserRole.fromString(json['role'] as String? ?? 'projectManager'),
      createdAt: _parseTimestamp(json['createdAt']),
      updatedAt: _parseTimestamp(json['updatedAt']),
      emailVerified: json['emailVerified'] as bool? ?? false,
      emailVerifiedAt: json['emailVerifiedAt'] != null
          ? _parseTimestamp(json['emailVerifiedAt'])
          : null,
      profilePictureUrl: json['profilePictureUrl'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      jobTitle: json['jobTitle'] as String?,
      bio: json['bio'] as String?,
      companyName: json['companyName'] as String?,
      timezone: json['timezone'] as String?,
      notificationPreferences: NotificationPreferences.fromJson(
        json['notificationPreferences'] as Map<String, dynamic>?,
      ),
      hourlyRate: (json['hourlyRate'] as num?)?.toDouble(),
    );
  }

  /// Parse timestamp from either Firestore Timestamp, DateTime, or ISO string
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    // Handle fake timestamp with toDate() method
    try {
      return value.toDate();
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'workspaceId': workspaceId,
      'activeWorkspaceId': activeWorkspaceId,
      'defaultWorkspaceId': defaultWorkspaceId,
      'displayName': displayName,
      'role': role.toString(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'emailVerified': emailVerified,
      'emailVerifiedAt': emailVerifiedAt != null
          ? Timestamp.fromDate(emailVerifiedAt!)
          : null,
      'profilePictureUrl': profilePictureUrl,
      'phoneNumber': phoneNumber,
      'jobTitle': jobTitle,
      'bio': bio,
      'companyName': companyName,
      'timezone': timezone,
      'notificationPreferences': notificationPreferences.toJson(),
      'hourlyRate': hourlyRate,
    };
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? workspaceId,
    String? activeWorkspaceId,
    String? defaultWorkspaceId,
    String? displayName,
    UserRole? role,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? emailVerified,
    DateTime? emailVerifiedAt,
    String? profilePictureUrl,
    String? phoneNumber,
    String? jobTitle,
    String? bio,
    String? companyName,
    String? timezone,
    NotificationPreferences? notificationPreferences,
    double? hourlyRate,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      workspaceId: workspaceId ?? this.workspaceId,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      defaultWorkspaceId: defaultWorkspaceId ?? this.defaultWorkspaceId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      emailVerified: emailVerified ?? this.emailVerified,
      emailVerifiedAt: emailVerifiedAt ?? this.emailVerifiedAt,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      jobTitle: jobTitle ?? this.jobTitle,
      bio: bio ?? this.bio,
      companyName: companyName ?? this.companyName,
      timezone: timezone ?? this.timezone,
      notificationPreferences: notificationPreferences ?? this.notificationPreferences,
      hourlyRate: hourlyRate ?? this.hourlyRate,
    );
  }

  // Helper method to get user initials for avatar
  String getInitials() {
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return displayName![0].toUpperCase();
    }
    // Fallback to email
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return '?';
  }
}
