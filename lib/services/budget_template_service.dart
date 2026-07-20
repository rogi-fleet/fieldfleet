import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/budget_template.dart';
import '../models/budget_item.dart';
import 'service_locator.dart';

class BudgetTemplateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  dynamic get _budgetService => ServiceLocator.budgetService;
  final _uuid = const Uuid();

  /// Get all budget templates for a workspace
  Stream<List<BudgetTemplate>> getTemplates(String workspaceId) {
    return _firestore
        .collection('budget_templates')
        .where('workspaceId', isEqualTo: workspaceId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => BudgetTemplate.fromJson(doc.data(), doc.id))
              .toList();
        });
  }

  /// Get a single budget template
  Future<BudgetTemplate?> getTemplate(String templateId) async {
    try {
      final doc = await _firestore
          .collection('budget_templates')
          .doc(templateId)
          .get();

      if (!doc.exists) return null;

      return BudgetTemplate.fromJson(doc.data()!, doc.id);
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
      final template = BudgetTemplate(
        id: _uuid.v4(),
        workspaceId: workspaceId,
        name: name,
        description: description,
        items: templateItems,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );

      await _firestore
          .collection('budget_templates')
          .doc(template.id)
          .set(template.toJson());

      return template;
    } catch (e) {
      throw Exception('Error creating template from budget: $e');
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

      // Create mapping from template temp IDs to new Firestore IDs
      final Map<String, String> idMapping = {};
      for (final templateItem in template.items) {
        idMapping[templateItem.tempId] = _uuid.v4();
      }

      // Create budget items from template
      final batch = _firestore.batch();
      final now = Timestamp.now();

      for (final templateItem in template.items) {
        final newId = idMapping[templateItem.tempId]!;
        final newParentId = templateItem.parentTempId != null
            ? idMapping[templateItem.parentTempId]
            : null;

        final budgetItem = BudgetItem(
          id: newId,
          workspaceId: workspaceId,
          projectId: projectId,
          parentId: newParentId,
          hierarchyLevel: templateItem.hierarchyLevel,
          sortOrder: templateItem.sortOrder,
          name: templateItem.name,
          description: templateItem.description,
          categoryId: templateItem.categoryId,
          approvedPrice: templateItem.approvedPrice,
          projectedCost: templateItem.projectedCost,
          finalCost: 0.0,
          isComplete: false,
          completedDate: null,
          itemType: templateItem.itemType,
          createdAt: now.toDate(),
          updatedAt: now.toDate(),
          notes: null,
        );

        batch.set(
          _firestore.collection('budget_items').doc(newId),
          budgetItem.toJson(),
        );
      }

      await batch.commit();
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
      final updates = <String, dynamic>{'updatedAt': Timestamp.now()};

      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;

      await _firestore
          .collection('budget_templates')
          .doc(templateId)
          .update(updates);
    } catch (e) {
      throw Exception('Error updating template: $e');
    }
  }

  /// Delete a budget template
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _firestore.collection('budget_templates').doc(templateId).delete();
    } catch (e) {
      throw Exception('Error deleting template: $e');
    }
  }
}
