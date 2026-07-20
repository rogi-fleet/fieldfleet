import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import '../../models/project.dart';
import '../../models/app_notification.dart';
import '../../models/price_type.dart';
import '../../models/cost_plus_type.dart';
import '../../models/job_type.dart';
import '../../models/asset.dart';
import '../../models/document_type.dart';
import '../../models/project_financial_summary.dart';
import '../../utils/app_logger.dart';
import 'automation_service.dart';
import '../../utils/user_facing_error.dart';
import 'notification_service.dart';

/// Supabase implementation of ProjectService
class SupabaseProjectService {
  @visibleForTesting
  static const List<String> collectedRevenueDocumentTypes = <String>[
    'invoice',
    'progress_invoice',
  ];

  @visibleForTesting
  static List<Map<String, dynamic>> eligibleBudgetRowsForFinancialSummary(
    List<dynamic> budgetRows, {
    Map<String, String> changeOrderStatuses = const {},
  }) {
    final normalizedRows = budgetRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    final parentIds = normalizedRows
        .map((row) => row['parent_id'] as String?)
        .whereType<String>()
        .toSet();

    return normalizedRows
        .where((row) {
          final id = row['id'] as String?;
          if (id == null || parentIds.contains(id)) return false;
          if ((row['item_type'] as String?) != 'item') return false;

          switch (row['source_type'] as String? ?? 'base') {
            case 'change_order':
              final changeOrderId = row['change_order_id'] as String?;
              final status = changeOrderStatuses[changeOrderId]?.toLowerCase();
              return status != null &&
                  const {'approved', 'signed', 'completed'}.contains(status);
            case 'upgrade':
              return (row['upgrade_status'] as String?) == 'accepted';
            default:
              return true;
          }
        })
        .toList(growable: false);
  }

  /// Sums the cash actually collected across invoice rows.
  ///
  /// Payments are recorded via `recordPartialPayment`, which advances
  /// `amount_paid` per payment and stamps `paid_date` only once the balance
  /// hits zero — so an open invoice's partial payments live solely in
  /// `amount_paid`. Fully-paid rows count their `total_amount` as a floor
  /// because legacy "mark paid" rows predate `amount_paid` and carry 0 there.
  static double sumCollectedRevenueFromRows(List<dynamic> documentRows) {
    return documentRows.fold<double>(0.0, (sum, row) {
      final normalized = Map<String, dynamic>.from(row as Map);
      final total =
          ((normalized['total_price'] ?? normalized['total_amount']) as num?)
                  ?.toDouble() ??
              0.0;
      final amountPaid =
          (normalized['amount_paid'] as num?)?.toDouble() ?? 0.0;
      final isFullyPaid = normalized['paid_date'] != null;
      final collected = isFullyPaid ? math.max(total, amountPaid) : amountPaid;
      return sum + collected;
    });
  }

  @visibleForTesting
  static double sumCostToCompleteFromBudgetRows(
    List<Map<String, dynamic>> rows,
  ) {
    return rows.fold<double>(0.0, (sum, row) {
      final isComplete = row['is_complete'] == true;
      final value = isComplete ? row['final_cost'] : row['projected_cost'];
      return sum + ((value as num?)?.toDouble() ?? 0.0);
    });
  }

  /// Convert PriceType enum to PostgreSQL enum value
  String _priceTypeToDb(PriceType type) {
    switch (type) {
      case PriceType.fixedPrice:
        return 'fixed_price';
      case PriceType.timeAndMaterial:
        return 'time_and_material';
      case PriceType.costPlus:
        return 'cost_plus';
      case PriceType.unitPrice:
        return 'time_and_material'; // DB doesn't have unit_price, fallback
    }
  }

  /// Convert CostPlusType enum to PostgreSQL enum value
  String _costPlusTypeToDb(CostPlusType type) {
    switch (type) {
      case CostPlusType.percentage:
        return 'percentage';
      case CostPlusType.fixedFee:
        return 'fixed_fee';
    }
  }

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all projects for a workspace (realtime stream)
  Stream<List<Project>> getProjects(String workspaceId) {
    AppLogger.debug(
      'getProjects: Creating stream',
      metadata: {'workspaceId': workspaceId},
    );
    return _supabase
        .from('projects')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .asyncMap((data) async {
          AppLogger.debug(
            'getProjects: Data received',
            metadata: {'workspaceId': workspaceId, 'count': data.length},
          );

          // Streams don't support joins, so fetch team members separately
          final projectIds = data.map((row) => row['id'] as String).toList();
          final teamMap = await _fetchTeamMemberMap(projectIds);

          return data.map((row) {
            row['team_member_ids'] = teamMap[row['id']] ?? [];
            return Project.fromJson(_toFirestoreFormat(row), row['id']);
          }).toList();
        });
  }

  /// Fetch all projects for a workspace (one-time)
  Future<List<Project>> getProjectsOnce(String workspaceId) async {
    try {
      final response = await _supabase
          .from('projects')
          .select('*, project_team_members(user_id)')
          .eq('workspace_id', workspaceId)
          .order('updated_at', ascending: false);

      return response
          .map((row) => Project.fromJson(_toFirestoreFormat(row), row['id']))
          .toList();
    } catch (e) {
      AppLogger.error(
        'getProjectsOnce: Error',
        error: e,
        metadata: {'workspaceId': workspaceId},
      );
      return [];
    }
  }

  /// Fetch a single project by ID
  Future<Project?> getProject(String projectId, {String? workspaceId}) async {
    try {
      AppLogger.debug('Fetching project', metadata: {'projectId': projectId});

      var query = _supabase
          .from('projects')
          .select('*, project_team_members(user_id)')
          .eq('id', projectId);
      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query.maybeSingle();

      if (response != null) {
        AppLogger.debug(
          'Project loaded successfully',
          metadata: {'projectId': projectId},
        );
        return Project.fromJson(_toFirestoreFormat(response), response['id']);
      }

      AppLogger.debug('Project not found', metadata: {'projectId': projectId});
      return null;
    } catch (e) {
      AppLogger.error(
        'Failed to fetch project',
        error: e,
        metadata: {'projectId': projectId},
      );
      throw UserFacingException(
        UserFacingError.projectLoadMessage(e),
        cause: e,
      );
    }
  }

