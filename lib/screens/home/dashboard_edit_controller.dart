import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/dashboard_config.dart';
import '../../models/widget_catalog_provider.dart';
import '../../models/widget_grid_layout.dart';
import '../../services/service_locator.dart';
import 'dashboard_widget_catalog.dart';
import 'field_technician_catalog.dart';

/// Manages edit mode state, config mutations, and save logic for the dashboard.
class DashboardEditController extends ChangeNotifier {
  static const List<List<String>> _legacyDefaultOrders = [
    [
      'daily_summary',
      'weekly_digest',
      'financial_summary',
      'recent_projects',
      'active_projects',
      'my_tasks',
      'messaging_summary',
      'capacity_alerts',
      'recent_activity',
    ],
    [
      'daily_summary',
      'weekly_digest',
      'recent_projects',
      'active_projects',
      'my_tasks',
      'messaging_summary',
      'capacity_alerts',
      'financial_summary',
      'recent_activity',
    ],
  ];

  static const List<List<String>> _legacyFieldDefaultOrders = [
    [
      'todays_schedule',
      'time_clock',
      'driving_directions',
      'safety_checklist',
      'pending_forms',
      'my_tasks',
      'job_site_weather',
      'photo_upload_queue',
      'vehicle_equipment',
      'messaging_summary',
      'material_usage',
      'active_projects',
      'daily_summary',
      'recent_activity',
    ],
  ];

  final WidgetCatalogProvider catalog;
  final String preferenceKey;

  DashboardEditController({
    WidgetCatalogProvider? catalog,
    this.preferenceKey = 'dashboard_widget_config',
  }) : catalog = catalog ?? DashboardCatalogInstance();

  DashboardWidgetConfig _config = const DashboardWidgetConfig();
  WidgetGridConfig _gridConfig = const WidgetGridConfig();
  bool _editMode = false;
  bool _loading = true;
  bool _saving = false;
  String? _saveError;
  Timer? _collapseDebounce;
  Timer? _autoSaveTimer;
  // Snapshot of config + gridConfig taken when entering edit mode, used for
  // undo. Cleared when edit mode exits.
  DashboardWidgetConfig? _editStartConfig;
  WidgetGridConfig? _editStartGridConfig;
  // Optional override forcing the grid to render at a specific breakpoint
  // regardless of viewport width. Used by the toolbar preview picker.
  GridBreakpoint? _previewBreakpoint;
  // Set whenever a mutation happens; cleared after a successful save. The
  // auto-save heartbeat skips writes when this is false.
  bool _dirty = false;
  // Timestamp of the row we loaded. Used to detect multi-tab conflicts before
  // a save overwrites another tab's edits. Updated after every successful
  // save so subsequent saves stay consistent.
  DateTime? _baselineUpdatedAt;

  DashboardWidgetConfig get config => _config;
  WidgetGridConfig get gridConfig => _gridConfig;
  bool get editMode => _editMode;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get saveError => _saveError;
  GridBreakpoint? get previewBreakpoint => _previewBreakpoint;
  bool get canUndo => _editStartGridConfig != null && _editMode;

  /// Returns the v3 grid layout for the given breakpoint. Backed by
  /// [_gridConfig] which is either loaded from disk or derived from the v2
  /// order on first load.
  WidgetGridLayout gridLayoutFor(GridBreakpoint breakpoint) =>
      _gridConfig.layoutFor(breakpoint);

  /// Recomputes all per-breakpoint layouts from the current v2 [_config] using
  /// catalog defaults. Used after large state changes (load, reset).
  void _rederiveGridConfig() {
    _gridConfig = WidgetGridConfig.migrateFromV2(_config, catalog);
  }

  /// Visible widget IDs in display order.
  List<String> get visibleOrder =>
      _config.order.where((id) => !_config.isHidden(id)).toList();

  /// Hidden widget IDs (available to re-add).
  List<String> get hiddenWidgets =>
      _config.order.where((id) => _config.isHidden(id)).toList();

