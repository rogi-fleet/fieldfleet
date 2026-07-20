import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/budget_task_link.dart';
import '../../models/budget_item_labor_summary.dart';

class SupabaseBudgetTaskLinkService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Link a task to a budget item
  Future<void> linkTaskToBudgetItem({
    required String taskId,
    required String budgetItemId,
    required String workspaceId,
    double allocationPercentage = 100.0,
  }) async {
    try {
      await _supabase.from('task_budget_items').upsert({
        'task_id': taskId,
        'budget_item_id': budgetItemId,
        'workspace_id': workspaceId,
        'allocation_percentage': allocationPercentage,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Error linking task to budget item: $e');
    }
  }

  /// Unlink a task from a budget item
  Future<void> unlinkTaskFromBudgetItem({
    required String taskId,
    required String budgetItemId,
  }) async {
    try {
      await _supabase
          .from('task_budget_items')
          .delete()
          .eq('task_id', taskId)
          .eq('budget_item_id', budgetItemId);
    } catch (e) {
      throw Exception('Error unlinking task from budget item: $e');
    }
  }

  /// Update allocation percentage for a link
  Future<void> updateAllocation({
    required String taskId,
    required String budgetItemId,
    required double allocationPercentage,
  }) async {
    try {
      await _supabase
          .from('task_budget_items')
          .update({'allocation_percentage': allocationPercentage})
          .eq('task_id', taskId)
          .eq('budget_item_id', budgetItemId);
    } catch (e) {
      throw Exception('Error updating allocation: $e');
    }
  }

  /// Bulk replace all budget item links for a task
  Future<void> setTaskBudgetItems(
    String taskId,
    List<BudgetTaskLink> links,
  ) async {
    try {
      // Delete existing links
      await _supabase
          .from('task_budget_items')
          .delete()
          .eq('task_id', taskId);

      // Insert new links
      if (links.isNotEmpty) {
        final rows = links.map((link) => link.toJson()).toList();
        await _supabase.from('task_budget_items').insert(rows);
      }
    } catch (e) {
      throw Exception('Error setting task budget items: $e');
    }
  }

  /// Get budget item IDs linked to a task
  Future<List<String>> getBudgetItemIdsForTask(String taskId) async {
    try {
      final response = await _supabase
          .from('task_budget_items')
          .select('budget_item_id')
          .eq('task_id', taskId);

      return response
          .map<String>((row) => row['budget_item_id'] as String)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting budget item IDs for task: $e');
      }
      return [];
    }
  }

  /// Get task IDs linked to a budget item
  Future<List<String>> getTaskIdsForBudgetItem(String budgetItemId) async {
    try {
      final response = await _supabase
          .from('task_budget_items')
          .select('task_id')
          .eq('budget_item_id', budgetItemId);

      return response
          .map<String>((row) => row['task_id'] as String)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting task IDs for budget item: $e');
      }
      return [];
    }
  }

  /// Get all links for a task
  Future<List<BudgetTaskLink>> getLinksForTask(String taskId) async {
    try {
      final response = await _supabase
          .from('task_budget_items')
          .select()
          .eq('task_id', taskId);

      return response.map((row) => BudgetTaskLink.fromJson(row)).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting links for task: $e');
      }
      return [];
    }
  }

  /// Get labor summaries for all budget items in a project
  Future<Map<String, BudgetItemLaborSummary>> getLaborSummaryForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      // Get budget item IDs for this project
      final budgetItems = await _supabase
          .from('budget_items')
          .select('id')
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);

      final budgetItemIds =
          budgetItems.map<String>((row) => row['id'] as String).toList();

      if (budgetItemIds.isEmpty) return {};

      // Query the labor summary view
      final response = await _supabase
          .from('budget_item_labor_summary')
          .select()
          .inFilter('budget_item_id', budgetItemIds);

      final result = <String, BudgetItemLaborSummary>{};
      for (final row in response) {
        final summary = BudgetItemLaborSummary.fromJson(row);
        result[summary.budgetItemId] = summary;
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting labor summary for project: $e');
      }
      return {};
    }
  }

  /// Stream links for a project (realtime)
  Stream<List<BudgetTaskLink>> streamLinksForProject(
    String workspaceId,
  ) {
    return _supabase
        .from('task_budget_items')
        .stream(primaryKey: ['task_id', 'budget_item_id'])
        .eq('workspace_id', workspaceId)
        .map((data) =>
            data.map((row) => BudgetTaskLink.fromJson(row)).toList());
  }
}
