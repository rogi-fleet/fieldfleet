import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../theme/theme.dart';
import '../../models/area.dart';
import '../../models/area_status.dart';
import '../../models/property.dart';
import '../../services/service_locator.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// Shows the create/edit area (room) form inside the canonical popup chrome.
Future<void> showAreaFormPopup(
  BuildContext context, {
  required Property property,
  Area? existingArea,
}) {
  final isEditing = existingArea != null;
  return showFormPopup<void>(
    context,
    icon: Icons.room,
    title: isEditing ? 'Edit Room' : 'Add Room',
    width: 500,
    builder: (ctx, scrollController) => _AreaFormContent(
      property: property,
      existingArea: existingArea,
      scrollController: scrollController,
    ),
  );
}

class _AreaFormContent extends StatefulWidget {
  final Property property;
  final Area? existingArea;
  final ScrollController? scrollController;

  const _AreaFormContent({
    required this.property,
    this.existingArea,
    this.scrollController,
  });

  @override
  State<_AreaFormContent> createState() => _AreaFormContentState();
}

class _AreaFormContentState extends State<_AreaFormContent> {
  final _formKey = GlobalKey<FormState>();
  final dynamic _areaService = ServiceLocator.areaService;
  bool _isLoading = false;

  late TextEditingController _nameController;
  late TextEditingController _notesController;
  bool _isAffected = false;
  AreaStatus _status = AreaStatus.notAffected;

  // Common area names for quick selection
  static const List<String> _commonAreas = [
    'Living Room',
    'Master Bedroom',
    'Bedroom',
    'Bathroom',
    'Kitchen',
    'Dining Room',
    'Basement',
    'Garage',
    'Hallway',
    'Closet',
    'Laundry Room',
    'Office',
    'Family Room',
    'Attic',
  ];

  @override
  void initState() {
    super.initState();
    final area = widget.existingArea;

    _nameController = TextEditingController(text: area?.name ?? '');
    _notesController = TextEditingController(text: area?.notes ?? '');
    _isAffected = area?.isAffected ?? false;
    _status = area?.status ?? AreaStatus.notAffected;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingArea != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick selection chips
                  if (!isEditing) ...[
                    Text(
                      'Quick Select',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _commonAreas.map((name) {
                        return ActionChip(
                          label: Text(name),
                          onPressed: () {
                            _nameController.text = name;
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Name field
                  StackedField(
                    label: 'Room Name *',
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g., Living Room, Master Bedroom',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Is Affected toggle
                  SwitchListTile(
                    title: const Text('Affected by Water Damage'),
                    subtitle: const Text(
                      'Mark if this area was affected by the loss',
                    ),
                    value: _isAffected,
                    onChanged: (value) {
                      setState(() {
                        _isAffected = value;
                        if (value && _status == AreaStatus.notAffected) {
                          _status = AreaStatus.affected;
                        } else if (!value) {
                          _status = AreaStatus.notAffected;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Status dropdown
                  StackedField(
                    label: 'Status',
                    child: DropdownButtonFormField<AreaStatus>(
                      borderRadius: AppRadius.cardRadius,
                      value: _status,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: AreaStatus.values.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Row(
                            children: [
                              Icon(
                                status.icon,
                                size: 18,
                                color: status.color,
                              ),
                              const SizedBox(width: 8),
                              Text(status.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _status = value;
                            // Update isAffected based on status
                            if (value == AreaStatus.notAffected) {
                              _isAffected = false;
                            } else if (value != AreaStatus.notAffected) {
                              _isAffected = true;
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notes field
                  StackedField(
                    label: 'Notes',
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        hintText: 'Additional notes about this area',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        FormPopupFooter(
          onSubmit: _isLoading ? null : _handleSave,
          submitLabel: isEditing ? 'Save Changes' : 'Add Room',
          busy: _isLoading,
        ),
      ],
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      final previousArea = widget.existingArea;

      final area = Area(
        id: previousArea?.id ?? '',
        workspaceId: widget.property.workspaceId,
        projectId: widget.property.projectId,
        propertyId: widget.property.id,
        name: _nameController.text.trim(),
        isAffected: _isAffected,
        status: _status,
        trend: previousArea?.trend,
        notes: _notesController.text.isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: previousArea?.createdAt ?? now,
        updatedAt: now,
      );

      if (previousArea != null) {
        await _areaService.updateArea(area, previousArea: previousArea);
      } else {
        await _areaService.createArea(area);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(previousArea != null ? 'Room updated' : 'Room added'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'complete this action'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
