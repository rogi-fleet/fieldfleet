import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/asset.dart';
import 'asset_event_service.dart';

/// Supabase implementation of AssetService
class SupabaseAssetService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseAssetEventService _events = SupabaseAssetEventService();
  final String workspaceId;

  SupabaseAssetService({required this.workspaceId});

  /// Get all assets for a workspace as a stream
  Stream<List<Asset>> getAssets() {
    // Guard against an unhydrated workspace id — firing
    // `workspace_id=eq.` (empty) makes PostgREST return 400 invalid uuid.
    if (workspaceId.isEmpty) {
      return Stream<List<Asset>>.value(const []);
    }
    return _supabase
        .from('assets')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          return data.map((row) => _toAsset(row)).toList();
        });
  }

  /// Add a new asset
  Future<Asset> addAsset(Asset asset) async {
    final response = await _supabase.from('assets').insert({
      'workspace_id': workspaceId,
      'name': asset.name,
      'serial_number': asset.serialNumber,
      'qr_code': asset.qrCode,
      'description': asset.description,
      'status': asset.status,
      'assigned_to_project_id': asset.assignedToProjectId,
      'assigned_to_user_id': asset.assignedToUserId,
      'purchase_date': asset.purchaseDate?.toIso8601String(),
      'purchase_price': asset.purchasePrice,
      'notes': asset.notes,
      'photo_urls': asset.photoUrls,
      'category': asset.category,
      'location': asset.location,
      'tags': asset.tags,
      'is_leasable': asset.isLeasable,
      'daily_rental_rate': asset.dailyRentalRate,
      'weekly_rental_rate': asset.weeklyRentalRate,
      'monthly_rental_rate': asset.monthlyRentalRate,
      'replacement_cost': asset.replacementCost,
      'area_id': asset.areaId,
      'position_x': asset.positionX,
      'position_y': asset.positionY,
    }).select().single();

    final created = _toAsset(response);
    await _events.record(created.id, 'created', payload: {'name': created.name});
    return created;
  }

  /// Targeted leasing-only update: flips `is_leasable` true and writes
  /// the rates without touching any other column. Used by the equipment
  /// rental form when the user picks an asset that hadn't been flagged
  /// for rental yet — avoids clobbering unrelated fields that another
  /// user may have edited since this client loaded the asset.
  Future<void> promoteToLeasable(
    String assetId, {
    double? dailyRentalRate,
    double? weeklyRentalRate,
    double? monthlyRentalRate,
  }) async {
    final patch = <String, dynamic>{'is_leasable': true};
    if (dailyRentalRate != null) patch['daily_rental_rate'] = dailyRentalRate;
    if (weeklyRentalRate != null) patch['weekly_rental_rate'] = weeklyRentalRate;
    if (monthlyRentalRate != null) {
      patch['monthly_rental_rate'] = monthlyRentalRate;
    }
    await _supabase
        .from('assets')
        .update(patch)
        .eq('id', assetId)
        .eq('workspace_id', workspaceId);
    await _events.record(assetId, 'leasing_enabled', payload: patch);
  }

  /// Update an existing asset. Diffs against the prior row so the audit
  /// timeline can show specific events (renamed, status_changed, etc.)
  /// rather than a generic "updated".
  Future<void> updateAsset(Asset asset) async {
    final before = await getAsset(asset.id);
    await _supabase.from('assets').update({
      'name': asset.name,
      'serial_number': asset.serialNumber,
      'qr_code': asset.qrCode,
      'description': asset.description,
      'status': asset.status,
      'assigned_to_project_id': asset.assignedToProjectId,
      'assigned_to_user_id': asset.assignedToUserId,
      'purchase_date': asset.purchaseDate?.toIso8601String(),
      'purchase_price': asset.purchasePrice,
      'notes': asset.notes,
      'photo_urls': asset.photoUrls,
      'category': asset.category,
      'location': asset.location,
      'tags': asset.tags,
      'is_leasable': asset.isLeasable,
      'daily_rental_rate': asset.dailyRentalRate,
      'weekly_rental_rate': asset.weeklyRentalRate,
      'monthly_rental_rate': asset.monthlyRentalRate,
      'replacement_cost': asset.replacementCost,
      'area_id': asset.areaId,
      'position_x': asset.positionX,
      'position_y': asset.positionY,
    }).eq('id', asset.id);

    if (before != null) {
      await _emitDiffEvents(before, asset);
    }
  }

  Future<void> _emitDiffEvents(Asset before, Asset after) async {
    if (before.name != after.name) {
      await _events.record(after.id, 'renamed', payload: {
        'from': before.name,
        'to': after.name,
      });
    }
    if (before.status != after.status) {
      // Special-case retire/restore so the timeline reads naturally.
      if (after.status == 'retired') {
        await _events.record(after.id, 'retired');
      } else if (before.status == 'retired') {
        await _events.record(after.id, 'restored', payload: {
          'status': after.status,
        });
      } else {
        await _events.record(after.id, 'status_changed', payload: {
          'from': before.status,
          'to': after.status,
        });
      }
    }
    if (before.category != after.category) {
      await _events.record(after.id, 'category_changed', payload: {
        'from': before.category,
        'to': after.category,
      });
    }
    if (before.location != after.location) {
      await _events.record(after.id, 'location_changed', payload: {
        'from': before.location,
        'to': after.location,
      });
    }
    final beforeTags = before.tags.toSet();
    final afterTags = after.tags.toSet();
    for (final added in afterTags.difference(beforeTags)) {
      await _events.record(after.id, 'tag_added', payload: {'tag': added});
    }
    for (final removed in beforeTags.difference(afterTags)) {
      await _events.record(after.id, 'tag_removed', payload: {'tag': removed});
    }
    final beforePhotos = before.photoUrls.toSet();
    final afterPhotos = after.photoUrls.toSet();
    final addedPhotos = afterPhotos.difference(beforePhotos).length;
    final removedPhotos = beforePhotos.difference(afterPhotos).length;
    if (addedPhotos > 0) {
      await _events.record(after.id, 'photo_added', payload: {
        'count': addedPhotos,
      });
    }
    if (removedPhotos > 0) {
      await _events.record(after.id, 'photo_removed', payload: {
        'count': removedPhotos,
      });
    }
    if (before.assignedToProjectId != after.assignedToProjectId ||
        before.assignedToUserId != after.assignedToUserId) {
      if ((after.assignedToProjectId ?? '').isNotEmpty) {
        await _events.record(after.id, 'assigned_project', payload: {
          'project_id': after.assignedToProjectId,
        });
      } else if ((after.assignedToUserId ?? '').isNotEmpty) {
        await _events.record(after.id, 'assigned_user', payload: {
          'user_id': after.assignedToUserId,
        });
      } else {
        await _events.record(after.id, 'unassigned');
      }
    }
  }

  /// Distinct tag values used across the workspace, lowercase, sorted.
  /// Powers the form's "suggested tags" affordance so users converge on
  /// a small shared vocabulary instead of inventing variants.
  Future<List<String>> getDistinctTags() async {
    final rows = await _supabase
        .from('assets')
        .select('tags')
        .eq('workspace_id', workspaceId);
    final set = <String>{};
    for (final row in rows as List) {
      final tags = (row['tags'] as List<dynamic>?)?.cast<String>() ?? const [];
      set.addAll(tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Replace the photo list without overwriting other unsaved fields.
  /// Records a photo_added / photo_removed event sized by the diff.
  Future<void> updateAssetPhotos(
    String assetId,
    List<String> photoUrls,
  ) async {
    final before = await getAsset(assetId);
    await _supabase
        .from('assets')
        .update({'photo_urls': photoUrls})
        .eq('id', assetId);

    if (before != null) {
      final beforeSet = before.photoUrls.toSet();
      final afterSet = photoUrls.toSet();
      final added = afterSet.difference(beforeSet).length;
      final removed = beforeSet.difference(afterSet).length;
      if (added > 0) {
        await _events.record(assetId, 'photo_added', payload: {'count': added});
      }
      if (removed > 0) {
        await _events.record(
          assetId,
          'photo_removed',
          payload: {'count': removed},
        );
      }
    }
  }

  /// Bulk-update status for multiple assets in one round-trip.
  Future<void> bulkUpdateStatus(List<String> assetIds, String status) async {
    if (assetIds.isEmpty) return;
    await _supabase
        .from('assets')
        .update({'status': status})
        .inFilter('id', assetIds);
    final action = status == 'retired' ? 'retired' : 'status_changed';
    await Future.wait(
      assetIds.map(
        (id) => _events.record(
          id,
          action,
          payload: action == 'status_changed' ? {'to': status} : null,
        ),
      ),
    );
  }

  /// Bulk-assign multiple assets to one project. Clears any user
  /// assignment and flips status to 'assigned' to match the single-asset
  /// behavior in [assignAssetToProject].
  Future<void> bulkAssignToProject(
    List<String> assetIds,
    String projectId,
  ) async {
    if (assetIds.isEmpty) return;
    await _supabase
        .from('assets')
        .update({
          'assigned_to_project_id': projectId,
          'assigned_to_user_id': null,
          'status': 'assigned',
        })
        .inFilter('id', assetIds);
    await Future.wait(
      assetIds.map(
        (id) => _events.record(
          id,
          'assigned_project',
          payload: {'project_id': projectId},
        ),
      ),
    );
  }

  /// Bulk-unassign — frees both project and user assignment, status →
  /// 'available'.
  Future<void> bulkUnassign(List<String> assetIds) async {
    if (assetIds.isEmpty) return;
    await _supabase
        .from('assets')
        .update({
          'assigned_to_project_id': null,
          'assigned_to_user_id': null,
          'status': 'available',
        })
        .inFilter('id', assetIds);
    await Future.wait(
      assetIds.map((id) => _events.record(id, 'unassigned')),
    );
  }

  /// Bulk-delete. Caller is responsible for confirmation UX. Asset
  /// events are wiped via ON DELETE CASCADE — no point recording a
  /// `deleted` event the caller can't see anymore.
  Future<void> bulkDelete(List<String> assetIds) async {
    if (assetIds.isEmpty) return;
    await _supabase.from('assets').delete().inFilter('id', assetIds);
  }

  /// Delete an asset. Audit row is wiped by ON DELETE CASCADE.
  Future<void> deleteAsset(String assetId) async {
    await _supabase.from('assets').delete().eq('id', assetId);
  }

  /// Assign asset to a project
  Future<void> assignAssetToProject(String assetId, String projectId) async {
    await _supabase.from('assets').update({
      'assigned_to_project_id': projectId,
      'assigned_to_user_id': null,
      'status': 'assigned',
    }).eq('id', assetId);
    await _events.record(
      assetId,
      'assigned_project',
      payload: {'project_id': projectId},
    );
  }

  /// Assign asset to a user
  Future<void> assignAssetToUser(String assetId, String userId) async {
    await _supabase.from('assets').update({
      'assigned_to_user_id': userId,
      'assigned_to_project_id': null,
      'status': 'assigned',
    }).eq('id', assetId);
    await _events.record(
      assetId,
      'assigned_user',
      payload: {'user_id': userId},
    );
  }

  /// Unassign asset
  Future<void> unassignAsset(String assetId) async {
    await _supabase.from('assets').update({
      'assigned_to_project_id': null,
      'assigned_to_user_id': null,
      'status': 'available',
    }).eq('id', assetId);
    await _events.record(assetId, 'unassigned');
  }

  /// Stream a single asset by ID. RLS scopes to the caller's workspace,
  /// so we only need the id filter — payload is one row instead of the
  /// full workspace list.
  Stream<Asset?> streamAsset(String assetId) {
    return _supabase
        .from('assets')
        .stream(primaryKey: ['id'])
        .eq('id', assetId)
        .map((data) => data.isEmpty ? null : _toAsset(data.first));
  }

  /// Get a single asset by ID
  Future<Asset?> getAsset(String assetId) async {
    final response = await _supabase
        .from('assets')
        .select()
        .eq('id', assetId)
        .maybeSingle();

    if (response == null) return null;
    return _toAsset(response);
  }

  /// Get assets by status
  Stream<List<Asset>> getAssetsByStatus(String status) {
    return _supabase
        .from('assets')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          return data
              .where((row) => row['status'] == status)
              .map((row) => _toAsset(row))
              .toList();
        });
  }

  /// Get assets assigned to a project
  Stream<List<Asset>> getProjectAssets(String projectId) {
    return _supabase
        .from('assets')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          return data
              .where((row) => row['assigned_to_project_id'] == projectId)
              .map((row) => _toAsset(row))
              .toList();
        });
  }

  /// Convert database row to Asset
  Asset _toAsset(Map<String, dynamic> row) {
    return Asset(
      id: row['id'],
      workspaceId: row['workspace_id'],
      name: row['name'],
      serialNumber: row['serial_number'],
      qrCode: row['qr_code'],
      description: row['description'],
      status: row['status'] ?? 'available',
      assignedToProjectId: row['assigned_to_project_id'],
      assignedToUserId: row['assigned_to_user_id'],
      purchaseDate: row['purchase_date'] != null
          ? DateTime.parse(row['purchase_date'])
          : null,
      purchasePrice: row['purchase_price']?.toDouble(),
      notes: row['notes'],
      photoUrls:
          (row['photo_urls'] as List<dynamic>?)?.cast<String>() ?? const [],
      category: row['category'] as String? ?? 'other',
      location: row['location'] as String?,
      tags: (row['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      isLeasable: row['is_leasable'] as bool? ?? false,
      dailyRentalRate: (row['daily_rental_rate'] as num?)?.toDouble(),
      weeklyRentalRate: (row['weekly_rental_rate'] as num?)?.toDouble(),
      monthlyRentalRate: (row['monthly_rental_rate'] as num?)?.toDouble(),
      replacementCost: (row['replacement_cost'] as num?)?.toDouble(),
      areaId: row['area_id'] as String?,
      positionX: (row['position_x'] as num?)?.toDouble(),
      positionY: (row['position_y'] as num?)?.toDouble(),
    );
  }

  /// Place an asset inside a room at a normalized 0..1 coordinate on the
  /// room sketch. Pass `areaId: null` to remove the placement.
  Future<void> setPlacement(
    String assetId, {
    required String? areaId,
    double? positionX,
    double? positionY,
  }) async {
    await _supabase.from('assets').update({
      'area_id': areaId,
      'position_x': areaId == null ? null : positionX,
      'position_y': areaId == null ? null : positionY,
    }).eq('id', assetId).eq('workspace_id', workspaceId);
    await _events.record(
      assetId,
      areaId == null ? 'unplaced_from_room' : 'placed_in_room',
      payload: areaId == null
          ? null
          : {'area_id': areaId, 'x': positionX, 'y': positionY},
    );
  }

  /// Get all assets currently placed in a given area (one-shot).
  Future<List<Asset>> getAssetsForArea(String areaId) async {
    final rows = await _supabase
        .from('assets')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('area_id', areaId);
    return (rows as List).map((r) => _toAsset(r as Map<String, dynamic>)).toList();
  }

  /// Stream of leasable assets only — used to populate the equipment
  /// rental picker on jobs.
  Stream<List<Asset>> getLeasableAssets() {
    return _supabase
        .from('assets')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) => data
            .where((row) => row['is_leasable'] == true)
            .map((row) => _toAsset(row))
            .toList());
  }
}
