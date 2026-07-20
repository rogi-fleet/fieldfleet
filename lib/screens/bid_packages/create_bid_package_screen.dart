import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/document_line_item.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/document_line_item_editor.dart';

/// Compose a new multi-vendor bid package: pick a project, pick vendors,
/// define the scope + line-item template, send.
class CreateBidPackageScreen extends StatefulWidget {
  const CreateBidPackageScreen({super.key, this.initialProjectId});

  final String? initialProjectId;

  @override
  State<CreateBidPackageScreen> createState() =>
      _CreateBidPackageScreenState();
}

class _CreateBidPackageScreenState extends State<CreateBidPackageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _scopeController = TextEditingController();

  DateTime? _dueDate;
  Project? _selectedProject;
  final Set<String> _selectedVendorIds = <String>{};
  List<DocumentLineItem> _lineItems = const [];

  List<Project> _projects = const [];
  List<Vendor> _vendors = const [];

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scopeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final workspaceId = context
          .read<AuthProvider>()
          .appUser
          ?.currentWorkspaceId;
      if (workspaceId == null) {
        setState(() {
          _loading = false;
          _error = 'No workspace in context.';
        });
        return;
      }

      final projectsFuture = ServiceLocator.projectService
          .getProjectsOnce(workspaceId);
      final vendorsFuture =
          ServiceLocator.vendorService.getVendors(workspaceId).first;
      final results = await Future.wait<dynamic>([projectsFuture, vendorsFuture]);

      if (!mounted) return;
      final projects = (results[0] as List).cast<Project>();
      final vendors = (results[1] as List).cast<Vendor>();

      setState(() {
        _loading = false;
        _projects = projects;
        _vendors = vendors;
        if (widget.initialProjectId != null) {
          _selectedProject = projects.firstWhere(
            (p) => p.id == widget.initialProjectId,
            orElse: () => projects.isNotEmpty ? projects.first : projects.first,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = UserFacingError.uiMessage(
          e,
          action: 'load projects and vendors',
        );
      });
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorIds.isEmpty) {
      setState(() => _error = 'Select at least one vendor');
      return;
    }
    if (_lineItems.where((li) => li.isItem).isEmpty) {
      setState(() => _error = 'Add at least one line item to quote');
      return;
    }

    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final packageId = await ServiceLocator.bidPackageService.createPackage(
        workspaceId: workspaceId,
        projectId: _selectedProject?.id,
        name: _nameController.text.trim(),
        scopeDescription: _scopeController.text.trim().isEmpty
            ? null
            : _scopeController.text.trim(),
        dueDate: _dueDate,
        vendorIds: _selectedVendorIds.toList(),
        lineItemTemplate: _lineItems.where((li) => li.isItem).toList(),
      );
      if (!mounted) return;
      context.go('/bid-packages/$packageId');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = UserFacingError.uiMessage(
          e,
          action: 'create the bid package',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Bid Package'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Package name',
                        hintText: 'e.g. HVAC rough-in — 123 Main St',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _scopeController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Scope description (optional)',
                        hintText:
                            'What you\'re asking vendors to quote — shown at the top of each RFB.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _projectPicker(),
                    const SizedBox(height: 12),
                    _dueDatePicker(),
                    const SizedBox(height: 20),
                    _vendorSelector(),
                    const SizedBox(height: 20),
                    Text(
                      'Line items',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'The scope the vendor will price. Unit price is your '
                      'internal estimate — vendors don\'t see it.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DocumentLineItemEditor(
                      projectId: _selectedProject?.id,
                      workspaceId: workspaceId,
                      initialItems: _lineItems,
                      onChanged: (items, _, __) {
                        setState(() => _lineItems = items);
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _projectPicker() {
    final projectTerm = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    return DropdownButtonFormField<String>(
      initialValue: _selectedProject?.id,
      decoration: InputDecoration(
        labelText: '$projectTerm (optional)',
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text('— Not linked to a ${projectTerm.toLowerCase()} —'),
        ),
        ..._projects.map(
          (p) => DropdownMenuItem<String>(
            value: p.id,
            child: Text(p.name),
          ),
        ),
      ],
      onChanged: (v) {
        setState(() {
          _selectedProject = v == null
              ? null
              : _projects.firstWhere((p) => p.id == v);
        });
      },
    );
  }

  Widget _dueDatePicker() {
    return InkWell(
      onTap: _pickDueDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Bid due date (optional)',
          border: OutlineInputBorder(),
        ),
        child: Text(
          _dueDate == null
              ? 'Pick a date'
              : DateFormat.yMMMd().format(_dueDate!),
          style: TextStyle(
            color: _dueDate == null ? AppColors.textTertiary : null,
          ),
        ),
      ),
    );
  }

  Widget _vendorSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Send to',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_selectedVendorIds.length} selected',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_vendors.isEmpty)
          Text(
            'No vendors in this workspace yet.',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              children: [
                for (final v in _vendors)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selectedVendorIds.contains(v.id),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedVendorIds.add(v.id);
                        } else {
                          _selectedVendorIds.remove(v.id);
                        }
                      });
                    },
                    title: Text(v.companyName),
                    subtitle: v.businessEmail != null && v.businessEmail!.isNotEmpty
                        ? Text(
                            v.businessEmail!,
                            style: const TextStyle(fontSize: 11),
                          )
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
