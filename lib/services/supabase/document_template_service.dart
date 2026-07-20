import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/document_template.dart';
import '../../models/document_type.dart';
import '../../models/template_category.dart';

/// Supabase implementation of DocumentTemplateService
class SupabaseDocumentTemplateService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all templates for a workspace (one-time)
  Future<List<DocumentTemplate>> getTemplatesOnce(
    String workspaceId, {
    DocumentType? type,
  }) async {
    try {
      var query = _supabase
          .from('document_templates')
          .select()
          .eq('workspace_id', workspaceId);

      if (type != null) {
        query = query.eq('type', type.dbValue);
      }

      final response = await query.order('created_at', ascending: false);
      return response.map((row) => _toDocumentTemplate(row)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get all templates for a workspace (stream)
  Stream<List<DocumentTemplate>> getTemplates(
    String workspaceId, {
    DocumentType? type,
  }) {
    return _supabase
        .from('document_templates')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .map((data) {
          var templates = data.map((row) => _toDocumentTemplate(row)).toList();
          if (type != null) {
            templates = templates.where((t) => t.type == type).toList();
          }
          return templates;
        });
  }

  /// Get templates grouped by category
  Stream<Map<TemplateCategory, List<DocumentTemplate>>> getTemplatesByCategory(
    String workspaceId,
  ) {
    return getTemplates(workspaceId).map((templates) {
      final grouped = <TemplateCategory, List<DocumentTemplate>>{};

      for (final category in TemplateCategory.values) {
        grouped[category] = [];
      }

      for (final template in templates) {
        grouped[template.category]!.add(template);
      }

      return grouped;
    });
  }

  /// Get a single template
  Future<DocumentTemplate?> getTemplate(String templateId) async {
    try {
      final response = await _supabase
          .from('document_templates')
          .select()
          .eq('id', templateId)
          .maybeSingle();

      if (response == null) return null;
      return _toDocumentTemplate(response);
    } catch (e) {
      throw Exception('Error fetching template: $e');
    }
  }

  /// Get default template for a document type
  Future<DocumentTemplate?> getDefaultTemplate(
    String workspaceId,
    DocumentType type,
  ) async {
    try {
      final response = await _supabase
          .from('document_templates')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('type', type.dbValue)
          .eq('is_default', true)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return _toDocumentTemplate(response);
    } catch (e) {
      throw Exception('Error fetching default template: $e');
    }
  }

  /// Create a new template
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

      if (isDefault) {
        await _unsetDefaultsForType(workspaceId, type);
      }

      final templateData = {
        'workspace_id': workspaceId,
        'name': name,
        'type': type.dbValue,
        'markdown_content': markdownContent,
        'is_default': isDefault,
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('document_templates')
          .insert(templateData)
          .select()
          .single();

      return _toDocumentTemplate(response);
    } catch (e) {
      throw Exception('Error creating template: $e');
    }
  }

  /// Update a template
  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? markdownContent,
    bool? isDefault,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null) {
        updates['name'] = name;
      }
      if (markdownContent != null) {
        updates['markdown_content'] = markdownContent;
      }

      if (isDefault != null && isDefault) {
        final template = await getTemplate(templateId);
        if (template != null) {
          await _unsetDefaultsForType(template.workspaceId, template.type);
        }
        updates['is_default'] = true;
      } else if (isDefault == false) {
        updates['is_default'] = false;
      }

      await _supabase
          .from('document_templates')
          .update(updates)
          .eq('id', templateId);
    } catch (e) {
      throw Exception('Error updating template: $e');
    }
  }

  /// Delete a template
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _supabase.from('document_templates').delete().eq('id', templateId);
    } catch (e) {
      throw Exception('Error deleting template: $e');
    }
  }

  /// Duplicate a template
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

  /// Initialize default templates for a workspace
  Future<void> initializeDefaultTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      final types = DocumentType.values
          .where((type) => type != DocumentType.custom)
          .toList();
      await _initializeDefaultsForTypes(
        workspaceId: workspaceId,
        createdBy: createdBy,
        types: types,
      );
    } catch (e) {
      throw Exception('Error initializing default templates: $e');
    }
  }

  /// Initialize only the core default templates for a workspace.
  Future<void> initializeCoreDefaultTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      await _initializeDefaultsForTypes(
        workspaceId: workspaceId,
        createdBy: createdBy,
        types: DocumentTypeExtension.coreDefaults,
      );
    } catch (e) {
      throw Exception('Error initializing core default templates: $e');
    }
  }

  /// Initialize default templates for a specific category
  Future<void> initializeCategoryTemplates(
    String workspaceId,
    TemplateCategory category,
    String createdBy,
  ) async {
    try {
      final typesForCategory = DocumentTypeExtension.forCategoryDefaults(category);
      await _initializeDefaultsForTypes(
        workspaceId: workspaceId,
        createdBy: createdBy,
        types: typesForCategory,
      );
    } catch (e) {
      throw Exception('Error initializing category templates: $e');
    }
  }

  Future<void> _initializeDefaultsForTypes({
    required String workspaceId,
    required String createdBy,
    required List<DocumentType> types,
  }) async {
    for (final type in types) {
      final existing = await getDefaultTemplate(workspaceId, type);
      if (existing != null) {
        continue;
      }

      await createTemplate(
        workspaceId: workspaceId,
        name: type.displayName,
        type: type,
        markdownContent: DocumentTemplate.getDefaultTemplate(type),
        isDefault: true,
        createdBy: createdBy,
      );
    }
  }

  /// Helper to unset defaults for a document type
  Future<void> _unsetDefaultsForType(
    String workspaceId,
    DocumentType type,
  ) async {
    final response = await _supabase
        .from('document_templates')
        .select('id')
        .eq('workspace_id', workspaceId)
        .eq('type', type.dbValue)
        .eq('is_default', true);

    for (final row in response) {
      await _supabase
          .from('document_templates')
          .update({'is_default': false})
          .eq('id', row['id']);
    }
  }

  /// Convert database row to DocumentTemplate
  DocumentTemplate _toDocumentTemplate(Map<String, dynamic> row) {
    return DocumentTemplate.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to Firestore camelCase format
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'name': row['name'],
      'type': row['type'],
      'markdownContent': row['markdown_content'],
      'isDefault': row['is_default'],
      'createdBy': row['created_by'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : _FakeTimestamp(DateTime.now()),
    };
  }
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
