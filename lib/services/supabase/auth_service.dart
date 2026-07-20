import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/company_type.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../utils/app_logger.dart';
import '../../utils/timezone_options.dart';
import 'field_form_service.dart';

/// Supabase implementation of AuthService
///
/// This replaces the Firebase AuthService with Supabase equivalents.
/// The API is kept similar for easier migration.
class SupabaseAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _signupEmailRedirectTo =
      'https://app.example.com/#/verify-email-pending';
  static const String _bugsEmail = 'bugs@example.com';

  String _buildEmailRedirectTo(String? from) {
    final trimmed = from?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        !trimmed.startsWith('/') ||
        trimmed.startsWith('//')) {
      return _signupEmailRedirectTo;
    }
    return '$_signupEmailRedirectTo?from=${Uri.encodeComponent(trimmed)}';
  }

  /// Get current user (Supabase User, not AppUser)
  User? get currentUser => _supabase.auth.currentUser;

  /// Get current user ID
  String? get currentUserId => _supabase.auth.currentUser?.id;

  /// Auth state stream (raw Supabase events)
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// User changes stream - compatible with Firebase pattern
  /// Emits User? whenever auth state changes
  Stream<User?> get userChanges =>
      _supabase.auth.onAuthStateChange.map((state) => state.session?.user);

  /// Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
    CompanyType? companyType,
    String? redirectTo,
  }) async {
    try {
      AppLogger.info('SIGNUP: Starting signup for $email');

      // Validate email format
      if (!_isValidEmail(email)) {
        throw AuthException('Invalid email format');
      }

      // Validate password length
      if (password.length < 6) {
        throw AuthException('Password must be at least 6 characters');
      }

      // Build emailRedirectTo so that whichever browser opens the email link
      // lands back in the original signup context (e.g. /invite/{token}).
      // Without this, Tab B (opened by the email link) has no idea an
      // invitation needs accepting and dumps the user on /.
      final emailRedirectTo = _buildEmailRedirectTo(redirectTo);

      // Create user in Supabase Auth
      AppLogger.info('SIGNUP: Creating Supabase Auth user...');
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName ?? email.split('@')[0]},
        emailRedirectTo: emailRedirectTo,
      );

      if (response.user == null) {
        throw AuthException('Failed to create user account');
      }

      AppLogger.info(
        'SIGNUP: Supabase Auth user created',
        metadata: {'userId': response.user!.id},
      );

      final requiresEmailConfirmation = response.user!.emailConfirmedAt == null;

      // Email/password signup must remain pending until confirmation is complete.
      // If Supabase returns a session here unexpectedly, clear it to avoid
      // skipping the verification screen and onboarding flow.
      if (requiresEmailConfirmation) {
        if (response.session != null) {
          AppLogger.warning(
            'SIGNUP: Session returned before email confirmation; signing out to enforce verification step',
          );
          await _supabase.auth.signOut();
        }
        AppLogger.info('SIGNUP: Awaiting email confirmation');
        return response;
      }

      AppLogger.info('SIGNUP: Session established directly from signUp');
      await _ensureUserBootstrap(
        response.user!,
        displayName: displayName,
        companyType: companyType,
      );

      AppLogger.info('SIGNUP: Signup completed successfully!');
      return response;
    } on AuthException catch (e) {
      AppLogger.error('AuthException during signup', error: e);
      throw _handleAuthException(e);
    } catch (e, stackTrace) {
      AppLogger.error('Error during signup', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        await _ensureUserBootstrap(response.user!);
      }
      return response;
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with Google OAuth
  Future<AuthResponse> signInWithGoogle() async {
    try {
      // Trigger the Google OAuth flow
      final response = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo:
            'io.supabase.taskfleet://login-callback/', // Update for your app
      );

      // Note: OAuth returns after redirect, check if user exists
      // The actual user creation happens in the auth callback
      if (!response) {
        throw AuthException('Google sign-in was cancelled');
      }

      // For OAuth, we need to wait for the auth state to change
      // The user will be available after the redirect
      final authState = await _supabase.auth.onAuthStateChange.first;

      if (authState.session == null) {
        throw AuthException('Failed to complete Google sign-in');
      }

      final user = authState.session!.user;
      await _ensureUserBootstrap(
        user,
        displayName: user.userMetadata?['full_name'],
      );

      return AuthResponse(session: authState.session, user: user);
    } on AuthException catch (e) {
      AppLogger.error('AuthException during Google sign-in', error: e);
      throw _handleAuthException(e);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error during Google sign-in',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Sign out of every device for this user (revoke all refresh tokens).
  /// Local session is also cleared.
  Future<void> signOutEverywhere() async {
    await _supabase.auth.signOut(scope: SignOutScope.global);
  }

  /// Whether the current user can update an email/password credential.
  /// Returns false for OAuth-only accounts (e.g. Google sign-in without
  /// a password set).
  bool get currentUserHasPasswordIdentity {
    final identities = _supabase.auth.currentUser?.identities ?? const [];
    return identities.any((i) => i.provider == 'email');
  }

  /// Change the current user's password. Re-authenticates with the
  /// supplied [currentPassword] before applying [newPassword] so that a
  /// hijacked session can't silently lock the account out.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _supabase.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw AuthException('No signed-in user');
    }
    if (newPassword.length < 6) {
      throw AuthException('Password must be at least 6 characters');
    }
    if (currentPassword == newPassword) {
      throw AuthException(
        'New password must be different from your current password',
      );
    }

    try {
      // Verify the current password — Supabase's updateUser doesn't ask
      // for it, so this is the security gate.
      await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login') ||
          msg.contains('invalid credentials')) {
        throw Exception('Current password is incorrect');
      }
      AppLogger.error('Error verifying current password', error: e);
      throw _handleAuthException(e);
    }

    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      AppLogger.error('Error updating password', error: e);
      throw _handleAuthException(e);
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      if (!_isValidEmail(email)) {
        throw AuthException('Invalid email format');
      }

      await _supabase.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      AppLogger.error('Error sending password reset', error: e);
      throw _handleAuthException(e);
    }
  }

  /// Resend verification email (Supabase handles this automatically on signup)
  Future<void> resendVerificationEmail({String? email}) async {
    final targetEmail = email?.trim();
    final resolvedEmail = (targetEmail != null && targetEmail.isNotEmpty)
        ? targetEmail
        : currentUser?.email;
    if (resolvedEmail == null || resolvedEmail.isEmpty) {
      throw AuthException('No email available for verification resend');
    }

    await _supabase.auth.resend(type: OtpType.signup, email: resolvedEmail);
  }

  /// Ensure the authenticated user has corresponding app bootstrap data.
  Future<void> ensureCurrentUserBootstrap() async {
    final user = currentUser;
    if (user == null) return;
    await _ensureUserBootstrap(user);
  }

  /// Get user document from database
  Future<AppUser?> getUserDocument(String userId) async {
    try {
      AppLogger.debug('Fetching user document', metadata: {'userId': userId});

      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        AppLogger.debug('User document found');
        return AppUser.fromJson(_convertToFirestoreFormat(response), userId);
      }

      AppLogger.warning(
        'User document does not exist',
        metadata: {'userId': userId},
      );
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error fetching user document',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Error fetching user document: $e');
    }
  }

  /// Update user role
  Future<void> updateUserRole(String userId, UserRole newRole) async {
    try {
      await _supabase
          .from('users')
          .update({
            'role': newRole.toString(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      throw Exception('Error updating user role: $e');
    }
  }

  /// Get all users in a workspace
  Stream<List<AppUser>> getWorkspaceUsers(String workspaceId) {
    return _supabase
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('active_workspace_id', workspaceId)
        .map(
          (data) => data
              .map(
                (row) =>
                    AppUser.fromJson(_convertToFirestoreFormat(row), row['id']),
              )
              .toList(),
        );
  }

  /// Create user document
  Future<void> _createUserDocument(
    User user,
    String? workspaceId,
    String? displayName, {
    UserRole? role,
  }) async {
    final now = DateTime.now();
    final userRole = role ?? UserRole.admin;
    final emailVerified = user.emailConfirmedAt != null;

    // Use upsert with ignoreDuplicates so a concurrent bootstrap call
    // (signIn() + AuthProvider auth-state change both fire _ensureUserBootstrap)
    // doesn't blow up with a 409 on users_email_key / users_pkey.
    await _supabase.from('users').upsert({
      'id': user.id,
      'email': user.email,
      'display_name': displayName,
      'active_workspace_id': workspaceId,
      'default_workspace_id': workspaceId,
      'role': _mapUserRoleToDbRole(userRole),
      'email_verified': emailVerified,
      'email_verified_at': user.emailConfirmedAt,
      'notification_preferences': {
        'taskAssignmentsEmail': true,
        'taskAssignmentsPush': true,
        'taskCompletionsEmail': true,
        'taskCompletionsPush': true,
        'projectUpdatesEmail': true,
        'projectUpdatesPush': true,
        'mentionsEmail': true,
        'mentionsPush': true,
      },
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }, ignoreDuplicates: true);

    // Create workspace member entry ONLY if workspaceId is provided
    if (workspaceId != null) {
      await _supabase.from('workspace_members').insert({
        'workspace_id': workspaceId,
        'user_id': user.id,
        'role': _mapUserRoleToMemberRole(userRole),
        'created_at': now.toIso8601String(),
      });
    }
  }

  Future<void> _ensureUserBootstrap(
    User user, {
    String? displayName,
    CompanyType? companyType,
  }) async {
    final existingUser = await getUserDocument(user.id);
    if (existingUser != null) {
      await _syncEmailVerificationState(user, existingUser);
      return;
    }

    final effectiveDisplayName =
        displayName ??
        user.userMetadata?['display_name']?.toString() ??
        user.userMetadata?['full_name']?.toString() ??
        user.email?.split('@')[0] ??
        'User';
    final effectiveCompanyType = companyType ?? CompanyType.other;
    final hasPendingInvitation = await _authUserHasPendingWorkspaceInvitation();
    final assignedRole = hasPendingInvitation
        ? UserRole.fieldTechnician
        : UserRole.admin;
    AppLogger.info(
      'SIGNUP: Bootstrap state',
      metadata: {
        'userId': user.id,
        'email': user.email,
        'hasPendingInvitation': hasPendingInvitation,
        'assignedRole': assignedRole.name,
        'dbRole': _mapUserRoleToDbRole(assignedRole),
      },
    );

    // 1. Create user document FIRST (with null workspaceId)
    // This is required because workspaces table has FK to users table
    AppLogger.info('SIGNUP: Creating user document...');
    await _createUserDocument(
      user,
      null, // No workspace yet
      effectiveDisplayName,
      role: hasPendingInvitation ? UserRole.fieldTechnician : UserRole.admin,
    );
    AppLogger.info('SIGNUP: User document created successfully');

    if (hasPendingInvitation) {
      AppLogger.info(
        'SIGNUP: Pending invitation detected; skipping automatic workspace creation',
        metadata: {'userId': user.id, 'email': user.email},
      );
      return;
    }

    // 2. Create workspace + owner membership + set active workspace atomically.
    //    bootstrap_owner_workspace is a SECURITY DEFINER RPC that wraps all
    //    three writes in one transaction, so a failure cannot orphan the
    //    workspace.
    //
    //    Concurrency note: this method is called from at least three places
    //    (signUp(), signIn() result handler, auth-state listener), and on
    //    a fresh signup the email-verify + first-sign-in callbacks can both
    //    race past the `existingUser != null` guard at the top of this
    //    method, producing duplicate workspaces. Re-fetch the user row
    //    just before issuing the RPC so we don't double-bootstrap. The
    //    user-doc upsert above is idempotent; this re-check makes the
    //    workspace creation idempotent too.
    final freshExisting = await getUserDocument(user.id);
    final alreadyHasWorkspace =
        freshExisting?.workspaceId.isNotEmpty == true ||
        freshExisting?.activeWorkspaceId?.isNotEmpty == true;
    if (alreadyHasWorkspace) {
      AppLogger.info(
        'SIGNUP: A concurrent bootstrap already created a workspace; '
        'skipping duplicate bootstrap_owner_workspace call',
        metadata: {
          'userId': user.id,
          'workspaceId': freshExisting?.activeWorkspaceId ??
              freshExisting?.workspaceId,
        },
      );
      return;
    }

    AppLogger.info('SIGNUP: Bootstrapping workspace (atomic RPC)...');
    final bootstrapResponse = await _supabase.rpc(
      'bootstrap_owner_workspace',
      params: {
        'p_name': '$effectiveDisplayName\'s Company',
        'p_company_type': effectiveCompanyType.name,
        'p_project_terminology': effectiveCompanyType.defaultProjectTerminology,
        'p_enabled_project_tabs': effectiveCompanyType.defaultEnabledTabs,
        'p_timezone': TimezoneOptions.defaultTimezone,
      },
    );
    final workspaceId = (bootstrapResponse as Map)['workspaceId'] as String?;
    if (workspaceId == null) {
      throw Exception('bootstrap_owner_workspace returned no workspaceId');
    }
    AppLogger.info(
      'SIGNUP: Workspace bootstrap complete',
      metadata: {'workspaceId': workspaceId},
    );

    // 3. Best-effort seeds. If these fail the workspace is still usable;
    //    they log warnings internally and must not roll back the bootstrap.
    AppLogger.info('SIGNUP: Creating default cost categories...');
    await _createDefaultCostCategories(workspaceId);
    await _seedCoreDocumentTemplates(workspaceId, user.id);
    await _seedCoreWorkflowTemplates(workspaceId, user.id);
    await _seedDefaultFieldFormTemplates(workspaceId, user.id);
  }

  Future<bool> _authUserHasPendingWorkspaceInvitation() async {
    try {
      final response = await _supabase.rpc(
        'auth_user_has_pending_workspace_invitation',
      );
      if (response is bool) {
        return response;
      }
      if (response is num) {
        return response != 0;
      }
      if (response is String) {
        return response.toLowerCase() == 'true';
      }
      return false;
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Failed to evaluate pending invitation status during bootstrap',
        metadata: {'error': e.toString(), 'stackTrace': stackTrace.toString()},
      );
      return false;
    }
  }

  Future<void> _syncEmailVerificationState(User user, AppUser appUser) async {
    if (user.emailConfirmedAt == null || appUser.emailVerified == true) {
      return;
    }

    await _supabase
        .from('users')
        .update({
          'email_verified': true,
          'email_verified_at': user.emailConfirmedAt,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', user.id);
  }

  /// Create default cost categories for a workspace
  Future<void> _createDefaultCostCategories(String workspaceId) async {
    final categories = [
      {'name': 'Materials', 'color': '#3B82F6', 'is_default': true},
      {'name': 'Labor', 'color': '#10B981', 'is_default': true},
      {'name': 'Equipment', 'color': '#F59E0B', 'is_default': true},
      {'name': 'Subcontractor', 'color': '#8B5CF6', 'is_default': true},
      {'name': 'Permits & Fees', 'color': '#EF4444', 'is_default': true},
      {'name': 'Overhead', 'color': '#6B7280', 'is_default': true},
    ];

    for (final category in categories) {
      await _supabase.from('cost_categories').insert({
        'workspace_id': workspaceId,
        ...category,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _seedCoreDocumentTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      await _supabase.rpc(
        'seed_core_document_templates',
        params: {'p_workspace_id': workspaceId, 'p_created_by': createdBy},
      );
    } catch (e, stackTrace) {
      // Template seeding should not block account creation.
      AppLogger.warning(
        'Failed to seed core document templates',
        metadata: {
          'workspaceId': workspaceId,
          'createdBy': createdBy,
          'error': e.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  Future<void> _seedCoreWorkflowTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      await _supabase.rpc(
        'seed_core_workflow_templates',
        params: {'p_workspace_id': workspaceId, 'p_created_by': createdBy},
      );
    } catch (e, stackTrace) {
      // Template seeding should not block account creation.
      AppLogger.warning(
        'Failed to seed core workflow templates',
        metadata: {
          'workspaceId': workspaceId,
          'createdBy': createdBy,
          'error': e.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  Future<void> _seedDefaultFieldFormTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      await FieldFormService().generateDefaultTemplates(
        workspaceId: workspaceId,
        createdBy: createdBy,
      );
    } catch (e, stackTrace) {
      // Template seeding should not block account creation.
      AppLogger.warning(
        'Failed to seed default field form templates',
        metadata: {
          'workspaceId': workspaceId,
          'createdBy': createdBy,
          'error': e.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  /// Map UserRole to user_role DB enum
  String _mapUserRoleToDbRole(UserRole role) {
    switch (role) {
      case UserRole.masterAdmin:
        return 'admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.projectManager:
        return 'project_manager';
      case UserRole.fieldTechnician:
        return 'technician';
      case UserRole.client:
        return 'customer';
      case UserRole.vendor:
        return 'customer';
    }
  }

  /// Map UserRole to workspace_member_role
  String _mapUserRoleToMemberRole(UserRole role) {
    switch (role) {
      case UserRole.masterAdmin:
        return 'master_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.projectManager:
        return 'project_manager';
      case UserRole.fieldTechnician:
        return 'field_technician';
      case UserRole.client:
        return 'client';
      case UserRole.vendor:
        return 'vendor';
    }
  }

  /// Convert PostgreSQL snake_case to Firestore camelCase for model compatibility
  Map<String, dynamic> _convertToFirestoreFormat(Map<String, dynamic> data) {
    AppLogger.debug('Converting Supabase user data', metadata: data);
    return {
      'id': data['id'],
      'email': data['email'],
      'displayName': data['display_name'],
      'workspaceId': data['active_workspace_id'], // Legacy field
      'activeWorkspaceId': data['active_workspace_id'],
      'defaultWorkspaceId': data['default_workspace_id'],
      'role': data['role'],
      'emailVerified': data['email_verified'],
      'emailVerifiedAt': data['email_verified_at'],
      'profilePictureUrl': data['profile_picture_url'],
      'phoneNumber': data['phone_number'],
      'jobTitle': data['job_title'],
      'bio': data['bio'],
      'companyName': data['company_name'],
      'timezone': data['timezone'],
      'hourlyRate': data['hourly_rate'],
      'notificationPreferences': data['notification_preferences'],
      'createdAt': data['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(data['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': data['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(data['updated_at']))
          : _FakeTimestamp(DateTime.now()),
    };
  }

  /// Validate email format
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  /// Handle Supabase Auth exceptions
  Exception _handleAuthException(AuthException e) {
    final message = e.message.toLowerCase();

    if (_isAuthConnectivityIssue(message)) {
      return Exception(
        'Unable to reach authentication services right now. '
        'Please check your connection and try again. '
        'If this keeps happening, email $_bugsEmail.',
      );
    }

    if (message.contains('already registered') ||
        message.contains('already been registered') ||
        e.statusCode == '422') {
      return Exception('An account already exists with this email');
    }
    if (message.contains('invalid email')) {
      return Exception('Invalid email address');
    }
    if (message.contains('weak password') ||
        message.contains('password must be at least') ||
        message.contains('password should be at least') ||
        message.contains('password is too short')) {
      return Exception('Password is too weak');
    }
    if (message.contains('user not found') || message.contains('no user')) {
      return Exception('No account found with this email');
    }
    if (message.contains('invalid login') ||
        message.contains('invalid credentials')) {
      return Exception('Invalid email or password');
    }
    if (message.contains('email not confirmed')) {
      return Exception('Please verify your email before signing in');
    }

    return Exception(
      'Authentication error. Please try again. '
      'If the issue continues, email $_bugsEmail.',
    );
  }

  bool _isAuthConnectivityIssue(String message) {
    return message.contains('authretryablefetchexception') ||
        message.contains('failed to fetch') ||
        message.contains('clientexception') ||
        message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection reset by peer') ||
        message.contains('connection closed') ||
        message.contains('connection refused') ||
        message.contains('/auth/v1/token?grant_type=password') ||
        message.contains('/auth/v1/token?grant_type=refresh_token');
  }
}

/// Wrapper class to mimic Firestore Timestamp for model compatibility
class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