  /// Loads config from preferences, merging with default catalog.
  Future<void> load() async {
    final raw = await ServiceLocator.userPreferencesService.getWidgetConfig(
      preferenceKey,
    );
    _config = DashboardWidgetConfig.fromJson(raw);
    final savedOrder = _config.order.where(catalog.labels.containsKey).toList();
    final shouldMigrateLegacyOrder = _legacyDefaultOrders.any(
      (legacyOrder) => _listEquals(savedOrder, legacyOrder),
    );
    final shouldMigrateLegacyFieldOrder =
        catalog is FieldTechnicianCatalog &&
        _legacyFieldDefaultOrders.any(
          (legacyOrder) => _listEquals(savedOrder, legacyOrder),
        );

    // Merge order: saved order first (filter stale), then any new defaults.
    var mergedOrder = <String>[
      ..._config.order.where(catalog.labels.containsKey),
      ...catalog.defaultOrder.where((id) => !_config.order.contains(id)),
    ];
    if (shouldMigrateLegacyOrder || shouldMigrateLegacyFieldOrder) {
      mergedOrder = List<String>.from(catalog.defaultOrder);
    }

    // Apply catalog default sizes for widgets that don't have an explicit size.
    final mergedSizes = Map<String, String>.from(_config.sizes);
    for (final id in mergedOrder) {
      if (!mergedSizes.containsKey(id)) {
        final defaultSize = catalog.metaFor(id).defaultSize;
        if (defaultSize != 'half') {
          mergedSizes[id] = defaultSize;
        }
      }
    }

    // Apply default hidden list for fresh installs (no saved hidden state).
    final mergedHidden = _config.hidden.isEmpty && savedOrder.isEmpty
        ? List<String>.from(catalog.defaultHidden)
        : _config.hidden;

    _config = _config.copyWith(
      order: mergedOrder,
      hidden: mergedHidden,
      sizes: mergedSizes,
    );

    // Load v3 layouts if present, else derive from v2.
    final hasSavedLayouts =
        raw['layouts'] is Map && (raw['layouts'] as Map).isNotEmpty;
    if (hasSavedLayouts) {
      _gridConfig = WidgetGridConfig.fromJson(raw);
      _reconcileGridConfigWithV2();
    } else {
      _rederiveGridConfig();
    }

    final updatedAtRaw = raw['updated_at'];
    _baselineUpdatedAt =
        updatedAtRaw is String ? DateTime.tryParse(updatedAtRaw) : null;

    _loading = false;
    notifyListeners();
  }

  /// After loading v3 layouts from disk, make sure they're consistent with the
  /// v2 visible widget set: drop any placement whose widget no longer exists
  /// (catalog removed it) or is now hidden, and insert any visible widget that
  /// has no placement (newly added catalog widget).
  void _reconcileGridConfigWithV2() {
    final visibleSet = visibleOrder.toSet();
    final updatedLayouts = <GridBreakpoint, WidgetGridLayout>{};
    for (final bp in GridBreakpoint.values) {
      var layout = _gridConfig.layoutFor(bp);
      // Drop placements for widgets that are gone or hidden.
      final filtered = layout.placements
          .where((p) => visibleSet.contains(p.id) && catalog.labels.containsKey(p.id))
          .toList();
      layout = WidgetGridLayout(breakpoint: bp, placements: filtered);
      // Insert any visible widget that lacks a placement.
      final placed = filtered.map((p) => p.id).toSet();
      for (final id in visibleOrder) {
        if (placed.contains(id)) continue;
        final meta = catalog.metaFor(id);
        layout = layout.withWidget(
          id,
          defaultWidthForBreakpoint(meta, bp),
          meta.desktopDefaultH,
        );
      }
      updatedLayouts[bp] = layout.compacted();
    }
    _gridConfig = _gridConfig.copyWith(layouts: updatedLayouts);
  }

  // ---------------------------------------------------------------------------
  // Edit mode
  // ---------------------------------------------------------------------------

  void toggleEditMode() {
    _editMode = !_editMode;
    if (_editMode) {
      // Snapshot for undo + start auto-save heartbeat.
      _editStartConfig = _config;
      _editStartGridConfig = _gridConfig;
      _scheduleAutoSave();
    } else {
      _autoSaveTimer?.cancel();
      _editStartConfig = null;
      _editStartGridConfig = null;
      _save();
    }
    notifyListeners();
  }

