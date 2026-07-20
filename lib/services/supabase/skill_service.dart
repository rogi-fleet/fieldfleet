import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../models/skill.dart';
import '../../theme/theme.dart';

/// Supabase implementation of SkillService
class SupabaseSkillService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all skills for a workspace as a stream
  Stream<List<Skill>> getSkills(String workspaceId) {
    return _supabase
        .from('skills')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('name')
        .map((data) {
          return data.map((row) => _toSkill(row)).toList();
        });
  }

  /// Get a single skill by ID
  Future<Skill?> getSkill(String skillId) async {
    final response = await _supabase
        .from('skills')
        .select()
        .eq('id', skillId)
        .maybeSingle();

    if (response == null) return null;
    return _toSkill(response);
  }

  /// Create a new skill
  Future<Skill> createSkill({
    required String workspaceId,
    required String name,
    String? description,
    Color color = AppColors.info,
  }) async {
    final now = DateTime.now();
    final response = await _withOptionalColorRetry((includeColor) async {
      final payload = <String, dynamic>{
        'workspace_id': workspaceId,
        'name': name,
        'description': description,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      if (includeColor) {
        payload['color'] = color.toARGB32();
      }

      return _supabase.from('skills').insert(payload).select().single();
    });

    return _toSkill(response);
  }

  /// Update an existing skill
  Future<void> updateSkill({
    required String skillId,
    String? name,
    String? description,
    Color? color,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;

    await _withOptionalColorRetry((includeColor) async {
      final payload = Map<String, dynamic>.from(updates);
      if (includeColor && color != null) {
        payload['color'] = color.toARGB32();
      }
      await _supabase.from('skills').update(payload).eq('id', skillId);
    });
  }

  /// Delete a skill and remove it from all members and tasks
  Future<void> deleteSkill(String skillId, String workspaceId) async {
    // Remove skill from workspace members. workspace_members has a composite
    // primary key (workspace_id, user_id) — there is no `id` column.
    final members = await _supabase
        .from('workspace_members')
        .select('user_id, skill_ids')
        .eq('workspace_id', workspaceId);

    for (final member in members) {
      final skillIds = List<String>.from(member['skill_ids'] ?? []);
      if (skillIds.contains(skillId)) {
        skillIds.remove(skillId);
        await _supabase
            .from('workspace_members')
            .update({'skill_ids': skillIds})
            .eq('workspace_id', workspaceId)
            .eq('user_id', member['user_id']);
      }
    }

    // Remove skill from tasks
    final tasks = await _supabase
        .from('tasks')
        .select('id, required_skill_ids')
        .eq('workspace_id', workspaceId);

    for (final task in tasks) {
      final skillIds = List<String>.from(task['required_skill_ids'] ?? []);
      if (skillIds.contains(skillId)) {
        skillIds.remove(skillId);
        await _supabase
            .from('tasks')
            .update({'required_skill_ids': skillIds})
            .eq('id', task['id']);
      }
    }

    // Delete the skill itself
    await _supabase.from('skills').delete().eq('id', skillId);
  }

  /// Get usage stats for a skill
  Future<Map<String, int>> getSkillUsage(
    String skillId,
    String workspaceId,
  ) async {
    // Count members with this skill. workspace_members has a composite
    // primary key (workspace_id, user_id) — selecting `id` would 400.
    final members = await _supabase
        .from('workspace_members')
        .select('user_id')
        .eq('workspace_id', workspaceId)
        .contains('skill_ids', [skillId]);

    // Count tasks requiring this skill
    final tasks = await _supabase
        .from('tasks')
        .select('id')
        .eq('workspace_id', workspaceId)
        .contains('required_skill_ids', [skillId]);

    return {'members': members.length, 'tasks': tasks.length};
  }

  /// Seed default skills for a new workspace
  Future<void> seedDefaultSkills(String workspaceId) async {
    final now = DateTime.now();
    final existingSkills = await _supabase
        .from('skills')
        .select('name')
        .eq('workspace_id', workspaceId);
    final existingNames = existingSkills
        .map((row) => _normalizeSkillName(row['name'] as String?))
        .whereType<String>()
        .toSet();

    final skillsToInsert = Skill.defaultSkills.where((skill) {
      final skillName = _normalizeSkillName(skill['name'] as String?);
      return skillName != null && !existingNames.contains(skillName);
    }).toList();

    if (skillsToInsert.isEmpty) {
      return;
    }

    await _withOptionalColorRetry((includeColor) async {
      final payload = skillsToInsert.map((skill) {
        final row = <String, dynamic>{
          'workspace_id': workspaceId,
          'name': skill['name'],
          'description': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };
        if (includeColor) {
          row['color'] = skill['color'];
        }
        return row;
      }).toList();

      await _supabase.from('skills').insert(payload);
    });
  }

  /// Convert database row to Skill
  Skill _toSkill(Map<String, dynamic> row) {
    return Skill(
      id: row['id'],
      workspaceId: row['workspace_id'],
      name: row['name'],
      description: row['description'],
      color: _parseColor(row),
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
    );
  }

  Color _parseColor(Map<String, dynamic> row) {
    final rawColor = row['color'];
    if (rawColor is int) {
      return Color(rawColor);
    }
    if (rawColor is num) {
      return Color(rawColor.toInt());
    }
    return Skill.fallbackColorForName(row['name'] as String?);
  }

  String? _normalizeSkillName(String? name) {
    final normalized = name?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<T> _withOptionalColorRetry<T>(
    Future<T> Function(bool includeColor) operation,
  ) async {
    try {
      return await operation(true);
    } on PostgrestException catch (error) {
      if (!_isMissingColorColumnError(error)) {
        rethrow;
      }
      return operation(false);
    }
  }

  bool _isMissingColorColumnError(PostgrestException error) {
    final details = [
      error.message,
      error.details,
      error.hint,
      error.code,
    ].whereType<String>().join(' ').toLowerCase();
    return details.contains('color') &&
        (details.contains('column') || details.contains('schema cache'));
  }
}
