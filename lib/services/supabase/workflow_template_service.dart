import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/workflow_template.dart';

class SupabaseWorkflowTemplateService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<List<WorkflowTemplate>> getTemplates(String workspaceId) {
    return _supabase
        .from('workflow_templates')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .map((rows) => rows.map(WorkflowTemplate.fromSupabase).toList());
  }

  Future<List<WorkflowTemplate>> getTemplatesOnce(String workspaceId) async {
    final rows = await _supabase
        .from('workflow_templates')
        .select()
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false);
    return rows.map(WorkflowTemplate.fromSupabase).toList();
  }

  Future<void> initializeCoreTemplates({
    required String workspaceId,
    required String createdBy,
  }) async {
    await _supabase.rpc(
      'seed_core_workflow_templates',
      params: {'p_workspace_id': workspaceId, 'p_created_by': createdBy},
    );
  }

  Future<WorkflowTemplate> createTemplate({
    required String workspaceId,
    required String name,
    required String slug,
    String? description,
    required String workflowMarkdown,
    Map<String, dynamic> workflowSchema = const {},
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final row = await _supabase
        .from('workflow_templates')
        .insert({
          'workspace_id': workspaceId,
          'name': name,
          'slug': slug,
          'description': description,
          'workflow_markdown': workflowMarkdown,
          'workflow_schema': workflowSchema,
          'is_system': false,
          'created_by': createdBy,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .select()
        .single();

    return WorkflowTemplate.fromSupabase(row);
  }

  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? description,
    String? slug,
    String? workflowMarkdown,
    Map<String, dynamic>? workflowSchema,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (slug != null) updates['slug'] = slug;
    if (workflowMarkdown != null) {
      updates['workflow_markdown'] = workflowMarkdown;
    }
    if (workflowSchema != null) updates['workflow_schema'] = workflowSchema;

    await _supabase
        .from('workflow_templates')
        .update(updates)
        .eq('id', templateId);
  }

  Future<WorkflowTemplate> duplicateTemplate({
    required WorkflowTemplate template,
    required String createdBy,
  }) async {
    return createTemplate(
      workspaceId: template.workspaceId,
      name: '${template.name} (Copy)',
      slug: '${template.slug}-copy-${DateTime.now().millisecondsSinceEpoch}',
      description: template.description,
      workflowMarkdown: template.workflowMarkdown,
      workflowSchema: template.workflowSchema,
      createdBy: createdBy,
    );
  }

  Future<void> deleteTemplate(String templateId) async {
    await _supabase.from('workflow_templates').delete().eq('id', templateId);
  }
}
