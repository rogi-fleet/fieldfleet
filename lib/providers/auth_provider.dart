import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../models/company_type.dart';
import '../services/service_locator.dart';
import '../models/user.dart';
import '../models/role_permissions.dart';
import '../models/user_role.dart';
import '../utils/app_logger.dart';
import '../services/push_service.dart';

class AuthProvider with ChangeNotifier {
  late final dynamic _authService;
  late final dynamic _analytics;

  // Store user ID instead of platform-specific user object
  String? _currentUserId;
  bool? _emailVerified;
  AppUser? _appUser;
  RolePermissions? _rolePermissions;
  String _interfaceMode = 'manager';
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _authSubscription;

  String? get currentUserId => _currentUserId;
  bool? get emailVerified => _emailVerified;
  AppUser? get appUser => _appUser;
  UserRole get effectiveRole =>
      _rolePermissions?.legacyRole ?? _appUser?.role ?? UserRole.projectManager;
  RolePermissions? get rolePermissions => _rolePermissions;
  RolePermissions get effectivePermissions =>
      _rolePermissions ??
      RolePermissions.fromLegacyRole(_appUser?.role ?? UserRole.projectManager);
  bool get canManageUsers => effectivePermissions.canManageUsers;
  bool get canCreateProjects => effectivePermissions.canCreateProjects;
  bool get canEditProjects => effectivePermissions.canEditProjects;
  bool get canDeleteProjects => effectivePermissions.canDeleteProjects;
  bool get canCreateTasks => effectivePermissions.canCreateTasks;
  bool get canEditTasks => effectivePermissions.canEditTasks;
  bool get canDeleteTasks => effectivePermissions.canDeleteTasks;
  bool get canUploadFiles => effectivePermissions.canUploadFiles;
  bool get canDeleteFiles => effectivePermissions.canDeleteFiles;
  bool get canAccessSettings => effectivePermissions.canAccessSettings;
  bool get canViewFinancials => effectivePermissions.canViewFinancials;
  bool get isReadOnlyUser => effectivePermissions.isReadOnly;
  bool get isClientRole => effectivePermissions.isClientMode;
  String get effectiveRoleName =>
      _rolePermissions?.roleName ??
      _appUser?.role.displayName ??
      UserRole.projectManager.displayName;
  String get interfaceMode => _interfaceMode;

  /// Authoritative field-mode flag. Derived from the member's stored
  /// interface_mode (set when the user was invited or changed in profile),
  /// not from a permission heuristic — that kept drifting as module
  /// permissions were rewritten and mis-labelled external portal users as
  /// field workers.
  bool get isFieldMode => _interfaceMode == 'field';
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUserId != null;

  AuthProvider() {
    _authService = ServiceLocator.authService;
    _analytics = ServiceLocator.analyticsService;

    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authSubscription = _authService.userChanges.listen((user) async {
      final supabaseUser = user as supabase.User?;
      if (kDebugMode) print('🟢 AUTH STATE CHANGE: User ${supabaseUser?.id ?? "null"}');
      await _handleAuthStateChange(
        userId: supabaseUser?.id,
        emailVerified: supabaseUser?.emailConfirmedAt != null,
      );
    });
  }

