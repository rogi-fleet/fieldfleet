import 'package:flutter/material.dart';

class DocumentActivity {
  final String id;
  final String documentId;
  final String action;
  final String? actorEmail;
  final String? actorName;
  final String? actorType;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  DocumentActivity({
    required this.id,
    required this.documentId,
    required this.action,
    this.actorEmail,
    this.actorName,
    this.actorType,
    this.details = const {},
    required this.createdAt,
  });

  factory DocumentActivity.fromRow(Map<String, dynamic> row) {
    return DocumentActivity(
      id: row['id'] as String,
      documentId: row['document_id'] as String,
      action: row['action'] as String,
      actorEmail: row['actor_email'] as String?,
      actorName: row['actor_name'] as String?,
      actorType: row['actor_type'] as String?,
      details: row['details'] is Map
          ? Map<String, dynamic>.from(row['details'] as Map)
          : const {},
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  String get displayTitle {
    final actor = actorName ?? actorEmail ?? 'Someone';
    switch (action) {
      case 'created':
        return 'Document created';
      case 'sent':
        return 'Document sent';
      case 'viewed':
        return 'Document viewed by $actor';
      case 'signed':
        return 'Signed by $actor';
      case 'denied':
        return 'Denied by $actor';
      case 'changes_requested':
        return 'Changes requested by $actor';
      case 'payment_initiated':
        return 'Payment initiated';
      case 'payment_completed':
        return 'Payment completed';
      default:
        return action;
    }
  }

  IconData get displayIcon {
    switch (action) {
      case 'created':
        return Icons.add_circle_outline;
      case 'sent':
        return Icons.send;
      case 'viewed':
        return Icons.visibility;
      case 'signed':
        return Icons.check_circle;
      case 'denied':
        return Icons.cancel;
      case 'changes_requested':
        return Icons.edit_note;
      case 'payment_initiated':
        return Icons.payment;
      case 'payment_completed':
        return Icons.paid;
      default:
        return Icons.info_outline;
    }
  }

  Color get displayColor {
    switch (action) {
      case 'signed':
      case 'payment_completed':
        return Colors.green;
      case 'denied':
        return Colors.red;
      case 'changes_requested':
        return Colors.orange;
      case 'payment_initiated':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
