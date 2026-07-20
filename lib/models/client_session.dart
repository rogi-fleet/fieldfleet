import 'package:cloud_firestore/cloud_firestore.dart';

/// Magic link session for client portal authentication
/// Tokens are single-use and expire after 1 hour
class ClientSession {
  final String id;
  final String email;
  final String token;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final DateTime createdAt;

  ClientSession({
    required this.id,
    required this.email,
    required this.token,
    required this.expiresAt,
    this.usedAt,
    required this.createdAt,
  });

  factory ClientSession.fromJson(Map<String, dynamic> json, String id) {
    return ClientSession(
      id: id,
      email: json['email'] as String,
      token: json['token'] as String,
      expiresAt: (json['expiresAt'] as Timestamp).toDate(),
      usedAt: json['usedAt'] != null
          ? (json['usedAt'] as Timestamp).toDate()
          : null,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'token': token,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'usedAt': usedAt != null ? Timestamp.fromDate(usedAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Check if session is still valid (not expired and not used)
  bool get isValid {
    final now = DateTime.now();
    return usedAt == null && expiresAt.isAfter(now);
  }

  /// Check if session has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Check if session has been used
  bool get isUsed => usedAt != null;
}