  /// Generate next sequential serial number for a workspace
  Future<String> _getNextSerialNumber(String workspaceId) async {
    try {
      // Get or create counter
      final counterId = '${workspaceId}_project_serial';

      final existing = await _supabase
          .from('counters')
          .select()
          .eq('id', counterId)
          .maybeSingle();

      int nextValue;
      if (existing != null) {
        nextValue = (existing['current_value'] as int) + 1;
      } else {
        // Get workspace's starting serial number
        final workspace = await _supabase
            .from('workspaces')
            .select('starting_project_serial_number')
            .eq('id', workspaceId)
            .maybeSingle();

        nextValue = workspace?['starting_project_serial_number'] ?? 1;
      }

      // Upsert counter
      await _supabase.from('counters').upsert({
        'id': counterId,
        'workspace_id': workspaceId,
        'counter_type': 'project_serial',
        'current_value': nextValue,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return nextValue.toString();
    } catch (e) {
      AppLogger.error(
        'Failed to generate serial number',
        error: e,
        metadata: {'workspaceId': workspaceId},
      );
      throw Exception('Error generating serial number: $e');
    }
  }

  /// Get the number of projects for a workspace
  Future<int> getProjectCount(String workspaceId) async {
    final result = await _supabase
        .from('projects')
        .select()
        .eq('workspace_id', workspaceId)
        .count();
    return result.count;
  }

  /// Create a new project
  Future<Project> createProject({
    required String workspaceId,
    required String name,
    required String address,
    required ProjectStatus status,
    String? clientId,
    double? estimatedBudget,
    double? materialMarkupPercent,
    double? laborMarkupPercent,
    DateTime? startDate,
    DateTime? targetCompletionDate,
    PriceType? priceType,
    double? contractAmount,
    CostPlusType? costPlusType,
    double? costPlusValue,
    String? description,
    String? projectManagerId,
    double? latitude,
    double? longitude,
    int? geofenceRadiusMeters,
    bool? requireGeofenceValidation,
    bool? allowClockInOutsideGeofence,
    String? photoUrl,
    JobType? jobType,
    String? purchaseOrderNumber,
    DateTime? dateRequestReceived,
    String? locationDetails,
    String? salespersonId,
    String? supervisorId,
    String? primaryContactName,
    String? customerName,
    String? primaryContactRole,
    String? primaryContactPhone,
    String? primaryContactEmail,
    String? serialNumber,
    String? customerLocationId,
    String? vendorSubdivisionId,
    List<String>? teamMemberIds,
    Map<String, dynamic>? customFields,
  }) async {
    var createStep = 'serial_number';
    try {
      final now = DateTime.now();
      final finalSerialNumber =
          serialNumber ?? await _getNextSerialNumber(workspaceId);

      createStep = 'insert_project';
      final projectData = {
        'workspace_id': workspaceId,
        'name': name,
        'address': address,
        'status': status.dbValue,
        'client_id': clientId,
        'estimated_budget': estimatedBudget,
        'material_markup_percent': materialMarkupPercent ?? 20.0,
        'labor_markup_percent': laborMarkupPercent ?? 30.0,
        'start_date': startDate?.toIso8601String(),
        'target_completion_date': targetCompletionDate?.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'price_type': _priceTypeToDb(priceType ?? PriceType.timeAndMaterial),
        'contract_amount': contractAmount,
        'cost_plus_type': costPlusType != null
            ? _costPlusTypeToDb(costPlusType)
            : null,
        'cost_plus_value': costPlusValue,
        'description': description,
        'project_manager_id': projectManagerId,
        'latitude': latitude,
        'longitude': longitude,
        if (geofenceRadiusMeters != null)
          'geofence_radius_meters': geofenceRadiusMeters,
        if (requireGeofenceValidation != null)
          'require_geofence_validation': requireGeofenceValidation,
        if (allowClockInOutsideGeofence != null)
          'allow_clock_in_outside_geofence': allowClockInOutsideGeofence,
        'photo_url': photoUrl,
        'job_type': jobType?.toJson(),
        'purchase_order_number': purchaseOrderNumber,
        'date_request_received': dateRequestReceived?.toIso8601String(),
        'location_details': locationDetails,
        'salesperson_id': salespersonId,
        'supervisor_id': supervisorId,
        'primary_contact_name': primaryContactName,
        'customer_name': customerName,
        'primary_contact_role': primaryContactRole,
        'primary_contact_phone': primaryContactPhone,
        'primary_contact_email': primaryContactEmail,
        'serial_number': finalSerialNumber,
        'customer_location_id': customerLocationId,
        'vendor_subdivision_id': vendorSubdivisionId,
        'custom_fields': customFields ?? <String, dynamic>{},
      };

      AppLogger.info(
        'Creating new project',
        metadata: {
          'name': name,
          'workspaceId': workspaceId,
          'status': status.dbValue,
          'priceType': _priceTypeToDb(priceType ?? PriceType.timeAndMaterial),
          'teamMemberCount': teamMemberIds?.length ?? 0,
          'hasClientId': clientId != null,
          'hasCustomerLocationId': customerLocationId != null,
          'hasVendorSubdivisionId': vendorSubdivisionId != null,
          'serialNumber': finalSerialNumber,
        },
      );

      final response = await _supabase
          .from('projects')
          .insert(projectData)
          .select()
          .single();

      // Add team members to junction table
      if (teamMemberIds != null && teamMemberIds.isNotEmpty) {
        createStep = 'insert_project_team_members';
        final teamEntries = teamMemberIds
            .map((userId) => {'project_id': response['id'], 'user_id': userId})
            .toList();
        await _supabase.from('project_team_members').insert(teamEntries);
      }

      await _ensureCostPlusFeeLine(response['id'] as String, workspaceId);

      AppLogger.info(
        'Project created successfully',
        metadata: {'projectId': response['id']},
      );

      // Fire-and-forget: automations (e.g. preload a schedule template) must
      // never fail project creation; _processEvent logs its own failures.
      unawaited(SupabaseAutomationService().processProjectCreated(
        workspaceId: workspaceId,
        projectId: response['id'] as String,
        projectName: name,
        actorUserId: _supabase.auth.currentUser?.id ?? 'system',
      ));

      return Project.fromJson(_toFirestoreFormat(response), response['id']);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to create project',
        error: e,
        stackTrace: stackTrace,
        metadata: {
          'name': name,
          'workspaceId': workspaceId,
          'step': createStep,
          'teamMemberCount': teamMemberIds?.length ?? 0,
          'clientId': clientId,
          'customerLocationId': customerLocationId,
          'vendorSubdivisionId': vendorSubdivisionId,
        },
      );
      if (e is UserFacingException) rethrow;
      throw Exception('Error creating project during $createStep: $e');
    }
  }

  /// Sentinel stored in `budget_items.source_line_item_id` to identify the
  /// auto-managed Cost-Plus fixed-fee line (so it can be found/synced/removed
  /// without fragile name matching).
  static const String _costPlusFeeMarker = '__cost_plus_fee__';

  /// Keep a cost-plus FIXED-FEE job's flat fee represented as a real budget
  /// line, so every revenue surface (which sums `approved_price`) reports
  /// `Σcost + fee`. Percentage jobs are handled per-line in
  /// `BudgetService._applyCostPlusPricing`; a flat fee can't be a per-line
  /// markup, so it lives on a dedicated managed line. [M001-ff]
  ///
  /// Upserts the line for fixed-fee jobs (syncing the amount to
  /// `cost_plus_value`), and removes it when a job is not (or no longer)
  /// cost-plus fixed-fee. Best-effort: never blocks the project save.
  Future<void> _ensureCostPlusFeeLine(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final p = await _supabase
          .from('projects')
          .select('price_type, cost_plus_type, cost_plus_value')
          .eq('id', projectId)
          .maybeSingle();
      final isFixedFee = p != null &&
          p['price_type'] == 'cost_plus' &&
          p['cost_plus_type'] == 'fixed_fee';
      final existing = await _supabase
          .from('budget_items')
          .select('id')
          .eq('project_id', projectId)
          .eq('source_line_item_id', _costPlusFeeMarker)
          .maybeSingle();

      if (!isFixedFee) {
        if (existing != null) {
          await _supabase
              .from('budget_items')
              .delete()
              .eq('id', existing['id']);
        }
        return;
      }

      final fee = (p['cost_plus_value'] as num?)?.toDouble() ?? 0.0;
      final now = DateTime.now().toIso8601String();
      if (existing == null) {
        await _supabase.from('budget_items').insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'item_type': 'item',
          'name': 'Cost-Plus Fee',
          'source_type': 'base',
          'source_line_item_id': _costPlusFeeMarker,
          'quantity': 1,
          'unit_cost': 0,
          'unit_price': fee,
          'markup': 0,
          'projected_cost': 0,
          'approved_price': fee,
          'hierarchy_level': 0,
          'sort_order': 9999,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await _supabase.from('budget_items').update({
          'unit_price': fee,
          'approved_price': fee,
          'updated_at': now,
        }).eq('id', existing['id']);
      }
    } catch (e) {
      AppLogger.error(
        'Failed to sync cost-plus fee line',
        error: e,
        metadata: {'projectId': projectId},
      );
    }
  }

