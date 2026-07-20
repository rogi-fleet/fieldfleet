import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/workspace_settings_profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class WorkspaceSettingsProfilesScreen extends StatefulWidget {
  const WorkspaceSettingsProfilesScreen({super.key});

  @override
  State<WorkspaceSettingsProfilesScreen> createState() =>
      _WorkspaceSettingsProfilesScreenState();
}

class _WorkspaceSettingsProfilesScreenState
    extends State<WorkspaceSettingsProfilesScreen> {
  final dynamic _profileService =
      ServiceLocator.workspaceSettingsProfileService;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _workspaceId;
  List<WorkspaceSettingsProfile> _profiles = const [];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';

    if (workspaceId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _workspaceId = null;
        _profiles = const [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _workspaceId = workspaceId;
      _isLoading = true;
    });

    try {
      final profiles = await _profileService.getProfiles(
        workspaceId: workspaceId,
      );
      if (!mounted) return;
      setState(() {
        _profiles = List<WorkspaceSettingsProfile>.from(profiles);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load profiles: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _saveCurrentAsProfile() async {
    if (_workspaceId == null) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Current Settings Profile'),
        content: StackedField(
          label: 'Profile Name',
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _profileService.createFromCurrentWorkspace(
        workspaceId: _workspaceId!,
        name: controller.text,
      );
      await _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save profile: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _renameProfile(WorkspaceSettingsProfile profile) async {
    final controller = TextEditingController(text: profile.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Profile'),
        content: StackedField(
          label: 'Profile Name',
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _profileService.renameProfile(
        profileId: profile.id,
        name: controller.text,
      );
      await _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to rename profile: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _applyProfile(WorkspaceSettingsProfile profile) async {
    if (_workspaceId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Settings Profile?'),
        content: Text(
          'Apply "${profile.name}" to this workspace now? This updates workspace settings immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _profileService.applyProfile(
        workspaceId: _workspaceId!,
        profileId: profile.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied profile: ${profile.name}')),
      );
      await _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to apply profile: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteProfile(WorkspaceSettingsProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: Text('Delete "${profile.name}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _profileService.deleteProfile(profileId: profile.id);
      await _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete profile: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _summarize(WorkspaceSettingsProfile profile) {
    return '${profile.currencyCode} • ${profile.timezone} • Business days: ${profile.showBusinessDaysOnly ? 'On' : 'Off'}';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final canManageProfiles =
        authProvider.canManageUsers || authProvider.canAccessSettings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings Profiles'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: canManageProfiles
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveCurrentAsProfile,
              icon: const Icon(Icons.save_as_outlined),
              label: const Text('Save Current'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !canManageProfiles
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Only workspace admins can manage settings profiles.',
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadProfiles,
              child: _profiles.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'No saved profiles yet. Save current workspace settings to create one.',
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      itemCount: _profiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final profile = _profiles[index];
                        return Card(
                          child: ListTile(
                            title: Text(profile.name),
                            subtitle: Text(_summarize(profile)),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_circle_outline),
                                  tooltip: 'Apply',
                                  onPressed: _isSaving
                                      ? null
                                      : () => _applyProfile(profile),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Rename',
                                  onPressed: _isSaving
                                      ? null
                                      : () => _renameProfile(profile),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete',
                                  onPressed: _isSaving
                                      ? null
                                      : () => _deleteProfile(profile),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
