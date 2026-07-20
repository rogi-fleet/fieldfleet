import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/role_permissions.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../models/vehicle.dart';
import '../../models/workspace_member.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/vehicle_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/messaging_popup.dart';
import '../../widgets/image_upload_options_dialog.dart';
import '../../widgets/forms/stacked_field.dart';
import '../../theme/theme.dart';
import '../../utils/app_time_formatter.dart';
import '../../utils/timezone_options.dart';
import 'widgets/profile_appearance_card.dart';
import 'widgets/profile_notifications_card.dart';
import 'widgets/profile_security_card.dart';

class ProfileViewScreen extends StatefulWidget {
  final String? userId;

  const ProfileViewScreen({super.key, this.userId});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  final _userService = ServiceLocator.userService;
  final _messageService = ServiceLocator.messageService;
  final _imagePicker = ImagePicker();
  AppUser? _user;
  WorkspaceMember? _workspaceMember;
  bool _isLoading = true;
  bool _isUploadingImage = false;
  String? _error;

  // Edit form state (used for own profile inline editing)
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _bioController = TextEditingController();
  String? _selectedTimezone;
  NotificationPreferences _notificationPreferences =
      const NotificationPreferences();
  bool _isSaving = false;

  bool _profileLoadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Defer the initial load until appUser has hydrated. On a cold load/refresh
    // of /profile appUser is briefly null; loading from initState read that
    // null and set a permanent "User not found". listen:true re-fires this once
    // appUser arrives. A specific /profile/:userId can load immediately.
    if (_profileLoadStarted) return;
    final hasUser = Provider.of<AuthProvider>(context).appUser != null;
    if (widget.userId != null || hasUser) {
      _profileLoadStarted = true;
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _jobTitleController.dispose();
    _companyNameController.dispose();
    _phoneNumberController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.appUser?.id;
      final viewUserId = widget.userId ?? currentUserId;

      if (viewUserId == null) {
        setState(() {
          _error = 'User not found';
          _isLoading = false;
        });
        return;
      }

      var user = await _userService.getUserById(viewUserId);
      // For a freshly-provisioned user, the auth row exists but the
      // `users` table row may not be inserted yet (workspace bootstrap
      // creates it lazily). Without a fallback the screen renders
      // "User not found" — for the *own* profile we already have enough
      // from AuthProvider to render the edit form so the user can fill
      // in details (the Save handler upserts).
      if (user == null &&
          viewUserId == currentUserId &&
          authProvider.appUser != null) {
        user = authProvider.appUser;
      }
      WorkspaceMember? workspaceMember;
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      if (workspaceId != null && workspaceId.isNotEmpty) {
        try {
          final members =
              await (ServiceLocator.workspaceMemberService.getWorkspaceMembers(
                        workspaceId,
                      )
                      as Stream<List<WorkspaceMember>>)
                  .first;
          for (final member in members) {
            if (member.userId == viewUserId) {
              workspaceMember = member;
              break;
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        // Populate edit controllers for own profile
        if (viewUserId == currentUserId && user != null) {
          _displayNameController.text = user.displayName ?? '';
          _jobTitleController.text = user.jobTitle ?? '';
          _companyNameController.text = user.companyName ?? '';
          _phoneNumberController.text = user.phoneNumber ?? '';
          _bioController.text = user.bio ?? '';
          _selectedTimezone = TimezoneOptions.isValid(user.timezone)
              ? user.timezone
              : null;
          _notificationPreferences = user.notificationPreferences;
        }
        setState(() {
          _user = user;
          _workspaceMember = workspaceMember;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = UserFacingError.uiMessage(e, action: 'load profile');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.appUser?.id;

      if (userId == null) throw Exception('No user logged in');

      final updates = <String, dynamic>{
        'displayName': _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        'jobTitle': _jobTitleController.text.trim().isEmpty
            ? null
            : _jobTitleController.text.trim(),
        'companyName': _companyNameController.text.trim().isEmpty
            ? null
            : _companyNameController.text.trim(),
        'phoneNumber': _phoneNumberController.text.trim().isEmpty
            ? null
            : _phoneNumberController.text.trim(),
        'bio': _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        'timezone': _selectedTimezone,
        'notificationPreferences': _notificationPreferences.toJson(),
      };

      await _userService.updateProfile(userId, updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        await _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating profile'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.masterAdmin:
        return AppColors.warning;
      case UserRole.admin:
        return AppColors.messageAccent;
      case UserRole.projectManager:
        return AppColors.info;
      case UserRole.fieldTechnician:
        return AppColors.success;
      case UserRole.client:
        return AppColors.warning;
      case UserRole.vendor:
        return AppColors.messageAccent;
    }
  }

  Color _getWorkspaceRoleColor(WorkspaceMember member) {
    if (member.isAdminRole) return AppColors.messageAccent;

    final permissions = RolePermissions(
      roleName: member.displayRoleName,
      isAdmin: false,
      modulePermissions: member.effectiveModulePermissions,
    );

    if (permissions.isClientMode) return AppColors.success;
    if (permissions.hasModuleAccess('projects', 'write') ||
        permissions.hasModuleAccess('budget', 'write') ||
        permissions.hasModuleAccess('team', 'write') ||
        permissions.hasModuleAccess('settings', 'read')) {
      return AppColors.info;
    }

    return AppColors.warning;
  }

  String _displayRoleName(AppUser user) {
    return _workspaceMember?.displayRoleName ?? user.role.displayName;
  }

  Color _displayRoleColor(AppUser user) {
    final workspaceMember = _workspaceMember;
    if (workspaceMember != null) {
      return _getWorkspaceRoleColor(workspaceMember);
    }
    return _getRoleColor(user.role);
  }

  String _formatDate(DateTime date, {String? timezone}) {
    return AppTimeFormatter.formatDate(
      date,
      pattern: 'MMM d, yyyy',
      timezone: timezone,
    );
  }

  Future<void> _sendMessage(AppUser otherUser) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.appUser;
    final workspaceId = currentUser?.currentWorkspaceId;

    if (workspaceId == null || currentUser == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final conversation = await _messageService.getOrCreateDirectConversation(
        workspaceId: workspaceId,
        currentUserId: currentUser.id,
        currentUserName: currentUser.displayName ?? 'Unknown',
        otherUserId: otherUser.id,
        otherUserName: otherUser.displayName ?? 'Unknown',
      );

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.of(context).pop();
        showMessagingPopup(context, conversationId: conversation.id);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start conversation: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.appUser?.id;
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      if (userId == null || workspaceId == null) {
        throw Exception('User not authenticated');
      }

      final bytes = await image.readAsBytes();
      final fileName = image.name;

      await _userService.uploadProfilePicture(
        userId,
        workspaceId,
        bytes,
        fileName,
      );
      await authProvider.refreshUser();

      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated')),
        );
        await _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'uploading image'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showImageOptions() {
    showImageUploadOptionsDialog(
      context: context,
      onChooseFromGallery: _pickAndUploadImage,
      onRemovePhoto: _user?.profilePictureUrl != null
          ? _removeProfilePicture
          : null,
    );
  }

  Future<void> _removeProfilePicture() async {
    try {
      setState(() => _isUploadingImage = true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.appUser?.id;

      if (userId == null) throw Exception('User not authenticated');

      if (_user?.profilePictureUrl != null) {
        await _userService.deleteProfilePicture(
          userId,
          _user!.profilePictureUrl!,
        );
      }
      await authProvider.refreshUser();

      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed')),
        );
        await _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'removing image'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.appUser?.id;
    final viewUserId = widget.userId ?? currentUserId;
    final isOwnProfile = viewUserId == currentUserId;

    if (_isLoading) {
      return Scaffold(body: _buildLoadingSkeleton(context));
    }

    if (_error != null) {
      return Scaffold(body: Center(child: SelectableText(_error!)));
    }

    if (_user == null) {
      return const Scaffold(body: Center(child: Text('User not found')));
    }

    if (isOwnProfile) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadProfile,
                child: _buildOwnProfileLayout(context, _user!),
              ),
            ),
            _buildSaveBar(context),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
            if (isWide) {
              return _buildDesktopLayout(context, _user!, isOwnProfile);
            } else {
              return _buildMobileLayout(context, _user!, isOwnProfile);
            }
          },
        ),
      ),
    );
  }

  // ─── Own-profile inline edit layout ──────────────────────────────────

  Widget _buildOwnProfileLayout(BuildContext context, AppUser user) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeroSection(context, user, true),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                children: [
                  _buildPersonalInfoCard(context, user),
                  const SizedBox(height: 16),
                  _buildProfessionalCard(context),
                  const SizedBox(height: 16),
                  _buildAboutEditCard(context),
                  const SizedBox(height: 16),
                  _buildPreferencesEditCard(context),
                  const SizedBox(height: 16),
                  const ProfileAppearanceCard(),
                  const SizedBox(height: 16),
                  ProfileNotificationsCard(
                    preferences: _notificationPreferences,
                    onChanged: (prefs) =>
                        setState(() => _notificationPreferences = prefs),
                  ),
                  const SizedBox(height: 16),
                  const ProfileSecurityCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _saveProfile,
        icon: _isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: const Text('Save Changes'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard(BuildContext context, AppUser user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal Information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            StackedField(
              label: 'Display Name',
              child: TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Email',
              child: Text(user.email, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Phone Number',
              child: TextFormField(
                controller: _phoneNumberController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  helperText: 'Optional',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (!_userService.isValidPhoneNumber(value)) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfessionalCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Professional',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            StackedField(
              label: 'Job Title',
              child: TextFormField(
                controller: _jobTitleController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                  helperText: 'Optional (max 100 characters)',
                ),
                maxLength: 100,
                validator: (value) {
                  if (!_userService.isValidJobTitle(value)) {
                    return 'Job title must be 100 characters or less';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Company Name',
              child: TextFormField(
                controller: _companyNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                  helperText: 'Optional (max 100 characters)',
                ),
                maxLength: 100,
                validator: (value) {
                  if (!_userService.isValidCompanyName(value)) {
                    return 'Company name must be 100 characters or less';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutEditCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            StackedField(
              label: 'Bio',
              child: TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  helperText: 'Optional (max 500 characters)',
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                maxLength: 500,
                validator: (value) {
                  if (!_userService.isValidBio(value)) {
                    return 'Bio must be 500 characters or less';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesEditCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preferences',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            StackedField(
              label: 'Timezone',
              child: DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                key: ValueKey(_selectedTimezone),
                initialValue: _selectedTimezone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.access_time),
                  helperText: 'Optional',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  ...TimezoneOptions.common.map((tz) {
                    return DropdownMenuItem<String>(
                      value: tz.id,
                      child: Text(tz.label),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() => _selectedTimezone = value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Read-only other-profile layouts ─────────────────────────────────

  Widget _buildLoadingSkeleton(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 200,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 60),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: List.generate(
                3,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    AppUser user,
    bool isOwnProfile,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeroSection(context, user, isOwnProfile),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      _buildQuickActionsCard(context, user, isOwnProfile),
                      const SizedBox(height: 16),
                      _buildStatsCard(context, user),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    children: [
                      _buildContactCard(context, user),
                      const SizedBox(height: 16),
                      _MemberVehiclesCard(userId: user.id),
                      if (user.bio != null) ...[
                        const SizedBox(height: 16),
                        _buildAboutCard(context, user),
                      ],
                      if (isOwnProfile && user.timezone != null) ...[
                        const SizedBox(height: 16),
                        _buildPreferencesCard(context, user),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    AppUser user,
    bool isOwnProfile,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeroSection(context, user, isOwnProfile),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              children: [
                _buildQuickActionsCard(context, user, isOwnProfile),
                const SizedBox(height: 16),
                _buildStatsCard(context, user),
                const SizedBox(height: 16),
                _buildContactCard(context, user),
                const SizedBox(height: 16),
                _MemberVehiclesCard(userId: user.id),
                if (user.bio != null) ...[
                  const SizedBox(height: 16),
                  _buildAboutCard(context, user),
                ],
                if (isOwnProfile && user.timezone != null) ...[
                  const SizedBox(height: 16),
                  _buildPreferencesCard(context, user),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    AppUser user,
    bool isOwnProfile,
  ) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Avatar and info
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: isOwnProfile && !_isUploadingImage
                        ? _showImageOptions
                        : null,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: _isUploadingImage
                              ? const SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : UserAvatar(
                                  user: user,
                                  size: AvatarSize.large,
                                  onTap: null,
                                ),
                        ),
                        if (isOwnProfile && !_isUploadingImage)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.displayName ?? user.email,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (user.jobTitle != null || user.companyName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        user.jobTitle,
                        user.companyName,
                      ].where((s) => s != null).join(' at '),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_user,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _displayRoleName(user),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(
    BuildContext context,
    AppUser user,
    bool isOwnProfile,
  ) {
    if (isOwnProfile && user.phoneNumber == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (!isOwnProfile)
              FilledButton.icon(
                onPressed: () => _sendMessage(user),
                icon: const Icon(Icons.message),
                label: const Text('Send Message'),
              ),
            if (user.phoneNumber != null) ...[
              if (!isOwnProfile) const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _launchPhone(user.phoneNumber!),
                icon: const Icon(Icons.phone),
                label: const Text('Call'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, AppUser user) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Details',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              Icons.circle,
              'Role',
              _displayRoleName(user),
              _displayRoleColor(user),
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              context,
              Icons.calendar_today,
              'Joined',
              _formatDate(user.createdAt, timezone: user.timezone),
              theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildContactCard(BuildContext context, AppUser user) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Information',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildContactRow(context, Icons.email, 'Email', user.email),
            if (user.phoneNumber != null) ...[
              const Divider(height: 24),
              _buildContactRow(
                context,
                Icons.phone,
                'Phone',
                user.phoneNumber!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAboutCard(BuildContext context, AppUser user) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.r12),
              ),
              child: Text(
                user.bio!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(BuildContext context, AppUser user) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preferences',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildContactRow(
              context,
              Icons.access_time,
              'Timezone',
              user.timezone!,
            ),
          ],
        ),
      ),
    );
  }
}

/// Vehicles for which this member is either the primary driver or
/// the current keyholder. Loads once per [userId] — rebuilds of the
/// outer profile screen don't re-fetch.
class _MemberVehiclesCard extends StatefulWidget {
  final String userId;

  const _MemberVehiclesCard({required this.userId});

  @override
  State<_MemberVehiclesCard> createState() => _MemberVehiclesCardState();
}

class _MemberVehiclesCardState extends State<_MemberVehiclesCard> {
  Future<List<Vehicle>>? _future;
  String? _loadedForWorkspace;

  Future<List<Vehicle>> _load(String workspaceId) {
    return SupabaseVehicleService(
      workspaceId: workspaceId,
    ).getVehiclesAssignedToUser(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspaceId =
        context.watch<AuthProvider>().appUser?.currentWorkspaceId ?? '';
    if (workspaceId.isEmpty) return const SizedBox.shrink();

    if (_future == null || _loadedForWorkspace != workspaceId) {
      _loadedForWorkspace = workspaceId;
      _future = _load(workspaceId);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Vehicles',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => setState(() {
                    _future = _load(workspaceId);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Vehicle>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.base),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return SelectableText(
                    UserFacingError.uiMessage(
                      snapshot.error,
                      action: 'load vehicles',
                    ),
                  );
                }
                final vehicles = snapshot.data ?? [];
                if (vehicles.isEmpty) {
                  return Text(
                    'No vehicles assigned',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final v in vehicles)
                      _MemberVehicleRow(vehicle: v, viewerUserId: widget.userId),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberVehicleRow extends StatelessWidget {
  final Vehicle vehicle;
  final String viewerUserId;

  const _MemberVehicleRow({required this.vehicle, required this.viewerUserId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrimary = vehicle.assignedToUserId == viewerUserId;
    final isCurrent = vehicle.currentDriverId == viewerUserId;

    final subtitleParts = <String>[];
    if (vehicle.licensePlate.isNotEmpty) {
      subtitleParts.add(vehicle.licensePlate);
    }
    final yearMakeModel = [
      if (vehicle.year > 0) vehicle.year.toString(),
      if (vehicle.make.isNotEmpty) vehicle.make,
      if (vehicle.model.isNotEmpty) vehicle.model,
    ].join(' ');
    if (yearMakeModel.isNotEmpty) subtitleParts.add(yearMakeModel);

    return InkWell(
      onTap: () => context.push('/vehicles/${vehicle.id}'),
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                Icons.directions_car,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join(' • '),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (isPrimary)
                        _RoleChip(
                          label: 'Primary',
                          color: theme.colorScheme.primary,
                        ),
                      if (isCurrent)
                        _RoleChip(
                          label: 'Currently driving',
                          color: AppColors.success,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final Color color;

  const _RoleChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
