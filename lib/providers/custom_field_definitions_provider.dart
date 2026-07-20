import 'package:flutter/foundation.dart';

import '../models/custom_field_definition.dart';
import '../models/custom_field_type.dart';
import '../services/service_locator.dart';

/// Workspace-scoped cache of [CustomFieldDefinition]s.
///
/// Mirrors the small-CRUD-cache pattern (similar in spirit to file/customer
/// tag providers): one instance per workspace+entity. Mutation methods
/// delegate to [SupabaseCustomFieldDefinitionService] and re-fetch the full
/// list before notifying listeners — the list is bounded by the 50-field
/// soft cap so a re-fetch is cheap and avoids subtle desync bugs from
/// optimistic updates.
class CustomFieldDefinitionsProvider with ChangeNotifier {
  final String entityType;

  CustomFieldDefinitionsProvider({this.entityType = 'project'});

  String? _workspaceId;
  List<CustomFieldDefinition> _all = const [];
  bool _loading = false;
  Object? _error;

  String? get workspaceId => _workspaceId;
  bool get isLoading => _loading;
  Object? get error => _error;

  /// All defs for the current workspace + entity, including archived.
  /// Sorted by [CustomFieldDefinition.sortOrder].
  List<CustomFieldDefinition> get all => _all;

  /// Active (non-archived) defs.
  List<CustomFieldDefinition> get active =>
      _all.where((d) => !d.isArchived).toList();

  /// Archived defs (separate section in the settings UI).
  List<CustomFieldDefinition> get archived =>
      _all.where((d) => d.isArchived).toList();

  /// Active defs grouped by [CustomFieldDefinition.fieldGroup]. Groups
  /// preserve first-seen order; the implicit `null` group renders last.
  /// Used by the project form to render collapsible subsections.
  Map<String?, List<CustomFieldDefinition>> get activeByGroup {
    final out = <String?, List<CustomFieldDefinition>>{};
    for (final d in active) {
      out.putIfAbsent(d.fieldGroup, () => []).add(d);
    }
    // Move null/"Other" to the end.
    if (out.containsKey(null)) {
      final other = out.remove(null)!;
      out[null] = other;
    }
    return out;
  }

  Future<void> load(String workspaceId) async {
    if (_workspaceId == workspaceId && _all.isNotEmpty && !_loading) return;
    _workspaceId = workspaceId;
    await _refresh();
  }

  /// Force a refresh of the cached list — useful after mutations on a
  /// different device (realtime not wired in v1).
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    if (_workspaceId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final defs = await ServiceLocator.customFieldDefinitionService
          .listDefinitions(
            workspaceId: _workspaceId!,
            entityType: entityType,
          );
      _all = defs;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<CustomFieldDefinition> create({
    required String label,
    required CustomFieldType type,
    String? fieldGroup,
    List<String>? options,
    dynamic defaultValue,
    bool isRequired = false,
    bool showInForm = true,
    bool groupable = false,
    String? createdBy,
  }) async {
    _ensureLoaded();
    final created =
        await ServiceLocator.customFieldDefinitionService.createDefinition(
      workspaceId: _workspaceId!,
      entityType: entityType,
      label: label,
      type: type,
      fieldGroup: fieldGroup,
      options: options,
      defaultValue: defaultValue,
      isRequired: isRequired,
      showInForm: showInForm,
      groupable: groupable,
      createdBy: createdBy,
    );
    await _refresh();
    return created;
  }

  Future<void> update({
    required String id,
    String? label,
    String? fieldGroup,
    bool clearFieldGroup = false,
    List<String>? options,
    bool clearOptions = false,
    dynamic defaultValue,
    bool clearDefaultValue = false,
    bool? isRequired,
    bool? showInForm,
    bool? groupable,
  }) async {
    // Detect a groupable false→true flip; we'll backfill the side-table
    // after the update lands so existing project values become reportable.
    final previous = _all.firstWhere(
      (d) => d.id == id,
      orElse: () => throw StateError('definition $id not in cache'),
    );
    final shouldBackfill = groupable == true && !previous.groupable;

    await ServiceLocator.customFieldDefinitionService.updateDefinition(
      id: id,
      label: label,
      fieldGroup: fieldGroup,
      clearFieldGroup: clearFieldGroup,
      options: options,
      clearOptions: clearOptions,
      defaultValue: defaultValue,
      clearDefaultValue: clearDefaultValue,
      isRequired: isRequired,
      showInForm: showInForm,
      groupable: groupable,
    );

    if (shouldBackfill) {
      try {
        await ServiceLocator.customFieldDefinitionService
            .backfillGroupableField(id);
      } catch (e) {
        // Backfill failure isn't fatal — future writes still populate the
        // side-table via the trigger. Surface as provider error so the
        // settings UI can warn the admin to re-trigger manually.
        _error = e;
      }
    }

    await _refresh();
  }

  Future<void> archive(String id) async {
    await ServiceLocator.customFieldDefinitionService.archiveDefinition(id);
    await _refresh();
  }

  Future<void> restore(String id) async {
    await ServiceLocator.customFieldDefinitionService.restoreDefinition(id);
    await _refresh();
  }

  /// Reorder active defs. [orderedIds] must contain every active def's id
  /// in the desired display order.
  Future<void> reorder(List<String> orderedIds) async {
    // Optimistic local apply so the list doesn't flicker during the bulk
    // update. The refresh below restores authoritative state.
    final byId = {for (final d in _all) d.id: d};
    final reordered = <CustomFieldDefinition>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final d = byId.remove(orderedIds[i]);
      if (d != null) reordered.add(d.copyWith(sortOrder: i));
    }
    reordered.addAll(byId.values);
    _all = reordered;
    notifyListeners();

    await ServiceLocator.customFieldDefinitionService
        .reorderDefinitions(orderedIds);
    await _refresh();
  }

  Future<List<String>> listGroups() async {
    _ensureLoaded();
    return ServiceLocator.customFieldDefinitionService.listFieldGroups(
      workspaceId: _workspaceId!,
      entityType: entityType,
    );
  }

  void _ensureLoaded() {
    if (_workspaceId == null) {
      throw StateError('CustomFieldDefinitionsProvider used before load()');
    }
  }
}
