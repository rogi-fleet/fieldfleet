import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import 'quick_action_config.dart';

/// Manages quick action configuration and state.
class QuickActionsController extends ChangeNotifier {
  QuickActionConfig _config = const QuickActionConfig(actions: []);
  bool _loading = true;

  QuickActionConfig get config => _config;
  bool get loading => _loading;
  bool _showPopup = true;
  bool get showPopup => _showPopup;

  List<QuickAction> get actions => _config.actions;

  /// Toggles whether tapping a quick action shows a popup or navigates directly.
  void togglePopupBehavior() {
    _showPopup = !_showPopup;
    notifyListeners();
  }

  /// Loads quick action configuration from preferences.
  Future<void> load() async {
    try {
      final raw = await ServiceLocator.userPreferencesService
          .getQuickActionConfig();
      if (raw.isNotEmpty) {
        _config = QuickActionConfig.fromJson(raw);
      } else {
        await resetDefaults();
        return;
      }
    } catch (_) {
      await resetDefaults();
      return;
    }
    _loading = false;
    notifyListeners();
  }

  /// Updates the quick action configuration.
  Future<void> updateConfig(QuickActionConfig newConfig) async {
    _config = newConfig;
    await ServiceLocator.userPreferencesService
        .saveQuickActionConfig(newConfig.toJson());
    notifyListeners();
  }

  /// Adds a new quick action.
  Future<void> addQuickAction(QuickAction action) async {
    final newActions = List<QuickAction>.from(_config.actions)
      ..add(action);
    final newConfig = _config.copyWith(actions: newActions);
    await updateConfig(newConfig);
  }

  /// Removes a quick action by label.
  Future<void> removeQuickAction(String label) async {
    final newActions = _config.actions.where((action) => action.label != label).toList();
    final newConfig = _config.copyWith(actions: newActions);
    await updateConfig(newConfig);
  }

  /// Updates an existing quick action.
  Future<void> updateQuickAction(String oldLabel, QuickAction newAction) async {
    final newActions = _config.actions
      .map((action) => action.label == oldLabel ? newAction : action)
      .toList();
    final newConfig = _config.copyWith(actions: newActions);
    await updateConfig(newConfig);
  }

  /// Resets to default quick actions.
  Future<void> resetDefaults() async {
    final defaultActions = const [
      QuickAction(
        label: 'New Project',
        icon: Icons.add_business,
        route: '/projects/new',
      ),
      QuickAction(
        label: 'New Task',
        icon: Icons.add_task,
        route: '/tasks',
      ),
      QuickAction(
        label: 'New Message',
        icon: Icons.chat,
        route: '/messages/new',
      ),
      QuickAction(
        label: 'New Document',
        icon: Icons.note_add,
        route: '/documents/create',
      ),
    ];
    final newConfig = QuickActionConfig(actions: defaultActions);
    await updateConfig(newConfig);
  }
}