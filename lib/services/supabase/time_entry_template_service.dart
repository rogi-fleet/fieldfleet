import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/time_entry_template.dart';
import '../../utils/app_logger.dart';

class SupabaseTimeEntryTemplateService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<List<TimeEntryTemplate>> getTemplates({
    required String workspaceId,
    required String userId,
  }) {
    return _supabase
        .from('time_entry_templates')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .map((data) {
      final templates = data
          .map((row) => TimeEntryTemplate.fromJson(_toFirestoreFormat(row), row['id']))
          .where((template) => template.userId == null || template.userId == userId)
          .toList();
      return templates;
    });
  }

  Future<TimeEntryTemplate> createTemplate({
    required String workspaceId,
    required String name,
    required String projectId,
    required String taskId,
    required String userId,
    bool shared = false,
    double defaultHours = 0,
    int defaultBreakMinutes = 0,
    String? notesTemplate,
  }) async {
    try {
      final now = DateTime.now();
      final response = await _supabase
          .from('time_entry_templates')
          .insert({
            'workspace_id': workspaceId,
            'user_id': shared ? null : userId,
            'name': name,
            'project_id': projectId,
            'task_id': taskId,
            'default_hours': defaultHours,
            'default_break_minutes': defaultBreakMinutes,
            'notes_template': notesTemplate,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
          .select()
          .single();

      return TimeEntryTemplate.fromJson(_toFirestoreFormat(response), response['id']);
    } catch (e) {
      AppLogger.error('Failed to create time entry template', error: e);
      rethrow;
    }
  }

  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? projectId,
    String? taskId,
    double? defaultHours,
    int? defaultBreakMinutes,
    String? notesTemplate,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (name != null) updates['name'] = name;
      if (projectId != null) updates['project_id'] = projectId;
      if (taskId != null) updates['task_id'] = taskId;
      if (defaultHours != null) updates['default_hours'] = defaultHours;
      if (defaultBreakMinutes != null) updates['default_break_minutes'] = defaultBreakMinutes;
      if (notesTemplate != null) updates['notes_template'] = notesTemplate;

      await _supabase.from('time_entry_templates').update(updates).eq('id', templateId);
    } catch (e) {
      AppLogger.error('Failed to update time entry template', error: e);
      rethrow;
    }
  }

  Future<void> deleteTemplate(String templateId) async {
    try {
      await _supabase.from('time_entry_templates').delete().eq('id', templateId);
    } catch (e) {
      AppLogger.error('Failed to delete time entry template', error: e);
      rethrow;
    }
  }

  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'userId': row['user_id'],
      'name': row['name'],
      'projectId': row['project_id'],
      'taskId': row['task_id'],
      'defaultHours': (row['default_hours'] as num?)?.toDouble() ?? 0,
      'defaultBreakMinutes': row['default_break_minutes'] as int? ?? 0,
      'notesTemplate': row['notes_template'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
    };
  }
}
