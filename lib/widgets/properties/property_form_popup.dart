import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_header.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/project.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

void showPropertyFormPopup(
  BuildContext context, {
  required Project project,
  Property? existingProperty,
}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PropertyFormBottomSheet(
        project: project,
        existingProperty: existingProperty,
      ),
    );
  } else {
    showDialog(
      context: context,
      builder: (context) => PropertyFormPopup(
        project: project,
        existingProperty: existingProperty,
      ),
    );
  }
}

/// Form popup for creating or editing a property.
class PropertyFormPopup extends StatelessWidget {
  final Project project;
  final Property? existingProperty;

  const PropertyFormPopup({
    super.key,
    required this.project,
    this.existingProperty,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        ),
        child: _PropertyFormContent(
          project: project,
          existingProperty: existingProperty,
        ),
      ),
    );
  }
}

class _PropertyFormBottomSheet extends StatelessWidget {
  final Project project;
  final Property? existingProperty;

  const _PropertyFormBottomSheet({
    required this.project,
    this.existingProperty,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Expanded(
                child: _PropertyFormContent(
                  project: project,
                  existingProperty: existingProperty,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PropertyFormContent extends StatefulWidget {
  final Project project;
  final Property? existingProperty;

  const _PropertyFormContent({required this.project, this.existingProperty});

  @override
  State<_PropertyFormContent> createState() => _PropertyFormContentState();
}

class _PropertyFormContentState extends State<_PropertyFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _propertyService = ServiceLocator.propertyService;
  bool _isLoading = false;
  String? _identifierError;

  late TextEditingController _nameController;
  late TextEditingController _identifierController;
  late TextEditingController _floorController;
  late TextEditingController _occupantController;
  late TextEditingController _notesController;
  PropertyStatus _status = PropertyStatus.pending;

  @override
  void initState() {
    super.initState();
    final property = widget.existingProperty;

    _nameController = TextEditingController(text: property?.name ?? '');
    _identifierController = TextEditingController(
      text: property?.identifier ?? '',
    );
    _floorController = TextEditingController(text: property?.floor ?? '');
    _occupantController = TextEditingController(text: property?.occupant ?? '');
    _notesController = TextEditingController(text: property?.notes ?? '');
    _status = property?.status ?? PropertyStatus.pending;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
    _floorController.dispose();
    _occupantController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingProperty != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        FormPopupHeader(
          icon: Icons.home_work,
          title: isEditing ? 'Edit Structure' : 'Add Structure',
          onClose: () => Navigator.pop(context),
        ),

        // Form content
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useSingleColumn = constraints.maxWidth < 640;

                return Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name and Identifier
                      _buildResponsiveRow(
                        useSingleColumn: useSingleColumn,
                        left: StackedField(
                          label: 'Structure *',
                          child: TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              helperText: 'Unit, Suite',
                              hintText: 'E.g Unit',
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Structure is required';
                              }
                              return null;
                            },
                          ),
                        ),
                        right: StackedField(
                          label: 'Number',
                          child: TextFormField(
                            controller: _identifierController,
                            decoration: InputDecoration(
                              helperText: 'Optional',
                              hintText: 'e.g. 101',
                              errorText: _identifierError,
                            ),
                            onChanged: (_) {
                              if (_identifierError != null) {
                                setState(() {
                                  _identifierError = null;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Floor and Occupant
                      _buildResponsiveRow(
                        useSingleColumn: useSingleColumn,
                        left: StackedField(
                          label: 'Floor',
                          child: TextFormField(
                            controller: _floorController,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 1st',
                            ),
                          ),
                        ),
                        right: StackedField(
                          label: 'Occupant',
                          child: TextFormField(
                            controller: _occupantController,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Owner name',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Status
                      StackedField(
                        label: 'Status',
                        child: DropdownButtonFormField<PropertyStatus>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: _status,
                          isExpanded: true,
                          decoration: const InputDecoration(
                          ),
                          items: PropertyStatus.values.map((status) {
                            return DropdownMenuItem(
                              value: status,
                              child: _buildDropdownItemLabel(
                                text: status.displayName,
                                icon: status.icon,
                                color: status.color,
                              ),
                            );
                          }).toList(),
                          selectedItemBuilder: (context) => PropertyStatus
                              .values
                              .map(
                                (status) => _buildDropdownItemLabel(
                                  text: status.displayName,
                                  icon: status.icon,
                                  color: status.color,
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _status = value;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      StackedField(
                        label: 'Notes',
                        child: TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            hintText: 'Additional notes about this structure',
                          ),
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Actions
        FormPopupFooter(
          onSubmit: _isLoading ? null : _handleSave,
          submitLabel: isEditing ? 'Save Changes' : 'Add Structure',
          busy: _isLoading,
        ),
      ],
    );
  }

  Widget _buildResponsiveRow({
    required bool useSingleColumn,
    required Widget left,
    required Widget right,
  }) {
    if (useSingleColumn) {
      return Column(children: [left, const SizedBox(height: 16), right]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildDropdownItemLabel({
    required String text,
    IconData? icon,
    Color? color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();

    setState(() {
      _isLoading = true;
      _identifierError = null;
    });

    try {
      // Number is optional: fall back to the structure name when left blank.
      final name = _nameController.text.trim();
      final identifier = _identifierController.text.trim().isEmpty
          ? name
          : _identifierController.text.trim();

      // Check identifier uniqueness
      final isUnique = await _propertyService.isIdentifierUnique(
        widget.project.id,
        identifier,
        widget.existingProperty?.id,
        workspaceId: widget.project.workspaceId,
      );

      if (!isUnique) {
        setState(() {
          _identifierError = 'This number is already in use';
          _isLoading = false;
        });
        return;
      }

      final now = DateTime.now();

      final property = Property(
        id: widget.existingProperty?.id ?? '',
        workspaceId: widget.project.workspaceId,
        projectId: widget.project.id,
        name: name,
        identifier: identifier,
        floor: _floorController.text.isEmpty
            ? null
            : _floorController.text.trim(),
        occupant: _occupantController.text.isEmpty
            ? null
            : _occupantController.text.trim(),
        status: _status,
        notes: _notesController.text.isEmpty
            ? null
            : _notesController.text.trim(),
        areaCount: widget.existingProperty?.areaCount ?? 0,
        dryAreaCount: widget.existingProperty?.dryAreaCount ?? 0,
        contentsCount: widget.existingProperty?.contentsCount ?? 0,
        createdAt: widget.existingProperty?.createdAt ?? now,
        updatedAt: now,
        createdBy:
            widget.existingProperty?.createdBy ?? authProvider.appUser?.id,
      );

      if (widget.existingProperty != null) {
        await _propertyService.updateProperty(property);
      } else {
        await _propertyService.createProperty(property);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingProperty != null
                  ? 'Structure updated'
                  : 'Structure created',
            ),
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