  /// Update an existing project
  Future<void> updateProject({
    required String projectId,
    String? name,
    String? address,
    ProjectStatus? status,
    String? clientId,
    double? estimatedBudget,
    double? materialMarkupPercent,
    double? laborMarkupPercent,
    DateTime? startDate,
    DateTime? targetCompletionDate,
    PriceType? priceType,
    double? contractAmount,
    CostPlusType? costPlusType,
    double? costPlusValue,
    String? description,
    String? projectManagerId,
    double? latitude,
    double? longitude,
    int? geofenceRadiusMeters,
    bool? requireGeofenceValidation,
    bool? allowClockInOutsideGeofence,
    String? photoUrl,
    JobType? jobType,
    String? purchaseOrderNumber,
    DateTime? dateRequestReceived,
    String? locationDetails,
    String? salespersonId,
    String? supervisorId,
    String? primaryContactName,
    String? customerName,
    String? primaryContactRole,
    String? primaryContactPhone,
    String? primaryContactEmail,
    String? serialNumber,
    String? customerLocationId,
    String? vendorSubdivisionId,
    List<String>? teamMemberIds,
    Map<String, dynamic>? customFields,
    Set<ProjectUpdateField> clearFields = const <ProjectUpdateField>{},
  }) async {
    try {
      final existingProject = await _supabase
          .from('projects')
          .select(
            'id, workspace_id, name, status, target_completion_date, project_manager_id',
          )
          .eq('id', projectId)
          .maybeSingle();
      if (existingProject == null) {
        throw Exception('Project not found');
      }

      final previousTeamRows = await _supabase
          .from('project_team_members')
          .select('user_id')
          .eq('project_id', projectId);
      final previousTeamIds = previousTeamRows
          .map((row) => row['user_id'] as String?)
          .whereType<String>()
          .toSet();

      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      bool shouldClear(ProjectUpdateField field) => clearFields.contains(field);

      void setNullableField(
        String dbField,
        dynamic value,
        ProjectUpdateField field,
      ) {
        if (value != null || shouldClear(field)) {
          updates[dbField] = value;
        }
      }

      if (name != null) updates['name'] = name;
      if (address != null) updates['address'] = address;
      if (status != null) updates['status'] = status.dbValue;
      setNullableField('client_id', clientId, ProjectUpdateField.clientId);
      setNullableField(
        'estimated_budget',
        estimatedBudget,
        ProjectUpdateField.estimatedBudget,
      );
      if (materialMarkupPercent != null) {
        updates['material_markup_percent'] = materialMarkupPercent;
      }
      if (laborMarkupPercent != null) {
        updates['labor_markup_percent'] = laborMarkupPercent;
      }
      setNullableField(
        'start_date',
        startDate?.toIso8601String(),
        ProjectUpdateField.startDate,
      );
      setNullableField(
        'target_completion_date',
        targetCompletionDate?.toIso8601String(),
        ProjectUpdateField.targetCompletionDate,
      );
      if (priceType != null) updates['price_type'] = _priceTypeToDb(priceType);
      setNullableField(
        'contract_amount',
        contractAmount,
        ProjectUpdateField.contractAmount,
      );
      setNullableField(
        'cost_plus_type',
        costPlusType != null ? _costPlusTypeToDb(costPlusType) : null,
        ProjectUpdateField.costPlusType,
      );
      setNullableField(
        'cost_plus_value',
        costPlusValue,
        ProjectUpdateField.costPlusValue,
      );
      setNullableField(
        'description',
        description,
        ProjectUpdateField.description,
      );
      setNullableField(
        'project_manager_id',
        projectManagerId,
        ProjectUpdateField.projectManagerId,
      );
      setNullableField('latitude', latitude, ProjectUpdateField.latitude);
      setNullableField('longitude', longitude, ProjectUpdateField.longitude);
      if (geofenceRadiusMeters != null) {
        updates['geofence_radius_meters'] = geofenceRadiusMeters;
      }
      if (requireGeofenceValidation != null) {
        updates['require_geofence_validation'] = requireGeofenceValidation;
      }
      if (allowClockInOutsideGeofence != null) {
        updates['allow_clock_in_outside_geofence'] = allowClockInOutsideGeofence;
      }
      setNullableField('photo_url', photoUrl, ProjectUpdateField.photoUrl);
      setNullableField(
        'job_type',
        jobType?.toJson(),
        ProjectUpdateField.jobType,
      );
      setNullableField(
        'purchase_order_number',
        purchaseOrderNumber,
        ProjectUpdateField.purchaseOrderNumber,
      );
      setNullableField(
        'date_request_received',
        dateRequestReceived?.toIso8601String(),
        ProjectUpdateField.dateRequestReceived,
      );
      setNullableField(
        'location_details',
        locationDetails,
        ProjectUpdateField.locationDetails,
      );
      setNullableField(
        'salesperson_id',
        salespersonId,
        ProjectUpdateField.salespersonId,
      );
      setNullableField(
        'supervisor_id',
        supervisorId,
        ProjectUpdateField.supervisorId,
      );
      setNullableField(
        'primary_contact_name',
        primaryContactName,
        ProjectUpdateField.primaryContactName,
      );
      setNullableField(
        'customer_name',
        customerName,
        ProjectUpdateField.customerName,
      );
      setNullableField(
        'primary_contact_role',
        primaryContactRole,
        ProjectUpdateField.primaryContactRole,
      );
      setNullableField(
        'primary_contact_phone',
        primaryContactPhone,
        ProjectUpdateField.primaryContactPhone,
      );
      setNullableField(
        'primary_contact_email',
        primaryContactEmail,
        ProjectUpdateField.primaryContactEmail,
      );
      setNullableField(
        'serial_number',
        serialNumber,
        ProjectUpdateField.serialNumber,
      );
      setNullableField(
        'customer_location_id',
        customerLocationId,
        ProjectUpdateField.customerLocationId,
      );
      setNullableField(
        'vendor_subdivision_id',
        vendorSubdivisionId,
        ProjectUpdateField.vendorSubdivisionId,
      );
      // Custom fields use a single full-replace payload (PostgREST cannot
      // jsonb-merge from the client). Lost-update risk under concurrent
      // edits is acknowledged in docs/plans/custom-fields.md; if it bites,
      // add an `update_project_custom_fields(project_id, patch)` RPC.
      if (customFields != null ||
          clearFields.contains(ProjectUpdateField.customFields)) {
        updates['custom_fields'] = customFields ?? <String, dynamic>{};
      }

      await _supabase.from('projects').update(updates).eq('id', projectId);

      await _ensureCostPlusFeeLine(
        projectId,
        existingProject['workspace_id'] as String,
      );

      // Update team members if provided
      if (teamMemberIds != null) {
        // Delete existing team members
        await _supabase
            .from('project_team_members')
            .delete()
            .eq('project_id', projectId);

        // Insert new team members
        if (teamMemberIds.isNotEmpty) {
          final teamEntries = teamMemberIds
              .map((userId) => {'project_id': projectId, 'user_id': userId})
              .toList();
          await _supabase.from('project_team_members').insert(teamEntries);
        }
      }

      await _notifyProjectUpdate(
        projectId: projectId,
        existingProject: existingProject,
        updates: updates,
        previousTeamIds: previousTeamIds,
        newTeamIds: teamMemberIds?.toSet(),
      );
    } catch (e) {
      throw Exception('Error updating project: $e');
    }
  }