  /// Reverts all in-edit-mode changes back to the snapshot taken when edit
  /// mode was entered. Stays in edit mode so the user can keep tweaking.
  void undo() {
    if (_editStartConfig == null || _editStartGridConfig == null) return;
    _config = _editStartConfig!;
    _gridConfig = _editStartGridConfig!;
    _markDirty();
    notifyListeners();
  }

  /// Forces the grid renderer to use a specific breakpoint regardless of
  /// viewport width. Pass null to restore automatic detection.
  void setPreviewBreakpoint(GridBreakpoint? bp) {
    if (_previewBreakpoint == bp) return;
    _previewBreakpoint = bp;
    notifyListeners();
  }

  /// Clears the last save error after a UI consumer (e.g. SnackBar) has
  /// surfaced it, so it doesn't re-trigger on subsequent rebuilds.
  void clearSaveError() {
    if (_saveError == null) return;
    _saveError = null;
    notifyListeners();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    if (!_editMode) return;
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (_dirty) _save();
      _scheduleAutoSave();
    });
  }

  void _markDirty() => _dirty = true;

  /// Regenerates v2 [_config.order] and [_config.sizes] from the current
  /// desktop layout so the legacy representation stays consistent. Called
  /// after every v3 layout mutation. Without this, rolling the feature flag
  /// off would leave users with a stale v2 layout that doesn't reflect their
  /// recent edits.
  void _syncV2FromGrid() {
    final desktop = _gridConfig.layoutFor(GridBreakpoint.desktop);
    if (desktop.placements.isEmpty) return;
    final sorted = [...desktop.placements]
      ..sort((a, b) {
        final dy = a.y.compareTo(b.y);
        if (dy != 0) return dy;
        return a.x.compareTo(b.x);
      });
    final visibleIds = sorted.map((p) => p.id).toList();
    // Preserve hidden ids (which aren't in v3 layouts) by appending them.
    final hiddenSet = _config.hidden.toSet();
    final hiddenOrdered =
        _config.order.where(hiddenSet.contains).toList(growable: false);
    // v2 sizes are lossy: width == columns → full, otherwise → half (default).
    // Best we can do given the v2 representation is binary.
    final desktopColumns = GridBreakpoint.desktop.columns;
    final newSizes = <String, String>{};
    for (final p in sorted) {
      if (p.w == desktopColumns) {
        newSizes[p.id] = 'full';
      }
    }
    _config = _config.copyWith(
      order: [...visibleIds, ...hiddenOrdered],
      sizes: newSizes,
    );
  }

  // ---------------------------------------------------------------------------
  // Reorder
  // ---------------------------------------------------------------------------

  void reorder(String widgetId, int newIndex) {
    final visible = visibleOrder;
    final currentVisibleIndex = visible.indexOf(widgetId);
    if (currentVisibleIndex == -1) return;

    final visibleWithoutDragged = List<String>.from(visible)..remove(widgetId);
    final targetVisibleIndex =
        (newIndex > currentVisibleIndex ? newIndex - 1 : newIndex).clamp(
          0,
          visibleWithoutDragged.length,
        );
    visibleWithoutDragged.insert(targetVisibleIndex, widgetId);

    final hiddenSet = _config.hidden.toSet();
    var visiblePointer = 0;
    final mergedOrder = _config.order.map((id) {
      if (hiddenSet.contains(id)) return id;
      return visibleWithoutDragged[visiblePointer++];
    }).toList();

    _config = _config.copyWith(order: mergedOrder);
    _markDirty();
    notifyListeners();
  }

  /// Moves a widget up (earlier) in the visible order.
  void moveUp(String widgetId) {
    final visible = visibleOrder;
    final idx = visible.indexOf(widgetId);
    if (idx <= 0) return;
    swap(widgetId, visible[idx - 1]);
  }

  /// Moves a widget down (later) in the visible order.
  void moveDown(String widgetId) {
    final visible = visibleOrder;
    final idx = visible.indexOf(widgetId);
    if (idx == -1 || idx >= visible.length - 1) return;
    swap(widgetId, visible[idx + 1]);
  }

  /// Swaps the positions of two widgets in the order list.
  void swap(String id1, String id2) {
    final order = List<String>.from(_config.order);
    final i1 = order.indexOf(id1);
    final i2 = order.indexOf(id2);
    if (i1 == -1 || i2 == -1) return;
    final tmp = order[i1];
    order[i1] = order[i2];
    order[i2] = tmp;
    _config = _config.copyWith(order: order);
    _markDirty();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Visibility
  // ---------------------------------------------------------------------------

  void hideWidget(String widgetId) {
    final hidden = List<String>.from(_config.hidden);
    if (!hidden.contains(widgetId)) {
      hidden.add(widgetId);
    }
    _config = _config.copyWith(hidden: hidden);
    // Drop the widget from every breakpoint's layout and compact upward so its
    // slot doesn't leave a gap.
    final updatedLayouts = <GridBreakpoint, WidgetGridLayout>{};
    for (final bp in GridBreakpoint.values) {
      updatedLayouts[bp] = _gridConfig.layoutFor(bp).without(widgetId).compacted();
    }
    _gridConfig = _gridConfig.copyWith(layouts: updatedLayouts);
    _syncV2FromGrid();
    _markDirty();
    notifyListeners();
  }

  void showWidget(String widgetId) {
    final hidden = List<String>.from(_config.hidden);
    hidden.remove(widgetId);
    _config = _config.copyWith(hidden: hidden);
    // Re-insert into every breakpoint's layout via first-fit at catalog defaults.
    final meta = catalog.metaFor(widgetId);
    final updatedLayouts = <GridBreakpoint, WidgetGridLayout>{};
    for (final bp in GridBreakpoint.values) {
      final existing = _gridConfig.layoutFor(bp);
      if (existing.placementOf(widgetId) != null) {
        updatedLayouts[bp] = existing;
        continue;
      }
      updatedLayouts[bp] = existing
          .withWidget(
            widgetId,
            defaultWidthForBreakpoint(meta, bp),
            meta.desktopDefaultH,
          )
          .compacted();
    }
    _gridConfig = _gridConfig.copyWith(layouts: updatedLayouts);
    _syncV2FromGrid();
    _markDirty();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // v3 grid mutations (drag + resize)
  // ---------------------------------------------------------------------------

  /// Moves a widget to (x, y) on the given breakpoint's layout. Other widgets
  /// gravity-pack around it. Used by the WidgetGrid drag-to-reposition gesture.
  void moveWidgetTo(String widgetId, GridBreakpoint bp, int x, int y) {
    final layout = _gridConfig.layoutFor(bp);
    if (layout.placementOf(widgetId) == null) return;
    final updated = layout.move(widgetId, x, y);
    _gridConfig = _gridConfig.copyWith(
      layouts: {..._gridConfig.layouts, bp: updated},
    );
    _syncV2FromGrid();
    _markDirty();
    notifyListeners();
  }

  /// Pins a widget to an arbitrary (x, y, w, h) rect on the given breakpoint.
  /// Used by the multi-corner resize handles where dragging the top-left or
  /// bottom-left changes x as well as w.
  void setWidgetPlacement(
    String widgetId,
    GridBreakpoint bp,
    int x,
    int y,
    int w,
    int h,
  ) {
    final layout = _gridConfig.layoutFor(bp);
    final prior = layout.placementOf(widgetId);
    if (prior == null) return;
    final meta = catalog.metaFor(widgetId);
    final maxW = (meta.maxW ?? bp.columns).clamp(meta.minW, bp.columns);
    final clampedW = w.clamp(meta.minW, maxW);
    final clampedH = h.clamp(meta.minH, meta.maxH ?? 9999);
    final clampedX = x.clamp(0, bp.columns - clampedW);
    final clampedY = y < 0 ? 0 : y;
    var updated = layout.setPlacement(
      widgetId,
      clampedX,
      clampedY,
      clampedW,
      clampedH,
    );
    // A deliberate resize means view-mode rendering must not override the
    // changed axis anymore (gap-filling for width, autoHeight for height).
    if (clampedW != prior.w || clampedH != prior.h) {
      updated = updated.markUserSized(
        widgetId,
        width: clampedW != prior.w,
        height: clampedH != prior.h,
      );
    }
    _gridConfig = _gridConfig.copyWith(
      layouts: {..._gridConfig.layouts, bp: updated},
    );
    _syncV2FromGrid();
    _markDirty();
    notifyListeners();
  }

  /// Resizes a widget to (w, h) on the given breakpoint's layout, clamped to
  /// the catalog's min/max constraints. Used by the corner resize handle.
  void resizeWidgetTo(String widgetId, GridBreakpoint bp, int w, int h) {
    final layout = _gridConfig.layoutFor(bp);
    final prior = layout.placementOf(widgetId);
    if (prior == null) return;
    final meta = catalog.metaFor(widgetId);
    var updated = layout.resize(
      widgetId,
      w,
      h,
      minW: meta.minW,
      minH: meta.minH,
      maxW: meta.maxW,
      maxH: meta.maxH,
    );
    final post = updated.placementOf(widgetId);
    if (post != null && (post.w != prior.w || post.h != prior.h)) {
      updated = updated.markUserSized(
        widgetId,
        width: post.w != prior.w,
        height: post.h != prior.h,
      );
    }
    _gridConfig = _gridConfig.copyWith(
      layouts: {..._gridConfig.layouts, bp: updated},
    );
    _syncV2FromGrid();
    _markDirty();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Size
  // ---------------------------------------------------------------------------

  void toggleSize(String widgetId) {
    final sizes = Map<String, String>.from(_config.sizes);
    final current = _config.sizeOf(widgetId);
    sizes[widgetId] = current == 'half' ? 'full' : 'half';
    _config = _config.copyWith(sizes: sizes);
    _markDirty();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Collapse / Expand
  // ---------------------------------------------------------------------------

  void toggleCollapse(String widgetId) {
    final collapsed = List<String>.from(_config.collapsed);
    if (collapsed.contains(widgetId)) {
      collapsed.remove(widgetId);
    } else {
      collapsed.add(widgetId);
    }
    _config = _config.copyWith(collapsed: collapsed);
    _markDirty();
    notifyListeners();
    _debouncedSave();
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  void resetDefaults() {
    final defaultSizes = <String, String>{};
    for (final id in catalog.defaultOrder) {
      final defaultSize = catalog.metaFor(id).defaultSize;
      if (defaultSize != 'half') {
        defaultSizes[id] = defaultSize;
      }
    }
    _config = const DashboardWidgetConfig().copyWith(
      order: List<String>.from(catalog.defaultOrder),
      hidden: List<String>.from(catalog.defaultHidden),
      sizes: defaultSizes,
    );
    _rederiveGridConfig();
    _markDirty();
    notifyListeners();
    _save();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  void _debouncedSave() {
    _collapseDebounce?.cancel();
    _collapseDebounce = Timer(const Duration(milliseconds: 300), _save);
  }

  Future<void> _save() async {
    _saving = true;
    _saveError = null;
    notifyListeners();
    final layoutsJson = <String, dynamic>{
      for (final entry in _gridConfig.layouts.entries)
        entry.key.key: entry.value.toJson(),
    };
    try {
      // Multi-tab conflict check: if another tab/window has saved since we
      // loaded, refuse to overwrite their work and surface a clear error.
      if (_baselineUpdatedAt != null) {
        final fresh = await ServiceLocator.userPreferencesService
            .getWidgetConfig(preferenceKey);
        final freshUpdatedAtRaw = fresh['updated_at'];
        final freshUpdatedAt = freshUpdatedAtRaw is String
            ? DateTime.tryParse(freshUpdatedAtRaw)
            : null;
        if (freshUpdatedAt != null &&
            freshUpdatedAt.isAfter(_baselineUpdatedAt!)) {
          _saveError =
              'Another window edited this dashboard. Reload the page to see '
              'the latest layout.';
          return;
        }
      }

      await ServiceLocator.userPreferencesService.saveWidgetConfig(
        preferenceKey,
        order: _config.order,
        hidden: _config.hidden,
        sizes: _config.sizes,
        collapsed: _config.collapsed,
        version: WidgetGridConfig.currentVersion,
        layouts: layoutsJson.isEmpty ? null : layoutsJson,
      );
      // Advance the baseline so subsequent saves in this session stay
      // consistent with what we just wrote.
      _baselineUpdatedAt = DateTime.now();
      _dirty = false;
    } catch (e) {
      _saveError = e.toString();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _collapseDebounce?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
