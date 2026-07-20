import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../../models/skill.dart';

import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/skill_chip.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';

class SkillsManagementScreen extends StatefulWidget {
  final bool embedded;

  const SkillsManagementScreen({super.key, this.embedded = false});

  @override
  State<SkillsManagementScreen> createState() => _SkillsManagementScreenState();
}

class _SkillsManagementScreenState extends State<SkillsManagementScreen> {
  final dynamic _skillService = ServiceLocator.skillService;

  Future<void> _showCreateSkillDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    Color selectedColor = Colors.blue;

    final result = await showFormPopup<Map<String, dynamic>>(
      context,
      icon: Icons.construction,
      title: 'Create New Skill',
      width: 480,
      builder: (popupContext, scrollController) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StackedField(
                      label: 'Skill Name',
                      child: TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          hintText: 'e.g., Electrical, Plumbing',
                        ),
                        autofocus: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Description (Optional)',
                      child: TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          hintText: 'Describe this skill',
                        ),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Color:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            Colors.amber,
                            Colors.blue,
                            Colors.cyan,
                            Colors.brown,
                            Colors.grey,
                            Colors.purple,
                            Colors.orange,
                            Colors.blueGrey,
                            Colors.red,
                            Colors.green,
                            Colors.teal,
                            Colors.indigo,
                          ].map((color) {
                            return InkWell(
                              onTap: () {
                                setDialogState(() {
                                  selectedColor = color;
                                });
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selectedColor == color
                                        ? Colors.black
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            FormPopupFooter(
              onSubmit: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'color': selectedColor,
                  });
                }
              },
              submitLabel: 'Create',
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId != null) {
        try {
          await _skillService.createSkill(
            workspaceId: workspaceId,
            name: result['name'],
            color: result['color'],
            description: result['description'].isEmpty
                ? null
                : result['description'],
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Skill created successfully')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  UserFacingError.uiMessage(e, action: 'creating skill'),
                ),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _showEditSkillDialog(Skill skill) async {
    final nameController = TextEditingController(text: skill.name);
    final descriptionController = TextEditingController(
      text: skill.description ?? '',
    );
    Color selectedColor = skill.color;

    final result = await showFormPopup<Map<String, dynamic>>(
      context,
      icon: Icons.edit,
      title: 'Edit Skill',
      width: 480,
      builder: (popupContext, scrollController) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StackedField(
                      label: 'Skill Name',
                      child: TextField(
                        controller: nameController,
                        decoration: const InputDecoration(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Description (Optional)',
                      child: TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Color:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            Colors.amber,
                            Colors.blue,
                            Colors.cyan,
                            Colors.brown,
                            Colors.grey,
                            Colors.purple,
                            Colors.orange,
                            Colors.blueGrey,
                            Colors.red,
                            Colors.green,
                            Colors.teal,
                            Colors.indigo,
                          ].map((color) {
                            return InkWell(
                              onTap: () {
                                setDialogState(() {
                                  selectedColor = color;
                                });
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selectedColor == color
                                        ? Colors.black
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            FormPopupFooter(
              onSubmit: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'color': selectedColor,
                  });
                }
              },
              submitLabel: 'Save',
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      try {
        await _skillService.updateSkill(
          skillId: skill.id,
          name: result['name'],
          color: result['color'],
          description: result['description'].isEmpty
              ? null
              : result['description'],
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Skill updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'updating skill'),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteSkill(Skill skill) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) return;

    // Get usage count first
    final usage = await _skillService.getSkillUsage(skill.id, workspaceId);
    final totalUsage = (usage['members'] ?? 0) + (usage['tasks'] ?? 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Skill'),
        content: Text(
          totalUsage > 0
              ? 'This skill is assigned to ${usage['members']} team member(s) and ${usage['tasks']} task(s). '
                    'Are you sure you want to delete it? It will be removed from all members and tasks.'
              : 'Are you sure you want to delete this skill?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _skillService.deleteSkill(skill.id, workspaceId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Skill deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting skill'),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _seedDefaultSkills() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Default Skills'),
        content: const Text(
          'This will add common construction skills: Electrical, Plumbing, HVAC, Carpentry, Drywall, Painting, Roofing, and Concrete.\n\n'
          'Existing skills with the same names will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add Skills'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _skillService.seedDefaultSkills(workspaceId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Default skills added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'adding default skills'),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      if (widget.embedded) {
        return const Center(child: Text('No workspace found'));
      }
      return const Scaffold(body: Center(child: Text('No workspace found')));
    }

    final body = _buildSkillsList(workspaceId);

    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage workspace skills',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: ChromeColors.of(context).scaffoldText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create skills for team members and task requirements.',
                        style: TextStyle(color: ChromeColors.of(context).scaffoldTextSecondary),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _seedDefaultSkills,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Add Default Skills'),
                    ),
                    FilledButton.icon(
                      onPressed: _showCreateSkillDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('New Skill'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Skills'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'seed') {
                _seedDefaultSkills();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'seed',
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high),
                    SizedBox(width: 8),
                    Text('Add Default Skills'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSkillDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Skill'),
      ),
    );
  }

  Widget _buildSkillsList(String workspaceId) {
    return StreamBuilder<List<Skill>>(
      stream: _skillService.getSkills(workspaceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  UserFacingError.uiMessage(
                    snapshot.error,
                    action: 'load data',
                  ),
                ),
              ],
            ),
          );
        }

        final skills = snapshot.data ?? [];

        if (skills.isEmpty) {
          final chrome = ChromeColors.of(context);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.build_circle_outlined,
                  size: 64,
                  color: chrome.scaffoldTextSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No skills yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: chrome.scaffoldText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create skills to track team member expertise',
                  style: TextStyle(color: chrome.scaffoldTextSecondary),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _seedDefaultSkills,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Add Default Skills'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: skills.length,
          itemBuilder: (context, index) {
            final skill = skills[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: SkillChip(skill: skill),
                title: Text(skill.name),
                subtitle: skill.description != null
                    ? Text(skill.description!)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FutureBuilder<Map<String, int>>(
                      future: _skillService.getSkillUsage(
                        skill.id,
                        workspaceId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final total =
                              (snapshot.data!['members'] ?? 0) +
                              (snapshot.data!['tasks'] ?? 0);
                          return Chip(
                            label: Text('$total uses'),
                            backgroundColor: AppColors.cardBorder,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showEditSkillDialog(skill),
                      tooltip: 'Edit skill',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      color: AppColors.error,
                      onPressed: () => _deleteSkill(skill),
                      tooltip: 'Delete skill',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
