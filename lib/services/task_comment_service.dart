import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_comment.dart';

/// Service for managing task comments
class TaskCommentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add a comment to a task
  Future<TaskComment> addComment({
    required String taskId,
    required String content,
    required String senderId,
    required String senderName,
    required String workspaceId,
    List<Map<String, dynamic>> attachments = const [],
    List<String> mentionedUserIds = const [],
  }) async {
    try {
      final now = DateTime.now();
      final commentData = {
        'taskId': taskId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'timestamp': Timestamp.fromDate(now),
        'workspaceId': workspaceId,
        'attachments': attachments,
        'mentionedUserIds': mentionedUserIds,
      };

      final docRef = await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('comments')
          .add(commentData);

      return TaskComment.fromJson(commentData, docRef.id);
    } catch (e) {
      throw Exception('Error adding comment: $e');
    }
  }

  /// Get all comments for a task, ordered by timestamp
  Stream<List<TaskComment>> getComments(String taskId) {
    return _firestore
        .collection('tasks')
        .doc(taskId)
        .collection('comments')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TaskComment.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Delete a comment
  Future<void> deleteComment(String taskId, String commentId) async {
    try {
      await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('comments')
          .doc(commentId)
          .delete();
    } catch (e) {
      throw Exception('Error deleting comment: $e');
    }
  }

  /// Get comment count for a task
  Future<int> getCommentCount(String taskId) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('comments')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get comment counts for many tasks.
  Future<Map<String, int>> getCommentCounts(List<String> taskIds) async {
    if (taskIds.isEmpty) return const <String, int>{};

    final uniqueTaskIds = taskIds.toSet().toList(growable: false);
    final counts = {for (final taskId in uniqueTaskIds) taskId: 0};

    // Firestore whereIn supports up to 10 values per query.
    const batchSize = 10;
    for (var i = 0; i < uniqueTaskIds.length; i += batchSize) {
      final end = (i + batchSize > uniqueTaskIds.length)
          ? uniqueTaskIds.length
          : i + batchSize;
      final chunk = uniqueTaskIds.sublist(i, end);

      try {
        final snapshot = await _firestore
            .collectionGroup('comments')
            .where('taskId', whereIn: chunk)
            .get();

        for (final doc in snapshot.docs) {
          final taskId = doc.data()['taskId'] as String?;
          if (taskId == null) continue;
          counts[taskId] = (counts[taskId] ?? 0) + 1;
        }
      } catch (_) {
        // Keep defaults for failed batches.
      }
    }

    return counts;
  }
}
