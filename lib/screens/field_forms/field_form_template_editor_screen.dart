import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/field_form_template.dart';
import '../../models/form_field_definition.dart';
import '../../models/form_field_type.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../widgets/forms/stacked_field.dart';
import '../../theme/theme.dart';

class FieldFormTemplateEditorScreen extends StatefulWidget {
  const FieldFormTemplateEditorScreen({
    super.key,
    this.templateId,
  });

  /// Null means creating a new template.
  final String? templateId;

  @override
  State<FieldFormTemplateEditorScreen> createState() =>
      _FieldFormTemplateEditorScreenState();
}

class _FieldFormTemplateEditorScreenState
    extends State<FieldFormTemplateEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _uuid = const Uuid();

  FieldFormCategory _category = FieldFormCategory.custom;
  bool _requiresTech = false;
  bool _requiresSupervisor = false;
  bool _requiresCustomer = false;
  List<FormFieldDefinition> _fields = [];

  bool _isLoading = false;
  bool _isSaving = false;

  dynamic get _service => ServiceLocator.fieldFormService;
  bool get _isEditing => widget.templateId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadTemplate();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() => _isLoading = true);
    try {
      final template = await _service.getTemplate(widget.templateId!);
      if (!mounted) return;

      if (template == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That template no longer exists.'),
          ),
        );
        context.go('/field-forms');
        return;
      }

      setState(() {
        _nameController.text = template.name;
        _descriptionController.text = template.description ?? '';
        _category = template.category;
        _requiresTech = template.requiresTechSignature;
        _requiresSupervisor = template.requiresSupervisorSignature;
        _requiresCustomer = template.requiresCustomerSignature;
        _fields = List<FormFieldDefinition>.from(template.fields);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id;
    final workspaceId = auth.appUser?.currentWorkspaceId;
    if (userId == null || workspaceId == null) return;

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await _service.updateTemplate(
          templateId: widget.templateId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          clearDescription: _descriptionController.text.trim().isEmpty,
          category: _category,
          fields: _fields,
          requiresTechSignature: _requiresTech,
          requiresSupervisorSignature: _requiresSupervisor,
          requiresCustomerSignature: _requiresCustomer,
        );
      } else {
        await _service.createTemplate(
          workspaceId: workspaceId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          category: _category,
          fields: _fields,
          requiresTechSignature: _requiresTech,
          requiresSupervisorSignature: _requiresSupervisor,
          requiresCustomerSignature: _requiresCustomer,
          createdBy: userId,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  _isEditing ? 'Template updated' : 'Template created')),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/field-forms');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isEditing ? 'Edit Template' : 'New Template'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  _buildInfoSection(context),
                  const SizedBox(height: 16),
                  _buildSignatureSection(context),
                  const SizedBox(height: 16),
                  _buildFieldsSection(context),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Template Info',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 16),
            StackedField(
              label: 'Name *',
              child: TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Job Completion Report',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Description',
              child: TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Optional description…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Category',
              child: DropdownButtonFormField<FieldFormCategory>(
                value: _category,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: FieldFormCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.displayName),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signature Requirements',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Select who must sign this form before it is considered complete.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _requiresTech,
              onChanged: (v) =>
                  setState(() => _requiresTech = v ?? false),
              title: const Text('Technician'),
              subtitle: const Text('The person filling the form'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              value: _requiresSupervisor,
              onChanged: (v) =>
                  setState(() => _requiresSupervisor = v ?? false),
              title: const Text('Supervisor'),
              subtitle: const Text('Internal review & approval'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              value: _requiresCustomer,
              onChanged: (v) =>
                  setState(() => _requiresCustomer = v ?? false),
              title: const Text('Customer'),
              subtitle: const Text('External — sent via link'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldsSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Fields',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton.icon(
                  onPressed: () => _showAddFieldDialog(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Field'),
                ),
              ],
            ),
            if (_fields.isEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'No fields yet. Add fields to build your form.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
            ] else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _fields.removeAt(oldIndex);
                    _fields.insert(newIndex, item);
                    // Re-assign order values
                    for (var i = 0; i < _fields.length; i++) {
                      _fields[i] = _fields[i].copyWith(order: i);
                    }
                  });
                },
                itemCount: _fields.length,
                itemBuilder: (context, index) {
                  final field = _fields[index];
                  return _FieldListTile(
                    key: ValueKey(field.id),
                    field: field,
                    onEdit: () => _showEditFieldDialog(context, index),
                    onDelete: () =>
                        setState(() => _fields.removeAt(index)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddFieldDialog(BuildContext context) async {
    final newField = FormFieldDefinition(
      id: _uuid.v4(),
      type: FormFieldType.text,
      label: '',
      order: _fields.length,
    );
    final result = await showDialog<FormFieldDefinition>(
      context: context,
      builder: (_) => _FieldEditorDialog(
        field: newField,
        otherFields: _fields,
      ),
    );
    if (result != null) {
      setState(() => _fields.add(result));
    }
  }

  Future<void> _showEditFieldDialog(BuildContext context, int index) async {
    final result = await showDialog<FormFieldDefinition>(
      context: context,
      builder: (_) => _FieldEditorDialog(
        field: _fields[index],
        otherFields: [
          for (var i = 0; i < _fields.length; i++)
            if (i != index) _fields[i],
        ],
      ),
    );
    if (result != null) {
      setState(() => _fields[index] = result);
    }
  }
}

class _FieldListTile extends StatelessWidget {
  const _FieldListTile({
    super.key,
    required this.field,
    required this.onEdit,
    required this.onDelete,
  });

  final FormFieldDefinition field;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: key,
      dense: true,
      leading: Icon(_typeIcon(field.type),
          size: 18, color: AppColors.textSecondary),
      title: Row(
        children: [
          Text(field.label.isEmpty ? '(untitled)' : field.label),
          if (field.isRequired)
            const Text(' *',
                style: TextStyle(color: AppColors.error)),
        ],
      ),
      subtitle: Text(field.type.displayName,
          style: const TextStyle(fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
            tooltip: 'Edit field',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
            tooltip: 'Remove field',
            color: AppColors.error,
            visualDensity: VisualDensity.compact,
          ),
          const Icon(Icons.drag_handle, size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  IconData _typeIcon(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
        return Icons.text_fields;
      case FormFieldType.email:
        return Icons.email_outlined;
      case FormFieldType.phone:
        return Icons.phone_outlined;
      case FormFieldType.textarea:
        return Icons.notes;
      case FormFieldType.number:
        return Icons.numbers;
      case FormFieldType.date:
        return Icons.calendar_today;
      case FormFieldType.datetime:
        return Icons.schedule;
      case FormFieldType.select:
        return Icons.arrow_drop_down_circle_outlined;
      case FormFieldType.multiSelect:
        return Icons.checklist;
      case FormFieldType.checkbox:
        return Icons.check_box_outlined;
      case FormFieldType.file:
        return Icons.attach_file;
      case FormFieldType.address:
        return Icons.location_on_outlined;
      case FormFieldType.photo:
        return Icons.photo_camera_outlined;
      case FormFieldType.inspectionItem:
        return Icons.fact_check_outlined;
      case FormFieldType.rating:
        return Icons.star_border;
      case FormFieldType.section:
        return Icons.title;
      case FormFieldType.table:
        return Icons.table_chart_outlined;
      case FormFieldType.time:
        return Icons.access_time;
    }
  }
}

/// Dialog for creating or editing a single form field.
class _FieldEditorDialog extends StatefulWidget {
  const _FieldEditorDialog({
    required this.field,
    this.otherFields = const [],
  });
  final FormFieldDefinition field;

  /// Other fields in the same template — used to populate the visibility
  /// dependency picker. Only select-typed fields are eligible as sources.
  final List<FormFieldDefinition> otherFields;

  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _optionsController;
  late FormFieldType _type;
  late bool _isRequired;
  late List<TableColumnDef> _columns;

  // Visibility condition state. The model supports multiple dependencies
  // but the UI exposes one for now (covers ~all real cases).
  String? _dependsOnFieldId;
  late List<String> _allowedValues;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.field.label);
    _descriptionController =
        TextEditingController(text: widget.field.description ?? '');
    _optionsController =
        TextEditingController(text: widget.field.options?.join('\n') ?? '');
    _type = widget.field.type;
    _isRequired = widget.field.isRequired;
    _columns = List<TableColumnDef>.from(widget.field.columns ?? []);
    // Initialize counter past any existing column keys to avoid collisions.
    for (final c in _columns) {
      final match = RegExp(r'^col_(\d+)$').firstMatch(c.key);
      if (match != null) {
        final n = int.parse(match.group(1)!);
        if (n >= _columnCounter) _columnCounter = n;
      }
    }
    final existingRules = widget.field.visibleWhen;
    if (existingRules != null && existingRules.isNotEmpty) {
      final entry = existingRules.entries.first;
      _dependsOnFieldId = entry.key;
      _allowedValues = List<String>.from(entry.value);
    } else {
      _allowedValues = [];
    }
  }

  List<FormFieldDefinition> get _conditionSources => widget.otherFields
      .where((f) => f.type == FormFieldType.select)
      .toList();

  @override
  void dispose() {
    _labelController.dispose();
    _descriptionController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  bool get _hasOptions =>
      _type == FormFieldType.select || _type == FormFieldType.multiSelect;

  bool get _isTable => _type == FormFieldType.table;

  bool get _isSection => _type == FormFieldType.section;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.field.label.isEmpty ? 'Add Field' : 'Edit Field'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StackedField(
                label: 'Field Type',
                child: DropdownButtonFormField<FormFieldType>(
                  value: _type,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: FormFieldType.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.displayName),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _type = v);
                  },
                ),
              ),
              const SizedBox(height: 16),
              StackedField(
                label: _isSection ? 'Section Title *' : 'Label *',
                child: TextField(
                  controller: _labelController,
                  decoration: InputDecoration(
                    hintText: _isSection
                        ? 'e.g. Customer & Site Information'
                        : 'e.g. Work completed?',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StackedField(
                label: _isSection ? 'Section description' : 'Helper text',
                child: TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    hintText: _isSection
                        ? 'Optional subtitle for this section'
                        : 'Optional instructions for the person filling this field',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (_hasOptions) ...[
                const SizedBox(height: 16),
                StackedField(
                  label: 'Options (one per line)',
                  child: TextField(
                    controller: _optionsController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Option 1\nOption 2\nOption 3',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
              if (_isTable) ...[
                const SizedBox(height: 16),
                _buildColumnsEditor(),
              ],
              if (!_isSection) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _isRequired,
                  onChanged: (v) =>
                      setState(() => _isRequired = v ?? false),
                  title: const Text('Required field'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 8),
                _buildVisibilityEditor(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_labelController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Label is required')),
              );
              return;
            }
            if (_isTable && _columns.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add at least one column')),
              );
              return;
            }
            final options = _hasOptions
                ? _optionsController.text
                    .split('\n')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList()
                : null;
            final visibleWhen =
                (_dependsOnFieldId != null && _allowedValues.isNotEmpty)
                    ? {_dependsOnFieldId!: List<String>.from(_allowedValues)}
                    : null;
            Navigator.pop(
              context,
              FormFieldDefinition(
                id: widget.field.id,
                order: widget.field.order,
                defaultValue: widget.field.defaultValue,
                type: _type,
                label: _labelController.text.trim(),
                description: _descriptionController.text.trim().isEmpty
                    ? null
                    : _descriptionController.text.trim(),
                isRequired: _isSection ? false : _isRequired,
                options: options,
                columns: _isTable ? _columns : null,
                visibleWhen: visibleWhen,
              ),
            );
          },
          child: const Text('Save Field'),
        ),
      ],
    );
  }

  Widget _buildVisibilityEditor() {
    final sources = _conditionSources;
    final hasCondition = _dependsOnFieldId != null;

    if (sources.isEmpty && !hasCondition) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          'Conditional visibility needs at least one dropdown field elsewhere in this template.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      );
    }

    final source = hasCondition
        ? sources.where((f) => f.id == _dependsOnFieldId).firstOrNull
        : null;
    final options = source?.options ?? const <String>[];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visibility',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _dependsOnFieldId,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
            ),
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Always show'),
              ),
              for (final f in sources)
                DropdownMenuItem<String?>(
                  value: f.id,
                  child: Text(
                    'Show only when "${f.label.isEmpty ? f.id : f.label}" is…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _dependsOnFieldId = v;
                _allowedValues = [];
              });
            },
          ),
          if (hasCondition) ...[
            const SizedBox(height: 8),
            if (options.isEmpty)
              Text(
                source == null
                    ? 'The selected source field no longer exists. Choose another or set to "Always show".'
                    : 'Source field has no options defined.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              )
            else ...[
              Text(
                'Allowed values',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: options.map((opt) {
                  final selected = _allowedValues.contains(opt);
                  return FilterChip(
                    label: Text(opt, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          _allowedValues.add(opt);
                        } else {
                          _allowedValues.remove(opt);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              if (_allowedValues.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Select at least one value, or visibility rule will be cleared on save.',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildColumnsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Table Columns',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
            const Spacer(),
            TextButton.icon(
              onPressed: _addColumn,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Column'),
            ),
          ],
        ),
        if (_columns.isEmpty)
          Text('No columns defined.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary))
        else
          ...List.generate(_columns.length, (i) {
            final col = _columns[i];
            return Container(
              key: ValueKey(col.key),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          initialValue: col.label,
                          decoration: const InputDecoration(
                            hintText: 'Column label',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) {
                            _columns[i] = TableColumnDef(
                              key: col.key,
                              label: v,
                              type: col.type,
                              options: col.options,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: col.type,
                          isDense: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                          ),
                          style: const TextStyle(fontSize: 12),
                          items: const [
                            DropdownMenuItem(
                                value: 'text', child: Text('Text')),
                            DropdownMenuItem(
                                value: 'number', child: Text('Number')),
                            DropdownMenuItem(
                                value: 'time', child: Text('Time')),
                            DropdownMenuItem(
                                value: 'select', child: Text('Select')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _columns[i] = TableColumnDef(
                                key: col.key,
                                label: col.label,
                                type: v,
                                options: col.options,
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () =>
                            setState(() => _columns.removeAt(i)),
                        visualDensity: VisualDensity.compact,
                        color: AppColors.textTertiary,
                        tooltip: 'Remove column',
                      ),
                    ],
                  ),
                  if (col.type == 'select') ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: col.options?.join('\n') ?? '',
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Options (one per line)',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                      ),
                      style: const TextStyle(fontSize: 11),
                      onChanged: (v) {
                        final opts = v
                            .split('\n')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        _columns[i] = TableColumnDef(
                          key: col.key,
                          label: col.label,
                          type: col.type,
                          options: opts.isEmpty ? null : opts,
                        );
                      },
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  int _columnCounter = 0;

  void _addColumn() {
    // Use a counter that never resets to avoid duplicate keys after deletions.
    _columnCounter++;
    while (_columns.any((c) => c.key == 'col_$_columnCounter')) {
      _columnCounter++;
    }
    setState(() {
      _columns.add(
          TableColumnDef(key: 'col_$_columnCounter', label: '', type: 'text'));
    });
  }
}
