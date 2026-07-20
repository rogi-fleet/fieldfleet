import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/workspace.dart';
import '../models/workspace_membership.dart';
import '../models/user_role.dart';
import '../services/ai_service.dart';
import '../services/service_locator.dart';
import '../utils/app_logger.dart';

class WorkspaceProvider with ChangeNotifier {
  final dynamic _memberService = ServiceLocator.workspaceMemberService;

  List<WorkspaceMembership> _workspaces = [];
  bool _isLoading = false;
  String? _error;
  String? _currentWorkspaceId;

  /// Workspaces whose built-in field form templates have already been
  /// reconciled this app session — keeps the catch-up seed to once per
  /// workspace per launch.
  final Set<String> _reconciledFieldFormDefaults = {};

  List<WorkspaceMembership> get workspaces => _workspaces;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Set the current workspace ID to enable proper terminology lookup
  void setCurrentWorkspaceId(String? workspaceId) {
    if (_currentWorkspaceId != workspaceId) {
      _currentWorkspaceId = workspaceId;
      notifyListeners();
    }
  }

  String get projectTerminology {
    if (_workspaces.isEmpty) {
      return 'Projects'; // Default terminology when no workspace loaded yet
    }

    // Find the workspace matching the current workspace ID
    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.projectTerminology ?? 'Projects';
  }

  List<String> get enabledNavigationTabs {
    if (_workspaces.isEmpty) {
      return [];
    }

    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.enabledNavigationTabs;
  }

  String get currentWorkspaceName {
    if (_workspaces.isEmpty) {
      return 'Projects';
    }

    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.workspaceName;
  }

  /// Whether the active workspace has finished onboarding. Returns true when
  /// no workspace is loaded yet so the router doesn't bounce users to
  /// /onboarding while still hydrating.
  bool get currentWorkspaceOnboardingCompleted {
    if (_workspaces.isEmpty) return true;
    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.onboardingCompleted;
  }

  bool get showBusinessDaysOnly {
    if (_workspaces.isEmpty) {
      return false;
    }

    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.showBusinessDaysOnly;
  }

  String get currencyCode {
    if (_workspaces.isEmpty) {
      return 'USD';
    }

    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.currencyCode;
  }

  String get timezone {
    if (_workspaces.isEmpty) {
      return 'UTC';
    }

    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.timezone;
  }

  UnitSystem get unitSystem {
    if (_workspaces.isEmpty) {
      return UnitSystem.imperial;
    }
    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.unitSystem;
  }

  bool get defaultTaxEnabled {
    if (_workspaces.isEmpty) return true;
    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.defaultTaxEnabled;
  }

  String get defaultTaxName {
    if (_workspaces.isEmpty) return 'Tax';
    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.defaultTaxName;
  }

  double get defaultTaxRate {
    if (_workspaces.isEmpty) return 0;
    final activeWorkspace = _workspaces.firstWhere(
      (w) => w.workspaceId == _currentWorkspaceId,
      orElse: () => _workspaces.first,
    );
    return activeWorkspace.defaultTaxRate;
  }

  /// Get the active workspace membership if available
  WorkspaceMembership? get activeWorkspace {
    if (_workspaces.isEmpty) {
      return null;
    }
    try {
      return _workspaces.firstWhere(
        (w) => w.workspaceId == _currentWorkspaceId,
      );
    } catch (_) {
      return _workspaces.isNotEmpty ? _workspaces.first : null;
    }
  }

  /// Returns the AI persona context for the active workspace.
  AiPersonaContext? get aiPersonaContext {
    final ws = activeWorkspace;
    if (ws == null) return null;
    return AiPersonaContext(
      name: ws.aiPersonaName,
      style: ws.aiPersonaStyle,
      customContext: ws.aiPersonaContext,
      workspaceName: ws.workspaceName,
    );
  }

  Future<void> loadWorkspaces(String userId) async {
    try {
      if (kDebugMode) print('WorkspaceProvider: Loading workspaces for user $userId');
      _isLoading = true;
      _error = null;
      notifyListeners();

      _workspaces = await _memberService.getUserWorkspaces(userId);
      _reconcileDefaultFieldForms(userId);
      if (kDebugMode) {
        print('WorkspaceProvider: Loaded ${_workspaces.length} workspaces');
        for (var ws in _workspaces) {
          print(
            '  - ${ws.workspaceName} (${ws.workspaceId}) - terminology: ${ws.projectTerminology}',
          );
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading workspaces', error: e);
      if (kDebugMode) print('WorkspaceProvider: Error loading workspaces: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Best-effort catch-up: bring each owned/admin workspace's built-in field
  /// form templates in line with the canonical definitions (insert newly added
  /// defaults, push version bumps to unedited copies). Fire-and-forget so it
  /// never blocks workspace loading; runs at most once per workspace per
  /// session and only for members who can manage the workspace. The underlying
  /// reconcile is idempotent and leaves edited/user templates untouched.
  void _reconcileDefaultFieldForms(String userId) {
    for (final ws in _workspaces) {
      final role = ws.role;
      final canManage =
          role == UserRole.masterAdmin || role == UserRole.admin;
      if (!canManage) continue;
      // add() returns false if the id was already present this session.
      if (!_reconciledFieldFormDefaults.add(ws.workspaceId)) continue;
      unawaited(
        ServiceLocator.fieldFormService
            .generateDefaultTemplates(
              workspaceId: ws.workspaceId,
              createdBy: userId,
            )
            .catchError((Object e) {
          // Allow a retry on the next load if it failed.
          _reconciledFieldFormDefaults.remove(ws.workspaceId);
          AppLogger.warning(
            'Failed to reconcile default field form templates',
            metadata: {'workspaceId': ws.workspaceId, 'error': e.toString()},
          );
        }),
      );
    }
  }

  void clear() {
    _workspaces = [];
    _error = null;
    _currentWorkspaceId = null;
    _reconciledFieldFormDefaults.clear();
    notifyListeners();
  }
}
