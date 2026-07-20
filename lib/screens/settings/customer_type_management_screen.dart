import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer_type_config.dart';
import '../../services/service_locator.dart';
import '../../utils/user_facing_error.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';

class CustomerTypeManagementScreen extends StatefulWidget {
  const CustomerTypeManagementScreen({super.key});

  @override
  State<CustomerTypeManagementScreen> createState() =>
      _CustomerTypeManagementScreenState();
}

class _CustomerTypeManagementScreenState
    extends State<CustomerTypeManagementScreen> {
  final _service = ServiceLocator.customerTypeService;

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    Color selectedColor = Colors.blue;

    final result = await showFormPopup<Map<String, dynamic>>(
      context,
      icon: Icons.category,
      title: 'Create Customer Type',
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
                      label: 'Type Name',
                      child: TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          hintText: 'e.g., Healthcare',
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
                          hintText: 'Describe this customer type',
                        ),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildColorPicker(selectedColor, (color) {
                      setDialogState(() => selectedColor = color);
                    }),
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
                    'color': _colorToHex(selectedColor),
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
      final workspaceId = _getWorkspaceId();
      if (workspaceId == null) return;

      try {
        await _service.createCustomerType(
          workspaceId: workspaceId,
          name: result['name'],
          color: result['color'],
          description: result['description'].isEmpty
              ? null
              : result['description'],
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Customer type created successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = e.toString().contains('duplicate key') ||
                  e.toString().contains('unique constraint')
              ? 'A customer type with that name already exists'
              : UserFacingError.uiMessage(e, action: 'creating customer type');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    }
  }

  Future<void> _showEditDialog(CustomerTypeConfig type) async {
    final nameController = TextEditingController(text: type.name);
    final descriptionController = TextEditingController(
      text: type.description ?? '',
    );
    Color selectedColor = _parseHexColor(type.color);

    final result = await showFormPopup<Map<String, dynamic>>(
      context,
      icon: Icons.edit,
      title: 'Edit Customer Type',
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
                      label: 'Type Name',
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
                    _buildColorPicker(selectedColor, (color) {
                      setDialogState(() => selectedColor = color);
                    }),
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
                    'color': _colorToHex(selectedColor),
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
      final workspaceId = _getWorkspaceId();
      if (workspaceId == null) return;

      try {
        await _service.fullUpdateCustomerType(
          workspaceId: workspaceId,
          typeId: type.id,
          oldName: type.name,
          newName: result['name'] as String,
          color: result['color'] as String,
          description: (result['description'] as String).isNotEmpty
              ? result['description'] as String
              : null,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Customer type updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'updating customer type'),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteType(CustomerTypeConfig type) async {
    final workspaceId = _getWorkspaceId();
    if (workspaceId == null) return;

    final usageCount = await _service.getTypeUsageCount(
      workspaceId,
      type.name,
    );

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer Type'),
        content: Text(
          usageCount > 0
              ? 'This type is used by $usageCount customer(s). '
                'Deleting it will remove it from the dropdown but existing customers will keep their current type.'
              : 'Are you sure you want to delete "${type.name}"?',
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
        await _service.deleteCustomerType(workspaceId, type.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Customer type deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting customer type'),
              ),
            ),
          );
        }
      }
    }
  }

  String? _getWorkspaceId() {
    return Provider.of<AuthProvider>(context, listen: false)
        .appUser
        ?.currentWorkspaceId;
  }

  Widget _buildColorPicker(Color selected, ValueChanged<Color> onChanged) {
    const colors = [
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
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.blueGrey,
      Colors.grey,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Color:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return InkWell(
              onTap: () => onChanged(color),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected == color
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
    );
  }

  static String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  static Color _parseHexColor(String hex) {
    try {
      String colorStr = hex.replaceAll('#', '');
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
    } catch (_) {
      return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Establish a dependency on AuthProvider so this rebuilds once appUser
    // hydrates. On a cold load/refresh appUser is briefly null; without this
    // the listen:false read renders a permanent "No workspace found".
    context.watch<AuthProvider>();
    final workspaceId = _getWorkspaceId();

    if (workspaceId == null) {
      return const Scaffold(body: Center(child: Text('No workspace found')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Customer Types')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('New Type'),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: StreamBuilder<List<CustomerTypeConfig>>(
              stream: _service.getCustomerTypes(workspaceId),
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

                final types = snapshot.data ?? [];

                if (types.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.category_outlined,
                          size: 64,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No customer types yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create customer types to classify your customers',
                          style: TextStyle(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: types.length,
                  itemBuilder: (context, index) {
                    final type = types[index];
                    final color = _parseHexColor(type.color);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(color: color, width: 1),
                          ),
                          child: Center(
                            child: Text(
                              type.name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(type.name),
                            if (type.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBorder,
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  'Default',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: type.description != null
                            ? Text(type.description!)
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FutureBuilder<int>(
                              future: _service.getTypeUsageCount(
                                workspaceId,
                                type.name,
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data! > 0) {
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
                              onPressed: () => _showEditDialog(type),
                              tooltip: 'Edit type',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              color: AppColors.error,
                              onPressed: () => _deleteType(type),
                              tooltip: 'Delete type',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
