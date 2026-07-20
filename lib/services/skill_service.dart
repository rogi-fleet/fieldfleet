import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/skill.dart';
import '../theme/theme.dart';

/// Service for managing skills at the workspace level.
class SkillService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _skillsCollection =>
      _firestore.collection('skills');

  /// Get all skills for a workspace as a stream
  Stream<List<Skill>> getSkills(String workspaceId) {
    return _skillsCollection
        .where('workspaceId', isEqualTo: workspaceId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Skill.fromJson(doc.data(), doc.id))
            .toList());
  }

  /// Get a single skill by ID
  Future<Skill?> getSkill(String skillId) async {
    final doc = await _skillsCollection.doc(skillId).get();
    if (!doc.exists) return null;
    return Skill.fromJson(doc.data()!, doc.id);
  }

  /// Create a new skill
  Future<Skill> createSkill({
    required String workspaceId,
    required String name,
    String? description,
    Color color = AppColors.info,
  }) async {
    final now = DateTime.now();
    final docRef = await _skillsCollection.add({
      'workspaceId': workspaceId,
      'name': name,
      'description': description,
      'color': color.value,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });

    return Skill(
      id: docRef.id,
      workspaceId: workspaceId,
      name: name,
      description: description,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Update an existing skill
  Future<void> updateSkill({
    required String skillId,
    String? name,
    String? description,
    Color? color,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (color != null) updates['color'] = color.value;

    await _skillsCollection.doc(skillId).update(updates);
  }

  /// Delete a skill and remove it from all members and tasks
  Future<void> deleteSkill(String skillId, String workspaceId) async {
    final batch = _firestore.batch();

    // Delete the skill itself
    batch.delete(_skillsCollection.doc(skillId));

    // Remove skill from all workspace members
    final membersSnapshot = await _firestore
        .collection('workspace_members')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('skillIds', arrayContains: skillId)
        .get();

    for (final doc in membersSnapshot.docs) {
      batch.update(doc.reference, {
        'skillIds': FieldValue.arrayRemove([skillId]),
      });
    }

    // Remove skill from all tasks in the workspace
    final tasksSnapshot = await _firestore
        .collection('tasks')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('requiredSkillIds', arrayContains: skillId)
        .get();

    for (final doc in tasksSnapshot.docs) {
      batch.update(doc.reference, {
        'requiredSkillIds': FieldValue.arrayRemove([skillId]),
      });
    }

    await batch.commit();
  }

  /// Get usage stats for a skill (how many members and tasks use it)
  Future<Map<String, int>> getSkillUsage(String skillId, String workspaceId) async {
    final membersCount = await _firestore
        .collection('workspace_members')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('skillIds', arrayContains: skillId)
        .count()
        .get();

    final tasksCount = await _firestore
        .collection('tasks')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('requiredSkillIds', arrayContains: skillId)
        .count()
        .get();

    return {
      'members': membersCount.count ?? 0,
      'tasks': tasksCount.count ?? 0,
    };
  }

  /// Seed default skills for a new workspace
  Future<void> seedDefaultSkills(String workspaceId) async {
    final batch = _firestore.batch();
    final now = DateTime.now();

    for (final skill in Skill.defaultSkills) {
      final docRef = _skillsCollection.doc();
      batch.set(docRef, {
        'workspaceId': workspaceId,
        'name': skill['name'],
        'description': null,
        'color': skill['color'],
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    }

    await batch.commit();
  }
}
