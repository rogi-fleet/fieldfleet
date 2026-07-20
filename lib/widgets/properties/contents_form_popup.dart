import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import '../../services/service_locator.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../theme/theme.dart';
import '../../models/area.dart';
import '../../models/property_contents.dart';
import '../../models/contents_status.dart';
import '../../models/property.dart';


import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// Shows the create/edit contents-item form inside the canonical popup chrome.
Future<void> showContentsFormPopup(
  BuildContext context, {
  required Property property,
  required List<Area> areas,
  PropertyContents? existingItem,
}) {
  final isEditing = existingItem != null;
  return showFormPopup<void>(
    context,
    icon: Icons.inventory_2,
    title: isEditing ? 'Edit Item' : 'Add Item',
    width: 550,
    fitContent: false,
    builder: (ctx, scrollController) => _ContentsFormContent(
      property: property,
      areas: areas,
      existingItem: existingItem,
      scrollController: scrollController,
    ),
  );
}

class _ContentsFormContent extends StatefulWidget {
  final Property property;
  final List<Area> areas;
  final PropertyContents? existingItem;
  final ScrollController? scrollController;

  const _ContentsFormContent({
    required this.property,
    required this.areas,
    this.existingItem,
    this.scrollController,
  });

  @override
  State<_ContentsFormContent> createState() => _ContentsFormContentState();
}

class _ContentsFormContentState extends State<_ContentsFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _contentsService = ServiceLocator.propertyContentsService;
  bool _isLoading = false;

  late TextEditingController _itemNameController;
  late TextEditingController _descriptionController;
  late TextEditingController _quantityController;
  late TextEditingController _barcodeController;
  late TextEditingController _notesController;
  late TextEditingController _photoUrlController;
  String? _selectedAreaId;
  ContentsStatus _status = ContentsStatus.identified;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;

    _itemNameController = TextEditingController(text: item?.itemName ?? '');
    _descriptionController = TextEditingController(
      text: item?.description ?? '',
    );
    _quantityController = TextEditingController(
      text: (item?.quantity ?? 1).toString(),
    );
    _barcodeController = TextEditingController(text: item?.barcode ?? '');
    _notesController = TextEditingController(text: item?.notes ?? '');
    _photoUrlController = TextEditingController(text: item?.photoUrl ?? '');
    _selectedAreaId = item?.areaId;
    _status = item?.status ?? ContentsStatus.identified;
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _barcodeController.dispose();
    _notesController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingItem != null;

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
                  // Item name
                  StackedField(
                    label: 'Item Name *',
                    child: TextFormField(
                      controller: _itemNameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g., Sofa, Television, Clothing',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Item name is required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  StackedField(
                    label: 'Description',
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        hintText: 'Brief description of the item',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Area and Status row
                  Row(
                    children: [
                      // Area selection
                      Expanded(
                        child: StackedField(
                          label: 'Area',
                          child: DropdownButtonFormField<String?>(
                            borderRadius: AppRadius.cardRadius,
                            value: _selectedAreaId,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('No specific area'),
                              ),
                              ...widget.areas.map((area) {
                                return DropdownMenuItem(
                                  value: area.id,
                                  child: Text(area.name),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedAreaId = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Status
                      Expanded(
                        child: StackedField(
                          label: 'Status',
                          child: DropdownButtonFormField<ContentsStatus>(
                            borderRadius: AppRadius.cardRadius,
                            value: _status,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: ContentsStatus.values.map((status) {
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
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Quantity and Barcode row
                  Row(
                    children: [
                      // Quantity
                      Expanded(
                        child: StackedField(
                          label: 'Quantity',
                          child: TextFormField(
                            controller: _quantityController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                final qty = int.tryParse(value);
                                if (qty == null || qty < 1) {
                                  return 'Invalid quantity';
                                }
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Barcode
                      Expanded(
                        flex: 2,
                        child: StackedField(
                          label: 'Barcode',
                          child: TextFormField(
                            controller: _barcodeController,
                            decoration: InputDecoration(
                              hintText: 'Scan or enter barcode',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: () {
                                  // TODO: Implement barcode scanning
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Barcode scanning not yet implemented',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Photo URL
                  StackedField(
                    label: 'Photo URL',
                    child: TextFormField(
                      controller: _photoUrlController,
                      decoration: InputDecoration(
                        hintText: 'https://...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.camera_alt),
                          onPressed: () {
                            // TODO: Implement photo upload
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Photo upload not yet implemented',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_photoUrlController.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: CachedNetworkImage(
                        imageUrl: _photoUrlController.text,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: double.infinity,
                          height: 150,
                          color: AppColors.cardBorder,
                          child: const Center(
                            child: Text('Invalid image URL'),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Notes
                  StackedField(
                    label: 'Notes',
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        hintText: 'Additional notes about this item',
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
          submitLabel: isEditing ? 'Save Changes' : 'Add Item',
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

      final item = PropertyContents(
        id: widget.existingItem?.id ?? '',
        workspaceId: widget.property.workspaceId,
        projectId: widget.property.projectId,
        propertyId: widget.property.id,
        areaId: _selectedAreaId,
        itemName: _itemNameController.text.trim(),
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text.trim(),
        status: _status,
        quantity: int.tryParse(_quantityController.text) ?? 1,
        photoUrl: _photoUrlController.text.isEmpty
            ? null
            : _photoUrlController.text.trim(),
        barcode: _barcodeController.text.isEmpty
            ? null
            : _barcodeController.text.trim(),
        notes: _notesController.text.isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: widget.existingItem?.createdAt ?? now,
        updatedAt: now,
      );

      if (widget.existingItem != null) {
        await _contentsService.updateContents(item);
      } else {
        await _contentsService.createContents(item);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingItem != null ? 'Item updated' : 'Item added',
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
