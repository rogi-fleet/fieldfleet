import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a client user who accesses the portal via magic link
/// A client user is linked to CustomerContacts by email address
class ClientUser {
  final String id;
  final String email;
  final String? displayName;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  ClientUser({
    required this.id,
    required this.email,
    this.displayName,
    this.lastLoginAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClientUser.fromJson(Map<String, dynamic> json, String id) {
    return ClientUser(
      id: id,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      lastLoginAt: json['lastLoginAt'] != null
          ? (json['lastLoginAt'] as Timestamp).toDate()
          : null,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'displayName': displayName,
      'lastLoginAt':
          lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  ClientUser copyWith({
    String? id,
    String? email,
    String? displayName,
    DateTime? lastLoginAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClientUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
