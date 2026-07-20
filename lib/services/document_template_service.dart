import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/document_template.dart';
import '../models/document_type.dart';
import '../models/template_category.dart';

class DocumentTemplateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all templates for a workspace
  // Fetch all templates for a workspace (one-time)
  Future<List<DocumentTemplate>> getTemplatesOnce(String workspaceId, {DocumentType? type}) async {
    try {
      Query query = _firestore
          .collection('document_templates')
          .where('workspaceId', isEqualTo: workspaceId);

      if (type != null) {
        query = query.where('type', isEqualTo: type.name);
      }

      final snapshot = await query.orderBy('createdAt', descending: true).get();
      return snapshot.docs
          .map((doc) => DocumentTemplate.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Stream<List<DocumentTemplate>> getTemplates(String workspaceId, {DocumentType? type}) {
    Query query = _firestore
        .collection('document_templates')
        .where('workspaceId', isEqualTo: workspaceId);

    if (type != null) {
      query = query.where('type', isEqualTo: type.name);
    }

    return query.orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => DocumentTemplate.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  // Get templates grouped by category
  Stream<Map<TemplateCategory, List<DocumentTemplate>>> getTemplatesByCategory(String workspaceId) {
    return getTemplates(workspaceId).map((templates) {
      final grouped = <TemplateCategory, List<DocumentTemplate>>{};
      
      // Initialize all categories with empty lists
      for (final category in TemplateCategory.values) {
        grouped[category] = [];
      }
      
      // Group templates by category
      for (final template in templates) {
        grouped[template.category]!.add(template);
      }
      
      return grouped;
    });
  }

  // Get a single template
  Future<DocumentTemplate?> getTemplate(String templateId) async {
    try {
      final doc = await _firestore.collection('document_templates').doc(templateId).get();
      if (doc.exists) {
        return DocumentTemplate.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw Exception('Error fetching template: $e');
    }
  }

  // Get default template for a document type
  Future<DocumentTemplate?> getDefaultTemplate(String workspaceId, DocumentType type) async {
    try {
      final snapshot = await _firestore
          .collection('document_templates')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('type', isEqualTo: type.name)
          .where('isDefault', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return DocumentTemplate.fromJson(snapshot.docs.first.data(), snapshot.docs.first.id);
      }
      return null;
    } catch (e) {
      throw Exception('Error fetching default template: $e');
    }
  }

  // Create a new template
  Future<DocumentTemplate> createTemplate({
    required String workspaceId,
    required String name,
    required DocumentType type,
    required String markdownContent,
    bool isDefault = false,
    required String createdBy,
  }) async {
    try {
      final now = DateTime.now();

      // If setting as default, unset other defaults of this type
      if (isDefault) {
        await _unsetDefaultsForType(workspaceId, type);
      }

      final template = DocumentTemplate(
        id: '',
        workspaceId: workspaceId,
        name: name,
        type: type,
        markdownContent: markdownContent,
        isDefault: isDefault,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
      );

      final docRef = await _firestore.collection('document_templates').add(template.toJson());

      return template.copyWith(id: docRef.id);
    } catch (e) {
      throw Exception('Error creating template: $e');
    }
  }

  // Update a template
  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? markdownContent,
    bool? isDefault,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (name != null) updates['name'] = name;
      if (markdownContent != null) updates['markdownContent'] = markdownContent;

      if (isDefault != null && isDefault) {
        // Get the template to know its type and workspace
        final template = await getTemplate(templateId);
        if (template != null) {
          await _unsetDefaultsForType(template.workspaceId, template.type);
        }
        updates['isDefault'] = true;
      } else if (isDefault == false) {
        updates['isDefault'] = false;
      }

      await _firestore.collection('document_templates').doc(templateId).update(updates);
    } catch (e) {
      throw Exception('Error updating template: $e');
    }
  }

  // Delete a template
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _firestore.collection('document_templates').doc(templateId).delete();
    } catch (e) {
      throw Exception('Error deleting template: $e');
    }
  }

  // Duplicate a template
  Future<DocumentTemplate> duplicateTemplate({
    required String templateId,
    required String createdBy,
  }) async {
    try {
      final original = await getTemplate(templateId);
      if (original == null) {
        throw Exception('Template not found');
      }

      return await createTemplate(
        workspaceId: original.workspaceId,
        name: '${original.name} (Copy)',
        type: original.type,
        markdownContent: original.markdownContent,
        isDefault: false,
        createdBy: createdBy,
      );
    } catch (e) {
      throw Exception('Error duplicating template: $e');
    }
  }

  // Initialize default templates for a workspace (all types)
  Future<void> initializeDefaultTemplates(String workspaceId, String createdBy) async {
    try {
      for (final type in DocumentType.values) {
        if (type == DocumentType.custom) continue;

        // Check if a template of this type already exists
        final existing = await getDefaultTemplate(workspaceId, type);
        if (existing != null) continue;

        await createTemplate(
          workspaceId: workspaceId,
          name: type.displayName,
          type: type,
          markdownContent: DocumentTemplate.getDefaultTemplate(type),
          isDefault: true,
          createdBy: createdBy,
        );
      }
    } catch (e) {
      throw Exception('Error initializing default templates: $e');
    }
  }

  // Initialize default templates for a specific category
  Future<void> initializeCategoryTemplates(
    String workspaceId,
    TemplateCategory category,
    String createdBy,
  ) async {
    try {
      final typesForCategory = DocumentTypeExtension.forCategoryDefaults(category);
      
      for (final type in typesForCategory) {
        // Check if a template of this type already exists
        final existing = await getDefaultTemplate(workspaceId, type);
        if (existing != null) continue;

        await createTemplate(
          workspaceId: workspaceId,
          name: type.displayName,
          type: type,
          markdownContent: DocumentTemplate.getDefaultTemplate(type),
          isDefault: true,
          createdBy: createdBy,
        );
      }
    } catch (e) {
      throw Exception('Error initializing category templates: $e');
    }
  }

  // Helper to unset defaults for a document type
  Future<void> _unsetDefaultsForType(String workspaceId, DocumentType type) async {
    final snapshot = await _firestore
        .collection('document_templates')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('type', isEqualTo: type.name)
        .where('isDefault', isEqualTo: true)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isDefault': false});
    }
    await batch.commit();
  }
}
