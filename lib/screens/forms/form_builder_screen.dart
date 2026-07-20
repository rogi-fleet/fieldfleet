import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/form_field_definition.dart';
import '../../models/form_field_type.dart';
import '../../models/project.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../theme/theme.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import '../../widgets/forms/form_field_preview.dart';

// Shared icon lookup used by _FormBuilderScreenState and _WysiwygFieldCard.
IconData _iconForFieldType(FormFieldType type) {
  switch (type) {
    case FormFieldType.text:
      return Icons.text_fields;
    case FormFieldType.email:
      return Icons.email;
    case FormFieldType.phone:
      return Icons.phone;
    case FormFieldType.textarea:
      return Icons.notes;
    case FormFieldType.number:
      return Icons.numbers;
    case FormFieldType.date:
      return Icons.calendar_today;
    case FormFieldType.select:
      return Icons.arrow_drop_down_circle;
    case FormFieldType.multiSelect:
      return Icons.checklist;
    case FormFieldType.checkbox:
      return Icons.check_box;
    case FormFieldType.file:
      return Icons.attach_file;
    case FormFieldType.address:
      return Icons.location_on;
    case FormFieldType.photo:
      return Icons.photo_camera;
    case FormFieldType.inspectionItem:
      return Icons.fact_check;
    case FormFieldType.rating:
      return Icons.star;
    case FormFieldType.datetime:
      return Icons.schedule;
    case FormFieldType.section:
      return Icons.title;
    case FormFieldType.table:
      return Icons.table_chart;
    case FormFieldType.time:
      return Icons.access_time;
  }
}

// Groups used by the field palette.
const _paletteGroups = [
  ('Layout', [FormFieldType.section]),
  ('Basic', [
    FormFieldType.text,
    FormFieldType.email,
    FormFieldType.phone,
    FormFieldType.number,
  ]),
  ('Long text', [
    FormFieldType.textarea,
    FormFieldType.address,
  ]),
  ('Date', [FormFieldType.date, FormFieldType.datetime, FormFieldType.time]),
  ('Choice', [
    FormFieldType.select,
    FormFieldType.multiSelect,
    FormFieldType.checkbox,
  ]),
  ('Field', [
    FormFieldType.inspectionItem,
    FormFieldType.rating,
    FormFieldType.photo,
  ]),
  ('Other', [FormFieldType.file, FormFieldType.table]),
];

class FormBuilderScreen extends StatefulWidget {
  final String? formId;
  final String? projectId;

  /// When true, hides the Scaffold/AppBar so the screen can be embedded
  /// inside another widget (e.g. the project forms tab).
  final bool embedded;

  /// Called when the user presses back in embedded mode.
  final VoidCallback? onBack;

  /// Called after a successful save in embedded mode.
  final VoidCallback? onFormCreated;

