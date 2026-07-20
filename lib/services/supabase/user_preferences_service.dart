import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

/// Service for reading/writing per-user preferences stored in the
/// `user_preferences` table (JSONB `preferences` column).
class SupabaseUserPreferencesService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Generic JSONB helpers
  // ---------------------------------------------------------------------------

  /// Returns the full preferences JSONB for the current user.
  Future<Map<String, dynamic>> getPreferences() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return {};

      final row = await _supabase
          .from('user_preferences')
          .select('preferences')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return {};
      return Map<String, dynamic>.from(row['preferences'] as Map? ?? {});
    } catch (e) {
      AppLogger.error('Error getting preferences', error: e);
      return {};
    }
  }

  /// Upserts a single key inside the JSONB preferences column.
  Future<void> updatePreferenceKey(String key, dynamic value) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final current = await getPreferences();
      current[key] = value;

      await _supabase.from('user_preferences').upsert({
        'user_id': userId,
        'preferences': current,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      AppLogger.error('Error updating preference key "$key"', error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Favorite projects
  // ---------------------------------------------------------------------------

  Future<List<String>> getFavoriteProjectIds() async {
    final prefs = await getPreferences();
    final raw = prefs['favorite_project_ids'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  Future<void> toggleFavoriteProject(String projectId) async {
    final favorites = await getFavoriteProjectIds();
    if (favorites.contains(projectId)) {
      favorites.remove(projectId);
    } else {
      favorites.add(projectId);
    }
    await updatePreferenceKey('favorite_project_ids', favorites);
  }

  // ---------------------------------------------------------------------------
  // Recently viewed projects
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getRecentProjectViews() async {
    final prefs = await getPreferences();
    final raw = prefs['recent_project_views'];
    if (raw is List) {
      return raw.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<void> recordProjectView(String projectId) async {
    final recents = await getRecentProjectViews();

    // Remove existing entry for this project
    recents.removeWhere((e) => e['project_id'] == projectId);

    // Prepend new entry
    recents.insert(0, {
      'project_id': projectId,
      'viewed_at': DateTime.now().toIso8601String(),
    });

    // Cap at 10
    final capped = recents.take(10).toList();
    await updatePreferenceKey('recent_project_views', capped);
  }

  Future<List<Map<String, dynamic>>> getSavedViews(String key) async {
    final prefs = await getPreferences();
    final raw = prefs[key];
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> upsertSavedView(
    String key,
    Map<String, dynamic> view, {
    int limit = 20,
  }) async {
    final views = await getSavedViews(key);
    final id = view['id'] as String?;
    if (id == null || id.isEmpty) return;

    final index = views.indexWhere((item) => item['id'] == id);
    if (index >= 0) {
      views[index] = view;
    } else {
      views.insert(0, view);
    }

    await updatePreferenceKey(key, views.take(limit).toList());
  }

  Future<void> deleteSavedView(String key, String viewId) async {
    final views = await getSavedViews(key);
    views.removeWhere((item) => item['id'] == viewId);
    await updatePreferenceKey(key, views);
  }

  // ---------------------------------------------------------------------------
  // Home dashboard widget layout
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getDashboardWidgetConfig() async {
    final prefs = await getPreferences();
    final raw = prefs['dashboard_widget_config'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  Future<void> saveDashboardWidgetConfig({
    required List<String> order,
    required List<String> hidden,
    Map<String, String>? sizes,
    List<String>? collapsed,
    int? version,
    Map<String, dynamic>? layouts,
  }) async {
    final payload = <String, dynamic>{
      'version': version ?? 2,
      'order': order,
      'hidden': hidden,
      'sizes': sizes ?? {},
      'collapsed': collapsed ?? [],
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (layouts != null) payload['layouts'] = layouts;
    await updatePreferenceKey('dashboard_widget_config', payload);
  }

  // ---------------------------------------------------------------------------
  // Generic widget config (used by project overview, etc.)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getWidgetConfig(String key) async {
    final prefs = await getPreferences();
    final raw = prefs[key];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  Future<void> saveWidgetConfig(
    String key, {
    required List<String> order,
    required List<String> hidden,
    Map<String, String>? sizes,
    List<String>? collapsed,
    int? version,
    Map<String, dynamic>? layouts,
  }) async {
    final payload = <String, dynamic>{
      'version': version ?? 2,
      'order': order,
      'hidden': hidden,
      'sizes': sizes ?? {},
      'collapsed': collapsed ?? [],
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (layouts != null) payload['layouts'] = layouts;
    await updatePreferenceKey(key, payload);
  }

  // ---------------------------------------------------------------------------
  // Getting Started checklist
  // ---------------------------------------------------------------------------

  String _gettingStartedKey(String base, String workspaceId, {String? scope}) {
    if (scope == null || scope.isEmpty || scope == 'manager') {
      return '${base}_$workspaceId';
    }
    return '${base}_${scope}_$workspaceId';
  }

  Future<bool> isGettingStartedDismissed(
    String workspaceId, {
    String? scope,
  }) async {
    final prefs = await getPreferences();
    return prefs[_gettingStartedKey(
          'getting_started_dismissed',
          workspaceId,
          scope: scope,
        )] ==
        true;
  }

  Future<void> dismissGettingStarted(
    String workspaceId, {
    String? scope,
  }) async {
    await updatePreferenceKey(
      _gettingStartedKey(
        'getting_started_dismissed',
        workspaceId,
        scope: scope,
      ),
      true,
    );
  }

  Future<bool> isGettingStartedCompleted(
    String workspaceId, {
    String? scope,
  }) async {
    final prefs = await getPreferences();
    return prefs[_gettingStartedKey(
          'getting_started_completed',
          workspaceId,
          scope: scope,
        )] ==
        true;
  }

  Future<void> markGettingStartedCompleted(
    String workspaceId, {
    String? scope,
  }) async {
    await updatePreferenceKey(
      _gettingStartedKey(
        'getting_started_completed',
        workspaceId,
        scope: scope,
      ),
      true,
    );
  }

  // ---------------------------------------------------------------------------
  // Quick action configuration
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getQuickActionConfig() async {
    final prefs = await getPreferences();
    final raw = prefs['quick_action_config'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  Future<void> saveQuickActionConfig(Map<String, dynamic> config) async {
    await updatePreferenceKey('quick_action_config', config);
  }

  // ---------------------------------------------------------------------------
  // KPI dashboard date range
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getKpiDashboardRangeConfig() async {
    final prefs = await getPreferences();
    final raw = prefs['kpi_dashboard_range'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  Future<void> saveKpiDashboardRangeConfig({
    required String preset,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    await updatePreferenceKey('kpi_dashboard_range', {
      'preset': preset,
      'custom_start': customStart?.toIso8601String(),
      'custom_end': customEnd?.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