  Future<void> _notifyProjectUpdate({
    required String projectId,
    required Map<String, dynamic> existingProject,
    required Map<String, dynamic> updates,
    required Set<String> previousTeamIds,
    required Set<String>? newTeamIds,
  }) async {
    try {
      final oldStatus = existingProject['status'] as String?;
      final newStatus = updates['status'] as String? ?? oldStatus;
      final oldTargetDate =
          existingProject['target_completion_date'] as String?;
      final newTargetDate = updates.containsKey('target_completion_date')
          ? updates['target_completion_date'] as String?
          : oldTargetDate;
      final oldProjectManagerId =
          existingProject['project_manager_id'] as String?;
      final newProjectManagerId = updates.containsKey('project_manager_id')
          ? updates['project_manager_id'] as String?
          : oldProjectManagerId;
      final finalTeamIds = newTeamIds ?? previousTeamIds;

      final statusChanged = oldStatus != newStatus;
      final targetDateChanged = oldTargetDate != newTargetDate;
      final projectManagerChanged = oldProjectManagerId != newProjectManagerId;
      final teamChanged =
          newTeamIds != null && !_sameStringSets(previousTeamIds, newTeamIds);

      if (!statusChanged &&
          !targetDateChanged &&
          !projectManagerChanged &&
          !teamChanged) {
        return;
      }

      final currentUserId = _supabase.auth.currentUser?.id;
      final recipientIds = <String>{
        ...previousTeamIds,
        ...finalTeamIds,
        if (oldProjectManagerId != null && oldProjectManagerId.isNotEmpty)
          oldProjectManagerId,
        if (newProjectManagerId != null && newProjectManagerId.isNotEmpty)
          newProjectManagerId,
      };
      if (currentUserId != null && currentUserId.isNotEmpty) {
        recipientIds.remove(currentUserId);
      }
      if (recipientIds.isEmpty) {
        return;
      }

      final changedUserIds = <String>{
        if (oldProjectManagerId != null && oldProjectManagerId.isNotEmpty)
          oldProjectManagerId,
        if (newProjectManagerId != null && newProjectManagerId.isNotEmpty)
          newProjectManagerId,
        ...previousTeamIds,
        ...finalTeamIds,
      };
      final userNames = await _loadUserNames(changedUserIds);
      final changeParts = <String>[];

      if (statusChanged && newStatus != null && newStatus.isNotEmpty) {
        changeParts.add(
          'Status: ${_displayStatus(oldStatus)} -> ${_displayStatus(newStatus)}',
        );
      }
      if (projectManagerChanged) {
        changeParts.add(
          'PM: ${_userLabel(oldProjectManagerId, userNames)} -> ${_userLabel(newProjectManagerId, userNames)}',
        );
      }
      if (targetDateChanged) {
        changeParts.add(
          'Target: ${_formatDateLabel(oldTargetDate)} -> ${_formatDateLabel(newTargetDate)}',
        );
      }
      if (teamChanged) {
        final changedTeamIds = newTeamIds;
        final added = changedTeamIds.difference(previousTeamIds);
        final removed = previousTeamIds.difference(changedTeamIds);
        final teamParts = <String>[];
        if (added.isNotEmpty) {
          teamParts.add(
            '+${added.map((id) => _userLabel(id, userNames)).join(', ')}',
          );
        }
        if (removed.isNotEmpty) {
          teamParts.add(
            '-${removed.map((id) => _userLabel(id, userNames)).join(', ')}',
          );
        }
        if (teamParts.isNotEmpty) {
          changeParts.add('Team: ${teamParts.join(' / ')}');
        }
      }

      if (changeParts.isEmpty) {
        return;
      }

      final projectName =
          (updates['name'] as String?)?.trim().isNotEmpty == true
          ? (updates['name'] as String).trim()
          : (existingProject['name'] as String?)?.trim() ?? 'Project';

      final title = changeParts.length == 1
          ? _projectUpdateTitle(
              projectName,
              statusChanged,
              projectManagerChanged,
              teamChanged,
              targetDateChanged,
              newStatus,
            )
          : 'Project updated: $projectName';

      final notificationService = SupabaseNotificationService();
      for (final recipientId in recipientIds) {
        await notificationService.createNotification(
          userId: recipientId,
          workspaceId: existingProject['workspace_id'] as String,
          type: AppNotificationTypes.projectUpdate,
          title: title,
          body: changeParts.join(' | '),
          metadata: {
            'target_type': 'project',
            'project_id': projectId,
            'deeplink_path': '/projects/$projectId',
          },
          dispatchPush: false,
        );
      }
    } catch (e) {
      AppLogger.warning(
        'Failed to create project update notifications',
        metadata: {'projectId': projectId, 'error': e.toString()},
      );
    }
  }

