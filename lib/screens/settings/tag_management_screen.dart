import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../../models/customer_tag.dart';

import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/customers/customer_tag_chip.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key});

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  final dynamic _tagService = ServiceLocator.customerTagService;

  Future<void> _showCreateTagDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    Color selectedColor = Colors.blue;

    final result = await showFormPopup<Map<String, dynamic>>(
      context,
      icon: Icons.new_label,
      title: 'Create New Tag',
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
                label: 'Tag Name',
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'e.g., VIP Customer',
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
                    hintText: 'Describe this tag',
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
                      Colors.red,
                      Colors.pink,
                      Colors.purple,
                      Colors.deepPurple,
                      Colors.indigo,
                      Colors.blue,
                      Colors.lightBlue,
                      Colors.cyan,
                      Colors.teal,
                      Colors.green,
                      Colors.lightGreen,
                      Colors.lime,
                      Colors.yellow,
                      Colors.amber,
                      Colors.orange,
                      Colors.deepOrange,
                      Colors.brown,
                      Colors.grey,
                    ].map((color) {
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            selectedColor = color;
                          });
                        },
                        child: Container(
                          width: 40,
                          height: 40,
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
                    'color':
                        '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
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
          await _tagService.createTag(
            workspaceId: workspaceId,
            name: result['name'],
            color: result['color'],
            description: result['description'].isEmpty
                ? null
                : result['description'],
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tag created successfully')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  UserFacingError.uiMessage(e, action: 'creating tag'),
                ),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _showEditTagDialog(CustomerTag tag) async {
    final nameController = TextEditingController(text: tag.name);
    final descriptionController = TextEditingController(
      text: tag.description ?? '',
    );
    Color selectedColor = _parseColor(tag.color);

    final result = await showFormPopup<Map<String, dynamic>>(
      context,
      icon: Icons.edit,
      title: 'Edit Tag',
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
                label: 'Tag Name',
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
                      Colors.red,
                      Colors.pink,
                      Colors.purple,
                      Colors.deepPurple,
                      Colors.indigo,
                      Colors.blue,
                      Colors.lightBlue,
                      Colors.cyan,
                      Colors.teal,
                      Colors.green,
                      Colors.lightGreen,
                      Colors.lime,
                      Colors.yellow,
                      Colors.amber,
                      Colors.orange,
                      Colors.deepOrange,
                      Colors.brown,
                      Colors.grey,
                    ].map((color) {
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            selectedColor = color;
                          });
                        },
                        child: Container(
                          width: 40,
                          height: 40,
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
                    'color':
                        '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
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
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) return;

      try {
        await _tagService.updateTag(workspaceId, tag.id, {
          'name': result['name'],
          'color': result['color'],
          if (result['description'].isNotEmpty)
            'description': result['description'],
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tag updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'updating tag'),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteTag(CustomerTag tag) async {
    // Get usage count first
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) return;

    final usageCount = await _tagService.getTagUsageCount(workspaceId, tag.id);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tag'),
        content: Text(
          usageCount > 0
              ? 'This tag is used by $usageCount customer(s). Are you sure you want to delete it? It will be removed from all customers.'
              : 'Are you sure you want to delete this tag?',
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
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) return;

      try {
        await _tagService.deleteTag(workspaceId, tag.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tag deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting tag'),
              ),
            ),
          );
        }
      }
    }
  }

  Color _parseColor(String hexColor) {
    try {
      String colorStr = hexColor.replaceAll('#', '');
      if (colorStr.length == 3) {
        colorStr = colorStr.split('').map((c) => c + c).join();
      }
      if (colorStr.length == 6) {
        return Color(int.parse('FF$colorStr', radix: 16));
      }
      if (colorStr.length == 8) {
        return Color(int.parse(colorStr, radix: 16));
      }
      return Colors.blue;
    } catch (e) {
      return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Scaffold(body: Center(child: Text('No workspace found')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Tags')),
      body: StreamBuilder<List<CustomerTag>>(
        stream: _tagService.getTags(workspaceId),
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

          final tags = snapshot.data ?? [];

          if (tags.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.label_outline,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tags yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create tags to organize your customers',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CustomerTagChip(tag: tag, small: false),
                  title: Text(tag.name),
                  subtitle: tag.description != null
                      ? Text(tag.description!)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<int>(
                        future: _tagService.getTagUsageCount(
                          workspaceId,
                          tag.id,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Chip(
                              label: Text('${snapshot.data} uses'),
                              backgroundColor: AppColors.cardBorder,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditTagDialog(tag),
                        tooltip: 'Edit tag',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        color: AppColors.error,
                        onPressed: () => _deleteTag(tag),
                        tooltip: 'Delete tag',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTagDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Tag'),
      ),
    );
  }
}
