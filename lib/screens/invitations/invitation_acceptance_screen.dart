import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/workspace_invitation.dart';
import '../../services/supabase/invitation_service.dart';
import '../../services/supabase/workspace_service.dart';
import '../../services/supabase/user_service.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';

class InvitationAcceptanceScreen extends StatefulWidget {
  final String token;

  const InvitationAcceptanceScreen({super.key, required this.token});

  @override
  State<InvitationAcceptanceScreen> createState() =>
      _InvitationAcceptanceScreenState();
}

class _InvitationAcceptanceScreenState
    extends State<InvitationAcceptanceScreen> {
  final SupabaseInvitationService _invitationService =
      SupabaseInvitationService();
  final SupabaseWorkspaceService _workspaceService = SupabaseWorkspaceService();
  final SupabaseUserService _userService = SupabaseUserService();

  bool _isLoading = true;
  bool _isAccepting = false;
  WorkspaceInvitation? _invitation;
  String? _errorMessage;
  String? _workspaceName;
  String? _inviterName;
  String? _roleName;
  bool _userExists = false;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  Future<void> _loadInvitation() async {
    try {
      final invitation = await _invitationService.getInvitationByToken(
        widget.token,
      );

      if (invitation == null) {
        setState(() {
          _errorMessage = 'Invitation not found or invalid';
          _isLoading = false;
        });
        return;
      }

      // Prefer context returned by token RPC. Fall back to direct queries for
      // environments that don't yet include the enriched RPC response.
      String workspaceName =
          _nonEmptyOrNull(invitation.workspaceName) ?? 'Unknown Workspace';
      if (workspaceName == 'Unknown Workspace') {
        try {
          final workspaceStream = _workspaceService.getWorkspace(
            invitation.workspaceId,
          );
          final workspaceData = await workspaceStream.first;
          workspaceName =
              _nonEmptyOrNull(workspaceData?['name'] as String?) ??
              'Unknown Workspace';
        } catch (e) {
          AppLogger.error('Failed to fetch workspace name', error: e);
        }
      }

      String inviterName =
          _nonEmptyOrNull(invitation.inviterName) ?? 'A team member';
      if (inviterName == 'A team member') {
        try {
          final inviter = await _userService.getUserById(invitation.invitedBy);
          if (inviter != null) {
            inviterName =
                _nonEmptyOrNull(inviter.displayName) ??
                _nonEmptyOrNull(inviter.email) ??
                'A team member';
          }
        } catch (e) {
          AppLogger.error('Failed to fetch inviter name', error: e);
        }
      }

      String roleName = invitation.displayRoleName;
      if (invitation.roleTemplateId != null) {
        try {
          final template = await ServiceLocator.roleTemplateService
              .getTemplateById(templateId: invitation.roleTemplateId!);
          final templateName = template?.name.trim();
          if (templateName != null && templateName.isNotEmpty) {
            roleName = templateName;
          }
        } catch (e) {
          AppLogger.warning(
            'Failed to fetch invitation role template',
            metadata: {
              'roleTemplateId': invitation.roleTemplateId,
              'error': e.toString(),
            },
          );
        }
      }

      // Check if user with this email already exists
      final userExists = await _invitationService.checkUserExistsByEmail(
        invitation.email,
      );

      setState(() {
        _invitation = invitation;
        _workspaceName = workspaceName;
        _inviterName = inviterName;
        _roleName = roleName;
        _userExists = userExists;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load invitation', error: e);
      setState(() {
        _errorMessage = 'Failed to load invitation';
        _isLoading = false;
      });
    }
  }

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> _acceptInvitation() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.appUser?.id;

    if (userId == null) {
      return;
    }

    setState(() => _isAccepting = true);

    try {
      await _invitationService.acceptInvitation(token: widget.token);

      if (mounted) {
        // Redirect to welcome screen so the new member can set up their profile
        final encodedName = Uri.encodeComponent(_workspaceName ?? '');
        context.go('/welcome?workspace=$encodedName');
      }
    } catch (e) {
      AppLogger.error('Failed to accept invitation', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Failed to accept invitation: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAccepting = false);
      }
    }
  }

  void _declineInvitation() {
    // Navigate to login or home since user may have come from email link
    context.go('/login');
  }

  /// Check if the currently logged in user's email matches the invitation email
  bool _isEmailMismatch(AuthProvider authProvider) {
    final appUser = authProvider.appUser;
    final invitation = _invitation;
    if (appUser == null || invitation == null) {
      return false;
    }
    final currentUserEmail = appUser.email.toLowerCase().trim();
    final invitationEmail = invitation.email.toLowerCase().trim();
    return currentUserEmail != invitationEmail;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace Invitation'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
          tooltip: 'Close',
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorView()
          : _invitation != null
          ? _buildInvitationView()
          : const SizedBox.shrink(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('Go to Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitationView() {
    final invitation = _invitation!;
    final authProvider = Provider.of<AuthProvider>(context);

    // Check if expired
    if (invitation.isExpired) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 64, color: AppColors.warning),
              const SizedBox(height: 16),
              Text(
                'Invitation Expired',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'This invitation has expired. Please request a new invitation from the workspace admin.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/login'),
                child: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    // Check if already accepted
    if (invitation.status == InvitationStatus.accepted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: AppColors.success,
              ),
              const SizedBox(height: 16),
              Text(
                'Already Accepted',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'This invitation has already been accepted.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    // Check for email mismatch when logged in
    final emailMismatch =
        authProvider.appUser != null && _isEmailMismatch(authProvider);

    return Center(
      child: Card(
        margin: const EdgeInsets.all(AppSpacing.xl),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mail_outline,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'You\'ve been invited!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$_inviterName has invited you to join $_workspaceName as a ${_roleName ?? invitation.role.displayName}.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Invitation sent to: ${invitation.email}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
              ),

              // Email mismatch warning
              if (emailMismatch) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.warningDark,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Email mismatch',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.warningDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You\'re logged in as ${authProvider.appUser?.email}, but this invitation was sent to ${invitation.email}. Please log in with the correct account.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.warningDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (authProvider.appUser == null) ...[
                    if (_userExists) ...[
                      // User already has an account, show login only
                      FilledButton(
                        onPressed: () =>
                            context.go('/login?from=/invite/${widget.token}'),
                        child: const Text('Log In to Accept'),
                      ),
                    ] else ...[
                      // New user, show sign up only
                      FilledButton(
                        onPressed: () => context.go(
                          '/signup?email=${Uri.encodeComponent(_invitation!.email)}&from=/invite/${widget.token}',
                        ),
                        child: const Text('Sign Up to Accept'),
                      ),
                    ],
                  ] else if (emailMismatch) ...[
                    // Email mismatch - show option to switch accounts
                    OutlinedButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Go to Dashboard'),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: () async {
                        // Log out and redirect to login with return URL
                        await authProvider.signOut();
                        if (mounted) {
                          context.go('/login?from=/invite/${widget.token}');
                        }
                      },
                      child: const Text('Switch Account'),
                    ),
                  ] else ...[
                    // Email matches - show accept/decline
                    OutlinedButton(
                      onPressed: _isAccepting ? null : _declineInvitation,
                      child: const Text('Decline'),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: _isAccepting ? null : _acceptInvitation,
                      child: _isAccepting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Accept Invitation'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