  Future<void> _handleAuthStateChange({
    required String? userId,
    required bool? emailVerified,
  }) async {
    _currentUserId = userId;
    _emailVerified = emailVerified;

    // Refresh per-user view preferences (filters, columns, …). Runs in the
    // background — UI never blocks on this.
    unawaited(ServiceLocator.viewPrefsService.onAuthChanged(userId));

    if (userId != null) {
      if (kDebugMode) print('🟢 AUTH: Fetching user document for $userId...');
      _appUser = await _fetchUserDocumentWithRetry(userId);

      if (_appUser == null) {
        try {
          if (kDebugMode) print('🔵 AUTH: User doc missing, ensuring bootstrap...');
          await _authService.ensureCurrentUserBootstrap();
          _appUser = await _fetchUserDocumentWithRetry(userId);
        } catch (e, stackTrace) {
          AppLogger.warning(
            'Failed to bootstrap Supabase user during auth callback',
            metadata: {'userId': userId, 'error': e.toString()},
          );
          AppLogger.debug(
            'Bootstrap callback stack trace',
            metadata: {'stackTrace': stackTrace.toString()},
          );
        }
      }

      // Set user context for Crashlytics and Analytics
      if (_appUser != null) {
        if (kDebugMode) print('✅ AUTH: User document loaded - activeWorkspaceId: ${_appUser!.activeWorkspaceId}');
        await _refreshCurrentWorkspaceRole();

        final workspaceId =
            _appUser!.activeWorkspaceId ?? _appUser!.workspaceId;
        if (kDebugMode) print('ℹ️  AUTH: Using workspace ID: $workspaceId');
        await PushService.instance.onUserContextUpdated(_appUser!);
        await AppLogger.setUserContext(
          userId: userId,
          workspaceId: workspaceId,
        );
        await _analytics.setUserProperties(
          userId: userId,
          workspaceId: workspaceId,
          userRole: effectiveRoleName,
        );
      } else {
        if (kDebugMode) print('❌ AUTH: Failed to load user document after retries');
      }
    } else {
      _appUser = null;
      _rolePermissions = null;
      _interfaceMode = 'manager';
      if (kDebugMode) print('🟢 AUTH: User signed out, clearing context');
      // Clear user context on logout
      await AppLogger.clearUserContext();
      await _analytics.clearUserProperties();
    }
    notifyListeners();
  }

  Future<AppUser?> _fetchUserDocumentWithRetry(
    String userId, {
    int maxRetries = 3,
  }) async {
    // A null result (row doesn't exist or RLS hides it) is treated as a
    // definitive answer — the caller will run bootstrap and call us again.
    // Retries here only cover transient network/server errors.
    for (int i = 0; i < maxRetries; i++) {
      try {
        final userDoc = await _authService.getUserDocument(userId);
        if (kDebugMode) {
          if (userDoc != null) {
            print('  ✅ User document found');
          } else {
            print('  ⚠️  User document not found');
          }
        }
        return userDoc;
      } catch (e) {
        if (kDebugMode) print('  ❌ Error on attempt ${i + 1}/$maxRetries: $e');
        AppLogger.debug(
          'Error fetching user document, retrying',
          metadata: {
            'userId': userId,
            'attempt': i + 1,
            'maxRetries': maxRetries,
            'error': e.toString(),
          },
        );
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
        }
      }
    }