  Future<Map<String, String>> _loadUserNames(Set<String> userIds) async {
    if (userIds.isEmpty) return const {};

    try {
      final rows = await _supabase
          .from('users')
          .select('id, display_name, email')
          .inFilter('id', userIds.toList());
      final names = <String, String>{};
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final displayName = (row['display_name'] as String?)?.trim();
        final email = (row['email'] as String?)?.trim();
        names[id] = (displayName != null && displayName.isNotEmpty)
            ? displayName
            : (email != null && email.isNotEmpty ? email : 'Unknown user');
      }
      return names;
    } catch (_) {
      return const {};
    }
  }

  bool _sameStringSets(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  String _projectUpdateTitle(
    String projectName,
    bool statusChanged,
    bool projectManagerChanged,
    bool teamChanged,
    bool targetDateChanged,
    String? newStatus,
  ) {
    if (statusChanged && newStatus != null && newStatus.isNotEmpty) {
      return '$projectName moved to ${_displayStatus(newStatus)}';
    }
    if (projectManagerChanged) {
      return 'Project manager updated for $projectName';
    }
    if (teamChanged) {
      return 'Project team updated for $projectName';
    }
    if (targetDateChanged) {
      return 'Target completion changed for $projectName';
    }
    return 'Project updated: $projectName';
  }

  String _displayStatus(String? status) {
    if (status == null || status.isEmpty) return 'Unspecified';
    return ProjectStatus.fromString(status).displayName;
  }

  String _userLabel(String? userId, Map<String, String> userNames) {
    if (userId == null || userId.isEmpty) return 'Unassigned';
    return userNames[userId] ?? 'Unknown user';
  }

  String _formatDateLabel(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'None';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return 'None';
    return '${date.month}/${date.day}/${date.year}';
  }

  /// Update project photo URL
  Future<void> updateProjectPhoto(String projectId, String photoUrl) async {
    try {
      await _supabase
          .from('projects')
          .update({
            'photo_url': photoUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', projectId);
    } catch (e) {
      throw Exception('Error updating project photo: $e');
    }
  }

  /// Delete a project
  Future<void> deleteProject(String projectId) async {
    try {
      await _supabase.from('projects').delete().eq('id', projectId);
    } catch (e) {
      throw Exception('Error deleting project: $e');
    }
  }

  /// Duplicate an existing project
  Future<Project> duplicateProject(String projectId, {String? newName}) async {
    try {
      final original = await getProject(projectId);
      if (original == null) {
        throw Exception('Project not found');
      }

      final duplicateName = newName ?? '${original.name} (Copy)';

      return createProject(
        workspaceId: original.workspaceId,
        name: duplicateName,
        address: original.address,
        status: original.status.isClosed
            ? ProjectStatus.active
            : original.status,
        clientId: original.clientId,
        estimatedBudget: original.estimatedBudget,
        materialMarkupPercent: original.materialMarkupPercent,
        laborMarkupPercent: original.laborMarkupPercent,
        startDate: original.startDate,
        targetCompletionDate: original.targetCompletionDate,
        priceType: original.priceType,
        contractAmount: original.contractAmount,
        costPlusType: original.costPlusType,
        costPlusValue: original.costPlusValue,
        description: original.description,
        projectManagerId: original.projectManagerId,
        latitude: original.latitude,
        longitude: original.longitude,
        photoUrl: original.photoUrl,
        jobType: original.jobType,
        purchaseOrderNumber: original.purchaseOrderNumber,
        dateRequestReceived: original.dateRequestReceived,
        locationDetails: original.locationDetails,
        salespersonId: original.salespersonId,
        supervisorId: original.supervisorId,
        primaryContactName: original.primaryContactName,
        customerName: original.customerName,
        primaryContactRole: original.primaryContactRole,
        primaryContactPhone: original.primaryContactPhone,
        primaryContactEmail: original.primaryContactEmail,
        customerLocationId: original.customerLocationId,
        vendorSubdivisionId: original.vendorSubdivisionId,
        teamMemberIds: original.teamMemberIds,
        customFields: Map<String, dynamic>.from(original.customFields),
      );
    } catch (e) {
      AppLogger.error(
        'Failed to duplicate project',
        error: e,
        metadata: {'projectId': projectId},
      );
      throw Exception('Error duplicating project: $e');
    }
  }

  /// Filter projects by status
  Stream<List<Project>> getProjectsByStatus(
    String workspaceId,
    ProjectStatus status,
  ) {
    return _supabase
        .from('projects')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where((row) => row['status'] == status.dbValue)
              .map(
                (row) => Project.fromJson(_toFirestoreFormat(row), row['id']),
              )
              .toList();
          filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return filtered;
        });
  }

  /// Calculate project progress percentage based on completed tasks
  Future<double> calculateProjectProgress(String projectId) async {
    try {
      final tasks = await _supabase
          .from('tasks')
          .select('is_complete')
          .eq('project_id', projectId);

      if (tasks.isEmpty) return 0.0;

      final totalTasks = tasks.length;
      final completedTasks = tasks
          .where((t) => t['is_complete'] == true)
          .length;

      return (completedTasks / totalTasks) * 100;
    } catch (e) {
      throw Exception('Error calculating project progress: $e');
    }
  }

  /// Get project date range based on task dates
  Future<Map<String, DateTime?>> getProjectDateRange(String projectId) async {
    try {
      final tasks = await _supabase
          .from('tasks')
          .select('start_date, due_date')
          .eq('project_id', projectId);

      if (tasks.isEmpty) {
        return {'start': null, 'end': null};
      }

      DateTime? earliestStart;
      DateTime? latestDue;

      for (final task in tasks) {
        if (task['start_date'] != null) {
          final startDate = DateTime.parse(task['start_date']);
          if (earliestStart == null || startDate.isBefore(earliestStart)) {
            earliestStart = startDate;
          }
        }

        if (task['due_date'] != null) {
          final dueDate = DateTime.parse(task['due_date']);
          if (latestDue == null || dueDate.isAfter(latestDue)) {
            latestDue = dueDate;
          }
        }
      }

      return {'start': earliestStart, 'end': latestDue};
    } catch (e) {
      throw Exception('Error getting project date range: $e');
    }
  }

  // ============================================================================
  // Asset Management Methods
  // ============================================================================

  /// Get all assets assigned to a specific project
  Stream<List<Asset>> getProjectAssets(String projectId, String workspaceId) {
    return _supabase
        .from('assets')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where((row) => row['assigned_to_project_id'] == projectId)
              .map((row) => _assetFromSupabase(row))
              .toList();
          return filtered;
        });
  }

  /// Calculate total asset purchase costs for a project
  Future<double> calculateAssetPurchaseCosts(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final assets = await _supabase
          .from('assets')
          .select('purchase_price')
          .eq('workspace_id', workspaceId)
          .eq('assigned_to_project_id', projectId);

      double total = 0.0;
      for (final asset in assets) {
        if (asset['purchase_price'] != null) {
          total += (asset['purchase_price'] as num).toDouble();
        }
      }

      return total;
    } catch (e) {
      AppLogger.error(
        'Failed to calculate asset purchase costs',
        error: e,
        metadata: {'projectId': projectId},
      );
      return 0.0;
    }
  }

  /// Calculate maintenance costs for assets assigned to a project
  Future<double> calculateAssetMaintenanceCosts(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final assets = await _supabase
          .from('assets')
          .select('id')
          .eq('workspace_id', workspaceId)
          .eq('assigned_to_project_id', projectId);

      if (assets.isEmpty) return 0.0;

      final assetIds = assets.map((a) => a['id'] as String).toList();

      final maintenanceLogs = await _supabase
          .from('maintenance_logs')
          .select('cost')
          .eq('workspace_id', workspaceId)
          .eq('entity_type', 'asset')
          .inFilter('entity_id', assetIds);

      double total = 0.0;
      for (final log in maintenanceLogs) {
        if (log['cost'] != null) {
          total += (log['cost'] as num).toDouble();
        }
      }

      return total;
    } catch (e) {
      AppLogger.error(
        'Failed to calculate asset maintenance costs',
        error: e,
        metadata: {'projectId': projectId},
      );
      return 0.0;
    }
  }

  /// Get total asset costs (purchase + maintenance) for financial reporting
  Future<({double purchase, double maintenance, double total})> getAssetCosts(
    String projectId, [
    Project? project,
  ]) async {
    final resolvedProject = project ?? await getProject(projectId);
    if (resolvedProject == null) {
      return (purchase: 0.0, maintenance: 0.0, total: 0.0);
    }

    final purchase = await calculateAssetPurchaseCosts(
      projectId,
      resolvedProject.workspaceId,
    );
    final maintenance = await calculateAssetMaintenanceCosts(
      projectId,
      resolvedProject.workspaceId,
    );

    return (
      purchase: purchase,
      maintenance: maintenance,
      total: purchase + maintenance,
    );
  }

  // ============================================================================
  // Financial Methods
  // ============================================================================

  /// Calculate total revenue from paid invoices for a project
  Future<double> calculateProjectRevenue(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final invoices = await _supabase
          .from('generated_documents')
          .select('total_price:total_amount, amount_paid, paid_date')
          .inFilter('document_type', collectedRevenueDocumentTypes)
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId)
          // Fully-paid invoices OR open invoices carrying partial payments.
          .or('paid_date.not.is.null,amount_paid.gt.0');

      return sumCollectedRevenueFromRows(invoices);
    } catch (e) {
      AppLogger.error(
        'Failed to calculate project revenue',
        error: e,
        metadata: {'projectId': projectId},
      );
      return 0.0;
    }
  }

  /// Calculate total costs (cost items + asset costs) for a project
  Future<double> calculateProjectCosts(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final costItems = await _supabase
          .from('cost_items')
          .select('total_cost')
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);

      double costItemsTotal = 0.0;
      for (final item in costItems) {
        if (item['total_cost'] != null) {
          costItemsTotal += (item['total_cost'] as num).toDouble();
        }
      }

      final assetCosts = await getAssetCosts(projectId);
      return costItemsTotal + assetCosts.total;
    } catch (e) {
      AppLogger.error(
        'Failed to calculate project costs',
        error: e,
        metadata: {'projectId': projectId},
      );
      return 0.0;
    }
  }

  /// Calculate project financials (revenue, costs, profit)
  Future<({double revenue, double costs, double profit})>
  calculateProjectFinancials(String projectId, String workspaceId) async {
    try {
      final revenue = await calculateProjectRevenue(projectId, workspaceId);
      final costs = await calculateProjectCosts(projectId, workspaceId);
      final profit = revenue - costs;

      return (revenue: revenue, costs: costs, profit: profit);
    } catch (e) {
      AppLogger.error(
        'Failed to calculate project financials',
        error: e,
        metadata: {'projectId': projectId},
      );
      return (revenue: 0.0, costs: 0.0, profit: 0.0);
    }
  }

  /// Get comprehensive financial summary for a project
  Future<ProjectFinancialSummary> getProjectFinancials(
    String projectId, [
    Project? project,
  ]) async {
    try {
      final resolvedProject = project ?? await getProject(projectId);
      if (resolvedProject == null) {
        return ProjectFinancialSummary.fromCalculation(
          approvedPrice: 0,
          collectedSoFar: 0,
          costToComplete: 0,
          budgetItemCount: 0,
          paidInvoiceCount: 0,
          costItemCount: 0,
        );
      }

      // Get approved price from budget items or contract
      final budgetRows = await _supabase
          .from('budget_items')
          .select(
            'id, parent_id, item_type, source_type, change_order_id, '
            'upgrade_status, approved_price, is_complete, final_cost, projected_cost',
          )
          .eq('project_id', projectId)
          .eq('workspace_id', resolvedProject.workspaceId);

      final changeOrderStatuses = <String, String>{};
      if (budgetRows.any((row) => row['source_type'] == 'change_order')) {
        final changeOrders = await _supabase
            .from('generated_documents')
            .select('id, status')
            .eq('project_id', projectId)
            .eq('workspace_id', resolvedProject.workspaceId)
            .eq('document_type', DocumentType.changeOrder.dbValue);
        for (final row in changeOrders) {
          final id = row['id'] as String?;
          final status = row['status'] as String?;
          if (id != null && status != null) {
            changeOrderStatuses[id] = status;
          }
        }
      }

      final eligibleBudgetRows = eligibleBudgetRowsForFinancialSummary(
        budgetRows,
        changeOrderStatuses: changeOrderStatuses,
      );

      double approvedPrice = 0;
      if (eligibleBudgetRows.isNotEmpty) {
        approvedPrice = eligibleBudgetRows.fold<double>(
          0.0,
          (sum, row) =>
              sum + ((row['approved_price'] as num?)?.toDouble() ?? 0.0),
        );
      } else {
        approvedPrice =
            resolvedProject.contractAmount ??
            resolvedProject.estimatedBudget ??
            0;
      }

      // Get collected amount from invoice payments (full and partial).
      final paidInvoices = await _supabase
          .from('generated_documents')
          .select('total_price:total_amount, amount_paid, paid_date')
          .inFilter('document_type', collectedRevenueDocumentTypes)
          .eq('project_id', projectId)
          .eq('workspace_id', resolvedProject.workspaceId)
          .or('paid_date.not.is.null,amount_paid.gt.0');

      final collectedSoFar = sumCollectedRevenueFromRows(paidInvoices);

      // Get cost to complete from budget items or cost items
      double costToComplete = 0;
      var costItemCount = 0;
      if (eligibleBudgetRows.isNotEmpty) {
        costToComplete = sumCostToCompleteFromBudgetRows(eligibleBudgetRows);
      } else {
        final costItems = await _supabase
            .from('cost_items')
            .select('total_cost')
            .eq('project_id', projectId)
            .eq('workspace_id', resolvedProject.workspaceId);

        for (final item in costItems) {
          costToComplete += (item['total_cost'] as num?)?.toDouble() ?? 0;
        }
        costItemCount = costItems.length;
      }

      // Get asset costs
      final assetCosts = await getAssetCosts(projectId, resolvedProject);

      return ProjectFinancialSummary.fromCalculation(
        approvedPrice: approvedPrice,
        collectedSoFar: collectedSoFar,
        costToComplete: costToComplete,
        budgetItemCount: eligibleBudgetRows.length,
        paidInvoiceCount: paidInvoices.length,
        costItemCount: costItemCount,
        assetPurchaseCosts: assetCosts.purchase,
        assetMaintenanceCosts: assetCosts.maintenance,
      );
    } catch (e) {
      AppLogger.error(
        'Failed to get project financials',
        error: e,
        metadata: {'projectId': projectId},
      );
      rethrow;
    }
  }

  /// Convert Supabase row to Asset
  Asset _assetFromSupabase(Map<String, dynamic> data) {
    return Asset(
      id: data['id'] ?? '',
      workspaceId: data['workspace_id'] ?? '',
      name: data['name'] ?? '',
      description: data['description'],
      serialNumber: data['serial_number'],
      qrCode: data['qr_code'],
      status: data['status'] ?? 'available',
      assignedToProjectId: data['assigned_to_project_id'],
      assignedToUserId: data['assigned_to_user_id'],
      purchaseDate: data['purchase_date'] != null
          ? DateTime.parse(data['purchase_date'])
          : null,
      purchasePrice: data['purchase_price']?.toDouble(),
      notes: data['notes'],
    );
  }

  /// Convert ISO date string to Firebase Timestamp
  Timestamp? _toTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is String) {
      return Timestamp.fromDate(DateTime.parse(value));
    }
    return null;
  }

  // ============================================================================
  // Bulk Operations
  // ============================================================================

  /// Bulk update status for multiple projects
  Future<void> bulkUpdateStatus(List<String> ids, ProjectStatus status) async {
    try {
      await _supabase
          .from('projects')
          .update({
            'status': status.dbValue,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .inFilter('id', ids);
      AppLogger.info(
        'Bulk status update',
        metadata: {'count': ids.length, 'status': status.dbValue},
      );
    } catch (e) {
      AppLogger.error('Failed to bulk update status', error: e);
      throw Exception('Error bulk updating status: $e');
    }
  }

  /// Bulk reassign project manager for multiple projects
  Future<void> bulkReassignPM(List<String> ids, String pmId) async {
    try {
      await _supabase
          .from('projects')
          .update({
            'project_manager_id': pmId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .inFilter('id', ids);
      AppLogger.info(
        'Bulk PM reassign',
        metadata: {'count': ids.length, 'pmId': pmId},
      );
    } catch (e) {
      AppLogger.error('Failed to bulk reassign PM', error: e);
      throw Exception('Error bulk reassigning PM: $e');
    }
  }

  /// Bulk delete multiple projects
  Future<void> bulkDelete(List<String> ids) async {
    try {
      await _supabase.from('projects').delete().inFilter('id', ids);
      AppLogger.info('Bulk delete', metadata: {'count': ids.length});
    } catch (e) {
      AppLogger.error('Failed to bulk delete', error: e);
      throw Exception('Error bulk deleting projects: $e');
    }
  }

  /// Fetch team member IDs for a list of projects, returned as a map.
  Future<Map<String, List<String>>> _fetchTeamMemberMap(
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) return {};
    final teamRows = await _supabase
        .from('project_team_members')
        .select('project_id, user_id')
        .inFilter('project_id', projectIds);
    final map = <String, List<String>>{};
    for (final row in teamRows) {
      final pid = row['project_id'] as String;
      map.putIfAbsent(pid, () => []).add(row['user_id'] as String);
    }
    return map;
  }

  /// Convert PostgreSQL snake_case to Firestore camelCase for model compatibility
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> data) {
    return {
      'id': data['id'],
      'workspaceId': data['workspace_id'],
      'name': data['name'],
      'address': data['address'],
      'status': data['status'],
      'clientId': data['client_id'],
      'estimatedBudget': data['estimated_budget'],
      'materialMarkupPercent': data['material_markup_percent'],
      'laborMarkupPercent': data['labor_markup_percent'],
      'startDate': _toTimestamp(data['start_date']),
      'targetCompletionDate': _toTimestamp(data['target_completion_date']),
      'createdAt': _toTimestamp(data['created_at']),
      'updatedAt': _toTimestamp(data['updated_at']),
      'priceType': data['price_type'],
      'contractAmount': data['contract_amount'],
      'costPlusType': data['cost_plus_type'],
      'costPlusValue': data['cost_plus_value'],
      'description': data['description'],
      'projectManagerId': data['project_manager_id'],
      'latitude': data['latitude'],
      'longitude': data['longitude'],
      'geofenceRadiusMeters': data['geofence_radius_meters'],
      'requireGeofenceValidation': data['require_geofence_validation'],
      'allowClockInOutsideGeofence': data['allow_clock_in_outside_geofence'],
      'photoUrl': data['photo_url'],
      'jobType': data['job_type'],
      'purchaseOrderNumber': data['purchase_order_number'],
      'dateRequestReceived': _toTimestamp(data['date_request_received']),
      'locationDetails': data['location_details'],
      'salespersonId': data['salesperson_id'],
      'supervisorId': data['supervisor_id'],
      'primaryContactName': data['primary_contact_name'],
      'customerName': data['customer_name'],
      'primaryContactRole': data['primary_contact_role'],
      'primaryContactPhone': data['primary_contact_phone'],
      'primaryContactEmail': data['primary_contact_email'],
      'serialNumber': data['serial_number'],
      'customerLocationId': data['customer_location_id'],
      'vendorSubdivisionId': data['vendor_subdivision_id'],
      'holdbackDefaultPercent': data['holdback_default_percent'],
      'teamMemberIds': data['project_team_members'] is List
          ? (data['project_team_members'] as List)
                .map((e) => e['user_id'] as String)
                .toList()
          : (data['team_member_ids'] as List?)?.cast<String>() ?? [],
      // Postgres returns jsonb as a Map already; default to empty when the
      // column is absent (e.g. pre-migration test fixtures).
      'customFields':
          (data['custom_fields'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
    };
  }
}
