import 'package:flutter/material.dart';
import '../services/service_locator.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../models/cost_item.dart';
import '../models/cost_category.dart';


import '../providers/auth_provider.dart';
import '../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class CostItemForm extends StatefulWidget {
  final String projectId;
  final CostItem? costItem; // null for new item, existing item for editing

  const CostItemForm({super.key, required this.projectId, this.costItem});

  @override
  State<CostItemForm> createState() => _CostItemFormState();
}

class _CostItemFormState extends State<CostItemForm> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _notesController = TextEditingController();

  final _costService = ServiceLocator.costService;
  final _categoryService = ServiceLocator.costCategoryService;

  CostItemType _selectedType = CostItemType.material;
  String? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.costItem != null) {
      // Populate form with existing data
      _descriptionController.text = widget.costItem!.description;
      _quantityController.text = widget.costItem!.quantity.toString();
      _unitPriceController.text = widget.costItem!.unitPrice.toString();
      _notesController.text = widget.costItem!.notes ?? '';
      _selectedType = widget.costItem!.type;
      _selectedCategoryId = widget.costItem!.categoryId;
      _selectedDate = widget.costItem!.date;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String get _quantityLabel {
    return _selectedType == CostItemType.labor ? 'Hours' : 'Quantity';
  }

  String get _unitPriceLabel {
    return _selectedType == CostItemType.labor ? 'Hourly Rate' : 'Unit Price';
  }

  Future<void> _saveCostItem() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser!.workspaceId;
      final userId = authProvider.currentUserId!;

      final now = DateTime.now();

      if (widget.costItem == null) {
        // Create new cost item
        final newItem = CostItem(
          id: '', // Will be set by Firestore
          projectId: widget.projectId,
          workspaceId: workspaceId,
          type: _selectedType,
          categoryId: _selectedCategoryId!,
          description: _descriptionController.text.trim(),
          quantity: double.parse(_quantityController.text),
          unitPrice: double.parse(_unitPriceController.text),
          date: _selectedDate,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          createdBy: userId,
          createdAt: now,
          updatedAt: now,
        );

        await _costService.createCostItem(newItem);
      } else {
        // Update existing cost item
        final updatedItem = widget.costItem!.copyWith(
          type: _selectedType,
          categoryId: _selectedCategoryId,
          description: _descriptionController.text.trim(),
          quantity: double.parse(_quantityController.text),
          unitPrice: double.parse(_unitPriceController.text),
          date: _selectedDate,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          updatedAt: now,
        );

        await _costService.updateCostItem(updatedItem);
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving cost item'),
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

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.workspaceId;

    if (workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: No workspace found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.costItem == null ? 'Add Cost Item' : 'Edit Cost Item',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Type selector
              SegmentedButton<CostItemType>(
                segments: const [
                  ButtonSegment(
                    value: CostItemType.material,
                    label: Text('Material'),
                    icon: Icon(Icons.construction),
                  ),
                  ButtonSegment(
                    value: CostItemType.labor,
                    label: Text('Labor'),
                    icon: Icon(Icons.person),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (Set<CostItemType> selection) {
                  setState(() {
                    _selectedType = selection.first;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Description field
              StackedField(
                label: 'Description',
                child: TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Quantity field
              StackedField(
                label: _quantityLabel,
                child: TextFormField(
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.pin),
                    helperText: _selectedType == CostItemType.labor
                        ? 'Number of hours worked'
                        : 'Number of units',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter $_quantityLabel';
                    }
                    final number = double.tryParse(value);
                    if (number == null || number <= 0) {
                      return 'Please enter a valid positive number';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Unit price field
              StackedField(
                label: _unitPriceLabel,
                child: TextFormField(
                  controller: _unitPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.attach_money),
                    helperText: _selectedType == CostItemType.labor
                        ? 'Rate per hour (\$)'
                        : 'Price per unit (\$)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter $_unitPriceLabel';
                    }
                    final number = double.tryParse(value);
                    if (number == null || number <= 0) {
                      return 'Please enter a valid positive number';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Category dropdown
              StreamBuilder<List<CostCategory>>(
                stream: _categoryService.getCategories(workspaceId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return SelectableText(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load data',
                      ),
                    );
                  }

                  final categories = snapshot.data ?? [];

                  if (categories.isEmpty) {
                    return const Text('No categories available');
                  }

                  // Set default if not already set
                  if (_selectedCategoryId == null && categories.isNotEmpty) {
                    _selectedCategoryId = categories.first.id;
                  }

                  return StackedField(
                    label: 'Category',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: categories.map((category) {
                        return DropdownMenuItem(
                          value: category.id,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Color(
                                    int.parse(
                                          category.color.substring(1),
                                          radix: 16,
                                        ) +
                                        0xFF000000,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(category.name),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Date picker
              StackedField(
                label: 'Date',
                child: InkWell(
                  onTap: () => _selectDate(context),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      '${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Notes field
              StackedField(
                label: 'Notes (optional)',
                child: TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Calculated total
              if (_quantityController.text.isNotEmpty &&
                  _unitPriceController.text.isNotEmpty)
                Card(
                  color: AppColors.infoLight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Cost:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${((double.tryParse(_quantityController.text) ?? 0) * (double.tryParse(_unitPriceController.text) ?? 0)).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveCostItem,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