    if (kDebugMode) print('  ❌ Failed to fetch user document after $maxRetries retries');
    AppLogger.warning(
      'Failed to fetch user document after all retries',
      metadata: {'userId': userId, 'maxRetries': maxRetries},
    );
    return null;
  }

  /// Refresh the current user document from database
  Future<void> refreshUser() async {
    if (_currentUserId == null) return;

    _appUser = await _fetchUserDocumentWithRetry(
      _currentUserId!,
      maxRetries: 1,
    );
    await _refreshCurrentWorkspaceRole();
    notifyListeners();
  }

  Future<void> _refreshCurrentWorkspaceRole() async {
    if (_appUser == null || _currentUserId == null) {
      _rolePermissions = null;
      return;
    }

    final workspaceId = _appUser!.currentWorkspaceId;
    if (workspaceId.isEmpty) {
      _rolePermissions = RolePermissions.fromLegacyRole(_appUser!.role);
      _interfaceMode = _appUser!.role == UserRole.fieldTechnician
          ? 'field'
          : 'manager';
      return;
    }

    try {
      final data = await ServiceLocator.workspaceMemberService
          .getMemberRoleData(workspaceId, _currentUserId!);
      _rolePermissions =
          data.permissions ?? RolePermissions.fromLegacyRole(_appUser!.role);
      _interfaceMode = data.interfaceMode;
    } catch (e) {
      AppLogger.warning(
        'Failed to resolve workspace role data, using fallback',
        metadata: {
          'userId': _currentUserId,
          'workspaceId': workspaceId,
          'error': e.toString(),
        },
      );
      _rolePermissions = RolePermissions.fromLegacyRole(_appUser!.role);
      _interfaceMode = 'manager';
    }
  }

  Future<void> setInterfaceMode(String mode) async {
    if (_appUser == null || _currentUserId == null) return;
    final workspaceId = _appUser!.currentWorkspaceId;
    if (workspaceId.isEmpty) return;

    await ServiceLocator.workspaceMemberService.updateMemberSettings(
      workspaceId: workspaceId,
      userId: _currentUserId!,
      interfaceMode: mode,
    );
    _interfaceMode = mode;
    notifyListeners();
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
    CompanyType? companyType,
    String? redirectTo,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authService.signUp(
        email: email,
        password: password,
        displayName: displayName,
        companyType: companyType,
        redirectTo: redirectTo,
      );

      // Track signup event
      await _analytics.logSignup(method: 'email');

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authService.signIn(email: email, password: password);

      // Track login event
      await _analytics.logLogin(method: 'email');

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await _authService.signInWithGoogle();

      // User cancelled the OAuth flow
      if (result == null) {
        _isLoading = false;
        _errorMessage = 'Google sign-in was cancelled';
        notifyListeners();
        return;
      }

      await _analytics.logLogin(method: 'google');

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> switchWorkspace(String workspaceId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final userId = _currentUserId;
      if (userId == null || _appUser == null) {
        throw Exception('User not authenticated');
      }

      await supabase.Supabase.instance.client
          .from('users')
          .update({
            'active_workspace_id': workspaceId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      // Refresh user document
      _appUser = await _fetchUserDocumentWithRetry(userId);
      await _refreshCurrentWorkspaceRole();

      // Update analytics context
      await AppLogger.setUserContext(userId: userId, workspaceId: workspaceId);
      await _analytics.setUserProperties(
        userId: userId,
        workspaceId: workspaceId,
        userRole: effectiveRoleName,
      );
      if (_appUser != null) {
        await PushService.instance.onUserContextUpdated(_appUser!);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      AppLogger.info('Starting logout process');

      // Track logout event
      await _analytics.logLogout();

      AppLogger.info('Calling auth service signOut');
      // Flush any debounced view-prefs writes while we still have a valid
      // session, so the most recent UI state survives logout.
      await ServiceLocator.viewPrefsService.flush();
      await PushService.instance.onSignedOut();
      await _authService.signOut();

      AppLogger.info('Waiting for auth state to become null');
      await _authService.userChanges
          .firstWhere((user) => user == null)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              AppLogger.warning(
                'Auth state change timeout - proceeding anyway',
              );
              return null;
            },
          );

      AppLogger.info('Logout complete');
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error during logout', error: e);
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Whether the signed-in user has an email/password identity (vs.
  /// OAuth-only). Used by the profile screen to decide whether to show
  /// the change-password row.
  bool get hasPasswordIdentity =>
      _authService.currentUserHasPasswordIdentity == true;

  /// Change the signed-in user's password. Throws on failure with a
  /// user-facing message.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _authService.updatePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// Sign out of every device for this user.
  Future<void> signOutEverywhere() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _analytics.logLogout();
      await ServiceLocator.viewPrefsService.flush();
      await PushService.instance.onSignedOut();
      await _authService.signOutEverywhere();

      await _authService.userChanges
          .firstWhere((user) => user == null)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              AppLogger.warning(
                'Auth state change timeout - proceeding anyway',
              );
              return null;
            },
          );

      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error during global sign-out', error: e);
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authService.sendPasswordResetEmail(email);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
