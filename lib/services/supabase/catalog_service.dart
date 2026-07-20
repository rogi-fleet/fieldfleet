import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/catalog/catalog_bundle_component.dart';
import '../../models/catalog/catalog_kind.dart';
import '../../models/catalog/catalog_price_tier.dart';
import '../../models/catalog_item.dart';
import '../../models/budget_item.dart';

/// Supabase implementation of CatalogService
class SupabaseCatalogService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  static const int _catalogWriteBatchSize = 200;

  /// Extract a catalog item draft from a supplier product-page URL via the
  /// `catalog-web-import` edge function (JSON-LD/meta first, AI fallback).
  /// Returns the raw extracted map: name, description, price, unit, sku,
  /// image_url, source_url, plus the `extraction_source` tier.
  Future<Map<String, dynamic>> importFromWeb({
    required String workspaceId,
    required String url,
  }) async {
    final response = await _supabase.functions.invoke(
      'catalog-web-import',
      body: {'workspace_id': workspaceId, 'url': url},
    );
    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw Exception(
        (data is Map ? data['error'] as String? : null) ??
            'Could not import from that URL',
      );
    }
    final item = Map<String, dynamic>.from(data['item'] as Map);
    item['extraction_source'] = data['source'];
    return item;
  }

  /// Get all catalog items for a workspace
  Stream<List<CatalogItem>> getCatalogItems(String workspaceId) {
    return _supabase
        .from('catalog_items')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('sort_order')
        .order('name')
        .map((data) {
          return data.map((row) => _toCatalogItem(row)).toList();
        });
  }

  /// Get catalog items (one-time fetch)
  Future<List<CatalogItem>> getCatalogItemsOnce(String workspaceId) async {
    try {
      final response = await _supabase
          .from('catalog_items')
          .select()
          .eq('workspace_id', workspaceId)
          .order('sort_order')
          .order('name');

      return response.map((row) => _toCatalogItem(row)).toList();
    } catch (e) {
      throw Exception('Error fetching catalog items: $e');
    }
  }

  /// Get a single catalog item
  Future<CatalogItem?> getCatalogItem(String itemId) async {
    try {
      final response = await _supabase
          .from('catalog_items')
          .select()
          .eq('id', itemId)
          .maybeSingle();

      if (response == null) return null;
      return _toCatalogItem(response);
    } catch (e) {
      throw Exception('Error fetching catalog item: $e');
    }
  }

  /// Update specific fields of a catalog item (for inline editing)
  Future<void> updateCatalogItemField(
    String itemId,
    Map<String, dynamic> fields,
  ) async {
    final snakeFields = <String, dynamic>{};
    fields.forEach((key, value) {
      snakeFields[_camelToSnake(key)] = value;
    });
    snakeFields['updated_at'] = DateTime.now().toIso8601String();
    await _supabase.from('catalog_items').update(snakeFields).eq('id', itemId);
  }

  /// Add a new catalog item
  Future<CatalogItem> addCatalogItem(
    String workspaceId,
    CatalogItem item,
  ) async {
    try {
      if (item.hierarchyLevel > 2) {
        throw Exception('Maximum hierarchy depth is 3 levels (0-2)');
      }
      final itemData = _toSupabaseFormat(item);
      itemData['workspace_id'] = workspaceId;

      final response = await _supabase
          .from('catalog_items')
          .insert(itemData)
          .select()
          .single();

      return _toCatalogItem(response);
    } catch (e) {
      throw Exception('Error adding catalog item: $e');
    }
  }

  /// Create a new catalog item (alternative method matching budget service pattern)
  Future<void> createCatalogItem(CatalogItem item) async {
    try {
      if (item.hierarchyLevel > 2) {
        throw Exception('Maximum hierarchy depth is 3 levels (0-2)');
      }
      final itemData = _toSupabaseFormat(item);
      await _supabase.from('catalog_items').insert(itemData);
    } catch (e) {
      throw Exception('Error creating catalog item: $e');
    }
  }

  /// Update a catalog item
  Future<void> updateCatalogItem(String workspaceId, CatalogItem item) async {
    try {
      final itemData = _toSupabaseFormat(item);
      itemData['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('catalog_items').update(itemData).eq('id', item.id);
    } catch (e) {
      throw Exception('Error updating catalog item: $e');
    }
  }

  /// Result of cascading catalog field overrides into open-job budget items.
  /// See [cascadeUpdatesToOpenJobs] / `catalog_cascade_to_open_jobs` RPC.

  /// Update multiple catalog items sequentially.
  Future<void> updateCatalogItems(
    String workspaceId,
    List<CatalogItem> items,
  ) async {
    try {
      await _upsertCatalogItems(items);
    } catch (e) {
      throw Exception('Error updating catalog items: $e');
    }
  }

  /// Cascade a set of catalog field overrides into matching `budget_items`
  /// on every open project (status active / on_hold / awarded) in the
  /// workspace. Approved (contracted) budget items are skipped server-side
  /// so contracted pricing is never silently overwritten.
  ///
  /// Returns a record of how many budget items and distinct projects were
  /// touched so the UI can confirm the blast radius to the user.
  Future<CatalogCascadeResult> cascadeUpdatesToOpenJobs({
    required String workspaceId,
    required List<String> catalogItemIds,
    required Map<String, dynamic> fieldOverrides,
  }) async {
    if (catalogItemIds.isEmpty || fieldOverrides.isEmpty) {
      return const CatalogCascadeResult(matchedCount: 0, projectCount: 0);
    }
    try {
      final rows = await _supabase.rpc(
        'catalog_cascade_to_open_jobs',
        params: {
          'p_workspace_id': workspaceId,
          'p_catalog_ids': catalogItemIds,
          'p_fields': fieldOverrides,
        },
      ) as List<dynamic>;
      if (rows.isEmpty) {
        return const CatalogCascadeResult(matchedCount: 0, projectCount: 0);
      }
      final row = rows.first as Map<String, dynamic>;
      return CatalogCascadeResult(
        matchedCount: (row['matched_count'] as num?)?.toInt() ?? 0,
        projectCount: (row['project_count'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw Exception('Error cascading catalog changes to open jobs: $e');
    }
  }

  /// Delete a catalog item (and its children due to CASCADE)
  Future<void> deleteCatalogItem(String workspaceId, String itemId) async {
    try {
      await _supabase.from('catalog_items').delete().eq('id', itemId);
    } catch (e) {
      throw Exception('Error deleting catalog item: $e');
    }
  }

  /// Delete multiple catalog items
  Future<void> deleteCatalogItems(
    String workspaceId,
    List<String> itemIds,
  ) async {
    try {
      await _supabase.from('catalog_items').delete().inFilter('id', itemIds);
    } catch (e) {
      throw Exception('Error deleting catalog items: $e');
    }
  }

  /// Get the next sort order for a parent
  Future<int> getNextSortOrder(String workspaceId, String? parentId) async {
    try {
      final query = _supabase
          .from('catalog_items')
          .select('sort_order')
          .eq('workspace_id', workspaceId);

      final response = parentId == null
          ? await query
                .isFilter('parent_id', null)
                .order('sort_order', ascending: false)
                .limit(1)
          : await query
                .eq('parent_id', parentId)
                .order('sort_order', ascending: false)
                .limit(1);

      if (response.isEmpty) return 0;
      return (response.first['sort_order'] as int) + 1;
    } catch (e) {
      return 0;
    }
  }

  /// Reorder items within the same parent.
  Future<void> reorderItems(List<String> orderedItemIds) async {
    try {
      for (var i = 0; i < orderedItemIds.length; i++) {
        await _supabase
            .from('catalog_items')
            .update({
              'sort_order': i,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', orderedItemIds[i]);
      }
    } catch (e) {
      throw Exception('Error reordering catalog items: $e');
    }
  }

  Future<CatalogCsvImportPreview> previewCatalogCsvImport({
    required String workspaceId,
    required String csvContent,
    CatalogCsvImportMode mode = CatalogCsvImportMode.createAndUpdate,
    bool allowHierarchyChanges = false,
    bool skipHierarchyConflicts = false,
  }) async {
    try {
      final parsed = _parseCatalogCsvRows(csvContent);
      final existingItems = await getCatalogItemsOnce(workspaceId);
      final existingById = {for (final item in existingItems) item.id: item};

      var createCount = 0;
      var updateCount = 0;
      var unresolvedParentCount = 0;
      var hierarchyConflictCount = 0;
      var skippedCount = 0;
      var groupCount = 0;
      var itemCount = 0;
      final reportRows = <CatalogCsvReportRow>[];

      final csvIds = parsed.rows
          .map((row) => row.sourceId)
          .whereType<String>()
          .toSet();

      for (final row in parsed.rows) {
        if (row.itemType == CatalogItemType.group) {
          groupCount++;
        } else {
          itemCount++;
        }

        final existingItem = row.sourceId == null
            ? null
            : existingById[row.sourceId];

        final rowContext = _describeRowContext(
          row: row,
          csvIds: csvIds,
          existingById: existingById,
        );
        final rowWarnings = [...rowContext.warnings];
        final desiredParentKey = _previewDesiredParentKey(
          row: row,
          csvIds: csvIds,
          existingById: existingById,
        );
        if (rowContext.hasUnresolvedParent) {
          unresolvedParentCount++;
        }

        final decision = _decideImportAction(
          existingItem: existingItem,
          row: row,
          mode: mode,
          desiredParentKey: desiredParentKey,
          existingById: existingById,
          allowHierarchyChanges: allowHierarchyChanges,
          skipHierarchyConflicts: skipHierarchyConflicts,
        );
        switch (decision.action) {
          case _CatalogCsvImportAction.create:
            createCount++;
            break;
          case _CatalogCsvImportAction.update:
            updateCount++;
            break;
          case _CatalogCsvImportAction.skip:
            skippedCount++;
            break;
          case _CatalogCsvImportAction.conflict:
            hierarchyConflictCount++;
            break;
        }
        if (decision.hasHierarchyConflict &&
            decision.action != _CatalogCsvImportAction.conflict) {
          hierarchyConflictCount++;
        }
        rowWarnings.addAll(decision.warnings);

        reportRows.add(
          CatalogCsvReportRow(
            rowNumber: row.rowNumber,
            sourceId: row.sourceId,
            name: row.name,
            itemType: row.itemType,
            actionLabel: switch (decision.action) {
              _CatalogCsvImportAction.create => 'Create',
              _CatalogCsvImportAction.update => 'Update',
              _CatalogCsvImportAction.skip => 'Skip',
              _CatalogCsvImportAction.conflict => 'Conflict',
            },
            parentSourceId: row.parentSourceId,
            parentLabel: rowContext.parentLabel,
            warnings: rowWarnings,
          ),
        );
      }

      final warnings = <String>[];
      if (unresolvedParentCount > 0) {
        warnings.add(
          '$unresolvedParentCount row${unresolvedParentCount == 1 ? '' : 's'} reference missing parent IDs and will be imported at the root level.',
        );
      }
      if (hierarchyConflictCount > 0) {
        warnings.add(
          '$hierarchyConflictCount existing row${hierarchyConflictCount == 1 ? '' : 's'} would move or change type.${allowHierarchyChanges
              ? ''
              : skipHierarchyConflicts
              ? ' Those rows will be skipped.'
              : ' Enable hierarchy changes or skip conflicts to proceed.'}',
        );
      }
      if (skippedCount > 0) {
        warnings.add(
          '$skippedCount row${skippedCount == 1 ? '' : 's'} will be skipped by the current import rules.',
        );
      }

      return CatalogCsvImportPreview(
        fileHeaders: parsed.headers,
        totalRows: parsed.rows.length,
        createCount: createCount,
        updateCount: updateCount,
        groupCount: groupCount,
        itemCount: itemCount,
        unresolvedParentCount: unresolvedParentCount,
        hierarchyConflictCount: hierarchyConflictCount,
        skippedCount: skippedCount,
        warnings: warnings,
        previewRows: reportRows.take(16).toList(growable: false),
        reportRows: reportRows,
        additionalRowCount: reportRows.length > 16 ? reportRows.length - 16 : 0,
      );
    } catch (e) {
      throw Exception('Error previewing catalog CSV import: $e');
    }
  }

  Future<CatalogCsvImportResult> importCatalogCsv({
    required String workspaceId,
    required String csvContent,
    CatalogCsvImportMode mode = CatalogCsvImportMode.createAndUpdate,
    bool allowHierarchyChanges = false,
    bool skipHierarchyConflicts = false,
  }) async {
    try {
      final parsed = _parseCatalogCsvRows(csvContent);
      final existingItems = await getCatalogItemsOnce(workspaceId);
      final existingByActualId = {
        for (final item in existingItems) item.id: item,
      };
      final importedRowsBySourceId = {
        for (final row in parsed.rows)
          if (row.sourceId != null) row.sourceId!: row,
      };
      final nextSortOrderByParent = _buildNextSortOrderMap(existingItems);
      final importedItemBySourceId = <String, CatalogItem>{};
      final resolvedItemBySourceId = <String, CatalogItem?>{};
      final processedSourceIds = <String>{};
      final visitingSourceIds = <String>{};
      final unresolvedParentRows = <String>{};
      final reportRows = <CatalogCsvReportRow>[];
      final itemsToPersistById = <String, CatalogItem>{};
      final csvIds = importedRowsBySourceId.keys.toSet();

      var createdCount = 0;
      var updatedCount = 0;
      var skippedCount = 0;
      var groupCount = 0;
      var itemCount = 0;

      Future<CatalogItem?> importRow(_CatalogCsvImportRow row) async {
        final sourceId = row.sourceId;
        if (sourceId != null) {
          if (resolvedItemBySourceId.containsKey(sourceId)) {
            return resolvedItemBySourceId[sourceId];
          }
          final existingImported = importedItemBySourceId[sourceId];
          if (existingImported != null) return existingImported;
          if (!visitingSourceIds.add(sourceId)) {
            throw Exception(
              'Cycle detected in catalog CSV hierarchy at ID $sourceId',
            );
          }
        }

        CatalogItem? resolvedParentItem;
        if (row.parentSourceId != null) {
          final parentSourceId = row.parentSourceId!;
          final importedParent = importedItemBySourceId[parentSourceId];
          if (importedParent != null) {
            resolvedParentItem = importedParent;
          } else if (importedRowsBySourceId.containsKey(parentSourceId)) {
            resolvedParentItem = await importRow(
              importedRowsBySourceId[parentSourceId]!,
            );
          } else if (existingByActualId.containsKey(parentSourceId)) {
            resolvedParentItem = existingByActualId[parentSourceId];
          } else {
            unresolvedParentRows.add(row.rowLabel);
          }
        }

        final resolvedParentId = resolvedParentItem?.id;
        final resolvedHierarchyLevel = resolvedParentItem == null
            ? 0
            : resolvedParentItem.hierarchyLevel + 1;

        final existingItem = sourceId == null
            ? null
            : existingByActualId[sourceId];
        final rowContext = _describeRowContext(
          row: row,
          csvIds: csvIds,
          existingById: existingByActualId,
        );
        final rowWarnings = [...rowContext.warnings];
        final desiredParentKey = _previewDesiredParentKey(
          row: row,
          csvIds: csvIds,
          existingById: existingByActualId,
        );
        final decision = _decideImportAction(
          existingItem: existingItem,
          row: row,
          mode: mode,
          desiredParentKey: desiredParentKey,
          existingById: existingByActualId,
          allowHierarchyChanges: allowHierarchyChanges,
          skipHierarchyConflicts: skipHierarchyConflicts,
        );
        if (decision.action == _CatalogCsvImportAction.conflict) {
          throw Exception(
            'Row ${row.rowNumber} would change hierarchy for "${existingItem?.name ?? row.name}". Enable hierarchy changes or skip conflicts to continue.',
          );
        }
        rowWarnings.addAll(decision.warnings);
        if (decision.action == _CatalogCsvImportAction.skip) {
          skippedCount++;
          reportRows.add(
            CatalogCsvReportRow(
              rowNumber: row.rowNumber,
              sourceId: row.sourceId,
              name: row.name,
              itemType: row.itemType,
              actionLabel: 'Skip',
              parentSourceId: row.parentSourceId,
              parentLabel: rowContext.parentLabel,
              warnings: rowWarnings,
            ),
          );
          if (sourceId != null) {
            final anchor = existingItem;
            resolvedItemBySourceId[sourceId] = anchor;
            processedSourceIds.add(sourceId);
            visitingSourceIds.remove(sourceId);
          }
          return existingItem;
        }

        final resolvedSortOrder = _resolveImportedSortOrder(
          row: row,
          existingItem: existingItem,
          resolvedParentId: resolvedParentId,
          nextSortOrderByParent: nextSortOrderByParent,
        );

        final item = (existingItem ?? _emptyCatalogItem(workspaceId)).copyWith(
          id: existingItem?.id ?? _uuid.v4(),
          name: row.name,
          description: row.description,
          unit: row.itemType == CatalogItemType.group ? null : row.unit,
          unitCost: row.itemType == CatalogItemType.group ? 0.0 : row.unitCost,
          unitPrice: row.itemType == CatalogItemType.group
              ? 0.0
              : row.unitPrice,
          markup: row.itemType == CatalogItemType.group
              ? 0.0
              : row.markup ??
                    CatalogItem.calculateMarkup(row.unitCost, row.unitPrice),
          margin: row.itemType == CatalogItemType.group
              ? 0.0
              : row.margin ??
                    CatalogItem.calculateMargin(row.unitCost, row.unitPrice),
          isTaxable: row.isTaxable,
          costTypeName: row.costTypeName,
          costCodeName: row.costCodeName,
          imageUrl: row.imageUrl,
          category: row.category,
          sku: row.sku,
          createdAt: row.createdAt ?? existingItem?.createdAt ?? DateTime.now(),
          updatedAt: row.updatedAt ?? DateTime.now(),
          parentId: resolvedParentId,
          hierarchyLevel: resolvedHierarchyLevel,
          itemType: row.itemType,
          sortOrder: resolvedSortOrder,
        );

        final importedItem = item;
        itemsToPersistById[importedItem.id] = importedItem;

        if (existingItem == null) {
          createdCount++;
          existingByActualId[importedItem.id] = importedItem;
        } else {
          updatedCount++;
          existingByActualId[existingItem.id] = importedItem;
        }
        if (row.itemType == CatalogItemType.group) {
          groupCount++;
        } else {
          itemCount++;
        }
        reportRows.add(
          CatalogCsvReportRow(
            rowNumber: row.rowNumber,
            sourceId: row.sourceId,
            name: row.name,
            itemType: row.itemType,
            actionLabel: existingItem == null ? 'Create' : 'Update',
            parentSourceId: row.parentSourceId,
            parentLabel: resolvedParentItem == null
                ? 'Root level'
                : resolvedParentItem.name,
            warnings: rowWarnings,
          ),
        );

        if (sourceId != null) {
          importedItemBySourceId[sourceId] = importedItem;
          resolvedItemBySourceId[sourceId] = importedItem;
          processedSourceIds.add(sourceId);
          visitingSourceIds.remove(sourceId);
        }

        return importedItem;
      }

      for (final row in parsed.rows) {
        final sourceId = row.sourceId;
        if (sourceId != null && processedSourceIds.contains(sourceId)) {
          continue;
        }
        await importRow(row);
      }

      await _upsertCatalogItemsForImport(itemsToPersistById.values.toList());

      return CatalogCsvImportResult(
        processedCount: createdCount + updatedCount,
        createdCount: createdCount,
        updatedCount: updatedCount,
        groupCount: groupCount,
        itemCount: itemCount,
        unresolvedParentCount: unresolvedParentRows.length,
        skippedCount: skippedCount,
        reportRows: reportRows,
      );
    } catch (e) {
      throw Exception('Error importing catalog CSV: $e');
    }
  }

  /// Copy budget items to catalog
  Future<void> copyBudgetItemsToCatalog({
    required List<BudgetItem> budgetItems,
    required String workspaceId,
  }) async {
    try {
      if (budgetItems.isEmpty) return;

      final projectIds = budgetItems
          .map((item) => item.projectId)
          .toSet()
          .toList();
      final budgetQuery = _supabase
          .from('budget_items')
          .select()
          .eq('workspace_id', workspaceId);
      final budgetRows = projectIds.length == 1
          ? await budgetQuery.eq('project_id', projectIds.single)
          : await budgetQuery.inFilter('project_id', projectIds);
      final allBudgetItems = budgetRows
          .map((row) => _toBudgetItem(row))
          .toList(growable: false);

      final budgetItemsById = {
        for (final item in allBudgetItems) item.id: item,
      };
      final childrenByParentId = <String?, List<BudgetItem>>{};
      for (final item in allBudgetItems) {
        childrenByParentId
            .putIfAbsent(item.parentId, () => <BudgetItem>[])
            .add(item);
      }
      for (final children in childrenByParentId.values) {
        children.sort((a, b) {
          final sortCompare = a.sortOrder.compareTo(b.sortOrder);
          if (sortCompare != 0) return sortCompare;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      }

      final selectedIds = budgetItems.map((item) => item.id).toSet();
      final rootItems = budgetItems
          .where(
            (item) => !_hasSelectedBudgetAncestor(
              item,
              selectedIds: selectedIds,
              itemsById: budgetItemsById,
            ),
          )
          .toList(growable: false);
      final includedBudgetItems = <BudgetItem>[];
      final includedBudgetItemIds = <String>{};
      for (final rootItem in rootItems) {
        _collectBudgetBranchItems(
          rootItem.id,
          childrenByParentId: childrenByParentId,
          itemsById: budgetItemsById,
          into: includedBudgetItems,
          seenIds: includedBudgetItemIds,
        );
      }
      final categoryNameById = await _loadBudgetCategoryNames(
        workspaceId,
        includedBudgetItems,
      );

      var rootSortOrder = await getNextSortOrder(workspaceId, null);
      for (final rootItem in rootItems) {
        await _insertBudgetBranchIntoCatalog(
          source: rootItem,
          workspaceId: workspaceId,
          targetParentId: null,
          targetHierarchyLevel: 0,
          sortOrder: rootSortOrder++,
          childrenByParentId: childrenByParentId,
          categoryNameById: categoryNameById,
        );
      }
    } catch (e) {
      throw Exception('Error copying budget items to catalog: $e');
    }
  }

  Future<void> _insertBudgetBranchIntoCatalog({
    required BudgetItem source,
    required String workspaceId,
    required String? targetParentId,
    required int targetHierarchyLevel,
    required int sortOrder,
    required Map<String?, List<BudgetItem>> childrenByParentId,
    required Map<String, String> categoryNameById,
  }) async {
    if (targetHierarchyLevel > 2) {
      throw Exception(
        'Cannot export "${source.name}" — exceeds catalog depth limit.',
      );
    }
    final now = DateTime.now().toIso8601String();
    final childItems = childrenByParentId[source.id] ?? const <BudgetItem>[];
    final isGroup = source.itemType == BudgetItemType.group;
    final unitCost = isGroup ? 0.0 : _catalogUnitCostFromBudget(source);
    final unitPrice = isGroup ? 0.0 : _catalogUnitPriceFromBudget(source);
    final markup = isGroup ? 0.0 : source.markup;
    final margin = isGroup
        ? 0.0
        : CatalogItem.calculateMargin(unitCost, unitPrice);

    final response = await _supabase
        .from('catalog_items')
        .insert({
          'workspace_id': workspaceId,
          'name': source.name,
          'description': source.description,
          'unit': isGroup ? null : source.unit,
          'unit_cost': unitCost,
          'unit_price': unitPrice,
          'markup': markup,
          'margin': margin,
          'is_taxable': source.isTaxable,
          'cost_type_name': source.costType?.displayLabel,
          'cost_code_name': null,
          'image_url': null,
          'category': source.categoryId != null
              ? categoryNameById[source.categoryId!]
              : null,
          'sku': null,
          'parent_id': targetParentId,
          'hierarchy_level': targetHierarchyLevel,
          'item_type': isGroup
              ? CatalogItemType.group.name
              : CatalogItemType.item.name,
          'sort_order': sortOrder,
          'created_at': now,
          'updated_at': now,
        })
        .select('id')
        .single();
    final insertedId = response['id'] as String;

    for (var index = 0; index < childItems.length; index++) {
      await _insertBudgetBranchIntoCatalog(
        source: childItems[index],
        workspaceId: workspaceId,
        targetParentId: insertedId,
        targetHierarchyLevel: targetHierarchyLevel + 1,
        sortOrder: index,
        childrenByParentId: childrenByParentId,
        categoryNameById: categoryNameById,
      );
    }
  }

  bool _hasSelectedBudgetAncestor(
    BudgetItem item, {
    required Set<String> selectedIds,
    required Map<String, BudgetItem> itemsById,
  }) {
    var parentId = item.parentId;
    while (parentId != null) {
      if (selectedIds.contains(parentId)) return true;
      parentId = itemsById[parentId]?.parentId;
    }
    return false;
  }

  void _collectBudgetBranchItems(
    String itemId, {
    required Map<String?, List<BudgetItem>> childrenByParentId,
    required Map<String, BudgetItem> itemsById,
    required List<BudgetItem> into,
    required Set<String> seenIds,
  }) {
    if (!seenIds.add(itemId)) return;
    final item = itemsById[itemId];
    if (item == null) return;
    into.add(item);
    for (final child in childrenByParentId[itemId] ?? const <BudgetItem>[]) {
      _collectBudgetBranchItems(
        child.id,
        childrenByParentId: childrenByParentId,
        itemsById: itemsById,
        into: into,
        seenIds: seenIds,
      );
    }
  }

  Future<Map<String, String>> _loadBudgetCategoryNames(
    String workspaceId,
    List<BudgetItem> budgetItems,
  ) async {
    final categoryIds = budgetItems
        .map((item) => item.categoryId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (categoryIds.isEmpty) return const <String, String>{};

    final rows = await _supabase
        .from('cost_categories')
        .select('id,name')
        .eq('workspace_id', workspaceId)
        .inFilter('id', categoryIds);
    return {for (final row in rows) row['id'] as String: row['name'] as String};
  }

  double _catalogUnitCostFromBudget(BudgetItem item) {
    if (item.unitCost > 0) return item.unitCost;
    if (item.quantity > 0 && item.projectedCost > 0) {
      return item.projectedCost / item.quantity;
    }
    // qty=0 or no cost data: store 0 rather than a total that would be
    // misinterpreted as a unit price when the item is reused in a new budget.
    return 0;
  }

  double _catalogUnitPriceFromBudget(BudgetItem item) {
    if (item.unitPrice > 0) return item.unitPrice;
    if (item.quantity > 0 && item.approvedPrice > 0) {
      return item.approvedPrice / item.quantity;
    }
    // qty=0 or no price data: store 0 for the same reason as above.
    return 0;
  }

  BudgetItem _toBudgetItem(Map<String, dynamic> row) {
    final hierarchyLevel = (row['hierarchy_level'] as num?)?.toInt() ?? 0;
    final itemTypeStr = row['item_type'] as String?;
    final sourceTypeStr = row['source_type'] as String?;
    final upgradeStatusStr = row['upgrade_status'] as String?;

    return BudgetItem(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      projectId: row['project_id'] as String,
      parentId: row['parent_id'] as String?,
      hierarchyLevel: hierarchyLevel,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      name: row['name'] as String,
      description: row['description'] as String?,
      categoryId: row['category_id'] as String?,
      quantity: (row['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: row['unit'] as String?,
      unitCost: (row['unit_cost'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0.0,
      markup: (row['markup'] as num?)?.toDouble() ?? 0.0,
      isTaxable: row['is_taxable'] as bool? ?? true,
      approvedPrice: (row['approved_price'] as num?)?.toDouble() ?? 0.0,
      projectedCost: (row['projected_cost'] as num?)?.toDouble() ?? 0.0,
      committedCost: (row['committed_cost'] as num?)?.toDouble() ?? 0.0,
      finalCost: (row['final_cost'] as num?)?.toDouble() ?? 0.0,
      isComplete: row['is_complete'] as bool? ?? false,
      completedDate: row['completed_date'] != null
          ? DateTime.parse(row['completed_date'] as String)
          : null,
      itemType: itemTypeStr == BudgetItemType.group.name
          ? BudgetItemType.group
          : BudgetItemType.item,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
      notes: row['notes'] as String?,
      sourceType: _budgetSourceTypeFromRow(sourceTypeStr),
      changeOrderId: row['change_order_id'] as String?,
      upgradeStatus: _upgradeStatusFromRow(upgradeStatusStr),
      costType: BudgetCostType.fromString(row['cost_type'] as String?),
      holdbackPercent: (row['holdback_percent'] as num?)?.toDouble(),
      holdbackReleased: row['holdback_released'] as bool? ?? false,
      holdbackReleasedDate: row['holdback_released_date'] != null
          ? DateTime.parse(row['holdback_released_date'] as String)
          : null,
    );
  }

  BudgetItemSource _budgetSourceTypeFromRow(String? sourceType) {
    final normalized = sourceType == null
        ? 'base'
        : sourceType.trim().toLowerCase();
    switch (normalized) {
      case 'change_order':
        return BudgetItemSource.changeOrder;
      case 'upgrade':
        return BudgetItemSource.upgrade;
      default:
        return BudgetItemSource.base;
    }
  }

  UpgradeStatus? _upgradeStatusFromRow(String? upgradeStatus) {
    if (upgradeStatus == null) return null;
    switch (upgradeStatus.trim().toLowerCase()) {
      case 'accepted':
        return UpgradeStatus.accepted;
      case 'declined':
        return UpgradeStatus.declined;
      case 'offered':
        return UpgradeStatus.offered;
      default:
        return null;
    }
  }

  _ParsedCatalogCsv _parseCatalogCsvRows(String csvContent) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(csvContent);

    if (rows.isEmpty) {
      throw Exception('CSV file is empty.');
    }

    final headers = rows.first
        .map((value) => value.toString().trim())
        .toList(growable: false);
    final headerIndex = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      headerIndex[_normalizeCsvHeader(headers[i])] = i;
    }

    if (!headerIndex.containsKey('name')) {
      throw Exception('CSV must include a "name" column.');
    }

    final parsedRows = <_CatalogCsvImportRow>[];
    final seenIds = <String>{};

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (_isEmptyCsvRow(row)) continue;

      final sourceId = _csvString(row, headerIndex, 'id');
      if (sourceId != null && !seenIds.add(sourceId)) {
        throw Exception('Duplicate catalog row id "$sourceId" in CSV.');
      }

      final itemType = _csvString(row, headerIndex, 'item_type') == 'group'
          ? CatalogItemType.group
          : CatalogItemType.item;
      final name =
          (_csvString(row, headerIndex, 'name')) ??
          (itemType == CatalogItemType.group
              ? 'Untitled group'
              : 'Untitled item');
      final nameWasAutoFilled = _csvString(row, headerIndex, 'name') == null;
      final unitCost =
          _csvDouble(row, headerIndex, ['base_cost', 'unit_cost']) ?? 0.0;
      final unitPrice =
          _csvDouble(row, headerIndex, ['default_price', 'unit_price']) ?? 0.0;

      parsedRows.add(
        _CatalogCsvImportRow(
          rowNumber: rowIndex + 1,
          sourceId: sourceId,
          parentSourceId: _csvString(row, headerIndex, 'parent_id'),
          name: name,
          description: _csvString(row, headerIndex, 'description'),
          sku: _csvString(row, headerIndex, 'sku'),
          category: _csvString(row, headerIndex, 'category'),
          unit: _csvString(row, headerIndex, 'unit'),
          unitCost: unitCost,
          unitPrice: unitPrice,
          markup: _csvDouble(row, headerIndex, ['markup', 'markup_pct']),
          margin: _csvDouble(row, headerIndex, ['margin', 'margin_pct']),
          isTaxable:
              _csvBool(row, headerIndex, ['taxable', 'is_taxable']) ?? true,
          costTypeName: _csvString(row, headerIndex, 'cost_type_name'),
          costCodeName: _csvString(row, headerIndex, 'cost_code_name'),
          imageUrl: _csvString(row, headerIndex, 'image_url'),
          itemType: itemType,
          nameWasAutoFilled: nameWasAutoFilled,
          hierarchyLevel: _csvInt(row, headerIndex, ['hierarchy_level']) ?? 0,
          sortOrder: _csvInt(row, headerIndex, ['sort_order']),
          createdAt: _csvDateTime(row, headerIndex, ['created_at']),
          updatedAt: _csvDateTime(row, headerIndex, ['updated_at']),
        ),
      );
    }

    return _ParsedCatalogCsv(headers: headers, rows: parsedRows);
  }

  String _normalizeCsvHeader(String value) {
    return value.replaceFirst('\uFEFF', '').trim().toLowerCase();
  }

  bool _isEmptyCsvRow(List<dynamic> row) {
    return row.every((cell) => cell.toString().trim().isEmpty);
  }

  String? _csvString(
    List<dynamic> row,
    Map<String, int> headerIndex,
    String header,
  ) {
    final index = headerIndex[_normalizeCsvHeader(header)];
    if (index == null || index >= row.length) return null;
    final value = row[index].toString().trim();
    return value.isEmpty ? null : value;
  }

  double? _csvDouble(
    List<dynamic> row,
    Map<String, int> headerIndex,
    List<String> headers,
  ) {
    for (final header in headers) {
      final value = _csvString(row, headerIndex, header);
      if (value == null) continue;
      final parsed = double.tryParse(value.replaceAll(',', ''));
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _csvInt(
    List<dynamic> row,
    Map<String, int> headerIndex,
    List<String> headers,
  ) {
    for (final header in headers) {
      final value = _csvString(row, headerIndex, header);
      if (value == null) continue;
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool? _csvBool(
    List<dynamic> row,
    Map<String, int> headerIndex,
    List<String> headers,
  ) {
    for (final header in headers) {
      final value = _csvString(row, headerIndex, header);
      if (value == null) continue;
      switch (value.toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
        case 'y':
          return true;
        case 'false':
        case '0':
        case 'no':
        case 'n':
          return false;
      }
    }
    return null;
  }

  DateTime? _csvDateTime(
    List<dynamic> row,
    Map<String, int> headerIndex,
    List<String> headers,
  ) {
    for (final header in headers) {
      final value = _csvString(row, headerIndex, header);
      if (value == null) continue;
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  Map<String?, int> _buildNextSortOrderMap(List<CatalogItem> items) {
    final next = <String?, int>{null: 0};
    for (final item in items) {
      final parentId = item.parentId;
      final candidate = item.sortOrder + 1;
      final current = next[parentId] ?? 0;
      if (candidate > current) {
        next[parentId] = candidate;
      }
    }
    return next;
  }

  int _resolveImportedSortOrder({
    required _CatalogCsvImportRow row,
    required CatalogItem? existingItem,
    required String? resolvedParentId,
    required Map<String?, int> nextSortOrderByParent,
  }) {
    if (row.sortOrder != null) {
      final next = nextSortOrderByParent[resolvedParentId] ?? 0;
      if (row.sortOrder! >= next) {
        nextSortOrderByParent[resolvedParentId] = row.sortOrder! + 1;
      }
      return row.sortOrder!;
    }

    if (existingItem != null && existingItem.parentId == resolvedParentId) {
      return existingItem.sortOrder;
    }

    final next = nextSortOrderByParent[resolvedParentId] ?? 0;
    nextSortOrderByParent[resolvedParentId] = next + 1;
    return next;
  }

  String _previewDesiredParentKey({
    required _CatalogCsvImportRow row,
    required Set<String> csvIds,
    required Map<String, CatalogItem> existingById,
  }) {
    final parentSourceId = row.parentSourceId;
    if (parentSourceId == null) return 'root';
    if (existingById.containsKey(parentSourceId)) {
      return 'existing:$parentSourceId';
    }
    if (csvIds.contains(parentSourceId)) {
      return 'csv:$parentSourceId';
    }
    return 'root';
  }

  _CatalogCsvRowContext _describeRowContext({
    required _CatalogCsvImportRow row,
    required Set<String> csvIds,
    required Map<String, CatalogItem> existingById,
  }) {
    final warnings = <String>[];
    var parentLabel = 'Root level';
    var hasUnresolvedParent = false;

    if (row.parentSourceId != null &&
        !csvIds.contains(row.parentSourceId) &&
        !existingById.containsKey(row.parentSourceId)) {
      hasUnresolvedParent = true;
      warnings.add('Parent not found; row will import at root');
    } else if (row.parentSourceId != null &&
        existingById.containsKey(row.parentSourceId)) {
      parentLabel = 'Existing: ${existingById[row.parentSourceId!]!.name}';
    } else if (row.parentSourceId != null) {
      parentLabel = 'CSV parent: ${row.parentSourceId}';
    }

    if (row.nameWasAutoFilled) {
      warnings.add('Blank name was replaced automatically');
    }

    return _CatalogCsvRowContext(
      parentLabel: parentLabel,
      warnings: warnings,
      hasUnresolvedParent: hasUnresolvedParent,
    );
  }

  List<String> _previewHierarchyWarnings({
    required CatalogItem existingItem,
    required _CatalogCsvImportRow row,
    required String desiredParentKey,
    required Map<String, CatalogItem> existingById,
  }) {
    final warnings = <String>[];
    final currentParentKey = existingItem.parentId == null
        ? 'root'
        : 'existing:${existingItem.parentId}';
    if (desiredParentKey != currentParentKey) {
      final currentParentName = existingItem.parentId == null
          ? 'Root level'
          : (existingById[existingItem.parentId!]?.name ??
                existingItem.parentId!);
      final desiredParentName = switch (desiredParentKey) {
        'root' => 'Root level',
        _ when desiredParentKey.startsWith('existing:') =>
          existingById[desiredParentKey.substring(9)]?.name ??
              desiredParentKey.substring(9),
        _ when desiredParentKey.startsWith('csv:') =>
          'CSV parent ${desiredParentKey.substring(4)}',
        _ => 'Root level',
      };
      warnings.add('Would move from $currentParentName to $desiredParentName');
    }
    if (existingItem.itemType != row.itemType) {
      warnings.add(
        'Would change type from ${existingItem.itemType.name} to ${row.itemType.name}',
      );
    }
    return warnings;
  }

  _CatalogCsvImportDecision _decideImportAction({
    required CatalogItem? existingItem,
    required _CatalogCsvImportRow row,
    required CatalogCsvImportMode mode,
    required String desiredParentKey,
    required Map<String, CatalogItem> existingById,
    required bool allowHierarchyChanges,
    required bool skipHierarchyConflicts,
  }) {
    if (existingItem == null) {
      if (mode == CatalogCsvImportMode.updateOnly) {
        return const _CatalogCsvImportDecision(
          action: _CatalogCsvImportAction.skip,
          warnings: [
            'No matching existing item; update-only mode skips new rows',
          ],
        );
      }
      return const _CatalogCsvImportDecision(
        action: _CatalogCsvImportAction.create,
      );
    }

    if (mode == CatalogCsvImportMode.createOnly) {
      return const _CatalogCsvImportDecision(
        action: _CatalogCsvImportAction.skip,
        warnings: [
          'Matching existing item found; create-only mode skips updates',
        ],
      );
    }

    final hierarchyWarnings = _previewHierarchyWarnings(
      existingItem: existingItem,
      row: row,
      desiredParentKey: desiredParentKey,
      existingById: existingById,
    );
    if (hierarchyWarnings.isEmpty || allowHierarchyChanges) {
      return _CatalogCsvImportDecision(
        action: _CatalogCsvImportAction.update,
        warnings: hierarchyWarnings,
        hasHierarchyConflict: hierarchyWarnings.isNotEmpty,
      );
    }

    if (skipHierarchyConflicts) {
      return _CatalogCsvImportDecision(
        action: _CatalogCsvImportAction.skip,
        warnings: [
          ...hierarchyWarnings,
          'Skipped because hierarchy changes are disabled',
        ],
        hasHierarchyConflict: true,
      );
    }

    return _CatalogCsvImportDecision(
      action: _CatalogCsvImportAction.conflict,
      warnings: hierarchyWarnings,
      hasHierarchyConflict: true,
    );
  }

  CatalogItem _emptyCatalogItem(String workspaceId) {
    final now = DateTime.now();
    return CatalogItem(
      id: '',
      workspaceId: workspaceId,
      name: '',
      unitCost: 0.0,
      unitPrice: 0.0,
      markup: 0.0,
      margin: 0.0,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _upsertCatalogItems(List<CatalogItem> items) async {
    if (items.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    for (var start = 0; start < items.length; start += _catalogWriteBatchSize) {
      final chunk = items.skip(start).take(_catalogWriteBatchSize).map((item) {
        final data = _toSupabaseFormat(item);
        data['id'] = item.id;
        data['updated_at'] = now;
        return data;
      }).toList();
      await _supabase.from('catalog_items').upsert(chunk);
    }
  }

  Future<void> _upsertCatalogItemsForImport(List<CatalogItem> items) async {
    if (items.isEmpty) return;

    final sortedItems = [...items]
      ..sort((a, b) {
        final levelCompare = a.hierarchyLevel.compareTo(b.hierarchyLevel);
        if (levelCompare != 0) return levelCompare;
        final parentCompare = (a.parentId ?? '').compareTo(b.parentId ?? '');
        if (parentCompare != 0) return parentCompare;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    var index = 0;
    while (index < sortedItems.length) {
      final level = sortedItems[index].hierarchyLevel;
      final levelItems = <CatalogItem>[];
      while (index < sortedItems.length &&
          sortedItems[index].hierarchyLevel == level) {
        levelItems.add(sortedItems[index]);
        index++;
      }
      await _upsertCatalogItems(levelItems);
    }
  }

  /// Search catalog items
  Future<List<CatalogItem>> searchCatalogItems(
    String workspaceId,
    String query,
  ) async {
    try {
      final response = await _supabase
          .from('catalog_items')
          .select()
          .eq('workspace_id', workspaceId)
          .or(
            'name.ilike.%$query%,description.ilike.%$query%,sku.ilike.%$query%',
          )
          .order('sort_order')
          .order('name')
          .limit(50);

      return response.map((row) => _toCatalogItem(row)).toList();
    } catch (e) {
      throw Exception('Error searching catalog items: $e');
    }
  }

  /// Get catalog items by category
  Future<List<CatalogItem>> getCatalogItemsByCategory(
    String workspaceId,
    String category,
  ) async {
    try {
      final response = await _supabase
          .from('catalog_items')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('category', category)
          .order('sort_order')
          .order('name');

      return response.map((row) => _toCatalogItem(row)).toList();
    } catch (e) {
      throw Exception('Error fetching catalog items by category: $e');
    }
  }

  /// Convert database row to CatalogItem
  CatalogItem _toCatalogItem(Map<String, dynamic> row) {
    return CatalogItem.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to Firestore camelCase format
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'name': row['name'],
      'description': row['description'],
      'unit': row['unit'],
      'unitCost': (row['unit_cost'] as num?)?.toDouble() ?? 0.0,
      'unitPrice': (row['unit_price'] as num?)?.toDouble() ?? 0.0,
      'markup': (row['markup'] as num?)?.toDouble() ?? 0.0,
      'margin': (row['margin'] as num?)?.toDouble() ?? 0.0,
      'isTaxable': row['is_taxable'] ?? true,
      'costTypeName': row['cost_type_name'],
      'costCodeName': row['cost_code_name'],
      'imageUrl': row['image_url'],
      'category': row['category'],
      'sku': row['sku'],
      'createdAt': row['created_at'] != null
          ? Timestamp.fromDate(DateTime.parse(row['created_at']))
          : Timestamp.now(),
      'updatedAt': row['updated_at'] != null
          ? Timestamp.fromDate(DateTime.parse(row['updated_at']))
          : Timestamp.now(),
      // Hierarchy fields
      'parentId': row['parent_id'],
      'hierarchyLevel': row['hierarchy_level'] ?? 0,
      'itemType': row['item_type'] ?? 'item',
      'sortOrder': row['sort_order'] ?? 0,
      // Robustness / integration fields (defensive: tolerate older rows)
      'kind': row['kind'] ?? 'service',
      'isActive': row['is_active'] ?? true,
      'internalNotes': row['internal_notes'],
      'barcode': row['barcode'],
      'tags': (row['tags'] as List?)?.cast<String>() ?? const <String>[],
      'currency': row['currency'] ?? 'USD',
      'minPrice': (row['min_price'] as num?)?.toDouble(),
      'defaultTaxRate': (row['default_tax_rate'] as num?)?.toDouble() ?? 0.0,
      'defaultVendorId': row['default_vendor_id'],
      'purchaseUnit': row['purchase_unit'],
      'purchaseCost': (row['purchase_cost'] as num?)?.toDouble(),
      'purchaseDescription': row['purchase_description'],
      'inventoryTracked': row['inventory_tracked'] ?? false,
      'inventoryItemId': row['inventory_item_id'],
      'usageCount': (row['usage_count'] as num?)?.toInt() ?? 0,
      'lastUsedAt': row['last_used_at'] != null
          ? Timestamp.fromDate(DateTime.parse(row['last_used_at']))
          : null,
    };
  }

  /// Convert camelCase to snake_case
  String _camelToSnake(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  /// Convert CatalogItem to Supabase format
  Map<String, dynamic> _toSupabaseFormat(CatalogItem item) {
    return {
      'workspace_id': item.workspaceId,
      'name': item.name,
      'description': item.description,
      'unit': item.unit,
      'unit_cost': item.unitCost,
      'unit_price': item.unitPrice,
      'markup': item.markup,
      'margin': item.margin,
      'is_taxable': item.isTaxable,
      'cost_type_name': item.costTypeName,
      'cost_code_name': item.costCodeName,
      'image_url': item.imageUrl,
      'category': item.category,
      'sku': item.sku,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
      'parent_id': item.parentId,
      'hierarchy_level': item.hierarchyLevel,
      'item_type': item.itemType.toString().split('.').last,
      'sort_order': item.sortOrder,
      // Robustness / integration fields
      'kind': item.kind.wire,
      'is_active': item.isActive,
      'internal_notes': item.internalNotes,
      'barcode': item.barcode,
      'tags': item.tags,
      'currency': item.currency,
      'min_price': item.minPrice,
      'default_tax_rate': item.defaultTaxRate,
      'default_vendor_id': item.defaultVendorId,
      'purchase_unit': item.purchaseUnit,
      'purchase_cost': item.purchaseCost,
      'purchase_description': item.purchaseDescription,
      'inventory_tracked': item.inventoryTracked,
      'inventory_item_id': item.inventoryItemId,
    };
  }

  // ---------------------------------------------------------------------------
  // Robustness extensions — used by accounting/invoicing/expense flows.
  // ---------------------------------------------------------------------------

  /// Active items only (for line-item pickers).
  Future<List<CatalogItem>> getActiveItems(
    String workspaceId, {
    CatalogKind? kind,
  }) async {
    var q = _supabase
        .from('catalog_items')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('is_active', true)
        .eq('item_type', 'item');
    if (kind != null) q = q.eq('kind', kind.wire);
    final res = await q.order('usage_count', ascending: false).order('name');
    return res.map((row) => _toCatalogItem(row)).toList();
  }

  /// Look up by barcode (e.g. scanner input).
  Future<CatalogItem?> getByBarcode(
    String workspaceId,
    String barcode,
  ) async {
    final res = await _supabase
        .from('catalog_items')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('barcode', barcode)
        .maybeSingle();
    return res == null ? null : _toCatalogItem(res);
  }

  /// Most-used items, ranked by `usage_count` then recency.
  Future<List<CatalogItem>> getMostUsed(
    String workspaceId, {
    int limit = 10,
  }) async {
    final res = await _supabase
        .from('catalog_items')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('is_active', true)
        .eq('item_type', 'item')
        .order('usage_count', ascending: false)
        .order('last_used_at', ascending: false, nullsFirst: false)
        .limit(limit);
    return res.map((row) => _toCatalogItem(row)).toList();
  }

  /// Bumps the usage counter (and last_used_at) for [itemId]. Best-effort.
  Future<void> incrementUsage(String itemId, {int delta = 1}) async {
    try {
      await _supabase.rpc(
        'catalog_increment_usage',
        params: {'p_id': itemId, 'p_delta': delta},
      );
    } catch (_) {
      // Non-fatal — usage stats are advisory.
    }
  }

  /// Bumps usage for several items in parallel (no await between calls).
  Future<void> incrementUsageBatch(Iterable<String> itemIds) async {
    await Future.wait(itemIds.map((id) => incrementUsage(id)));
  }

  /// Resolves the effective unit price for [itemId] given an optional customer
  /// and quantity, honoring per-customer overrides and volume breaks.
  Future<double> getEffectivePrice(
    String itemId, {
    String? customerId,
    double quantity = 1,
  }) async {
    try {
      final res = await _supabase.rpc(
        'catalog_effective_price',
        params: {
          'p_catalog_item_id': itemId,
          'p_customer_id': customerId,
          'p_quantity': quantity,
        },
      );
      if (res is num) return res.toDouble();
      if (res is String) return double.tryParse(res) ?? 0;
      return 0;
    } catch (_) {
      // Fall back to the catalog item's own unit price on RPC errors.
      final item = await getCatalogItem(itemId);
      return item?.unitPrice ?? 0;
    }
  }

  // ---------- Bundle components -------------------------------------------

  Future<List<CatalogBundleComponent>> listBundleComponents(
    String bundleId,
  ) async {
    final res = await _supabase
        .from('catalog_bundle_components')
        .select()
        .eq('bundle_id', bundleId)
        .order('sort_order');
    return res
        .map((r) => CatalogBundleComponent.fromRow(r))
        .toList(growable: false);
  }

  Future<CatalogBundleComponent> addBundleComponent(
    CatalogBundleComponent c,
  ) async {
    final res = await _supabase
        .from('catalog_bundle_components')
        .insert(c.toInsert())
        .select()
        .single();
    return CatalogBundleComponent.fromRow(res);
  }

  Future<void> removeBundleComponent(String id) async {
    await _supabase.from('catalog_bundle_components').delete().eq('id', id);
  }

  // ---------- Price tiers --------------------------------------------------

  Future<List<CatalogPriceTier>> listPriceTiers(String catalogItemId) async {
    final res = await _supabase
        .from('catalog_price_tiers')
        .select()
        .eq('catalog_item_id', catalogItemId)
        .order('customer_id', nullsFirst: false)
        .order('min_quantity');
    return res
        .map((r) => CatalogPriceTier.fromRow(r))
        .toList(growable: false);
  }

  Future<CatalogPriceTier> addPriceTier(CatalogPriceTier tier) async {
    final res = await _supabase
        .from('catalog_price_tiers')
        .insert(tier.toInsert())
        .select()
        .single();
    return CatalogPriceTier.fromRow(res);
  }

  Future<void> removePriceTier(String id) async {
    await _supabase.from('catalog_price_tiers').delete().eq('id', id);
  }
}

class CatalogCsvImportPreview {
  final List<String> fileHeaders;
  final int totalRows;
  final int createCount;
  final int updateCount;
  final int groupCount;
  final int itemCount;
  final int unresolvedParentCount;
  final int hierarchyConflictCount;
  final int skippedCount;
  final List<String> warnings;
  final List<CatalogCsvReportRow> previewRows;
  final List<CatalogCsvReportRow> reportRows;
  final int additionalRowCount;

  const CatalogCsvImportPreview({
    required this.fileHeaders,
    required this.totalRows,
    required this.createCount,
    required this.updateCount,
    required this.groupCount,
    required this.itemCount,
    required this.unresolvedParentCount,
    required this.hierarchyConflictCount,
    required this.skippedCount,
    required this.warnings,
    required this.previewRows,
    required this.reportRows,
    required this.additionalRowCount,
  });
}

class CatalogCsvImportResult {
  final int processedCount;
  final int createdCount;
  final int updatedCount;
  final int groupCount;
  final int itemCount;
  final int unresolvedParentCount;
  final int skippedCount;
  final List<CatalogCsvReportRow> reportRows;

  const CatalogCsvImportResult({
    required this.processedCount,
    required this.createdCount,
    required this.updatedCount,
    required this.groupCount,
    required this.itemCount,
    required this.unresolvedParentCount,
    required this.skippedCount,
    required this.reportRows,
  });
}

class CatalogCsvReportRow {
  final int rowNumber;
  final String? sourceId;
  final String name;
  final CatalogItemType itemType;
  final String actionLabel;
  final String? parentSourceId;
  final String parentLabel;
  final List<String> warnings;

  const CatalogCsvReportRow({
    required this.rowNumber,
    required this.sourceId,
    required this.name,
    required this.itemType,
    required this.actionLabel,
    required this.parentSourceId,
    required this.parentLabel,
    required this.warnings,
  });
}

enum CatalogCsvImportMode { createAndUpdate, createOnly, updateOnly }

enum _CatalogCsvImportAction { create, update, skip, conflict }

class _CatalogCsvImportDecision {
  final _CatalogCsvImportAction action;
  final List<String> warnings;
  final bool hasHierarchyConflict;

  const _CatalogCsvImportDecision({
    required this.action,
    this.warnings = const [],
    this.hasHierarchyConflict = false,
  });
}

class _CatalogCsvRowContext {
  final String parentLabel;
  final List<String> warnings;
  final bool hasUnresolvedParent;

  const _CatalogCsvRowContext({
    required this.parentLabel,
    required this.warnings,
    required this.hasUnresolvedParent,
  });
}

class _ParsedCatalogCsv {
  final List<String> headers;
  final List<_CatalogCsvImportRow> rows;

  const _ParsedCatalogCsv({required this.headers, required this.rows});
}

class _CatalogCsvImportRow {
  final int rowNumber;
  final String? sourceId;
  final String? parentSourceId;
  final String name;
  final String? description;
  final String? sku;
  final String? category;
  final String? unit;
  final double unitCost;
  final double unitPrice;
  final double? markup;
  final double? margin;
  final bool isTaxable;
  final String? costTypeName;
  final String? costCodeName;
  final String? imageUrl;
  final CatalogItemType itemType;
  final bool nameWasAutoFilled;
  final int hierarchyLevel;
  final int? sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const _CatalogCsvImportRow({
    required this.rowNumber,
    required this.sourceId,
    required this.parentSourceId,
    required this.name,
    required this.description,
    required this.sku,
    required this.category,
    required this.unit,
    required this.unitCost,
    required this.unitPrice,
    required this.markup,
    required this.margin,
    required this.isTaxable,
    required this.costTypeName,
    required this.costCodeName,
    required this.imageUrl,
    required this.itemType,
    required this.nameWasAutoFilled,
    required this.hierarchyLevel,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  String get rowLabel => sourceId ?? 'row $rowNumber';
}

/// Result row from the `catalog_cascade_to_open_jobs` RPC.
class CatalogCascadeResult {
  final int matchedCount;
  final int projectCount;
  const CatalogCascadeResult({
    required this.matchedCount,
    required this.projectCount,
  });
}
