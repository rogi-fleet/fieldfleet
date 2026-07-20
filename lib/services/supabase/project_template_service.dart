import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/project_template.dart';
import '../../utils/app_logger.dart';

/// Supabase implementation of ProjectTemplateService
class SupabaseProjectTemplateService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  /// Get all project templates for a workspace
  Stream<List<ProjectTemplate>> getTemplates(String workspaceId) {
    return _supabase
        .from('project_templates')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .map((data) {
          return data.map((row) => _toProjectTemplate(row)).toList();
        });
  }

  /// Get a single project template
  Future<ProjectTemplate?> getTemplate(String templateId) async {
    try {
      final response = await _supabase
          .from('project_templates')
          .select()
          .eq('id', templateId)
          .maybeSingle();

      if (response == null) return null;
      return _toProjectTemplate(response);
    } catch (e) {
      throw Exception('Error getting project template: $e');
    }
  }

  /// Create a project template from an existing project.
  ///
  /// Snapshots project settings, and optionally tasks and budget items.
  Future<ProjectTemplate> createTemplateFromProject({
    required String projectId,
    required String workspaceId,
    required String name,
    String? description,
    required String createdBy,
    bool includeTasks = true,
    bool includeBudgetItems = true,
  }) async {
    try {
      // Fetch the source project
      final projectResponse = await _supabase
          .from('projects')
          .select()
          .eq('id', projectId)
          .single();

      // Build settings snapshot
      final settings = ProjectTemplateSettings(
        jobType: projectResponse['job_type'] as String?,
        priceType: projectResponse['price_type'] as String?,
        materialMarkupPercent:
            (projectResponse['material_markup_percent'] as num?)?.toDouble(),
        laborMarkupPercent:
            (projectResponse['labor_markup_percent'] as num?)?.toDouble(),
        estimatedBudget:
            (projectResponse['estimated_budget'] as num?)?.toDouble(),
        contractAmount:
            (projectResponse['contract_amount'] as num?)?.toDouble(),
        costPlusType: projectResponse['cost_plus_type'] as String?,
        costPlusValue:
            (projectResponse['cost_plus_value'] as num?)?.toDouble(),
        description: projectResponse['description'] as String?,
      );

      // Snapshot tasks
      List<ProjectTemplateTask> templateTasks = [];
      if (includeTasks) {
        final tasksResponse = await _supabase
            .from('tasks')
            .select()
            .eq('project_id', projectId)
            .order('sort_order', ascending: true);

        final Map<String, String> taskIdMapping = {};
        for (final task in tasksResponse) {
          taskIdMapping[task['id'] as String] = _uuid.v4();
        }

        templateTasks = tasksResponse.map<ProjectTemplateTask>((task) {
          final originalId = task['id'] as String;
          final originalParentId = task['parent_id'] as String?;
          return ProjectTemplateTask(
            tempId: taskIdMapping[originalId]!,
            parentTempId:
                originalParentId != null ? taskIdMapping[originalParentId] : null,
            title: task['title'] as String? ?? '',
            description: task['description'] as String?,
            sortOrder: (task['sort_order'] as num?)?.toInt() ?? 0,
            groupName: task['group_name'] as String?,
            groupColor: task['group_color'] != null
                ? task['group_color'].toString()
                : null,
          );
        }).toList();
      }

      // Snapshot budget items
      List<ProjectTemplateBudgetItem> templateBudgetItems = [];
      if (includeBudgetItems) {
        final budgetResponse = await _supabase
            .from('budget_items')
            .select()
            .eq('project_id', projectId)
            .order('sort_order', ascending: true);

        final Map<String, String> budgetIdMapping = {};
        for (final item in budgetResponse) {
          budgetIdMapping[item['id'] as String] = _uuid.v4();
        }

        templateBudgetItems =
            budgetResponse.map<ProjectTemplateBudgetItem>((item) {
          final originalId = item['id'] as String;
          final originalParentId = item['parent_id'] as String?;
          return ProjectTemplateBudgetItem(
            tempId: budgetIdMapping[originalId]!,
            parentTempId: originalParentId != null
                ? budgetIdMapping[originalParentId]
                : null,
            hierarchyLevel: (item['hierarchy_level'] as num?)?.toInt() ?? 0,
            sortOrder: (item['sort_order'] as num?)?.toInt() ?? 0,
            name: item['name'] as String? ?? '',
            description: item['description'] as String?,
            categoryId: item['category_id'] as String?,
            approvedPrice: (item['approved_price'] as num?)?.toDouble() ?? 0.0,
            projectedCost: (item['projected_cost'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList();
      }

      final now = DateTime.now();
      final templateId = _uuid.v4();

      final templateData = {
        'id': templateId,
        'workspace_id': workspaceId,
        'name': name,
        'description': description,
        'project_settings': settings.toJson(),
        'tasks': templateTasks.map((t) => t.toJson()).toList(),
        'budget_items': templateBudgetItems.map((b) => b.toJson()).toList(),
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      await _supabase.from('project_templates').insert(templateData);

      AppLogger.info('Project template created', metadata: {
        'templateId': templateId,
        'name': name,
        'taskCount': templateTasks.length,
        'budgetItemCount': templateBudgetItems.length,
      });

      return ProjectTemplate(
        id: templateId,
        workspaceId: workspaceId,
        name: name,
        description: description,
        settings: settings,
        tasks: templateTasks,
        budgetItems: templateBudgetItems,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      AppLogger.error('Failed to create project template', error: e);
      throw Exception('Error creating project template: $e');
    }
  }

  /// Create a new project from a template.
  ///
  /// Returns the ID of the newly created project.
  Future<String> createProjectFromTemplate({
    required String templateId,
    required String workspaceId,
    required String projectName,
    required String projectAddress,
  }) async {
    try {
      final template = await getTemplate(templateId);
      if (template == null) {
        throw Exception('Template not found');
      }

      final now = DateTime.now();
      final settings = template.settings;

      // Build the project data from template settings
      final projectData = {
        'workspace_id': workspaceId,
        'name': projectName,
        'address': projectAddress,
        'status': 'active',
        'job_type': settings.jobType,
        'price_type': settings.priceType ?? 'time_and_material',
        'material_markup_percent': settings.materialMarkupPercent ?? 20.0,
        'labor_markup_percent': settings.laborMarkupPercent ?? 30.0,
        'estimated_budget': settings.estimatedBudget,
        'contract_amount': settings.contractAmount,
        'cost_plus_type': settings.costPlusType,
        'cost_plus_value': settings.costPlusValue,
        'description': settings.description,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final projectResponse = await _supabase
          .from('projects')
          .insert(projectData)
          .select()
          .single();

      final newProjectId = projectResponse['id'] as String;

      // Create tasks from template
      if (template.tasks.isNotEmpty) {
        final Map<String, String> taskIdMapping = {};
        for (final templateTask in template.tasks) {
          taskIdMapping[templateTask.tempId] = _uuid.v4();
        }

        for (final templateTask in template.tasks) {
          final newTaskId = taskIdMapping[templateTask.tempId]!;
          final newParentId = templateTask.parentTempId != null
              ? taskIdMapping[templateTask.parentTempId]
              : null;

          final taskData = {
            'id': newTaskId,
            'workspace_id': workspaceId,
            'project_id': newProjectId,
            'title': templateTask.title,
            'description': templateTask.description,
            'sort_order': templateTask.sortOrder,
            'parent_id': newParentId,
            'group_name': templateTask.groupName,
            'group_color': templateTask.groupColor != null
                ? int.tryParse(templateTask.groupColor!)
                : null,
            'status': 'not_started',
            'priority': 'medium',
            'is_complete': false,
            'progress': 0,
            'task_type': 'standard',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          };

          await _supabase.from('tasks').insert(taskData);
        }
      }

      // Create budget items from template
      if (template.budgetItems.isNotEmpty) {
        final Map<String, String> budgetIdMapping = {};
        for (final templateItem in template.budgetItems) {
          budgetIdMapping[templateItem.tempId] = _uuid.v4();
        }

        for (final templateItem in template.budgetItems) {
          final newId = budgetIdMapping[templateItem.tempId]!;
          final newParentId = templateItem.parentTempId != null
              ? budgetIdMapping[templateItem.parentTempId]
              : null;

          final budgetItemData = {
            'id': newId,
            'workspace_id': workspaceId,
            'project_id': newProjectId,
            'parent_id': newParentId,
            'hierarchy_level': templateItem.hierarchyLevel,
            'sort_order': templateItem.sortOrder,
            'name': templateItem.name,
            'description': templateItem.description,
            'category_id': templateItem.categoryId,
            'approved_price': templateItem.approvedPrice,
            'projected_cost': templateItem.projectedCost,
            'final_cost': 0.0,
            'is_complete': false,
            'item_type': templateItem.hierarchyLevel < 2 ? 'group' : 'item',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          };

          await _supabase.from('budget_items').insert(budgetItemData);
        }
      }

      AppLogger.info('Project created from template', metadata: {
        'projectId': newProjectId,
        'templateId': templateId,
      });

      return newProjectId;
    } catch (e) {
      AppLogger.error('Failed to create project from template', error: e);
      throw Exception('Error creating project from template: $e');
    }
  }

  /// Update an existing template metadata
  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? description,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;

      await _supabase
          .from('project_templates')
          .update(updates)
          .eq('id', templateId);
    } catch (e) {
      throw Exception('Error updating project template: $e');
    }
  }

  /// Delete a project template
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _supabase
          .from('project_templates')
          .delete()
          .eq('id', templateId);
    } catch (e) {
      throw Exception('Error deleting project template: $e');
    }
  }

  /// Convert database row to ProjectTemplate
  ProjectTemplate _toProjectTemplate(Map<String, dynamic> row) {
    final settingsJson = row['project_settings'] as Map<String, dynamic>? ?? {};
    final tasksJson = row['tasks'] as List? ?? [];
    final budgetItemsJson = row['budget_items'] as List? ?? [];

    return ProjectTemplate(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: row['name'] as String? ?? '',
      description: row['description'] as String?,
      settings: ProjectTemplateSettings.fromJson(settingsJson),
      tasks: tasksJson
          .map((t) =>
              ProjectTemplateTask.fromJson(Map<String, dynamic>.from(t)))
          .toList(),
      budgetItems: budgetItemsJson
          .map((b) => ProjectTemplateBudgetItem.fromJson(
              Map<String, dynamic>.from(b)))
          .toList(),
      createdBy: row['created_by'] as String? ?? '',
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
    );
  }
}
