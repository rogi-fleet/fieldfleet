import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/budget_template.dart';
import '../../models/budget_item.dart';
import 'budget_service.dart';

/// Supabase implementation of BudgetTemplateService
class SupabaseBudgetTemplateService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _budgetService = SupabaseBudgetService();
  final _uuid = const Uuid();

  /// Get all budget templates for a workspace
  Stream<List<BudgetTemplate>> getTemplates(String workspaceId) {
    return _supabase
        .from('budget_templates')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .map((data) {
          return data.map((row) => _toBudgetTemplate(row)).toList();
        });
  }

  /// Get a single budget template
  Future<BudgetTemplate?> getTemplate(String templateId) async {
    try {
      final response = await _supabase
          .from('budget_templates')
          .select()
          .eq('id', templateId)
          .maybeSingle();

      if (response == null) return null;
      return _toBudgetTemplate(response);
    } catch (e) {
      throw Exception('Error getting template: $e');
    }
  }

  /// Create a budget template from existing budget items
  Future<BudgetTemplate> createTemplateFromBudget({
    required String projectId,
    required String workspaceId,
    required String name,
    String? description,
    required String createdBy,
  }) async {
    try {
      // Get all budget items for the project
      final budgetItems = await _budgetService
          .getBudgetItems(projectId, workspaceId: workspaceId)
          .first;

      if (budgetItems.isEmpty) {
        throw Exception('No budget items found to create template');
      }

      // Create temp ID mapping (old ID -> new temp ID)
      final Map<String, String> idMapping = {};
      for (final item in budgetItems) {
        idMapping[item.id] = _uuid.v4();
      }

      // Convert budget items to template items
      final templateItems = budgetItems.map((item) {
        return BudgetTemplateItem(
          tempId: idMapping[item.id]!,
          parentTempId: item.parentId != null ? idMapping[item.parentId] : null,
          hierarchyLevel: item.hierarchyLevel,
          sortOrder: item.sortOrder,
          itemType: item.itemType,
          name: item.name,
          description: item.description,
          categoryId: item.categoryId,
          approvedPrice: item.approvedPrice,
          projectedCost: item.projectedCost,
        );
      }).toList();

      final now = DateTime.now();
      final templateId = _uuid.v4();

      final templateData = {
        'id': templateId,
        'workspace_id': workspaceId,
        'name': name,
        'description': description,
        'items': templateItems
            .map(
              (item) => {
                'temp_id': item.tempId,
                'parent_temp_id': item.parentTempId,
                'hierarchy_level': item.hierarchyLevel,
                'sort_order': item.sortOrder,
                'item_type': item.itemType.name,
                'name': item.name,
                'description': item.description,
                'category_id': item.categoryId,
                'approved_price': item.approvedPrice,
                'projected_cost': item.projectedCost,
              },
            )
            .toList(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'created_by': createdBy,
      };

      await _supabase.from('budget_templates').insert(templateData);

      return BudgetTemplate(
        id: templateId,
        workspaceId: workspaceId,
        name: name,
        description: description,
        items: templateItems,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );
    } catch (e) {
      throw Exception('Error creating template from budget: $e');
    }
  }

  /// Create a budget template from a list of budget items (e.g. a single item or a group + descendants)
  Future<BudgetTemplate> createTemplateFromItems({
    required List<BudgetItem> items,
    required String workspaceId,
    required String name,
    String? description,
    required String createdBy,
  }) async {
    try {
      if (items.isEmpty) {
        throw Exception('No items provided to create template');
      }

      final Map<String, String> idMapping = {};
      for (final item in items) {
        idMapping[item.id] = _uuid.v4();
      }

      final templateItems = items.map((item) {
        return BudgetTemplateItem(
          tempId: idMapping[item.id]!,
          parentTempId: item.parentId != null ? idMapping[item.parentId] : null,
          hierarchyLevel: item.hierarchyLevel,
          sortOrder: item.sortOrder,
          itemType: item.itemType,
          name: item.name,
          description: item.description,
          categoryId: item.categoryId,
          approvedPrice: item.approvedPrice,
          projectedCost: item.projectedCost,
        );
      }).toList();

      final now = DateTime.now();
      final templateId = _uuid.v4();

      final templateData = {
        'id': templateId,
        'workspace_id': workspaceId,
        'name': name,
        'description': description,
        'items': templateItems
            .map(
              (item) => {
                'temp_id': item.tempId,
                'parent_temp_id': item.parentTempId,
                'hierarchy_level': item.hierarchyLevel,
                'sort_order': item.sortOrder,
                'item_type': item.itemType.name,
                'name': item.name,
                'description': item.description,
                'category_id': item.categoryId,
                'approved_price': item.approvedPrice,
                'projected_cost': item.projectedCost,
              },
            )
            .toList(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'created_by': createdBy,
      };

      await _supabase.from('budget_templates').insert(templateData);

      return BudgetTemplate(
        id: templateId,
        workspaceId: workspaceId,
        name: name,
        description: description,
        items: templateItems,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );
    } catch (e) {
      throw Exception('Error creating template from items: $e');
    }
  }

  /// Create budget items from a template
  Future<void> applyTemplateToProject({
    required String templateId,
    required String projectId,
    required String workspaceId,
  }) async {
    try {
      final template = await getTemplate(templateId);
      if (template == null) {
        throw Exception('Template not found');
      }

      // Create mapping from template temp IDs to new IDs
      final Map<String, String> idMapping = {};
      for (final templateItem in template.items) {
        idMapping[templateItem.tempId] = _uuid.v4();
      }

      final now = DateTime.now();

      // Create budget items from template
      for (final templateItem in template.items) {
        final newId = idMapping[templateItem.tempId]!;
        final newParentId = templateItem.parentTempId != null
            ? idMapping[templateItem.parentTempId]
            : null;

        final budgetItemData = {
          'id': newId,
          'workspace_id': workspaceId,
          'project_id': projectId,
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
          'completed_date': null,
          'item_type': templateItem.itemType.name,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'notes': null,
        };

        await _supabase.from('budget_items').insert(budgetItemData);
      }
    } catch (e) {
      throw Exception('Error applying template to project: $e');
    }
  }

  /// Update an existing template
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
          .from('budget_templates')
          .update(updates)
          .eq('id', templateId);
    } catch (e) {
      throw Exception('Error updating template: $e');
    }
  }

  /// Delete a budget template
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _supabase.from('budget_templates').delete().eq('id', templateId);
    } catch (e) {
      throw Exception('Error deleting template: $e');
    }
  }

  /// Convert database row to BudgetTemplate
  BudgetTemplate _toBudgetTemplate(Map<String, dynamic> row) {
    final itemsList =
        (row['items'] as List?)?.map((item) {
          final itemMap = Map<String, dynamic>.from(item);
          return BudgetTemplateItem(
            tempId: itemMap['temp_id'] ?? itemMap['tempId'] ?? '',
            parentTempId: itemMap['parent_temp_id'] ?? itemMap['parentTempId'],
            hierarchyLevel:
                itemMap['hierarchy_level'] ?? itemMap['hierarchyLevel'] ?? 0,
            sortOrder: itemMap['sort_order'] ?? itemMap['sortOrder'] ?? 0,
            itemType: (itemMap['item_type'] ?? itemMap['itemType']) != null
                ? BudgetItemType.values.firstWhere(
                    (value) =>
                        value.name ==
                        (itemMap['item_type'] ?? itemMap['itemType']),
                    orElse: () =>
                        (itemMap['hierarchy_level'] ??
                                itemMap['hierarchyLevel'] ??
                                0) <
                            2
                        ? BudgetItemType.group
                        : BudgetItemType.item,
                  )
                : (itemMap['hierarchy_level'] ??
                          itemMap['hierarchyLevel'] ??
                          0) <
                      2
                ? BudgetItemType.group
                : BudgetItemType.item,
            name: itemMap['name'] ?? '',
            description: itemMap['description'],
            categoryId: itemMap['category_id'] ?? itemMap['categoryId'],
            approvedPrice:
                (itemMap['approved_price'] ?? itemMap['approvedPrice'] as num?)
                    ?.toDouble() ??
                0.0,
            projectedCost:
                (itemMap['projected_cost'] ?? itemMap['projectedCost'] as num?)
                    ?.toDouble() ??
                0.0,
          );
        }).toList() ??
        [];

    return BudgetTemplate(
      id: row['id'],
      workspaceId: row['workspace_id'],
      name: row['name'] ?? '',
      description: row['description'],
      items: itemsList,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
      createdBy: row['created_by'],
    );
  }
}
