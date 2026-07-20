import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../config/supabase_config.dart';
import '../../models/app_notification.dart';
import '../../models/field_form_template.dart';
import '../../models/field_form_submission.dart';
import '../../models/form_field_definition.dart';
import '../../models/form_field_type.dart';
import '../../utils/app_logger.dart';
import 'notification_service.dart';
import 'storage_service.dart';

class FieldFormService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseStorageService _storage = SupabaseStorageService();
  final SupabaseNotificationService _notificationService =
      SupabaseNotificationService();
  final _uuid = const Uuid();

  // =========================================================
  // Templates
  // =========================================================

  Stream<List<FieldFormTemplate>> getTemplates(String workspaceId) {
    return _supabase
        .from('field_form_templates')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('name', ascending: true)
        .map((rows) => rows.map(FieldFormTemplate.fromRow).toList());
  }

  Future<List<FieldFormTemplate>> getDefaultTemplates(
    String workspaceId,
  ) async {
    final rows = await _supabase
        .from('field_form_templates')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('is_default', true)
        .order('name', ascending: true);
    return rows.map<FieldFormTemplate>(FieldFormTemplate.fromRow).toList();
  }

  Future<FieldFormTemplate?> getTemplate(String templateId) async {
    final row = await _supabase
        .from('field_form_templates')
        .select()
        .eq('id', templateId)
        .maybeSingle();
    if (row == null) return null;
    return FieldFormTemplate.fromRow(row);
  }

  Future<FieldFormTemplate> createTemplate({
    required String workspaceId,
    required String name,
    String? description,
    FieldFormCategory category = FieldFormCategory.custom,
    List<FormFieldDefinition> fields = const [],
    bool requiresTechSignature = false,
    bool requiresSupervisorSignature = false,
    bool requiresCustomerSignature = false,
    bool isDefault = false,
    List<String> defaultTaskCategories = const [],
    String? defaultKey,
    int? defaultVersion,
    String? defaultSeedHash,
    required String createdBy,
  }) async {
    final row = await _supabase
        .from('field_form_templates')
        .insert({
          'workspace_id': workspaceId,
          'name': name,
          'description': description,
          'category': category.name,
          'fields': fields.map((f) => f.toJson()).toList(),
          'requires_tech_signature': requiresTechSignature,
          'requires_supervisor_signature': requiresSupervisorSignature,
          'requires_customer_signature': requiresCustomerSignature,
          'is_default': isDefault,
          'default_task_categories': defaultTaskCategories,
          'default_key': defaultKey,
          'default_version': defaultVersion,
          'default_seed_hash': defaultSeedHash,
          'created_by': createdBy,
        })
        .select()
        .single();
    return FieldFormTemplate.fromRow(row);
  }

  /// Set [clearDescription] to true to remove an existing description.
  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? description,
    bool clearDescription = false,
    FieldFormCategory? category,
    List<FormFieldDefinition>? fields,
    bool? requiresTechSignature,
    bool? requiresSupervisorSignature,
    bool? requiresCustomerSignature,
    bool? isDefault,
    List<String>? defaultTaskCategories,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) {
      updates['description'] = description;
    } else if (clearDescription) {
      updates['description'] = null;
    }
    if (category != null) updates['category'] = category.name;
    if (fields != null) {
      updates['fields'] = fields.map((f) => f.toJson()).toList();
    }
    if (requiresTechSignature != null) {
      updates['requires_tech_signature'] = requiresTechSignature;
    }
    if (requiresSupervisorSignature != null) {
      updates['requires_supervisor_signature'] = requiresSupervisorSignature;
    }
    if (requiresCustomerSignature != null) {
      updates['requires_customer_signature'] = requiresCustomerSignature;
    }
    if (isDefault != null) updates['is_default'] = isDefault;
    if (defaultTaskCategories != null) {
      updates['default_task_categories'] = defaultTaskCategories;
    }
    if (updates.isEmpty) return;
    await _supabase
        .from('field_form_templates')
        .update(updates)
        .eq('id', templateId);
  }

  Future<void> deleteTemplate(String templateId) async {
    await _supabase.from('field_form_templates').delete().eq('id', templateId);
  }

  Future<FieldFormTemplate> duplicateTemplate({
    required String templateId,
    required String createdBy,
    String? name,
  }) async {
    final original = await getTemplate(templateId);
    if (original == null) throw Exception('Template not found');
    return createTemplate(
      workspaceId: original.workspaceId,
      name: name ?? '${original.name} (Copy)',
      description: original.description,
      category: original.category,
      fields: original.fields,
      requiresTechSignature: original.requiresTechSignature,
      requiresSupervisorSignature: original.requiresSupervisorSignature,
      requiresCustomerSignature: original.requiresCustomerSignature,
      isDefault: false,
      defaultTaskCategories: original.defaultTaskCategories,
      createdBy: createdBy,
    );
  }

  // =========================================================
  // Submissions
  // =========================================================

  Stream<List<FieldFormSubmission>> getSubmissions(
    String workspaceId, {
    String? taskId,
    String? projectId,
    FieldFormStatus? status,
  }) {
    // Streams don't support multiple eq filters via .stream(), so we use
    // a one-time fetch + periodic refresh pattern via a realtime channel
    // for filtered queries. For the base workspace stream this is fine.
    var query = _supabase
        .from('field_form_submissions')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false);

    return query.map((rows) {
      var submissions = rows.map(FieldFormSubmission.fromRow).toList();
      if (taskId != null) {
        submissions = submissions.where((s) => s.taskId == taskId).toList();
      }
      if (projectId != null) {
        submissions = submissions
            .where((s) => s.projectId == projectId)
            .toList();
      }
      if (status != null) {
        submissions = submissions.where((s) => s.status == status).toList();
      }
      return submissions;
    });
  }

  Future<FieldFormSubmission?> getSubmission(String submissionId) async {
    final row = await _supabase
        .from('field_form_submissions')
        .select()
        .eq('id', submissionId)
        .maybeSingle();
    if (row == null) return null;
    return FieldFormSubmission.fromRow(row);
  }

  Future<FieldFormSubmission> createSubmission({
    required String workspaceId,
    required String templateId,
    required String templateName,
    String? projectId,
    String? taskId,
    String? title,
    required String filledById,
    required String filledByName,
    Map<String, dynamic> data = const {},
    List<String> attachedPhotoIds = const [],
    List<String> notifiedUserIds = const [],
  }) async {
    final now = DateTime.now();
    final row = await _supabase
        .from('field_form_submissions')
        .insert({
          'workspace_id': workspaceId,
          'template_id': templateId,
          'template_name': templateName,
          'project_id': projectId,
          'task_id': taskId,
          'title': title,
          'status': FieldFormStatus.draft.name,
          'data': data,
          'filled_by_id': filledById,
          'filled_by_name': filledByName,
          'filled_at': now.toIso8601String(),
          if (attachedPhotoIds.isNotEmpty)
            'attached_photo_ids': attachedPhotoIds,
          if (notifiedUserIds.isNotEmpty)
            'notified_user_ids': notifiedUserIds,
        })
        .select()
        .single();
    return FieldFormSubmission.fromRow(row);
  }

  Future<void> saveProgress({
    required String submissionId,
    required Map<String, dynamic> data,
    String? notes,
    List<String>? attachedPhotoIds,
    List<String>? notifiedUserIds,
  }) async {
    final updates = <String, dynamic>{'data': data};
    if (notes != null) updates['notes'] = notes;
    if (attachedPhotoIds != null) {
      updates['attached_photo_ids'] = attachedPhotoIds;
    }
    if (notifiedUserIds != null) {
      updates['notified_user_ids'] = notifiedUserIds;
    }
    await _supabase
        .from('field_form_submissions')
        .update(updates)
        .eq('id', submissionId);
  }

  Future<void> submitForm(String submissionId) async {
    await _supabase
        .from('field_form_submissions')
        .update({
          'status': FieldFormStatus.submitted.name,
          'submitted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', submissionId);

    await _notifySubscribers(submissionId);
  }

  /// Fires an in-app notification to every user in `notified_user_ids` for the
  /// submitted form. Best-effort — failures are logged but don't break submit.
  Future<void> _notifySubscribers(String submissionId) async {
    try {
      final row = await _supabase
          .from('field_form_submissions')
          .select(
              'workspace_id, template_name, filled_by_name, notified_user_ids, filled_by_id, project_id')
          .eq('id', submissionId)
          .maybeSingle();
      if (row == null) return;
      final ids =
          (row['notified_user_ids'] as List?)?.cast<String>() ?? const [];
      if (ids.isEmpty) return;

      final workspaceId = row['workspace_id'] as String;
      final templateName = row['template_name'] as String? ?? 'a form';
      final filledByName = row['filled_by_name'] as String? ?? 'A teammate';
      final filledById = row['filled_by_id'] as String?;
      final projectId = row['project_id'] as String?;

      for (final userId in ids) {
        // Skip notifying the submitter themselves if they checked themselves.
        if (userId == filledById) continue;
        await _notificationService.createNotification(
          userId: userId,
          workspaceId: workspaceId,
          type: AppNotificationTypes.formSubmission,
          title: '$filledByName submitted $templateName',
          body: 'Tap to review the submitted form.',
          metadata: {
            'submissionId': submissionId,
            if (projectId != null) 'projectId': projectId,
          },
        );
      }
    } catch (e) {
      AppLogger.warning('Failed to dispatch form submission notifications',
          metadata: {'submissionId': submissionId, 'error': e.toString()});
    }
  }

  Future<void> approveSubmission(String submissionId) async {
    await _supabase
        .from('field_form_submissions')
        .update({'status': FieldFormStatus.approved.name})
        .eq('id', submissionId);
  }

  Future<void> rejectSubmission(String submissionId, {String? reason}) async {
    final updates = <String, dynamic>{'status': FieldFormStatus.rejected.name};
    if (reason != null) updates['notes'] = reason;
    await _supabase
        .from('field_form_submissions')
        .update(updates)
        .eq('id', submissionId);
  }

  Future<void> deleteSubmission(String submissionId) async {
    await _supabase
        .from('field_form_submissions')
        .delete()
        .eq('id', submissionId);
  }

  // =========================================================
  // Signing
  // =========================================================

  /// Sign as technician. Called internally when the tech submits the form.
  Future<void> signAsTechnician({
    required String submissionId,
    required String workspaceId,
    required Uint8List signatureBytes,
    required String name,
    required String email,
    String? ip,
  }) async {
    final url = await _storage.uploadSignature(
      signatureBytes: signatureBytes,
      workspaceId: workspaceId,
      documentId: submissionId,
    );
    await _supabase
        .from('field_form_submissions')
        .update({
          'tech_signature_url': url,
          'tech_signed_by_name': name,
          'tech_signed_by_email': email,
          'tech_signed_at': DateTime.now().toIso8601String(),
          if (ip != null) 'tech_signature_ip': ip,
        })
        .eq('id', submissionId);
  }

  /// Sign as supervisor. Called by a supervisor reviewing the submission.
  Future<void> signAsSupervisor({
    required String submissionId,
    required String workspaceId,
    required Uint8List signatureBytes,
    required String name,
    required String email,
    String? ip,
  }) async {
    final url = await _storage.uploadSignature(
      signatureBytes: signatureBytes,
      workspaceId: workspaceId,
      documentId: submissionId,
    );
    await _supabase
        .from('field_form_submissions')
        .update({
          'supervisor_signature_url': url,
          'supervisor_signed_by_name': name,
          'supervisor_signed_by_email': email,
          'supervisor_signed_at': DateTime.now().toIso8601String(),
          if (ip != null) 'supervisor_signature_ip': ip,
        })
        .eq('id', submissionId);
  }

  /// Creates a public sign link for customer signing.
  /// Returns the full URL the customer should visit.
  Future<String> createCustomerSignLink({
    required String submissionId,
    required String workspaceId,
    String? recipientEmail,
    Duration validity = const Duration(days: 30),
    required String createdBy,
  }) async {
    final token = _uuid.v4().replaceAll('-', '');
    final expiresAt = DateTime.now().add(validity);

    await _supabase.from('field_form_sign_links').insert({
      'workspace_id': workspaceId,
      'submission_id': submissionId,
      'token': token,
      'recipient_email': recipientEmail,
      'created_by': createdBy,
      'expires_at': expiresAt.toIso8601String(),
    });

    final siteUrl = SupabaseConfig.siteUrl;
    return '$siteUrl/sign-form/$token';
  }

  // =========================================================
  // Task integration
  // =========================================================

  Stream<List<TaskRequiredForm>> getTaskRequiredForms(String taskId) {
    return _supabase
        .from('task_required_forms')
        .stream(primaryKey: ['task_id', 'template_id'])
        .eq('task_id', taskId)
        .map((rows) => rows.map(TaskRequiredForm.fromRow).toList());
  }

  Future<void> addRequiredFormToTask({
    required String taskId,
    required String templateId,
    bool blocksCompletion = false,
  }) async {
    await _supabase.from('task_required_forms').upsert({
      'task_id': taskId,
      'template_id': templateId,
      'blocks_completion': blocksCompletion,
    });
  }

  Future<void> removeRequiredFormFromTask({
    required String taskId,
    required String templateId,
  }) async {
    await _supabase
        .from('task_required_forms')
        .delete()
        .eq('task_id', taskId)
        .eq('template_id', templateId);
  }

  Future<void> linkSubmissionToTaskForm({
    required String taskId,
    required String templateId,
    required String submissionId,
  }) async {
    await _supabase
        .from('task_required_forms')
        .update({'submission_id': submissionId})
        .eq('task_id', taskId)
        .eq('template_id', templateId);
  }

  // =========================================================
  // Default Templates
  // =========================================================

  /// Reconciles the workspace's built-in ("default") field form templates with
  /// the canonical definitions:
  ///   • inserts any default the workspace is missing;
  ///   • for a default the workspace has NOT edited, pushes a version bump
  ///     (overwrites content) when that template's definition version advances;
  ///   • never touches a default the workspace has edited, nor any user-created
  ///     template.
  ///
  /// Idempotent and safe to call on every workspace load. The name is retained
  /// for backwards compatibility with existing callers (signup / workspace
  /// bootstrap and the manual "Generate Default Form Templates" buttons).
  Future<void> generateDefaultTemplates({
    required String workspaceId,
    required String createdBy,
  }) async {
    final existing = await _supabase
        .from('field_form_templates')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('is_default', true);
    final rows =
        existing.map<FieldFormTemplate>(FieldFormTemplate.fromRow).toList();

    // Index existing defaults by stable key, falling back to name so legacy
    // rows seeded before keys existed (and any the backfill missed) are matched
    // and adopted rather than duplicated.
    final byKey = <String, FieldFormTemplate>{};
    final byName = <String, FieldFormTemplate>{};
    for (final row in rows) {
      final k = row.defaultKey;
      if (k != null) byKey[k] = row;
      byName[row.name] = row;
    }

    for (final def in _defaultTemplateDefinitions()) {
      final key = def['key'] as String;
      final version = def['version'] as int;
      final name = def['name'] as String;
      final description = def['description'] as String?;
      final category = def['category'] as FieldFormCategory;
      final fields = def['fields'] as List<FormFieldDefinition>;
      final defaultTaskCategories =
          def['defaultTaskCategories'] as List<String>? ?? const <String>[];
      final requiresTech = def['requiresTechSignature'] as bool? ?? false;
      final requiresSup = def['requiresSupervisorSignature'] as bool? ?? false;
      final requiresCust = def['requiresCustomerSignature'] as bool? ?? false;
      final codeHash = fieldFormDefaultContentHash(
        name: name,
        description: description,
        category: category,
        fields: fields,
        requiresTechSignature: requiresTech,
        requiresSupervisorSignature: requiresSup,
        requiresCustomerSignature: requiresCust,
        defaultTaskCategories: defaultTaskCategories,
      );

      final existingRow = byKey[key] ?? byName[name];

      // 1. Missing — insert fresh, fully tracked.
      if (existingRow == null) {
        await createTemplate(
          workspaceId: workspaceId,
          name: name,
          description: description,
          category: category,
          fields: fields,
          requiresTechSignature: requiresTech,
          requiresSupervisorSignature: requiresSup,
          requiresCustomerSignature: requiresCust,
          isDefault: true,
          defaultTaskCategories: defaultTaskCategories,
            defaultKey: key,
          defaultVersion: version,
          defaultSeedHash: codeHash,
          createdBy: createdBy,
        );
        continue;
      }

      // 2. Not yet tracked (legacy / freshly backfilled) — adopt the row's
      //    current content as its baseline without overwriting, so future
      //    version bumps can apply but nothing is clobbered on first contact.
      if (existingRow.defaultSeedHash == null) {
        await _supabase.from('field_form_templates').update({
          'default_key': key,
          'default_version': version,
          'default_seed_hash': existingRow.defaultContentHash,
        }).eq('id', existingRow.id);
        continue;
      }

      // 3. Workspace edited its copy — leave it untouched.
      if (existingRow.defaultContentHash != existingRow.defaultSeedHash) {
        continue;
      }

      // 4. Unedited and the definition advanced — push the new content.
      if ((existingRow.defaultVersion ?? 0) < version) {
        await _supabase.from('field_form_templates').update({
          'name': name,
          'description': description,
          'category': category.name,
          'fields': fields.map((f) => f.toJson()).toList(),
          'requires_tech_signature': requiresTech,
          'requires_supervisor_signature': requiresSup,
          'requires_customer_signature': requiresCust,
          'default_task_categories': defaultTaskCategories,
          'default_key': key,
          'default_version': version,
          'default_seed_hash': codeHash,
        }).eq('id', existingRow.id);
      }
    }
  }

  static List<Map<String, dynamic>> _defaultTemplateDefinitions() {
    int order = 0;
    FormFieldDefinition f(
      String id,
      FormFieldType type,
      String label, {
      bool required = false,
      String? description,
      List<String>? options,
      List<TableColumnDef>? columns,
      Map<String, List<String>>? visibleWhen,
      String? unit,
    }) {
      return FormFieldDefinition(
        id: id,
        type: type,
        label: label,
        description: description,
        isRequired: required,
        order: order++,
        options: options,
        columns: columns,
        visibleWhen: visibleWhen,
        unit: unit,
      );
    }

    return [
      // ── Generic Work Order ──
      {
        'key': 'generic_work_order',
        'version': 1,
        'name': 'Generic Work Order',
        'description':
            'All-purpose work order for any service type. Covers customer info, scope, labour, materials, and sign-off.',
        'category': FieldFormCategory.custom,
        'requiresTechSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': <String>[],
        'fields': () {
          order = 0;
          return [
            // Section 1 — Customer & Site
            f('sec_client', FormFieldType.section, 'Customer & Site Information'),
            f(
              'client_name',
              FormFieldType.text,
              'Customer / Company Name',
              required: true,
            ),
            f('client_phone', FormFieldType.phone, 'Primary Contact Phone'),
            f('client_email', FormFieldType.email, 'Contact Email'),
            f(
              'site_address',
              FormFieldType.address,
              'Service / Job Site Address',
              required: true,
            ),
            f('unit_suite', FormFieldType.text, 'Unit / Suite / Floor'),
            f(
              'property_type',
              FormFieldType.select,
              'Property Type',
              options: [
                'Residential — Single Family',
                'Residential — Multi-Unit / Condo',
                'Commercial — Office',
                'Commercial — Retail',
                'Commercial — Warehouse / Industrial',
                'Institutional (School, Hospital, etc.)',
                'Government / Municipal',
                'Other',
              ],
            ),
            f(
              'onsite_contact',
              FormFieldType.text,
              'On-Site Contact (if different)',
              description: 'Name and phone number',
            ),
            f(
              'access_instructions',
              FormFieldType.text,
              'Site Access Instructions',
              description: 'Key code, lockbox, buzz unit, etc.',
            ),

            // Section 2 — Work Order Details
            f('sec_details', FormFieldType.section, 'Work Order Details'),
            f(
              'work_type',
              FormFieldType.select,
              'Work Type / Category',
              required: true,
              options: [
                'Water Damage Mitigation',
                'Fire & Smoke Restoration',
                'Mold Remediation',
                'Biohazard / Trauma Cleanup',
                'Reconstruction / Rebuild',
                'Contents Pack-Out / Storage',
                'Equipment Installation',
                'Inspection / Assessment',
                'Preventive Maintenance',
                'General Repair',
                'Cleaning / Final Clean',
                'Other',
              ],
            ),
            f('start_time', FormFieldType.time, 'Scheduled Start Time'),
            f(
              'est_duration',
              FormFieldType.text,
              'Estimated Duration',
              description: 'e.g. 4 hours, Full day',
            ),
            f('lead_tech', FormFieldType.text, 'Lead Technician / Crew Lead'),
            f('crew', FormFieldType.text, 'Additional Crew (names or count)'),
            f('vehicle', FormFieldType.text, 'Vehicle / Unit #'),
            f(
              'dispatch_notes',
              FormFieldType.textarea,
              'Dispatch Notes / Reason for Call',
              description:
                  'Describe the issue or request as reported by the customer or dispatcher.',
            ),
            f(
              'scope_of_work',
              FormFieldType.textarea,
              'Authorized Scope of Work',
              required: true,
              description:
                  'Clearly describe the work the customer has authorized.',
            ),
            f('po_number', FormFieldType.text, 'Purchase / PO Number'),
            f('insurance_claim', FormFieldType.text, 'Insurance Claim #'),
            f('insurance_carrier', FormFieldType.text, 'Insurance Carrier'),

            // Section 3 — Pre-Job Checklist
            f('sec_prejob', FormFieldType.section, 'Pre-Job Checklist'),
            f(
              'chk_scope_reviewed',
              FormFieldType.checkbox,
              'Work order reviewed and scope understood',
            ),
            f(
              'chk_tools_loaded',
              FormFieldType.checkbox,
              'All tools and materials loaded on vehicle',
            ),
            f(
              'chk_ppe',
              FormFieldType.checkbox,
              'PPE on-hand and worn (as required)',
            ),
            f(
              'chk_access_confirmed',
              FormFieldType.checkbox,
              'Site access confirmed with customer',
            ),
            f(
              'chk_utilities',
              FormFieldType.checkbox,
              'Utilities / hazards checked before starting',
            ),
            f(
              'chk_area_protected',
              FormFieldType.checkbox,
              'Work area protected (drop cloths, barriers)',
            ),
            f(
              'chk_client_notified',
              FormFieldType.checkbox,
              'Customer or on-site contact notified of arrival',
            ),
            f(
              'chk_before_photos',
              FormFieldType.checkbox,
              'Before photos taken',
            ),

            // Section 4 — Labour Record
            f('sec_labour', FormFieldType.section, 'Labour Record'),
            f(
              'labour_table',
              FormFieldType.table,
              'Labour',
              columns: [
                const TableColumnDef(key: 'name', label: 'Technician Name'),
                const TableColumnDef(key: 'role', label: 'Role / Trade'),
                const TableColumnDef(
                  key: 'time_in',
                  label: 'Time In',
                  type: 'time',
                ),
                const TableColumnDef(
                  key: 'time_out',
                  label: 'Time Out',
                  type: 'time',
                ),
                const TableColumnDef(
                  key: 'break_min',
                  label: 'Break (min)',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'total_hrs',
                  label: 'Total Hrs',
                  type: 'number',
                ),
                const TableColumnDef(key: 'bill_rate', label: 'Bill Rate'),
              ],
            ),
            f('total_labour_hrs', FormFieldType.number, 'Total Labour Hours'),
            f('travel_time', FormFieldType.number, 'Travel Time (hrs)'),

            // Section 5 — Materials & Parts
            f('sec_materials', FormFieldType.section, 'Materials & Parts Used'),
            f(
              'materials_table',
              FormFieldType.table,
              'Materials',
              columns: [
                const TableColumnDef(key: 'description', label: 'Description'),
                const TableColumnDef(key: 'qty', label: 'Qty', type: 'number'),
                const TableColumnDef(key: 'unit', label: 'Unit'),
                const TableColumnDef(key: 'unit_cost', label: 'Unit Cost'),
                const TableColumnDef(key: 'total', label: 'Total'),
                const TableColumnDef(
                  key: 'billable',
                  label: 'Billable?',
                  type: 'select',
                  options: ['Yes', 'No', 'Warranty'],
                ),
              ],
            ),

            // Section 6 — Work Performed
            f(
              'sec_work',
              FormFieldType.section,
              'Work Performed & Field Notes',
            ),
            f(
              'work_description',
              FormFieldType.textarea,
              'Detailed Description of Work Completed',
              required: true,
              description:
                  'Include methods used, areas serviced, conditions found, and any relevant observations.',
            ),
            f(
              'deficiencies',
              FormFieldType.textarea,
              'Deficiencies, Concerns, or Observations',
              description:
                  'Pre-existing damage, conditions outside scope, code issues, etc.',
            ),
            f(
              'recommendations',
              FormFieldType.textarea,
              'Recommendations & Follow-Up Required',
            ),
            f('chk_after_photos', FormFieldType.checkbox, 'After photos taken'),
            f(
              'chk_area_cleaned',
              FormFieldType.checkbox,
              'Work area cleaned and debris removed',
            ),
            f(
              'chk_tools_collected',
              FormFieldType.checkbox,
              'All tools and equipment collected',
            ),
            f(
              'chk_client_walkthrough',
              FormFieldType.checkbox,
              'Customer walked through completed work',
            ),
            f(
              'chk_no_damage',
              FormFieldType.checkbox,
              'No damage caused to property',
            ),
            f(
              'chk_client_satisfied',
              FormFieldType.checkbox,
              'Customer verbally satisfied at departure',
            ),

            // Section 7 — Cost Summary
            f('sec_cost', FormFieldType.section, 'Cost Summary'),
            f(
              'payment_terms',
              FormFieldType.select,
              'Payment Terms',
              options: [
                'Due on Receipt',
                'Net 15',
                'Net 30',
                'Net 60',
                'Insurance Direct Billing',
                'Pre-Authorized',
                'Progress Billing',
              ],
            ),
            f(
              'payment_method',
              FormFieldType.select,
              'Payment Method',
              options: [
                'Cash',
                'Cheque',
                'Credit Card',
                'E-Transfer',
                'EFT / Bank Transfer',
                'Insurance — Direct Pay',
                'Purchase Order',
              ],
            ),
            f(
              'billing_notes',
              FormFieldType.textarea,
              'Billing Notes',
              description:
                  'Holdback amounts, deposit received, partial payment notes, etc.',
            ),
          ];
        }(),
      },

      // ── Installation Service Work Order ──
      {
        'key': 'installation_service_work_order',
        'version': 1,
        'name': 'Installation Service Work Order',
        'description':
            'Equipment, systems & component installation with pre/post checklists and warranty.',
        'category': FieldFormCategory.completion,
        'requiresTechSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': ['installation'],
        'fields': () {
          order = 0;
          return [
            f('sec_client', FormFieldType.section, 'Customer & Site Information'),
            f('client_name', FormFieldType.text, 'Customer Name', required: true),
            f('client_phone', FormFieldType.phone, 'Phone'),
            f(
              'install_address',
              FormFieldType.address,
              'Installation Address',
              required: true,
            ),
            f(
              'access_instructions',
              FormFieldType.text,
              'Site Access Instructions',
            ),
            f(
              'permit_required',
              FormFieldType.select,
              'Permit / Inspection Required?',
              options: ['Yes', 'No', 'Pending'],
            ),

            f(
              'sec_equipment',
              FormFieldType.section,
              'Equipment / System Being Installed',
            ),
            f(
              'equipment_table',
              FormFieldType.table,
              'Equipment List',
              columns: [
                const TableColumnDef(
                  key: 'equipment',
                  label: 'Equipment / Component',
                ),
                const TableColumnDef(key: 'make_model', label: 'Make / Model'),
                const TableColumnDef(key: 'serial', label: 'Serial / Asset #'),
                const TableColumnDef(
                  key: 'location',
                  label: 'Location Installed',
                ),
                const TableColumnDef(key: 'qty', label: 'Qty', type: 'number'),
              ],
            ),

            f(
              'sec_pre_install',
              FormFieldType.section,
              'Pre-Installation Checklist',
            ),
            f(
              'chk_site_survey',
              FormFieldType.checkbox,
              'Site survey completed prior to arrival',
            ),
            f(
              'chk_utilities',
              FormFieldType.checkbox,
              'Utilities located and marked',
            ),
            f(
              'chk_permits',
              FormFieldType.checkbox,
              'Required permits obtained',
            ),
            f(
              'chk_ppe',
              FormFieldType.checkbox,
              'Safety equipment on-site (PPE)',
            ),
            f(
              'chk_materials',
              FormFieldType.checkbox,
              'All materials and tools on hand',
            ),
            f(
              'chk_area_cleared',
              FormFieldType.checkbox,
              'Work area cleared and protected',
            ),
            f(
              'chk_existing_doc',
              FormFieldType.checkbox,
              'Existing system documented / photographed',
            ),
            f(
              'chk_client_informed',
              FormFieldType.checkbox,
              'Customer informed of work scope and timeline',
            ),

            f(
              'sec_install_details',
              FormFieldType.section,
              'Installation Details',
            ),
            f(
              'install_method',
              FormFieldType.textarea,
              'Installation Method / Notes',
              required: true,
              description:
                  'Describe how the installation was performed, special techniques, code compliance steps.',
            ),
            f(
              'deviations',
              FormFieldType.textarea,
              'Deviations from Original Scope',
              description: 'Note any changes from the original plan and why.',
            ),

            f(
              'sec_post_install',
              FormFieldType.section,
              'Post-Installation Checklist & Testing',
            ),
            f(
              'chk_system_tested',
              FormFieldType.checkbox,
              'System tested and functioning correctly',
            ),
            f(
              'chk_no_issues',
              FormFieldType.checkbox,
              'No leaks, sparks, or irregularities noted',
            ),
            f(
              'chk_client_walk',
              FormFieldType.checkbox,
              'Customer walked through operation',
            ),
            f(
              'chk_manuals',
              FormFieldType.checkbox,
              'User manuals / documentation left on-site',
            ),
            f(
              'chk_warranty_cards',
              FormFieldType.checkbox,
              'Warranty cards registered',
            ),
            f(
              'chk_cleaned',
              FormFieldType.checkbox,
              'Work area cleaned and debris removed',
            ),
            f(
              'chk_permit_inspect',
              FormFieldType.checkbox,
              'Permit inspection scheduled (if required)',
            ),
            f(
              'chk_install_photos',
              FormFieldType.checkbox,
              'Photos of completed install captured',
            ),

            f('sec_warranty', FormFieldType.section, 'Warranty & Guarantee'),
            f(
              'parts_warranty',
              FormFieldType.text,
              'Parts Warranty',
              description: 'e.g. 1 Year Manufacturer',
            ),
            f(
              'labour_warranty',
              FormFieldType.text,
              'Labour Warranty',
              description: 'e.g. 90 Days',
            ),
            f('warranty_expiry', FormFieldType.date, 'Warranty Expiry Date'),
            f(
              'warranty_notes',
              FormFieldType.text,
              'Warranty Exclusions / Notes',
            ),
          ];
        }(),
      },

      // ── 12-Hour Mitigation Report — Residential ──
      {
        'key': 'twelve_hour_mitigation_residential',
        'version': 1,
        'name': '12-Hour Mitigation Report — Residential',
        'description':
            'IICRC S500-compliant 12-hour initial mitigation report for residential water losses.',
        'category': FieldFormCategory.assessment,
        'requiresTechSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': ['mitigation', 'water_damage'],
        'fields': () {
          order = 0;
          return [
            f('sec_loss', FormFieldType.section, 'Loss & Property Information'),
            f(
              'insured_name',
              FormFieldType.text,
              'Insured Name',
              required: true,
            ),
            f('insurance_carrier', FormFieldType.text, 'Insurance Carrier'),
            f(
              'loss_address',
              FormFieldType.address,
              'Loss Address',
              required: true,
            ),
            f('adjuster_name', FormFieldType.text, 'Adjuster Name'),
            f('adjuster_contact', FormFieldType.text, 'Adjuster Phone / Email'),
            f('policy_number', FormFieldType.text, 'Policy Number'),
            f('deductible', FormFieldType.text, 'Deductible'),

            f(
              'sec_classification',
              FormFieldType.section,
              'Water Category & Class (IICRC S500)',
            ),
            f(
              'water_category',
              FormFieldType.select,
              'Water Category',
              required: true,
              options: [
                'Category 1 — Clean Water (sanitary source)',
                'Category 2 — Grey Water (significant contamination)',
                'Category 3 — Black Water (grossly contaminated)',
              ],
            ),
            f(
              'water_class',
              FormFieldType.select,
              'Water Class',
              required: true,
              options: [
                'Class 1 — Least amount / minimal absorption',
                'Class 2 — Large amount / floor affected',
                'Class 3 — Greatest amount / walls, ceilings, insulation',
                'Class 4 — Specialty drying required',
              ],
            ),
            f(
              'water_source',
              FormFieldType.text,
              'Source of Water Loss',
              required: true,
            ),
            f(
              'loss_start',
              FormFieldType.datetime,
              'Estimated Loss Start Date / Time',
            ),
            f(
              'source_contained',
              FormFieldType.select,
              'Source Contained?',
              options: ['Yes', 'No', 'Plumber Required'],
            ),

            f(
              'sec_psych',
              FormFieldType.section,
              'Psychrometric Conditions — Arrival Reading',
            ),
            f('temp_f', FormFieldType.number, 'Temperature (F)'),
            f('rel_humidity', FormFieldType.number, 'Relative Humidity (%)'),
            f('dewpoint', FormFieldType.number, 'Dewpoint (F)'),
            f(
              'specific_humidity',
              FormFieldType.number,
              'Specific Humidity (Grains/lb)',
            ),
            f('gpp_outdoor', FormFieldType.number, 'GPP Outdoors (Grains/lb)'),

            f(
              'sec_moisture',
              FormFieldType.section,
              'Moisture Readings — Affected Areas',
            ),
            f(
              'moisture_table',
              FormFieldType.table,
              'Moisture Readings',
              columns: [
                const TableColumnDef(key: 'room', label: 'Room / Area'),
                const TableColumnDef(key: 'material', label: 'Material'),
                const TableColumnDef(
                  key: 'reading',
                  label: 'Reading (%)',
                  type: 'number',
                ),
                const TableColumnDef(key: 'meter_type', label: 'Meter Type'),
                const TableColumnDef(
                  key: 'wet_dry',
                  label: 'Wet / Dry?',
                  type: 'select',
                  options: ['Wet', 'Dry', 'Borderline'],
                ),
                const TableColumnDef(
                  key: 'drying_goal',
                  label: 'Drying Goal (%)',
                  type: 'number',
                ),
                const TableColumnDef(key: 'notes', label: 'Notes'),
              ],
            ),

            f(
              'sec_equipment',
              FormFieldType.section,
              'Drying Equipment Deployed',
            ),
            f(
              'equipment_table',
              FormFieldType.table,
              'Equipment',
              columns: [
                const TableColumnDef(
                  key: 'type',
                  label: 'Equipment Type',
                  type: 'select',
                  options: [
                    'Air Mover',
                    'Dehumidifier (LGR)',
                    'Desiccant Dehumidifier',
                    'Air Scrubber',
                    'Negative Air Machine',
                    'Hydroxyl Generator',
                    'Heater',
                    'Specialty Drying System',
                  ],
                ),
                const TableColumnDef(key: 'qty', label: 'Qty', type: 'number'),
                const TableColumnDef(key: 'serial', label: 'Asset / Serial #'),
                const TableColumnDef(key: 'location', label: 'Location Placed'),
                const TableColumnDef(
                  key: 'time_set',
                  label: 'Time Set',
                  type: 'time',
                ),
              ],
            ),
            f('total_air_movers', FormFieldType.number, 'Total Air Movers'),
            f(
              'total_dehumidifiers',
              FormFieldType.number,
              'Total Dehumidifiers',
            ),

            f(
              'sec_demo',
              FormFieldType.section,
              'Demolition / Material Removal Summary',
            ),
            f(
              'demo_table',
              FormFieldType.table,
              'Material Removal',
              columns: [
                const TableColumnDef(
                  key: 'material',
                  label: 'Material Removed',
                ),
                const TableColumnDef(
                  key: 'area',
                  label: 'Area / Qty',
                  type: 'number',
                ),
                const TableColumnDef(key: 'unit', label: 'Unit'),
                const TableColumnDef(key: 'reason', label: 'Reason'),
              ],
            ),

            f(
              'sec_drying_goal',
              FormFieldType.section,
              'Drying Goal & Expected Timeline',
            ),
            f(
              'target_standard',
              FormFieldType.text,
              'Target Dry Standard',
              description: 'e.g. IICRC S500',
            ),
            f('expected_days', FormFieldType.number, 'Expected Drying Days'),
            f('next_monitoring', FormFieldType.date, 'Next Monitoring Visit'),
            f(
              'drying_plan',
              FormFieldType.textarea,
              'Drying Plan Summary',
              required: true,
            ),
          ];
        }(),
      },

      // ── Initial Inspection — Residential ──
      {
        'key': 'initial_inspection_residential',
        'version': 1,
        'name': 'Initial Inspection — Residential',
        'description':
            'IICRC S500/S520-compliant initial inspection for residential emergency losses.',
        'category': FieldFormCategory.inspection,
        'requiresTechSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': ['inspection', 'mitigation'],
        'fields': () {
          order = 0;
          return [
            f(
              'sec_insured',
              FormFieldType.section,
              'Insured & Adjuster Details',
            ),
            f(
              'insured_name',
              FormFieldType.text,
              'Insured Name',
              required: true,
            ),
            f('insured_phone', FormFieldType.phone, 'Phone'),
            f(
              'property_address',
              FormFieldType.address,
              'Property Address',
              required: true,
            ),
            f('insurance_carrier', FormFieldType.text, 'Insurance Carrier'),
            f('claim_number', FormFieldType.text, 'Claim Number'),
            f('adjuster_name', FormFieldType.text, 'Adjuster Name'),
            f('adjuster_contact', FormFieldType.text, 'Adjuster Phone / Email'),

            f(
              'sec_loss_assessment',
              FormFieldType.section,
              'Scope of Loss — Initial Assessment',
            ),
            f(
              'loss_type',
              FormFieldType.select,
              'Type of Loss',
              required: true,
              options: [
                'Water — Supply Line Break',
                'Water — Appliance Overflow',
                'Water — Sewer / Drain Backup',
                'Water — Roof / Skylight Leak',
                'Water — HVAC / Condensate',
                'Water — Flood / Weather',
                'Fire Damage',
                'Smoke & Soot',
                'Mold / Microbial',
                'Biohazard',
                'Other',
              ],
            ),
            f(
              'loss_duration',
              FormFieldType.select,
              'Estimated Loss Duration',
              options: [
                'Less than 24 hours',
                '1–3 days',
                '3–7 days',
                'More than 7 days',
                'Unknown',
              ],
            ),
            f(
              'affected_areas',
              FormFieldType.multiSelect,
              'Affected Areas',
              options: [
                'Basement',
                'Ground Floor',
                'Upper Floor',
                'Kitchen',
                'Bathroom',
                'Living Room',
                'Bedroom(s)',
                'Laundry Room',
                'Garage',
                'Crawlspace',
                'Attic',
                'HVAC System',
                'Electrical',
                'Structural',
              ],
            ),
            f(
              'affected_sqft',
              FormFieldType.number,
              'Approx. Affected Area (sq ft)',
            ),
            f(
              'affected_rooms',
              FormFieldType.number,
              'Number of Affected Rooms',
            ),

            f('sec_iicrc', FormFieldType.section, 'IICRC Classification'),
            f(
              'water_category',
              FormFieldType.select,
              'Water Category',
              required: true,
              options: [
                'Category 1 — Clean Water',
                'Category 2 — Grey Water',
                'Category 3 — Black Water',
              ],
            ),
            f(
              'water_class',
              FormFieldType.select,
              'Water Class',
              required: true,
              options: [
                'Class 1 — Least amount',
                'Class 2 — Significant amount',
                'Class 3 — Greatest amount',
                'Class 4 — Specialty drying',
              ],
            ),
            f(
              'classification_rationale',
              FormFieldType.textarea,
              'Classification Rationale',
              description: 'Explain why this category and class was assigned.',
            ),

            f(
              'sec_moisture_map',
              FormFieldType.section,
              'Room-by-Room Moisture Map',
            ),
            f(
              'moisture_map_table',
              FormFieldType.table,
              'Moisture Map',
              columns: [
                const TableColumnDef(key: 'room', label: 'Room / Area'),
                const TableColumnDef(key: 'surface', label: 'Surface'),
                const TableColumnDef(key: 'material', label: 'Material'),
                const TableColumnDef(
                  key: 'moisture_pct',
                  label: 'Moisture %',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'thermal',
                  label: 'Thermal Imaging?',
                  type: 'select',
                  options: ['Yes', 'No'],
                ),
                const TableColumnDef(
                  key: 'iicrc_wet',
                  label: 'IICRC Wet?',
                  type: 'select',
                  options: ['Yes', 'No', 'Borderline'],
                ),
                const TableColumnDef(key: 'action', label: 'Action Required'),
              ],
            ),

            f('sec_contents', FormFieldType.section, 'Contents Assessment'),
            f(
              'contents_present',
              FormFieldType.select,
              'Affected Contents Present?',
              options: ['Yes', 'No', 'Minimal'],
            ),
            f(
              'contents_action',
              FormFieldType.select,
              'Contents Action',
              options: [
                'In-place drying only',
                'Pack-out required',
                'Discard items present',
                'Contents inventory required',
                'Not applicable',
              ],
            ),
            f(
              'high_value_items',
              FormFieldType.textarea,
              'High-Value / Specialty Items Noted',
              description: 'Electronics, artwork, documents, jewelry, etc.',
            ),

            f('sec_photos', FormFieldType.section, 'Photo Documentation'),
            f('photo_source', FormFieldType.photo, 'Source of Loss'),
            f('photo_readings', FormFieldType.photo, 'Moisture Readings'),
            f('photo_affected', FormFieldType.photo, 'Affected Areas'),
            f('photo_thermal', FormFieldType.photo, 'Thermal Imaging'),
            f('photo_overview', FormFieldType.photo, 'Overview / Wide Shot'),
            f('photo_notes', FormFieldType.textarea, 'Photo Log Notes'),

            f('sec_scope', FormFieldType.section, 'Preliminary Scope of Work'),
            f(
              'immediate_actions',
              FormFieldType.textarea,
              'Immediate Actions Taken',
              required: true,
            ),
            f(
              'recommended_next',
              FormFieldType.textarea,
              'Recommended Next Steps',
            ),
            f(
              'safety_concerns',
              FormFieldType.textarea,
              'Safety Concerns or Hazards Identified',
            ),
          ];
        }(),
      },

      // ── Employee Clock-Out Questionnaire ──
      {
        'key': 'employee_clock_out_questionnaire',
        'version': 1,
        'name': 'Employee Clock-Out Questionnaire',
        'description':
            'End-of-shift questionnaire covering task completion, safety, and incident reporting.',
        'category': FieldFormCategory.safety,
        'requiresTechSignature': true,
        'requiresSupervisorSignature': true,
        'defaultTaskCategories': <String>[],
        'fields': () {
          order = 0;
          return [
            f('sec_task', FormFieldType.section, 'Task Completion Status'),
            f(
              'task_status',
              FormFieldType.select,
              'Task Status',
              required: true,
              options: [
                'Fully Completed',
                'Partially Completed',
                'Not Completed',
              ],
            ),
            f(
              'task_details',
              FormFieldType.textarea,
              'Details / Reason',
              description:
                  'Required if partially or not completed. Explain what was done, what remains, and any blockers.',
            ),

            f(
              'sec_safety',
              FormFieldType.section,
              'Workplace Safety & Incident Report',
            ),
            f(
              'any_incidents',
              FormFieldType.select,
              'Any workplace accidents or injuries today?',
              required: true,
              options: ['Yes', 'No'],
            ),
            f('incident_persons', FormFieldType.text, 'Person(s) Involved'),
            f('incident_time', FormFieldType.time, 'Incident Time'),
            f(
              'incident_type',
              FormFieldType.select,
              'Type of Incident',
              options: [
                'Injury — Self',
                'Injury — Co-worker',
                'Near Miss',
                'Property Damage',
                'Equipment Damage',
                'Vehicle Incident',
                'Other',
              ],
            ),
            f(
              'body_part',
              FormFieldType.text,
              'Body Part Affected (if injury)',
            ),
            f(
              'incident_description',
              FormFieldType.textarea,
              'Describe What Happened',
            ),
            f(
              'medical_attention',
              FormFieldType.select,
              'Medical Attention Required?',
              options: ['Yes — emergency', 'Yes — non-urgent', 'No'],
            ),
            f('witnesses', FormFieldType.text, 'Witnesses'),
            f(
              'corrective_actions',
              FormFieldType.textarea,
              'Corrective Actions Taken',
            ),
            f(
              'hazards_observed',
              FormFieldType.select,
              'Unsafe conditions or hazards observed today?',
              required: true,
              options: ['Yes', 'No'],
            ),
            f(
              'hazard_description',
              FormFieldType.textarea,
              'Describe hazards observed',
            ),
            f(
              'ppe_worn',
              FormFieldType.select,
              'All required PPE worn for full shift?',
              required: true,
              options: ['Yes', 'No'],
            ),
          ];
        }(),
      },

      // ── Daily Job Site Log ──
      {
        'key': 'daily_job_site_log',
        'version': 1,
        'name': 'Daily Job Site Log',
        'description':
            'Daily field report covering crew attendance, work performed, materials, equipment, and safety.',
        'category': FieldFormCategory.completion,
        'requiresTechSignature': true,
        'defaultTaskCategories': <String>[],
        'fields': () {
          order = 0;
          return [
            f(
              'site_address',
              FormFieldType.address,
              'Site Address',
              required: true,
            ),
            f(
              'phase_of_work',
              FormFieldType.select,
              'Phase of Work',
              options: [
                'Emergency Mitigation',
                'Drying / Monitoring',
                'Demolition',
                'Reconstruction',
                'Contents / Pack-Out',
                'Final Clean',
                'Inspection',
              ],
            ),
            f('crew_size', FormFieldType.number, 'Crew Size'),
            f(
              'weather',
              FormFieldType.select,
              'Weather',
              options: [
                'Clear / Sunny',
                'Partly Cloudy',
                'Overcast',
                'Rain',
                'Snow / Ice',
                'Windy',
                'Fog / Poor Visibility',
              ],
            ),
            f(
              'temperature',
              FormFieldType.number,
              'Temperature',
              unit: 'temperature',
            ),

            f('sec_crew', FormFieldType.section, 'Crew Attendance & Hours'),
            f(
              'crew_table',
              FormFieldType.table,
              'Crew Attendance',
              columns: [
                const TableColumnDef(
                  key: 'name',
                  label: 'Employee Name',
                  type: 'employeeRef',
                ),
                const TableColumnDef(key: 'role', label: 'Role / Trade'),
                const TableColumnDef(
                  key: 'time_in',
                  label: 'Time In',
                  type: 'timesheetPull',
                  computeFrom: 'name',
                  pullField: 'startTime',
                  readOnly: true,
                ),
                const TableColumnDef(
                  key: 'time_out',
                  label: 'Time Out',
                  type: 'timesheetPull',
                  computeFrom: 'name',
                  pullField: 'endTime',
                  readOnly: true,
                ),
                const TableColumnDef(
                  key: 'break_min',
                  label: 'Break (min)',
                  type: 'timesheetPull',
                  computeFrom: 'name',
                  pullField: 'breakMinutes',
                  readOnly: true,
                ),
                const TableColumnDef(
                  key: 'total_hrs',
                  label: 'Total Hrs',
                  type: 'timesheetPull',
                  computeFrom: 'name',
                  pullField: 'totalHours',
                  readOnly: true,
                ),
                const TableColumnDef(
                  key: 'on_site',
                  label: 'On-Site?',
                  type: 'select',
                  options: ['Yes', 'No — Remote', 'Late Arrival', 'Left Early'],
                ),
              ],
            ),
            f(
              'total_labour',
              FormFieldType.number,
              'Total Labour Hours (All Crew)',
            ),
            f(
              'subs_on_site',
              FormFieldType.select,
              'Subcontractors On-Site?',
              options: ['Yes', 'No'],
            ),
            f(
              'sub_company',
              FormFieldType.text,
              'Subcontractor Company',
              visibleWhen: {
                'subs_on_site': ['Yes'],
              },
            ),

            f('sec_work', FormFieldType.section, 'Work Performed Today'),
            f(
              'work_table',
              FormFieldType.table,
              'Tasks',
              columns: [
                const TableColumnDef(key: 'task', label: 'Task / Activity'),
                const TableColumnDef(
                  key: 'area',
                  label: 'Area / Location',
                  type: 'locationRef',
                ),
                const TableColumnDef(
                  key: 'hours',
                  label: 'Hours',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'status',
                  label: 'Status',
                  type: 'select',
                  options: ['Completed', 'In Progress', 'On Hold', 'Blocked'],
                ),
                const TableColumnDef(key: 'notes', label: 'Notes'),
              ],
            ),
            f(
              'daily_narrative',
              FormFieldType.textarea,
              'Daily Work Narrative',
              required: true,
              description: 'Summarize the day\'s work in 2-4 sentences.',
            ),

            f(
              'water_loss_job',
              FormFieldType.select,
              'Water-Loss / Restoration Job?',
              description:
                  'Select Yes to log psychrometric and moisture readings.',
              options: ['Yes', 'No'],
            ),
            f(
              'sec_drying',
              FormFieldType.section,
              'Daily Drying & Monitoring Log',
              description: 'Psychrometric readings and moisture logs.',
              visibleWhen: {
                'water_loss_job': ['Yes'],
              },
            ),
            f(
              'psych_temp',
              FormFieldType.number,
              'Temperature',
              unit: 'temperature',
              visibleWhen: {
                'water_loss_job': ['Yes'],
              },
            ),
            f(
              'psych_rh',
              FormFieldType.number,
              'Relative Humidity (%)',
              visibleWhen: {
                'water_loss_job': ['Yes'],
              },
            ),
            f(
              'psych_dewpoint',
              FormFieldType.number,
              'Dewpoint',
              unit: 'temperature',
              visibleWhen: {
                'water_loss_job': ['Yes'],
              },
            ),
            f(
              'psych_gpp',
              FormFieldType.number,
              'Grains / lb (GPP)',
              visibleWhen: {
                'water_loss_job': ['Yes'],
              },
            ),
            f(
              'psych_time',
              FormFieldType.time,
              'Reading Time',
              visibleWhen: {
                'water_loss_job': ['Yes'],
              },
            ),
            f(
              'drying_log_table',
              FormFieldType.table,
              'Moisture Readings',
              visibleWhen: {
                'water_loss_job': ['Yes'],
              },
              columns: [
                const TableColumnDef(
                  key: 'room',
                  label: 'Room / Area',
                  type: 'locationRef',
                ),
                const TableColumnDef(key: 'material', label: 'Material'),
                const TableColumnDef(
                  key: 'yesterday',
                  label: 'Yesterday %',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'today',
                  label: 'Today %',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'target',
                  label: 'Target %',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'trend',
                  label: 'Trend',
                  type: 'select',
                  options: ['Improving', 'Stable', 'Worsening', 'Declared Dry'],
                ),
                const TableColumnDef(key: 'action', label: 'Action'),
              ],
            ),

            f(
              'sec_materials',
              FormFieldType.section,
              'Materials & Supplies Used Today',
            ),
            f(
              'materials_table',
              FormFieldType.table,
              'Materials',
              columns: [
                const TableColumnDef(
                  key: 'description',
                  label: 'Material / Supply',
                ),
                const TableColumnDef(
                  key: 'qty',
                  label: 'Qty Used',
                  type: 'number',
                ),
                const TableColumnDef(key: 'unit', label: 'Unit'),
                const TableColumnDef(
                  key: 'disposal',
                  label: 'Waste / Disposal?',
                  type: 'select',
                  options: ['No', 'Yes — landfill', 'Yes — disposal bin'],
                ),
              ],
            ),

            f('sec_safety', FormFieldType.section, 'Safety & Site Conditions'),
            f(
              'chk_toolbox_talk',
              FormFieldType.checkbox,
              'Daily safety briefing (toolbox talk) conducted',
            ),
            f(
              'chk_incidents',
              FormFieldType.checkbox,
              'Any workplace incidents or injuries today',
            ),
            f(
              'chk_ppe',
              FormFieldType.checkbox,
              'All PPE worn for full duration of work',
            ),
            f(
              'chk_hazmat',
              FormFieldType.checkbox,
              'Hazardous materials / asbestos concern identified',
            ),
            f(
              'safety_notes',
              FormFieldType.textarea,
              'Safety Notes / Incident Details',
            ),

            f(
              'sec_visitors',
              FormFieldType.section,
              'Deliveries, Visitors & Site Access',
            ),
            f(
              'deliveries',
              FormFieldType.multiSelect,
              'Deliveries Received Today',
              options: [
                'Drywall',
                'Plywood / Sheathing',
                'Lumber',
                'Insulation',
                'Flooring',
                'Tile',
                'Trim / Molding',
                'Paint / Primer',
                'Adhesives / Sealants',
                'Fasteners',
                'Concrete / Mortar',
                'Roofing Materials',
                'Plumbing Supplies',
                'Electrical Supplies',
                'HVAC Supplies',
                'Cleaning Supplies',
                'PPE',
                'Equipment / Tools',
                'Dumpster / Waste Bin',
                'Other',
              ],
            ),
            f(
              'visitors',
              FormFieldType.textarea,
              'Visitors / Third Parties On-Site',
            ),
          ];
        }(),
      },

      // ── 12-Hour Mitigation Report — Multi-Res / Commercial ──
      {
        'key': 'twelve_hour_mitigation_commercial',
        'version': 1,
        'name': '12-Hour Mitigation Report — Multi-Res / Commercial',
        'description':
            'IICRC S500-compliant 12-hour report for multi-residential and commercial water losses with unit access logs and building systems.',
        'category': FieldFormCategory.assessment,
        'requiresTechSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': ['mitigation', 'water_damage', 'commercial'],
        'fields': () {
          order = 0;
          return [
            f(
              'sec_building',
              FormFieldType.section,
              'Building & Property Information',
            ),
            f(
              'building_name',
              FormFieldType.text,
              'Building / Property Name',
              required: true,
            ),
            f(
              'building_type',
              FormFieldType.select,
              'Building Type',
              required: true,
              options: [
                'Multi-Residential — Condo / Strata',
                'Multi-Residential — Apartment / Rental',
                'Mixed-Use (Residential + Retail)',
                'Commercial — Office',
                'Commercial — Retail / Mall',
                'Commercial — Warehouse / Industrial',
                'Institutional (School, Hospital, Gov\'t)',
                'Hotel / Hospitality',
                'Other',
              ],
            ),
            f('year_built', FormFieldType.text, 'Year Built (approx.)'),
            f(
              'property_address',
              FormFieldType.address,
              'Property Address',
              required: true,
            ),
            f('total_floors', FormFieldType.number, 'Total Floors in Building'),
            f('total_units', FormFieldType.number, 'Total Units in Building'),
            f(
              'floors_affected',
              FormFieldType.text,
              'Floors Affected',
              description: 'e.g. B1, 3, 4, 5',
            ),
            f(
              'units_affected_count',
              FormFieldType.number,
              'Units / Suites Affected (count)',
            ),

            f(
              'sec_stakeholders',
              FormFieldType.section,
              'Stakeholder Directory',
            ),
            f(
              'stakeholder_table',
              FormFieldType.table,
              'Stakeholders',
              columns: [
                const TableColumnDef(key: 'role', label: 'Role'),
                const TableColumnDef(key: 'name', label: 'Name / Company'),
                const TableColumnDef(key: 'phone', label: 'Phone'),
                const TableColumnDef(key: 'email', label: 'Email'),
                const TableColumnDef(
                  key: 'on_site',
                  label: 'On-Site?',
                  type: 'select',
                  options: ['Yes', 'No', 'Available by phone'],
                ),
              ],
            ),
            f('insurance_carrier', FormFieldType.text, 'Insurance Carrier'),
            f('policy_number', FormFieldType.text, 'Policy Number'),

            f(
              'sec_classification',
              FormFieldType.section,
              'Water Category & Class (IICRC S500)',
            ),
            f(
              'water_cat_source',
              FormFieldType.select,
              'Water Category (at Source)',
              required: true,
              options: [
                'Category 1 — Clean Water',
                'Category 2 — Grey Water',
                'Category 3 — Black Water',
              ],
            ),
            f(
              'water_cat_affected',
              FormFieldType.select,
              'Water Category (at Affected Areas)',
              options: [
                'Category 1 — Clean',
                'Category 2 — Grey (migrated or elapsed)',
                'Category 3 — Black (sewage, contaminated)',
              ],
            ),
            f(
              'water_class',
              FormFieldType.select,
              'Water Class',
              required: true,
              options: [
                'Class 1 — Least evaporation load',
                'Class 2 — Significant (floor + wall)',
                'Class 3 — Greatest (ceiling, walls, insulation)',
                'Class 4 — Specialty drying',
              ],
            ),
            f(
              'loss_source',
              FormFieldType.select,
              'Source of Loss',
              options: [
                'Plumbing riser / stack failure',
                'Sprinkler system discharge',
                'Roof / parapet infiltration',
                'Mechanical / HVAC condensate',
                'Unit-to-unit migration',
                'Sewer / drain backup',
                'Municipal service connection',
                'Window / curtain wall failure',
                'Elevator pit flooding',
                'Parking garage drain backup',
                'Other',
              ],
            ),
            f('source_description', FormFieldType.text, 'Source Description'),
            f('loss_start', FormFieldType.datetime, 'Estimated Loss Start'),
            f(
              'source_contained',
              FormFieldType.select,
              'Source Contained / Isolated?',
              options: [
                'Yes',
                'No — Active',
                'Plumber Required',
                'Building Mech. Required',
              ],
            ),

            f(
              'sec_access_log',
              FormFieldType.section,
              'Affected Units / Suites Access Log',
            ),
            f(
              'unit_access_table',
              FormFieldType.table,
              'Unit Access Log',
              columns: [
                const TableColumnDef(key: 'unit', label: 'Unit #'),
                const TableColumnDef(key: 'floor', label: 'Floor'),
                const TableColumnDef(key: 'occupant', label: 'Occupant Name'),
                const TableColumnDef(key: 'phone', label: 'Occupant Phone'),
                const TableColumnDef(
                  key: 'access',
                  label: 'Access Gained?',
                  type: 'select',
                  options: [
                    'Yes — Full',
                    'Yes — Partial',
                    'No — Refused',
                    'No — Unoccupied',
                    'Pending',
                  ],
                ),
                const TableColumnDef(key: 'areas', label: 'Areas Affected'),
                const TableColumnDef(key: 'cat_class', label: 'Cat / Class'),
                const TableColumnDef(
                  key: 'sqft',
                  label: 'Approx. SF',
                  type: 'number',
                ),
              ],
            ),
            f('units_accessed', FormFieldType.number, 'Units Accessed'),
            f('units_pending', FormFieldType.number, 'Units Pending Access'),
            f('total_affected_sf', FormFieldType.number, 'Total Affected SF'),
            f(
              'common_areas',
              FormFieldType.select,
              'Common Areas Affected?',
              options: ['Yes', 'No'],
            ),
            f(
              'common_areas_desc',
              FormFieldType.text,
              'Common Areas Affected (describe)',
            ),

            f(
              'sec_building_systems',
              FormFieldType.section,
              'Building Systems Affected',
            ),
            f('chk_hvac', FormFieldType.checkbox, 'HVAC / Air handling units'),
            f(
              'chk_plumbing_riser',
              FormFieldType.checkbox,
              'Plumbing riser / wet stack',
            ),
            f(
              'chk_sprinkler',
              FormFieldType.checkbox,
              'Fire suppression / sprinkler',
            ),
            f(
              'chk_electrical',
              FormFieldType.checkbox,
              'Electrical panels / conduits',
            ),
            f('chk_elevator', FormFieldType.checkbox, 'Elevator shaft / pit'),
            f(
              'chk_parking',
              FormFieldType.checkbox,
              'Parking garage / underground',
            ),
            f('chk_roof', FormFieldType.checkbox, 'Roof membrane / drainage'),
            f(
              'chk_curtain_wall',
              FormFieldType.checkbox,
              'Curtain wall / window system',
            ),
            f('chk_mechanical', FormFieldType.checkbox, 'Mechanical room'),
            f(
              'chk_boiler',
              FormFieldType.checkbox,
              'Boiler / hot water systems',
            ),
            f('chk_telecom', FormFieldType.checkbox, 'Telecom / data room'),
            f(
              'chk_commercial_kitchen',
              FormFieldType.checkbox,
              'Commercial kitchen systems',
            ),
            f(
              'building_systems_notes',
              FormFieldType.textarea,
              'Building Systems Notes',
            ),

            f(
              'sec_environmental',
              FormFieldType.section,
              'Environmental & Regulatory Concerns',
            ),
            f(
              'chk_acm',
              FormFieldType.checkbox,
              'Suspected asbestos-containing materials (pre-1990)',
            ),
            f(
              'chk_lead',
              FormFieldType.checkbox,
              'Suspected lead paint or lead pipes',
            ),
            f(
              'chk_mold',
              FormFieldType.checkbox,
              'Mold / microbial growth visible',
            ),
            f(
              'chk_hazmat',
              FormFieldType.checkbox,
              'Hazardous materials in affected area',
            ),
            f(
              'chk_building_permit',
              FormFieldType.checkbox,
              'Building permit required for remediation',
            ),
            f(
              'chk_env_consultant',
              FormFieldType.checkbox,
              'Environmental consultant required',
            ),
            f(
              'chk_air_testing',
              FormFieldType.checkbox,
              'Air quality / IH testing required',
            ),
            f(
              'chk_structural_eng',
              FormFieldType.checkbox,
              'Structural engineer assessment required',
            ),
            f(
              'env_consultant_name',
              FormFieldType.text,
              'Environmental Consultant (if engaged)',
            ),
            f('permit_number', FormFieldType.text, 'Permit Application #'),

            f(
              'sec_psych_zones',
              FormFieldType.section,
              'Psychrometric Conditions — By Zone',
            ),
            f(
              'psych_zone_table',
              FormFieldType.table,
              'Psychrometric Readings',
              columns: [
                const TableColumnDef(key: 'zone', label: 'Zone / Floor / Unit'),
                const TableColumnDef(
                  key: 'temp',
                  label: 'Temp (F)',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'rh',
                  label: 'RH (%)',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'dewpoint',
                  label: 'Dewpoint (F)',
                  type: 'number',
                ),
                const TableColumnDef(key: 'gpp', label: 'GPP', type: 'number'),
                const TableColumnDef(
                  key: 'outdoor_gpp',
                  label: 'Outdoor GPP',
                  type: 'number',
                ),
                const TableColumnDef(key: 'time', label: 'Time', type: 'time'),
              ],
            ),

            f(
              'sec_moisture',
              FormFieldType.section,
              'Moisture Readings — All Affected Areas',
            ),
            f(
              'moisture_table',
              FormFieldType.table,
              'Moisture Readings',
              columns: [
                const TableColumnDef(key: 'unit_zone', label: 'Unit / Zone'),
                const TableColumnDef(key: 'room', label: 'Room'),
                const TableColumnDef(key: 'material', label: 'Material'),
                const TableColumnDef(
                  key: 'reading',
                  label: 'Reading (%)',
                  type: 'number',
                ),
                const TableColumnDef(key: 'meter', label: 'Meter Type'),
                const TableColumnDef(
                  key: 'wet_dry',
                  label: 'Wet/Dry?',
                  type: 'select',
                  options: ['Wet', 'Dry', 'Borderline'],
                ),
                const TableColumnDef(
                  key: 'goal',
                  label: 'Drying Goal (%)',
                  type: 'number',
                ),
              ],
            ),

            f(
              'sec_equipment',
              FormFieldType.section,
              'Drying Equipment Deployed',
            ),
            f(
              'equipment_table',
              FormFieldType.table,
              'Equipment',
              columns: [
                const TableColumnDef(
                  key: 'type',
                  label: 'Equipment Type',
                  type: 'select',
                  options: [
                    'Air Mover (axial)',
                    'Air Mover (LGR)',
                    'LGR Dehumidifier',
                    'Desiccant Dehumidifier (commercial)',
                    'Industrial Air Scrubber',
                    'Negative Air Machine',
                    'Hydroxyl Generator',
                    'Commercial Heater',
                    'Injection Drying System',
                  ],
                ),
                const TableColumnDef(key: 'qty', label: 'Qty', type: 'number'),
                const TableColumnDef(key: 'serial', label: 'Asset / Serial #'),
                const TableColumnDef(
                  key: 'location',
                  label: 'Unit / Zone Placed',
                ),
                const TableColumnDef(
                  key: 'time_set',
                  label: 'Time Set',
                  type: 'time',
                ),
              ],
            ),
            f('total_air_movers', FormFieldType.number, 'Total Air Movers'),
            f(
              'total_dehumidifiers',
              FormFieldType.number,
              'Total Dehumidifiers',
            ),
            f(
              'total_air_scrubbers',
              FormFieldType.number,
              'Total Air Scrubbers',
            ),

            f(
              'sec_demo',
              FormFieldType.section,
              'Demolition & Material Removal',
            ),
            f(
              'demo_table',
              FormFieldType.table,
              'Material Removal',
              columns: [
                const TableColumnDef(key: 'unit_zone', label: 'Unit / Zone'),
                const TableColumnDef(
                  key: 'material',
                  label: 'Material Removed',
                ),
                const TableColumnDef(key: 'qty', label: 'Qty', type: 'number'),
                const TableColumnDef(key: 'unit', label: 'Unit'),
                const TableColumnDef(
                  key: 'disposal',
                  label: 'Disposal Method',
                  type: 'select',
                  options: [
                    'Disposal bin',
                    'Landfill direct',
                    'Hazmat disposal',
                    'ACM — licensed disposal',
                  ],
                ),
              ],
            ),

            f(
              'sec_tenant',
              FormFieldType.section,
              'Tenant & Occupant Notification',
            ),
            f(
              'notification_methods',
              FormFieldType.multiSelect,
              'Notification Methods Used',
              options: [
                'Door notice posted',
                'Phone call / voicemail',
                'Email notification',
                'In-person visit',
                'Building-wide notice',
                'Authorized by property mgr',
              ],
            ),
            f(
              'displacement_required',
              FormFieldType.select,
              'Tenant Displacement Required?',
              options: ['Yes — ALE applicable', 'No', 'Partial — some units'],
            ),
            f(
              'units_displacement',
              FormFieldType.text,
              'Units Requiring Displacement',
            ),
            f(
              'ale_arranged',
              FormFieldType.select,
              'Temporary Accommodation Arranged?',
              options: ['Yes', 'No', 'In Progress'],
            ),
            f(
              'tenant_notes',
              FormFieldType.textarea,
              'Tenant Notification Notes',
            ),

            f(
              'sec_drying_plan',
              FormFieldType.section,
              'Drying Plan & Timeline',
            ),
            f('target_standard', FormFieldType.text, 'Target Dry Standard'),
            f('expected_days', FormFieldType.number, 'Expected Drying Days'),
            f('next_monitoring', FormFieldType.date, 'Next Monitoring Visit'),
            f(
              'business_interruption',
              FormFieldType.select,
              'Business Interruption Applicable?',
              options: ['Yes', 'No'],
            ),
            f(
              'loss_rental_income',
              FormFieldType.select,
              'Loss of Rental Income Applicable?',
              options: ['Yes', 'No'],
            ),
            f(
              'drying_plan',
              FormFieldType.textarea,
              'Commercial Drying Plan Narrative',
              required: true,
              description:
                  'Multi-zone strategy, containment, phased access plan, and timeline factors.',
            ),
          ];
        }(),
      },

      // ── Initial Inspection — Multi-Res / Commercial ──
      {
        'key': 'initial_inspection_commercial',
        'version': 1,
        'name': 'Initial Inspection — Multi-Res / Commercial',
        'description':
            'IICRC-compliant initial inspection for multi-residential and commercial properties with unit access tracking.',
        'category': FieldFormCategory.inspection,
        'requiresTechSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': ['inspection', 'mitigation', 'commercial'],
        'fields': () {
          order = 0;
          return [
            f(
              'sec_building',
              FormFieldType.section,
              'Building & Property Information',
            ),
            f(
              'building_name',
              FormFieldType.text,
              'Building / Property Name',
              required: true,
            ),
            f(
              'building_type',
              FormFieldType.select,
              'Building Type',
              options: [
                'Multi-Residential — Condo / Strata',
                'Multi-Residential — Apartment / Rental',
                'Mixed-Use',
                'Commercial — Office',
                'Commercial — Retail',
                'Commercial — Warehouse / Industrial',
                'Institutional',
                'Hotel / Hospitality',
                'Other',
              ],
            ),
            f(
              'property_address',
              FormFieldType.address,
              'Property Address',
              required: true,
            ),
            f('total_floors', FormFieldType.number, 'Total Floors'),
            f('total_units', FormFieldType.number, 'Total Units'),

            f(
              'sec_stakeholders',
              FormFieldType.section,
              'Stakeholder Directory',
            ),
            f(
              'stakeholder_table',
              FormFieldType.table,
              'Stakeholders',
              columns: [
                const TableColumnDef(key: 'role', label: 'Role'),
                const TableColumnDef(key: 'name', label: 'Name / Company'),
                const TableColumnDef(key: 'phone', label: 'Phone'),
                const TableColumnDef(key: 'email', label: 'Email'),
              ],
            ),
            f('insurance_carrier', FormFieldType.text, 'Insurance Carrier'),
            f('claim_number', FormFieldType.text, 'Claim Number'),

            f(
              'sec_loss',
              FormFieldType.section,
              'Scope of Loss — Initial Assessment',
            ),
            f(
              'loss_type',
              FormFieldType.select,
              'Type of Loss',
              required: true,
              options: [
                'Water — Plumbing riser / stack',
                'Water — Sprinkler discharge',
                'Water — Roof infiltration',
                'Water — HVAC / condensate',
                'Water — Unit-to-unit migration',
                'Water — Sewer / drain backup',
                'Fire Damage',
                'Smoke & Soot',
                'Mold / Microbial',
                'Other',
              ],
            ),
            f(
              'loss_duration',
              FormFieldType.select,
              'Estimated Loss Duration',
              options: [
                'Less than 24 hours',
                '1–3 days',
                '3–7 days',
                'More than 7 days',
                'Unknown',
              ],
            ),
            f('floors_affected', FormFieldType.text, 'Floors Affected'),
            f(
              'units_affected',
              FormFieldType.number,
              'Units / Suites Affected',
            ),
            f(
              'total_sqft',
              FormFieldType.number,
              'Total Affected Area (sq ft)',
            ),

            f('sec_iicrc', FormFieldType.section, 'IICRC Classification'),
            f(
              'water_category',
              FormFieldType.select,
              'Water Category',
              required: true,
              options: [
                'Category 1 — Clean Water',
                'Category 2 — Grey Water',
                'Category 3 — Black Water',
              ],
            ),
            f(
              'water_class',
              FormFieldType.select,
              'Water Class',
              required: true,
              options: [
                'Class 1 — Least amount',
                'Class 2 — Significant',
                'Class 3 — Greatest',
                'Class 4 — Specialty drying',
              ],
            ),
            f(
              'classification_rationale',
              FormFieldType.textarea,
              'Classification Rationale',
            ),

            f(
              'sec_unit_access',
              FormFieldType.section,
              'Unit-by-Unit Moisture Map',
            ),
            f(
              'unit_moisture_table',
              FormFieldType.table,
              'Unit Moisture Map',
              columns: [
                const TableColumnDef(key: 'unit', label: 'Unit #'),
                const TableColumnDef(key: 'room', label: 'Room'),
                const TableColumnDef(key: 'surface', label: 'Surface'),
                const TableColumnDef(key: 'material', label: 'Material'),
                const TableColumnDef(
                  key: 'moisture',
                  label: 'Moisture %',
                  type: 'number',
                ),
                const TableColumnDef(
                  key: 'thermal',
                  label: 'Thermal?',
                  type: 'select',
                  options: ['Yes', 'No'],
                ),
                const TableColumnDef(
                  key: 'wet',
                  label: 'IICRC Wet?',
                  type: 'select',
                  options: ['Yes', 'No', 'Borderline'],
                ),
                const TableColumnDef(key: 'action', label: 'Action'),
              ],
            ),

            f(
              'sec_building_systems',
              FormFieldType.section,
              'Building Systems Affected',
            ),
            f(
              'affected_systems',
              FormFieldType.multiSelect,
              'Systems Affected',
              options: [
                'HVAC / Air handling',
                'Plumbing riser',
                'Fire suppression / sprinkler',
                'Electrical panels',
                'Elevator shaft / pit',
                'Parking garage',
                'Roof membrane',
                'Curtain wall / windows',
                'Mechanical room',
                'Boiler / hot water',
                'Telecom / data room',
              ],
            ),
            f(
              'systems_notes',
              FormFieldType.textarea,
              'Building Systems Notes',
            ),

            f(
              'sec_environmental',
              FormFieldType.section,
              'Environmental & Regulatory',
            ),
            f(
              'env_concerns',
              FormFieldType.multiSelect,
              'Environmental Concerns',
              options: [
                'Suspected asbestos (pre-1990)',
                'Suspected lead paint / pipes',
                'Mold / microbial growth visible',
                'Hazardous materials present',
                'Building permit required',
                'Environmental consultant required',
                'Air quality testing required',
                'Structural engineer required',
              ],
            ),

            f('sec_contents', FormFieldType.section, 'Contents Assessment'),
            f(
              'contents_present',
              FormFieldType.select,
              'Affected Contents?',
              options: ['Yes', 'No', 'Minimal'],
            ),
            f(
              'contents_action',
              FormFieldType.select,
              'Contents Action',
              options: [
                'In-place drying only',
                'Pack-out required',
                'Discard items present',
                'Contents inventory required',
                'Not applicable',
              ],
            ),

            f('sec_photos', FormFieldType.section, 'Photo Documentation'),
            f('photo_source', FormFieldType.photo, 'Source of Loss'),
            f('photo_affected', FormFieldType.photo, 'Affected Areas'),
            f('photo_readings', FormFieldType.photo, 'Moisture Readings'),
            f(
              'photo_building_systems',
              FormFieldType.photo,
              'Building Systems',
            ),
            f('photo_overview', FormFieldType.photo, 'Overview / Wide Shot'),

            f('sec_scope', FormFieldType.section, 'Preliminary Scope of Work'),
            f(
              'immediate_actions',
              FormFieldType.textarea,
              'Immediate Actions Taken',
              required: true,
            ),
            f(
              'recommended_next',
              FormFieldType.textarea,
              'Recommended Next Steps',
            ),
            f(
              'safety_concerns',
              FormFieldType.textarea,
              'Safety Concerns or Hazards',
            ),
            f(
              'tenant_notification',
              FormFieldType.textarea,
              'Tenant Notification Plan',
            ),
          ];
        }(),
      },

      // ── Site Inspection ──
      {
        'key': 'site_inspection',
        'version': 1,
        'name': 'Site Inspection',
        'description':
            'General site inspection form for verifying conditions and compliance.',
        'category': FieldFormCategory.inspection,
        'requiresTechSignature': true,
        'requiresSupervisorSignature': true,
        'defaultTaskCategories': ['inspection', 'maintenance'],
        'fields': () {
          order = 0;
          return [
            f(
              'site_condition',
              FormFieldType.inspectionItem,
              'Overall Site Condition',
              required: true,
            ),
            f(
              'safety_signage',
              FormFieldType.inspectionItem,
              'Safety Signage in Place',
            ),
            f(
              'access_clear',
              FormFieldType.inspectionItem,
              'Access Routes Clear',
            ),
            f(
              'utilities_marked',
              FormFieldType.inspectionItem,
              'Utilities Properly Marked',
            ),
            f(
              'housekeeping',
              FormFieldType.inspectionItem,
              'Housekeeping',
              description: 'Work area clean and organized',
            ),
            f(
              'hazards_identified',
              FormFieldType.textarea,
              'Hazards Identified',
              description: 'Describe any hazards found',
            ),
            f(
              'corrective_actions',
              FormFieldType.textarea,
              'Corrective Actions Required',
            ),
            f(
              'site_photo',
              FormFieldType.photo,
              'Site Photo',
              description: 'Photo evidence of site condition',
            ),
            f(
              'overall_rating',
              FormFieldType.rating,
              'Overall Rating',
              required: true,
            ),
            f('notes', FormFieldType.textarea, 'Additional Notes'),
          ];
        }(),
      },

      // ── Work Completion Report ──
      {
        'key': 'work_completion_report',
        'version': 1,
        'name': 'Work Completion Report',
        'description': 'Document completed work with photos and sign-off.',
        'category': FieldFormCategory.completion,
        'requiresTechSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': ['installation', 'repair', 'maintenance'],
        'fields': () {
          order = 0;
          return [
            f(
              'work_description',
              FormFieldType.textarea,
              'Work Performed',
              required: true,
              description: 'Describe all work completed',
            ),
            f(
              'materials_used',
              FormFieldType.textarea,
              'Materials Used',
              description: 'List materials and quantities',
            ),
            f('before_photo', FormFieldType.photo, 'Before Photo'),
            f(
              'after_photo',
              FormFieldType.photo,
              'After Photo',
              required: true,
            ),
            f(
              'work_quality',
              FormFieldType.rating,
              'Work Quality',
              required: true,
            ),
            f(
              'completion_status',
              FormFieldType.select,
              'Completion Status',
              required: true,
              options: [
                'Fully Complete',
                'Partially Complete',
                'Requires Follow-Up',
              ],
            ),
            f(
              'follow_up_needed',
              FormFieldType.textarea,
              'Follow-Up Details',
              description: 'Describe remaining work',
              visibleWhen: {
                'completion_status': [
                  'Partially Complete',
                  'Requires Follow-Up',
                ],
              },
            ),
            f(
              'customer_satisfied',
              FormFieldType.checkbox,
              'Customer Confirmed Satisfaction',
            ),
            f('notes', FormFieldType.textarea, 'Additional Notes'),
          ];
        }(),
      },

      // ── Safety Checklist ──
      {
        'key': 'safety_checklist',
        'version': 1,
        'name': 'Safety Checklist',
        'description':
            'Pre-work safety checklist to ensure compliance before starting.',
        'category': FieldFormCategory.safety,
        'requiresTechSignature': true,
        'requiresSupervisorSignature': true,
        'defaultTaskCategories': ['construction', 'installation'],
        'fields': () {
          order = 0;
          return [
            f(
              'ppe_worn',
              FormFieldType.inspectionItem,
              'PPE Worn Properly',
              required: true,
              description: 'Hard hat, gloves, safety glasses, etc.',
            ),
            f(
              'area_secured',
              FormFieldType.inspectionItem,
              'Work Area Secured',
              required: true,
            ),
            f(
              'fire_extinguisher',
              FormFieldType.inspectionItem,
              'Fire Extinguisher Accessible',
            ),
            f(
              'first_aid',
              FormFieldType.inspectionItem,
              'First Aid Kit Available',
            ),
            f(
              'electrical_safe',
              FormFieldType.inspectionItem,
              'Electrical Sources De-Energized / Locked Out',
            ),
            f(
              'fall_protection',
              FormFieldType.inspectionItem,
              'Fall Protection in Place',
              description: 'If working at height',
            ),
            f(
              'weather_conditions',
              FormFieldType.select,
              'Weather Conditions',
              options: [
                'Clear',
                'Rain',
                'Wind',
                'Extreme Heat',
                'Extreme Cold',
                'Other',
              ],
            ),
            f(
              'hazards_noted',
              FormFieldType.textarea,
              'Hazards Noted',
              description: 'Describe any safety concerns',
            ),
            f(
              'safe_to_proceed',
              FormFieldType.checkbox,
              'Safe to Proceed with Work',
              required: true,
            ),
          ];
        }(),
      },

      // ── Equipment Inspection ──
      {
        'key': 'equipment_inspection',
        'version': 1,
        'name': 'Equipment Inspection',
        'description':
            'Inspect equipment or assets for proper function and condition.',
        'category': FieldFormCategory.inspection,
        'requiresTechSignature': true,
        'defaultTaskCategories': ['maintenance', 'inspection'],
        'fields': () {
          order = 0;
          return [
            f(
              'equipment_id',
              FormFieldType.text,
              'Equipment ID / Tag',
              required: true,
            ),
            f('equipment_type', FormFieldType.text, 'Equipment Type'),
            f(
              'visual_condition',
              FormFieldType.inspectionItem,
              'Visual Condition',
              required: true,
            ),
            f(
              'operational_check',
              FormFieldType.inspectionItem,
              'Operational / Functional Check',
              required: true,
            ),
            f(
              'safety_devices',
              FormFieldType.inspectionItem,
              'Safety Devices Working',
            ),
            f(
              'leaks_damage',
              FormFieldType.inspectionItem,
              'No Leaks or Visible Damage',
            ),
            f('condition_photo', FormFieldType.photo, 'Condition Photo'),
            f(
              'condition_rating',
              FormFieldType.rating,
              'Overall Condition',
              required: true,
            ),
            f(
              'action_required',
              FormFieldType.select,
              'Action Required',
              options: [
                'None — Good Condition',
                'Minor Repair Needed',
                'Major Repair Needed',
                'Replace',
                'Out of Service',
              ],
            ),
            f('notes', FormFieldType.textarea, 'Notes'),
          ];
        }(),
      },

      // ── Room / Area Completion ──
      {
        'key': 'room_area_completion',
        'version': 1,
        'name': 'Room / Area Completion',
        'description':
            'Room-by-room or area-by-area sign-off for completed work.',
        'category': FieldFormCategory.completion,
        'requiresTechSignature': true,
        'requiresSupervisorSignature': true,
        'requiresCustomerSignature': true,
        'defaultTaskCategories': ['construction', 'renovation'],
        'fields': () {
          order = 0;
          return [
            f(
              'area_name',
              FormFieldType.text,
              'Room / Area Name',
              required: true,
            ),
            f('floor_level', FormFieldType.text, 'Floor / Level'),
            f(
              'walls_ceiling',
              FormFieldType.inspectionItem,
              'Walls & Ceiling Complete',
            ),
            f('flooring', FormFieldType.inspectionItem, 'Flooring Complete'),
            f(
              'electrical',
              FormFieldType.inspectionItem,
              'Electrical Fixtures Installed & Working',
            ),
            f(
              'plumbing',
              FormFieldType.inspectionItem,
              'Plumbing Fixtures Installed & Working',
            ),
            f(
              'paint_finish',
              FormFieldType.inspectionItem,
              'Paint / Finish Acceptable',
            ),
            f(
              'cleanup',
              FormFieldType.inspectionItem,
              'Area Cleaned & Debris Removed',
            ),
            f(
              'punch_list',
              FormFieldType.textarea,
              'Punch List Items',
              description: 'Remaining items to address',
            ),
            f('area_photo', FormFieldType.photo, 'Area Photo', required: true),
            f(
              'overall_rating',
              FormFieldType.rating,
              'Overall Quality',
              required: true,
            ),
          ];
        }(),
      },
    ];
  }

  /// Returns true if all blocking required forms for a task are completed.
  Future<bool> canCompleteTask(String taskId) async {
    final rows = await _supabase
        .from('task_required_forms')
        .select()
        .eq('task_id', taskId)
        .eq('blocks_completion', true);

    if (rows.isEmpty) return true;
    return rows.every((r) => r['submission_id'] != null);
  }
}
