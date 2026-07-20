import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/company_type.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';

import '../../theme/theme.dart';
import '../../utils/timezone_options.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class CreateWorkspaceScreen extends StatefulWidget {
  const CreateWorkspaceScreen({super.key});

  @override
  State<CreateWorkspaceScreen> createState() => _CreateWorkspaceScreenState();
}

class _CreateWorkspaceScreenState extends State<CreateWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _projectTerminologyController = TextEditingController();
  final _startingSerialNumberController = TextEditingController();
  bool _isLoading = false;
  String _selectedTimezone = TimezoneOptions.defaultTimezone;
  CompanyType? _selectedCompanyType = CompanyType.other; // Default to 'Other'

  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _nameController.dispose();
    _projectTerminologyController.dispose();
    _startingSerialNumberController.dispose();
    super.dispose();
  }

  void _clearValidationErrors() {
    if (_showFieldErrors || _validationMessage != null) {
      setState(() {
        _showFieldErrors = false;
        _validationMessage = null;
      });
    }
  }

  Widget _buildValidationBanner() {
    if (!_showFieldErrors || _validationMessage == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _validationMessage!,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<CompanyType>> _buildCompanyTypeItems() {
    final Map<String, List<CompanyType>> grouped = {};

    // Group company types by category
    for (final type in CompanyType.values) {
      final category = type.category;
      if (!grouped.containsKey(category)) {
        grouped[category] = [];
      }
      grouped[category]!.add(type);
    }

    final List<DropdownMenuItem<CompanyType>> items = [];

    // Add items with category headers
    grouped.forEach((category, types) {
      // Add category header (disabled)
      items.add(
        DropdownMenuItem<CompanyType>(
          value: null,
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              category,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ),
      );

      // Add company types under this category
      items.addAll(
        types.map(
          (type) => DropdownMenuItem<CompanyType>(
            value: type,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Row(
                children: [
                  Icon(type.icon, size: 20, color: AppColors.textTertiary),
                  const SizedBox(width: 12),
                  Text(type.displayName),
                ],
              ),
            ),
          ),
        ),
      );
    });

    return items;
  }

  Future<void> _createWorkspace() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Please fix the errors above';
      });
      _shakeController.forward(from: 0);
      return;
    }

    if (_selectedCompanyType == null) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Please select a company type';
      });
      _shakeController.forward(from: 0);
      return;
    }

    _clearValidationErrors();

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Create workspace
      final workspaceId = await ServiceLocator.workspaceService.createWorkspace(
        name: _nameController.text.trim(),
        ownerId: userId,
        companyType: _selectedCompanyType!,
        projectTerminology: _projectTerminologyController.text.trim().isEmpty
            ? null
            : _projectTerminologyController.text.trim(),
        startingProjectSerialNumber:
            _startingSerialNumberController.text.trim().isEmpty
            ? null
            : int.tryParse(_startingSerialNumberController.text.trim()),
        timezone: _selectedTimezone,
      );

      if (!mounted) return;

      // Switch to new workspace
      await authProvider.switchWorkspace(workspaceId);

      if (!mounted) return;

      // Refresh workspace list
      await context.read<WorkspaceProvider>().loadWorkspaces(userId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workspace created successfully')),
      );

      // Navigate to dashboard
      context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Error creating workspace: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Workspace')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildValidationBanner(),
                Icon(Icons.work_outline, size: 64, color: AppColors.info),
                const SizedBox(height: 32),
                Text(
                  'Name your workspace',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This is the name of your company or team.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                StackedField(
                  label: 'Workspace Name',
                  child: TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Acme Corp',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a workspace name';
                      }
                      return null;
                    },
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: 'Company Type',
                  child: DropdownButtonFormField<CompanyType>(
                    borderRadius: AppRadius.cardRadius,
                    value: _selectedCompanyType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business_center),
                      helperText: 'Select the type of company',
                    ),
                    items: _buildCompanyTypeItems(),
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a company type';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setState(() {
                        _selectedCompanyType = value;
                        // Auto-fill project terminology if empty
                        if (_projectTerminologyController.text.isEmpty &&
                            value != null) {
                          _projectTerminologyController.text =
                              value.defaultProjectTerminology;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: 'Project Terminology (Optional)',
                  child: TextFormField(
                    controller: _projectTerminologyController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Jobs, Sites, Projects',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder),
                      helperText:
                          'Customize what you call projects in your workspace',
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _createWorkspace(),
                  ),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: 'Starting Project Serial Number (Optional)',
                  child: TextFormField(
                    controller: _startingSerialNumberController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 100',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                      helperText: 'Set the starting number for new projects',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final number = int.tryParse(value.trim());
                        if (number == null || number < 1) {
                          return 'Please enter a positive number';
                        }
                      }
                      return null;
                    },
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _createWorkspace(),
                  ),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: 'Timezone',
                  child: DropdownButtonFormField<String>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: _selectedTimezone,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.schedule),
                      helperText: 'Default workspace timezone',
                    ),
                    items: TimezoneOptions.common.map((tz) {
                      return DropdownMenuItem<String>(
                        value: tz.id,
                        child: Text(tz.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedTimezone = value);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final dx = _shakeController.isAnimating
                        ? math.sin(_shakeController.value * math.pi * 4) * 6
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: FilledButton(
                    onPressed: _isLoading ? null : _createWorkspace,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Workspace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
