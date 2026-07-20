import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/form_template.dart';
import '../../models/form_submission.dart';
import '../../models/form_field_definition.dart';

/// Supabase implementation of FormService
class SupabaseFormService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  /// Get all form templates for a workspace
  Stream<List<FormTemplate>> getFormTemplates(String workspaceId,
      {String? projectId}) {
    return _supabase
        .from('forms')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .map((data) {
          var templates = data.map((row) => _toFormTemplate(row)).toList();
          if (projectId != null) {
            templates =
                templates.where((t) => t.projectId == projectId).toList();
          }
          return templates;
        });
  }

  /// Get form templates for a specific project
  Stream<List<FormTemplate>> getProjectForms(
      String workspaceId, String projectId) {
    return _supabase
        .from('forms')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .map((data) {
          return data
              .where((row) => row['project_id'] == projectId)
              .map((row) => _toFormTemplate(row))
              .toList();
        });
  }

  /// Get a single form template by ID
  Future<FormTemplate?> getFormTemplate(String formId) async {
    try {
      final response = await _supabase
          .from('forms')
          .select()
          .eq('id', formId)
          .maybeSingle();

      if (response == null) return null;
      return _toFormTemplate(response);
    } catch (e) {
      throw Exception('Error fetching form template: $e');
    }
  }

  /// Get a form template by public slug
  Future<FormTemplate?> getFormBySlug(String slug) async {
    try {
      final response = await _supabase
          .from('forms')
          .select()
          .eq('public_slug', slug)
          .eq('is_public', true)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return _toFormTemplate(response);
    } catch (e) {
      throw Exception('Error fetching form by slug: $e');
    }
  }

  /// Generate a unique public slug
  Future<String> generateUniqueSlug(String baseName) async {
    String slug = baseName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    if (slug.isEmpty) {
      slug = 'form';
    }

    final existing = await _supabase
        .from('forms')
        .select('id')
        .eq('public_slug', slug)
        .limit(1);

    if (existing.isEmpty) {
      return slug;
    }

    final suffix = _uuid.v4().substring(0, 6);
    return '$slug-$suffix';
  }

  /// Create a new form template
  Future<FormTemplate> createFormTemplate({
    required String workspaceId,
    String? projectId,
    required String name,
    String? description,
    List<FormFieldDefinition>? fields,
    bool isPublic = false,
    required String createdBy,
  }) async {
    try {
      final now = DateTime.now();
      String? publicSlug;

      if (isPublic) {
        publicSlug = await generateUniqueSlug(name);
      }

      final formData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'name': name,
        'description': description,
        'fields': fields?.map((f) => f.toJson()).toList() ?? [],
        'is_public': isPublic,
        'public_slug': publicSlug,
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response =
          await _supabase.from('forms').insert(formData).select().single();

      return _toFormTemplate(response);
    } catch (e) {
      throw Exception('Error creating form template: $e');
    }
  }

  /// Update a form template
  Future<void> updateFormTemplate({
    required String formId,
    String? name,
    String? description,
    List<FormFieldDefinition>? fields,
    bool? isPublic,
    String? projectId,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
        'project_id': projectId,
      };

      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (fields != null) {
        updates['fields'] = fields.map((f) => f.toJson()).toList();
      }

      if (isPublic != null) {
        updates['is_public'] = isPublic;
        if (isPublic && name != null) {
          final existingForm = await getFormTemplate(formId);
          if (existingForm?.publicSlug == null) {
            updates['public_slug'] = await generateUniqueSlug(name);
          }
        }
      }

      await _supabase.from('forms').update(updates).eq('id', formId);
    } catch (e) {
      throw Exception('Error updating form template: $e');
    }
  }

  /// Toggle public status
  Future<String?> togglePublic(String formId, bool isPublic) async {
    try {
      String? publicSlug;

      if (isPublic) {
        final form = await getFormTemplate(formId);
        if (form != null && form.publicSlug == null) {
          publicSlug = await generateUniqueSlug(form.name);
        } else {
          publicSlug = form?.publicSlug;
        }
      }

      await _supabase.from('forms').update({
        'is_public': isPublic,
        'public_slug': publicSlug,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', formId);

      return publicSlug;
    } catch (e) {
      throw Exception('Error toggling public status: $e');
    }
  }

  /// Delete a form template
  Future<void> deleteFormTemplate(String formId) async {
    try {
      // Delete all submissions for this form
      await _supabase
          .from('form_submissions')
          .delete()
          .eq('form_template_id', formId);

      // Delete the form itself
      await _supabase.from('forms').delete().eq('id', formId);
    } catch (e) {
      throw Exception('Error deleting form template: $e');
    }
  }

  /// Duplicate a form template
  Future<FormTemplate> duplicateFormTemplate({
    required String formId,
    required String createdBy,
    String? projectId,
    /// Custom name for the copy. Defaults to "<original name> (Copy)".
    String? name,
  }) async {
    try {
      final original = await getFormTemplate(formId);
      if (original == null) {
        throw Exception('Form not found');
      }

      return await createFormTemplate(
        workspaceId: original.workspaceId,
        projectId: projectId ?? original.projectId,
        name: name ?? '${original.name} (Copy)',
        description: original.description,
        fields: original.fields,
        isPublic: false,
        createdBy: createdBy,
      );
    } catch (e) {
      throw Exception('Error duplicating form template: $e');
    }
  }

  // ========================
  // Form Submissions
  // ========================

  /// Get all submissions for a form
  Stream<List<FormSubmission>> getSubmissions(String formTemplateId) {
    return _supabase
        .from('form_submissions')
        .stream(primaryKey: ['id'])
        .eq('form_template_id', formTemplateId)
        .order('submitted_at', ascending: false)
        .map((data) {
          return data.map((row) => _toFormSubmission(row)).toList();
        });
  }

  /// Get workspace-level form templates (forms with no project association).
  /// Used as templates when attaching a form to a project.
  Future<List<FormTemplate>> getWorkspaceTemplateForms(
      String workspaceId) async {
    try {
      final response = await _supabase
          .from('forms')
          .select()
          .eq('workspace_id', workspaceId)
          .isFilter('project_id', null)
          .order('created_at', ascending: false);
      return response.map<FormTemplate>((row) => _toFormTemplate(row)).toList();
    } catch (e) {
      throw Exception('Error fetching workspace form templates: $e');
    }
  }

  /// Get submission count for a form
  Future<int> getSubmissionCount(String formTemplateId) async {
    try {
      final response = await _supabase
          .from('form_submissions')
          .select('id')
          .eq('form_template_id', formTemplateId);

      return response.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get a single submission
  Future<FormSubmission?> getSubmission(String submissionId) async {
    try {
      final response = await _supabase
          .from('form_submissions')
          .select()
          .eq('id', submissionId)
          .maybeSingle();

      if (response == null) return null;
      return _toFormSubmission(response);
    } catch (e) {
      throw Exception('Error fetching submission: $e');
    }
  }

  /// Submit a form response (public)
  Future<FormSubmission> submitForm({
    required String formTemplateId,
    required String workspaceId,
    required Map<String, dynamic> data,
    String? submittedByEmail,
    String? submittedByName,
    String? ipAddress,
  }) async {
    try {
      final now = DateTime.now();

      final submissionData = {
        'form_template_id': formTemplateId,
        'workspace_id': workspaceId,
        'data': data,
        'submitted_at': now.toIso8601String(),
        'submitted_by_email': submittedByEmail,
        'submitted_by_name': submittedByName,
        'ip_address': ipAddress,
      };

      final response = await _supabase
          .from('form_submissions')
          .insert(submissionData)
          .select()
          .single();

      return _toFormSubmission(response);
    } catch (e) {
      throw Exception('Error submitting form: $e');
    }
  }

  /// Delete a submission
  Future<void> deleteSubmission(String submissionId) async {
    try {
      await _supabase.from('form_submissions').delete().eq('id', submissionId);
    } catch (e) {
      throw Exception('Error deleting submission: $e');
    }
  }

  /// Export submissions to CSV
  String exportSubmissionsToCSV(
      FormTemplate form, List<FormSubmission> submissions) {
    final buffer = StringBuffer();

    final headers = ['Submitted At', 'Email', 'Name'];
    headers.addAll(form.fields.map((f) => f.label));
    buffer.writeln(headers.map(_csvCell).join(','));

    for (final submission in submissions) {
      final row = [
        submission.formattedSubmittedAt,
        submission.submittedByEmail ?? '',
        submission.submittedByName ?? '',
      ];
      row.addAll(form.fields.map((f) => submission.getFieldValue(f.id)));
      buffer.writeln(row.map(_csvCell).join(','));
    }

    return buffer.toString();
  }

  /// Wraps a value in double quotes and escapes embedded quotes per RFC 4180.
  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  /// Export the form template structure (name, description, fields) as a
  /// pretty-printed JSON string. Suitable for backup or sharing as a template.
  String exportFormAsJson(FormTemplate form) {
    final data = {
      'name': form.name,
      if (form.description != null) 'description': form.description,
      'fields': form.fields.map((f) => f.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Convert database row to FormTemplate
  FormTemplate _toFormTemplate(Map<String, dynamic> row) {
    return FormTemplate.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert database row to FormSubmission
  FormSubmission _toFormSubmission(Map<String, dynamic> row) {
    return FormSubmission.fromJson(_toSubmissionFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to the camelCase format expected by [FormTemplate.fromJson].
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'projectId': row['project_id'],
      'name': row['name'],
      'description': row['description'],
      'fields': row['fields'],
      'isPublic': row['is_public'],
      'publicSlug': row['public_slug'],
      'createdBy': row['created_by'],
      'createdAt': row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      'updatedAt': row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
    };
  }

  /// Convert Supabase snake_case to the camelCase format expected by [FormSubmission.fromJson].
  Map<String, dynamic> _toSubmissionFirestoreFormat(Map<String, dynamic> row) {
    return {
      'formTemplateId': row['form_template_id'],
      'workspaceId': row['workspace_id'],
      'data': row['data'],
      'submittedAt': row['submitted_at'] != null
          ? DateTime.parse(row['submitted_at'] as String)
          : DateTime.now(),
      'submittedByEmail': row['submitted_by_email'],
      'submittedByName': row['submitted_by_name'],
      'ipAddress': row['ip_address'],
    };
  }
}