  const FormBuilderScreen({
    super.key,
    this.formId,
    this.projectId,
    this.embedded = false,
    this.onBack,
    this.onFormCreated,
  });

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen>
    with SingleTickerProviderStateMixin {
  dynamic get _formService => ServiceLocator.formService;
  dynamic get _projectService => ServiceLocator.projectService;
  final _uuid = const Uuid();

  // Form-level controllers (also used in the mobile Setup tab)
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Field settings controllers
  final _fieldLabelController = TextEditingController();
  final _fieldDescriptionController = TextEditingController();
  final _fieldDefaultValueController = TextEditingController();

  List<FormFieldDefinition> _fields = [];
  FormFieldDefinition? _selectedField;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isPublic = false;
  bool _isDirty = false;
  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;
  int _mobileTab = 1; // 0 = Setup, 1 = Fields, 2 = Edit

  String? _selectedProjectId;
  List<Project> _projects = [];

  // Debounce for field-settings text changes — avoids canvas rebuild on every keystroke.
  Timer? _updateDebounce;
  FormFieldDefinition? _pendingFieldUpdate;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _selectedProjectId = widget.projectId;
    if (widget.formId != null) _isLoading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProjects();
      if (widget.formId != null) _loadForm();
    });
  }

  @override
  void dispose() {
    _updateDebounce?.cancel();
    _shakeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _fieldLabelController.dispose();
    _fieldDescriptionController.dispose();
    _fieldDefaultValueController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool get _isMobile => MediaQuery.of(context).size.width < AppBreakpoints.compact;

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  /// Schedules a field update 300 ms after the last keystroke, so the canvas
  /// only rebuilds when the user pauses — not on every character.
  void _debouncedUpdateField(FormFieldDefinition updated) {
    _pendingFieldUpdate = updated;
    _updateDebounce?.cancel();
    _updateDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_pendingFieldUpdate != null) {
        _updateField(_pendingFieldUpdate!);
        _pendingFieldUpdate = null;
      }
    });
  }

  /// Flushes any pending debounced update immediately (called before switching
  /// the selected field so in-flight edits are not lost).
  void _flushPendingUpdate() {
    if (_pendingFieldUpdate != null) {
      _updateDebounce?.cancel();
      _updateField(_pendingFieldUpdate!);
      _pendingFieldUpdate = null;
    }
  }

  void _clearValidationErrors() {
    if (_showFieldErrors) {
      setState(() {
        _showFieldErrors = false;
        _validationMessage = null;
      });
    }
  }

  bool _supportsDefaultValue(FormFieldType type) => switch (type) {
        FormFieldType.text ||
        FormFieldType.email ||
        FormFieldType.phone ||
        FormFieldType.textarea ||
        FormFieldType.number ||
        FormFieldType.date ||
        FormFieldType.address =>
          true,
        _ => false,
      };

  // ---------------------------------------------------------------------------
  // Data loading & saving
  // ---------------------------------------------------------------------------

  Future<void> _loadProjects() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
      if (workspaceId.isEmpty) return;
      final projects = await _projectService.getProjectsOnce(workspaceId);
      if (mounted) setState(() => _projects = projects);
    } catch (e) {
      debugPrint('Failed to load projects: $e');
    }
  }

  Future<void> _loadForm() async {
    try {
      final form = await _formService.getFormTemplate(widget.formId!);
      if (!mounted) return;

      if (form == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That form no longer exists.'),
          ),
        );
        context.go('/forms');
        return;
      }

      setState(() {
        _nameController.text = form.name;
        _descriptionController.text = form.description ?? '';
        _fields = List.from(form.fields);
        _isPublic = form.isPublic;
        _selectedProjectId = form.projectId;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'loading form')),
        ));
      }
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes. Leave without saving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _navigateBack() async {
    if (!_isDirty) {
      _doBack();
      return;
    }
    if (await _confirmDiscardChanges() && mounted) {
      _doBack();
    }
  }

  void _doBack() {
    if (widget.embedded && widget.onBack != null) {
      widget.onBack!();
    } else {
      context.go('/forms');
    }
  }

  Future<void> _saveForm() async {
    // Flush any debounced field edit before validating / saving.
    _flushPendingUpdate();

    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Please enter a form name';
      });
      _shakeController.forward(from: 0);
      return;
    }

    final emptyLabelIndex =
        _fields.indexWhere((f) => f.label.trim().isEmpty);
    if (emptyLabelIndex != -1) {
      final bad = _fields[emptyLabelIndex];
      setState(() {
        _showFieldErrors = true;
        _validationMessage =
            'All fields must have a label — check field ${emptyLabelIndex + 1}';
        _selectedField = bad;
        _fieldLabelController.value = const TextEditingValue(text: '');
        _fieldDescriptionController.value =
            TextEditingValue(text: bad.description ?? '');
        _fieldDefaultValueController.value =
            TextEditingValue(text: bad.defaultValue ?? '');
        if (_isMobile) _mobileTab = 2;
      });
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
      final userId = authProvider.appUser?.id ?? '';

      if (!authProvider.canCreateProjects) {
        throw const UserFacingException(
          'You do not have permission to create or edit forms in this workspace.',
        );
      }
      if (workspaceId.isEmpty) {
        throw const UserFacingException(
            'Select a workspace before saving this form.');
      }
      if (widget.formId == null && userId.isEmpty) {
        throw const UserFacingException(
            'Your account is still loading. Wait a moment and try saving again.');
      }

      if (widget.formId != null) {
        await _formService.updateFormTemplate(
          formId: widget.formId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          fields: _fields,
          isPublic: _isPublic,
          projectId: _selectedProjectId,
        );
      } else {
        await _formService.createFormTemplate(
          workspaceId: workspaceId,
          projectId: _selectedProjectId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          fields: _fields,
          isPublic: _isPublic,
          createdBy: userId,
        );
      }

      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Form saved successfully')),
        );
        if (widget.embedded && widget.onFormCreated != null) {
          widget.onFormCreated!();
        } else {
          context.go('/forms');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(UserFacingError.uiMessage(e, action: 'save this form')),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Field actions
  // ---------------------------------------------------------------------------

  void _selectField(FormFieldDefinition? field) {
    // Flush any in-flight edit for the previously selected field before switching.
    _flushPendingUpdate();
    setState(() {
      _selectedField = field;
      if (field != null) {
        // Use .value = to reset cursor position and undo history along with text.
        _fieldLabelController.value = TextEditingValue(text: field.label);
        _fieldDescriptionController.value =
            TextEditingValue(text: field.description ?? '');
        _fieldDefaultValueController.value =
            TextEditingValue(text: field.defaultValue ?? '');
        if (_isMobile) _mobileTab = 2;
      }
    });
  }

  void _addField(FormFieldType type) {
    final newField = FormFieldDefinition(
      id: _uuid.v4(),
      type: type,
      label: '${type.displayName} Field',
      isRequired: false,
      order: _fields.length,
    );
    setState(() => _fields.add(newField));
    _markDirty();
    _selectField(newField);
  }

  void _updateField(FormFieldDefinition updated) {
    setState(() {
      final index = _fields.indexWhere((f) => f.id == updated.id);
      if (index != -1) {
        _fields[index] = updated;
        _selectedField = updated;
      }
    });
    _markDirty();
  }

  void _deleteField(String fieldId) {
    final wasSelected = _selectedField?.id == fieldId;
    setState(() {
      _fields.removeWhere((f) => f.id == fieldId);
      if (wasSelected) _selectedField = null;
      for (int i = 0; i < _fields.length; i++) {
        _fields[i] = _fields[i].copyWith(order: i);
      }
    });
    _markDirty();
  }

  void _duplicateField(String fieldId) {
    final index = _fields.indexWhere((f) => f.id == fieldId);
    if (index == -1) return;
    final duplicate = _fields[index].copyWith(
      id: _uuid.v4(),
      label: '${_fields[index].label} (copy)',
      order: _fields.length,
    );
    setState(() => _fields.add(duplicate));
    _markDirty();
  }

  void _reorderFields(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final field = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, field);
      for (int i = 0; i < _fields.length; i++) {
        _fields[i] = _fields[i].copyWith(order: i);
      }
      // Keep _selectedField pointing at the updated object (copyWith creates new instances).
      if (_selectedField != null) {
        _selectedField = _fields.firstWhere(
          (f) => f.id == _selectedField!.id,
          orElse: () => _selectedField!,
        );
      }
    });
    _markDirty();
  }

  // ---------------------------------------------------------------------------
  // Mobile: add-field bottom sheet
  // ---------------------------------------------------------------------------

  void _showAddFieldSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add a field',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: FormFieldType.values.map((type) {
                  return ListTile(
                    leading: Icon(_iconForFieldType(type),
                        color: AppColors.textSecondary),
                    title: Text(type.displayName),
                    onTap: () {
                      Navigator.pop(context);
                      _addField(type);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final saveButton = AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final dx = _shakeController.isAnimating
            ? math.sin(_shakeController.value * math.pi * 4) * 6
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: TextButton.icon(
        onPressed: _isSaving ? null : _saveForm,
        icon: _isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: const Text('Save'),
      ),
    );

    final appBar = AppBar(
      title: Text(widget.formId != null ? 'Edit Form' : 'Create Form'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _navigateBack,
      ),
      actions: [
        if (_isDirty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                '●',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
        saveButton,
      ],
    );

    // PopScope intercepts the Android back button / predictive-back gesture.
    // The leading close button uses _navigateBack() which runs the same check.
    Widget wrapPopScope(Widget child) => PopScope(
          canPop: !_isDirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final shouldLeave = await _confirmDiscardChanges();
            if (shouldLeave && mounted) {
              _doBack();
            }
          },
          child: child,
        );

    if (_isMobile) {
      Widget mobileBody;
      switch (_mobileTab) {
        case 0:
          mobileBody =
              SingleChildScrollView(child: _buildMobileSetupTab());
        case 2:
          mobileBody = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_selectedField != null)
                  _buildFieldSettingsContent()
                else
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      children: [
                        Icon(Icons.touch_app_outlined,
                            size: 32, color: AppColors.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          'Select a field in the Fields tab to edit it',
                          style:
                              TextStyle(color: AppColors.textTertiary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                _buildFormSettingsSection(),
              ],
            ),
          );
        default: // 1 = Fields
          mobileBody = _buildFormCanvas();
      }

      if (widget.embedded) {
        return wrapPopScope(Column(
          children: [
            _buildEmbeddedHeader(saveButton),
            Expanded(child: mobileBody),
            NavigationBar(
              selectedIndex: _mobileTab,
              onDestinationSelected: (i) => setState(() => _mobileTab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Setup',
                ),
                NavigationDestination(
                  icon: Icon(Icons.list_outlined),
                  selectedIcon: Icon(Icons.list),
                  label: 'Fields',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Edit',
                ),
              ],
            ),
          ],
        ));
      }

      return wrapPopScope(Scaffold(
        appBar: appBar,
        body: mobileBody,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _mobileTab,
          onDestinationSelected: (i) => setState(() => _mobileTab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Setup',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_outlined),
              selectedIcon: Icon(Icons.list),
              label: 'Fields',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Edit',
            ),
          ],
        ),
      ));
    }

    // Desktop — 3-column layout
    if (widget.embedded) {
      return wrapPopScope(Column(
        children: [
          _buildEmbeddedHeader(saveButton),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFieldPalette(),
                const VerticalDivider(width: 1),
                Expanded(child: _buildFormCanvas()),
                _buildRightPanel(),
              ],
            ),
          ),
        ],
      ));
    }

    return wrapPopScope(Scaffold(
      appBar: appBar,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFieldPalette(),
          const VerticalDivider(width: 1),
          Expanded(child: _buildFormCanvas()),
          _buildRightPanel(),
        ],
      ),
    ));
  }

  // ---------------------------------------------------------------------------
  // Embedded header bar (used instead of AppBar when embedded: true)
  // ---------------------------------------------------------------------------

  Widget _buildEmbeddedHeader(Widget saveButton) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _navigateBack,
          ),
          Expanded(
            child: Text(
              widget.formId != null ? 'Edit Form' : 'Create Form',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (_isDirty)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                '●',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          saveButton,
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Left panel — field palette (desktop)
  // ---------------------------------------------------------------------------

  Widget _buildFieldPalette() {
    return SizedBox(
      width: 200,
      child: Container(
        color: AppColors.surfaceAlt,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                'ADD FIELD',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            for (final (groupLabel, types) in _paletteGroups)
              _buildPaletteGroup(groupLabel, types),
          ],
        ),
      ),
    );
  }

  Widget _buildPaletteGroup(String label, List<FormFieldType> types) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final type in types) _buildPaletteItem(type),
      ],
    );
  }

  Widget _buildPaletteItem(FormFieldType type) {
    return InkWell(
      onTap: () => _addField(type),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 7),
        child: Row(
          children: [
            Icon(_iconForFieldType(type),
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                type.displayName,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile setup tab
  // ---------------------------------------------------------------------------

  Widget _buildMobileSetupTab() {
    final projectTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildValidationBanner(),
          StackedField(
            label: 'Form Name',
            child: TextField(
              controller: _nameController,
              onChanged: (_) {
                _clearValidationErrors();
                _markDirty();
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.md),
                errorText: _showFieldErrors &&
                        _nameController.text.trim().isEmpty
                    ? 'Form name is required'
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          StackedField(
            label: 'Description',
            child: TextField(
              controller: _descriptionController,
              maxLines: 3,
              onChanged: (_) => _markDirty(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(AppSpacing.md),
              ),
            ),
          ),
          const SizedBox(height: 12),
          StackedField(
            label: '$singular (optional)',
            child: DropdownButtonFormField<String?>(
              borderRadius: AppRadius.cardRadius,
              initialValue: _selectedProjectId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
              ),
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'No ${singular.toLowerCase()}',
                    style:
                        const TextStyle(color: AppColors.textTertiary),
                  ),
                ),
                ..._projects.map(
                  (p) => DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedProjectId = value;
                  _isDirty = true;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title:
                const Text('Public Form', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Allow anyone to submit',
                style: TextStyle(fontSize: 12)),
            value: _isPublic,
            onChanged: (value) =>
                setState(() => _isPublic = value),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Center — WYSIWYG canvas
  // ---------------------------------------------------------------------------

  Widget _buildFormCanvas() {
    return Container(
      color: AppColors.surfaceAlt,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Inline form header (desktop only; mobile uses Setup tab)
                if (!_isMobile) ...[
                  _buildCanvasHeader(),
                  const SizedBox(height: 20),
                ],

                // Field list
                if (_fields.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _fields.length,
                    onReorder: _reorderFields,
                    proxyDecorator: (child, index, animation) => Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      shadowColor: Colors.black26,
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      final field = _fields[index];
                      return _WysiwygFieldCard(
                        key: ValueKey(field.id),
                        field: field,
                        index: index,
                        isSelected: _selectedField?.id == field.id,
                        onTap: () => _selectField(
                          _selectedField?.id == field.id ? null : field,
                        ),
                        onDuplicate: () => _duplicateField(field.id),
                        onDelete: () => _deleteField(field.id),
                      );
                    },
                  ),

                // Empty state
                if (_fields.isEmpty) _buildEmptyCanvasHint(),

                // Add-field button (mobile only — desktop uses left palette)
                if (_isMobile) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _showAddFieldSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a field'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Inline, borderless form title + description at the top of the canvas.
  Widget _buildCanvasHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildValidationBanner(),
          TextField(
            controller: _nameController,
            onChanged: (_) {
              _clearValidationErrors();
              _markDirty();
            },
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            decoration: InputDecoration(
              hintText: 'Form title',
              hintStyle: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.bold,
                  ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          TextField(
            controller: _descriptionController,
            onChanged: (_) => _markDirty(),
            maxLines: null,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
            decoration: InputDecoration(
              hintText: 'Add a description (optional)',
              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textTertiary,
                  ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCanvasHint() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl, horizontal: AppSpacing.xxl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.add_box_outlined,
              size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            _isMobile
                ? 'Tap "Add a field" below to get started'
                : 'Click a field type on the left to add it',
            style:
                TextStyle(fontSize: 14, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Right panel — field settings + form settings (no tabs)
  // ---------------------------------------------------------------------------

  Widget _buildRightPanel() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Field settings or hint
            if (_selectedField != null)
              _buildFieldSettingsContent()
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
                child: Column(
                  children: [
                    Icon(Icons.touch_app_outlined,
                        size: 28, color: AppColors.textTertiary),
                    const SizedBox(height: 10),
                    Text(
                      'Click a field to edit its settings',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            _buildFormSettingsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldSettingsContent() {
    final field = _selectedField!;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconForFieldType(field.type),
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Text(
                  field.type.displayName,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          StackedField(
            label: 'Label',
            child: TextField(
              controller: _fieldLabelController,
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
              onChanged: (value) =>
                  _debouncedUpdateField(field.copyWith(label: value)),
            ),
          ),
          const SizedBox(height: 14),

          StackedField(
            label: 'Description (optional)',
            child: TextField(
              controller: _fieldDescriptionController,
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
              onChanged: (value) =>
                  _debouncedUpdateField(field.copyWith(description: value)),
            ),
          ),
          const SizedBox(height: 14),

          if (_supportsDefaultValue(field.type)) ...[
            StackedField(
              label: 'Default value (optional)',
              child: TextField(
                controller: _fieldDefaultValueController,
                decoration:
                    const InputDecoration(border: OutlineInputBorder()),
                onChanged: (value) =>
                    _debouncedUpdateField(field.copyWith(defaultValue: value)),
              ),
            ),
            const SizedBox(height: 14),
          ],

          SwitchListTile(
            title: const Text('Required'),
            subtitle: const Text('Users must fill this field'),
            value: field.isRequired,
            onChanged: (value) =>
                _updateField(field.copyWith(isRequired: value)),
            contentPadding: EdgeInsets.zero,
          ),

          if (field.type == FormFieldType.select ||
              field.type == FormFieldType.multiSelect) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 14),
            Text(
              'Options',
              style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            _OptionsEditor(field: field, onChanged: _updateField),
          ],

          const SizedBox(height: 8),
          // Dismiss / close
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _selectField(null),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Done'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Form-level settings — always visible at the bottom of the right panel.
  Widget _buildFormSettingsSection() {
    final projectTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_outlined,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'FORM SETTINGS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StackedField(
            label: '$singular (optional)',
            child: DropdownButtonFormField<String?>(
              borderRadius: AppRadius.cardRadius,
              initialValue: _selectedProjectId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
              ),
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'No ${singular.toLowerCase()}',
                    style:
                        const TextStyle(color: AppColors.textTertiary),
                  ),
                ),
                ..._projects.map(
                  (p) => DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedProjectId = value;
                  _isDirty = true;
                });
              },
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('Public form',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text('Allow anyone to submit',
                style: TextStyle(fontSize: 12)),
            value: _isPublic,
            onChanged: (value) {
              setState(() {
                _isPublic = value;
                _isDirty = true;
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildValidationBanner() {
    if (!_showFieldErrors || _validationMessage == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: AppColors.error),
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
}

// =============================================================================
// WYSIWYG field card — renders the field as it looks to a submitter.
// Tapping selects/deselects; an action bar appears above when selected.
// =============================================================================

class _WysiwygFieldCard extends StatelessWidget {
  final FormFieldDefinition field;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _WysiwygFieldCard({
    required super.key,
    required this.field,
    required this.index,
    required this.isSelected,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Action bar — slides in above the selected field
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _actionButton(
                          Icons.content_copy_outlined,
                          'Duplicate',
                          onDuplicate,
                          Colors.white,
                        ),
                        _actionButton(
                          Icons.delete_outline,
                          'Delete',
                          onDelete,
                          Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Field card
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color:
                      isSelected ? primaryColor : AppColors.cardBorder,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subtle drag handle
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 18, 6, 16),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 16,
                        color: isSelected
                            ? primaryColor.withValues(alpha: 0.45)
                            : AppColors.textTertiary
                                .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  // Field content
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(8, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  field.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (field.isRequired)
                                const Text(
                                  ' *',
                                  style: TextStyle(
                                      color: AppColors.error),
                                ),
                            ],
                          ),
                          if (field.description != null &&
                              field.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              field.description!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 10),
                          FormFieldPreview(field: field),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
    Color color,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }

}

// =============================================================================
// Options editor — StatefulWidget with properly managed TextEditingControllers.
// =============================================================================

class _OptionsEditor extends StatefulWidget {
  final FormFieldDefinition field;
  final ValueChanged<FormFieldDefinition> onChanged;

  const _OptionsEditor({required this.field, required this.onChanged});

  @override
  State<_OptionsEditor> createState() => _OptionsEditorState();
}

class _OptionsEditorState extends State<_OptionsEditor> {
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    for (final opt in widget.field.options ?? []) {
      _controllers.add(TextEditingController(text: opt));
    }
  }

  @override
  void didUpdateWidget(_OptionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.field.id != widget.field.id) {
      _disposeAll();
      for (final opt in widget.field.options ?? []) {
        _controllers.add(TextEditingController(text: opt));
      }
    } else {
      final options = widget.field.options ?? [];
      while (_controllers.length > options.length) {
        _controllers.removeLast().dispose();
      }
      while (_controllers.length < options.length) {
        _controllers.add(
          TextEditingController(text: options[_controllers.length]),
        );
      }
    }
  }

  void _disposeAll() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
  }

  @override
  void dispose() {
    _disposeAll();
    super.dispose();
  }

  void _addOption() {
    final options = List<String>.from(widget.field.options ?? []);
    final label = 'Option ${options.length + 1}';
    options.add(label);
    setState(() => _controllers.add(TextEditingController(text: label)));
    widget.onChanged(widget.field.copyWith(options: options));
  }

  void _removeOption(int index) {
    final options = List<String>.from(widget.field.options ?? []);
    options.removeAt(index);
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
    widget.onChanged(widget.field.copyWith(options: options));
  }

  void _updateOption(int index, String value) {
    final options = List<String>.from(widget.field.options ?? []);
    options[index] = value;
    widget.onChanged(widget.field.copyWith(options: options));
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.field.options ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[i],
                    decoration: InputDecoration(
                      hintText: 'Option ${i + 1}',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      isDense: true,
                    ),
                    onChanged: (value) => _updateOption(i, value),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppColors.error,
                  onPressed: () => _removeOption(i),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: _addOption,
          icon: const Icon(Icons.add),
          label: const Text('Add Option'),
        ),
      ],
    );
  }
}
