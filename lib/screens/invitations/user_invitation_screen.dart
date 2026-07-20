import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/workspace_invitation.dart';
import '../../models/workspace_role_template.dart';
import '../../models/role_permissions.dart';
import '../../models/user_role.dart';
import '../../services/supabase/invitation_service.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/app_config.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class UserInvitationScreen extends StatefulWidget {
  final String workspaceId;

  const UserInvitationScreen({super.key, required this.workspaceId});

  @override
  State<UserInvitationScreen> createState() => _UserInvitationScreenState();
}

class _UserInvitationScreenState extends State<UserInvitationScreen> {
  final SupabaseInvitationService _invitationService =
      SupabaseInvitationService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  List<WorkspaceRoleTemplate> _roleTemplates = [];
  WorkspaceRoleTemplate? _selectedTemplate;
  String _selectedInterfaceMode = 'field'; // fieldTechnician default
  bool _isSending = false;
  bool _isLoadingTemplates = true;

  // Starts from the route-provided id, but on a cold load/refresh appUser is
  // briefly null so the route passes '' — recover it from AuthProvider in
  // didChangeDependencies once it hydrates so the pending-invitations stream
  // and role templates query don't run against an empty workspace and fail.
  late String _workspaceId = widget.workspaceId;
  bool _templatesRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workspaceId.isEmpty) {
      final wid =
          Provider.of<AuthProvider>(context).appUser?.currentWorkspaceId ?? '';
      if (wid.isNotEmpty) {
        setState(() => _workspaceId = wid);
      }
    }
    if (_workspaceId.isNotEmpty && !_templatesRequested) {
      _templatesRequested = true;
      _loadRoleTemplates();
    }
  }

  Future<void> _loadRoleTemplates() async {
    try {
      final templates = await ServiceLocator.roleTemplateService.getTemplates(
        workspaceId: _workspaceId,
      );
      if (!mounted) return;
      setState(() {
        _roleTemplates = List<WorkspaceRoleTemplate>.from(templates);
        final defaultTemplate = _defaultInviteTemplate();
        if (defaultTemplate != null) {
          _selectTemplate(defaultTemplate);
        }
        _isLoadingTemplates = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load role templates', error: e);
      if (!mounted) return;
      setState(() => _isLoadingTemplates = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to load roles. Please try again.'),
          backgroundColor: AppColors.error,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _loadRoleTemplates,
          ),
        ),
      );
    }
  }

  void _selectTemplate(WorkspaceRoleTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _selectedInterfaceMode = template.defaultInterfaceMode;
    });
  }

  WorkspaceRoleTemplate? _defaultInviteTemplate() {
    for (final template in _roleTemplates) {
      if (template.isSystem && template.role == UserRole.fieldTechnician) {
        return template;
      }
    }

    for (final template in _roleTemplates) {
      if (_isTeamRoleTemplate(template)) return template;
    }

    return _roleTemplates.isNotEmpty ? _roleTemplates.first : null;
  }

  bool _isTeamRoleTemplate(WorkspaceRoleTemplate template) {
    final permissions = RolePermissions(
      roleTemplateId: template.id,
      roleName: template.name,
      isAdmin: template.isAdmin,
      modulePermissions: template.modulePermissions,
      defaultInterfaceMode: template.defaultInterfaceMode,
    );
    return !permissions.isClientMode;
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendInvitation() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final invitedBy = authProvider.appUser?.id;

    if (invitedBy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: SelectableText(
            'Error: Not logged in',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 10),
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final selectedTemplate = _selectedTemplate;
      if (selectedTemplate == null) {
        throw Exception('Please select a role template');
      }

      await _invitationService.inviteUser(
        workspaceId: _workspaceId,
        email: _emailController.text.trim(),
        role: selectedTemplate.legacyRole,
        invitedBy: invitedBy,
        interfaceMode: _selectedInterfaceMode,
        roleTemplateId: selectedTemplate.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation sent successfully!')),
        );

        // Clear form
        _emailController.clear();
        final defaultTemplate = _defaultInviteTemplate();
        if (defaultTemplate != null) {
          _selectTemplate(defaultTemplate);
        }
      }
    } catch (e) {
      AppLogger.error('Failed to send invitation', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Failed to send invitation: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _resendInvitation(String invitationId) async {
    try {
      await _invitationService.resendInvitation(invitationId);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation resent!')));
      }
    } catch (e) {
      AppLogger.error('Failed to resend invitation', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Failed to resend: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  Future<void> _revokeInvitation(String invitationId) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Invitation?'),
        content: const Text('Are you sure you want to revoke this invitation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _invitationService.revokeInvitation(invitationId);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation revoked')));
      }
    } catch (e) {
      AppLogger.error('Failed to revoke invitation', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Failed to revoke: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  Future<void> _copyInvitationLink(String token) async {
    final link = AppConfig.getInvitationUrl(token);

    try {
      await Clipboard.setData(ClipboardData(text: link));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitation link copied to clipboard!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Clipboard API failed (common on web), show dialog with selectable link instead
      AppLogger.warning(
        'Clipboard API not available, showing dialog',
        metadata: {'error': e.toString()},
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Invitation Link'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Copy this link to share:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: SelectableText(
                    link,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite Team Member')),
      body: Column(
        children: [
          // Invitation Form
          Card(
            margin: const EdgeInsets.all(AppSpacing.base),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Team Invitation',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Email Address',
                      child: TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          hintText: 'user@example.com',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          // More permissive email regex that allows + and other valid characters
                          final emailRegex = RegExp(
                            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                          );
                          if (!emailRegex.hasMatch(value)) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Role',
                      child: _isLoadingTemplates
                          ? const LinearProgressIndicator()
                          : DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              initialValue: _selectedTemplate?.id,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                              items: _roleTemplates
                                  .where(_isTeamRoleTemplate)
                                  .map((template) {
                                    return DropdownMenuItem(
                                      value: template.id,
                                      child: Text(template.name),
                                    );
                                  })
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  final template = _roleTemplates.firstWhere(
                                    (t) => t.id == value,
                                  );
                                  _selectTemplate(template);
                                }
                              },
                            ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSending || _roleTemplates.isEmpty
                            ? null
                            : _sendInvitation,
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: const Text('Send Team Invite'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Pending Invitations List
          Expanded(
            child: Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Text(
                      'Pending Team Invitations',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: StreamBuilder<List<WorkspaceInvitation>>(
                      stream: _invitationService.getWorkspaceInvitations(
                        _workspaceId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.base),
                              child: SelectableText(
                                UserFacingError.uiMessage(
                                  snapshot.error,
                                  action: 'load data',
                                ),
                                style: const TextStyle(
                                  color: AppColors.errorDark,
                                ),
                              ),
                            ),
                          );
                        }

                        final now = DateTime.now();
                        final invitations =
                            snapshot.data
                                ?.where(
                                  (inv) =>
                                      inv.status == InvitationStatus.pending &&
                                      inv.expiresAt.isAfter(now),
                                )
                                .toList() ??
                            [];

                        if (invitations.isEmpty) {
                          return const Center(
                            child: Text('No pending invitations'),
                          );
                        }

                        return ListView.separated(
                          itemCount: invitations.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final invitation = invitations[index];
                            return _buildInvitationTile(invitation);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _resolveInvitationRoleName(WorkspaceInvitation invitation) {
    if (invitation.roleTemplateId != null && _roleTemplates.isNotEmpty) {
      final match = _roleTemplates.where(
        (t) => t.id == invitation.roleTemplateId,
      );
      if (match.isNotEmpty) return match.first.name;
    }
    return invitation.displayRoleName;
  }

  Widget _buildInvitationTile(WorkspaceInvitation invitation) {
    final daysUntilExpiry = invitation.expiresAt
        .difference(DateTime.now())
        .inDays;
    final isExpiringSoon = daysUntilExpiry >= 0 && daysUntilExpiry <= 2;
    final expiryLabel = daysUntilExpiry < 0
        ? 'Expired'
        : daysUntilExpiry == 0
            ? 'Expires today'
            : 'Expires in $daysUntilExpiry day${daysUntilExpiry == 1 ? '' : 's'}';

    return ListTile(
      leading: CircleAvatar(child: Text(invitation.email[0].toUpperCase())),
      title: Text(invitation.email),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Role: ${_resolveInvitationRoleName(invitation)}'),
          Text(
            expiryLabel,
            style: TextStyle(
              color: isExpiringSoon ? AppColors.warning : null,
              fontWeight: isExpiringSoon ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Copy Link',
            onPressed: () => _copyInvitationLink(invitation.token),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Resend',
            onPressed: () => _resendInvitation(invitation.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Revoke',
            onPressed: () => _revokeInvitation(invitation.id),
          ),
        ],
      ),
    );
  }
}
