import 'package:flutter/material.dart';

import '../models/custom_field_definition.dart';
import '../models/custom_field_type.dart';
import '../theme/theme.dart';
import '../utils/numeric_input.dart';

/// Renders the workspace's custom-field definitions as form inputs that
/// embed inside a parent [Form]. Designed for the project create/edit
/// screen — does NOT own its own `_formKey` or submit button.
///
/// Behavior:
///   * Active definitions render grouped by [CustomFieldDefinition.fieldGroup]
///     into collapsible subsections. Definitions with no group fall under
///     "Other".
///   * Archived definitions render only when an existing project has a
///     value for them; they appear read-only with an "Archived" chip.
///   * Returns `SizedBox.shrink()` when there is nothing to render so the
///     section disappears cleanly for workspaces that don't use the feature.
///
/// V1 deliberately does NOT support file/photo upload UI — those types
/// render as a stub with a "(file upload coming soon)" hint. The values
/// can still flow through if pre-populated from import/automation. Full
/// upload UX lands when the storage-attached field types are ready.
class CustomFieldsSection extends StatefulWidget {
  /// Active definitions to render as inputs.
  final List<CustomFieldDefinition> activeDefinitions;

  /// All definitions (including archived). Used to surface read-only
  /// values for archived defs that still have data on this project.
  final List<CustomFieldDefinition> allDefinitions;

  /// Initial values keyed by [CustomFieldDefinition.key]. Mutated in
  /// place via [onChanged] so the parent can read the final state at
  /// save time without holding a controller reference.
  final Map<String, dynamic> values;

  final void Function(Map<String, dynamic> values) onChanged;

  const CustomFieldsSection({
    super.key,
    required this.activeDefinitions,
    required this.allDefinitions,
    required this.values,
    required this.onChanged,
  });

  @override
  State<CustomFieldsSection> createState() => _CustomFieldsSectionState();
}

class _CustomFieldsSectionState extends State<CustomFieldsSection> {
  late Map<String, dynamic> _values;
  final Map<String, TextEditingController> _textControllers = {};

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.values);
    _seedControllers();
  }

  @override
  void didUpdateWidget(covariant CustomFieldsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The set of definitions can change after async load; ensure every
    // text-backed field has a controller.
    _seedControllers();
  }

  void _seedControllers() {
    for (final def in widget.activeDefinitions) {
      if (!_isTextBacked(def.type)) continue;
      _textControllers.putIfAbsent(
        def.key,
        () => TextEditingController(text: _values[def.key]?.toString() ?? ''),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isTextBacked(CustomFieldType type) {
    return type == CustomFieldType.text ||
        type == CustomFieldType.longText ||
        type == CustomFieldType.number;
  }

  void _setValue(String key, dynamic value) {
    setState(() {
      if (value == null ||
          (value is String && value.isEmpty) ||
          (value is List && value.isEmpty)) {
        _values.remove(key);
      } else {
        _values[key] = value;
      }
    });
    widget.onChanged(_values);
  }

  /// Active defs that are flagged `showInForm = true`, grouped by
  /// `fieldGroup`. Maintains insertion order; the implicit `null` group
  /// renders last as "Other".
  Map<String?, List<CustomFieldDefinition>> _activeByGroup() {
    final out = <String?, List<CustomFieldDefinition>>{};
    for (final d in widget.activeDefinitions) {
      if (!d.showInForm) continue;
      out.putIfAbsent(d.fieldGroup, () => []).add(d);
    }
    if (out.containsKey(null)) {
      final other = out.remove(null)!;
      out[null] = other;
    }
    return out;
  }

  /// Archived defs that have a non-null value on this project — render
  /// read-only so the data isn't silently dropped from the UI.
  List<CustomFieldDefinition> _archivedWithValue() {
    final activeKeys = widget.activeDefinitions.map((d) => d.key).toSet();
    return widget.allDefinitions
        .where((d) =>
            d.isArchived &&
            !activeKeys.contains(d.key) &&
            _values[d.key] != null)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _activeByGroup();
    final archived = _archivedWithValue();

    if (groups.isEmpty && archived.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
          child: Text(
            'Custom Fields',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        for (final entry in groups.entries)
          _buildGroup(entry.key, entry.value),
        if (archived.isNotEmpty) _buildArchivedBlock(archived),
      ],
    );
  }

  Widget _buildGroup(String? groupName, List<CustomFieldDefinition> defs) {
    final title = groupName ?? 'Other';
    // Single-group case (or only "Other") doesn't need the expansion
    // chrome — render fields flat.
    final useExpansion =
        groupName != null || _activeByGroup().keys.length > 1;

    final fields = Column(
      children: [
        for (final def in defs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildField(def),
          ),
      ],
    );

    if (!useExpansion) return fields;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [fields],
      ),
    );
  }

  Widget _buildArchivedBlock(List<CustomFieldDefinition> defs) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: AppColors.surfaceAlt,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Row(
          children: [
            const Text(
              'Archived fields with values',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                '${defs.length}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final d in defs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildArchivedRow(d),
            ),
        ],
      ),
    );
  }

  Widget _buildArchivedRow(CustomFieldDefinition def) {
    final raw = _values[def.key];
    final display = raw == null
        ? '—'
        : raw is List
            ? raw.join(', ')
            : raw.toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              def.label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            display,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.textTertiary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: const Text(
            'Archived',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Per-type renderers
  // ---------------------------------------------------------------------------

  Widget _buildField(CustomFieldDefinition def) {
    switch (def.type) {
      case CustomFieldType.text:
        return _buildTextField(def, maxLines: 1);
      case CustomFieldType.longText:
        return _buildTextField(def, maxLines: 4);
      case CustomFieldType.number:
        return _buildNumberField(def);
      case CustomFieldType.date:
        return _buildDateField(def);
      case CustomFieldType.picklist:
        return _buildPicklistField(def);
      case CustomFieldType.multiSelect:
        return _buildMultiSelectField(def);
      case CustomFieldType.checkbox:
        return _buildCheckboxField(def);
      case CustomFieldType.file:
      case CustomFieldType.photo:
        return _buildUploadStub(def);
    }
  }

  String _labelText(CustomFieldDefinition def) =>
      def.isRequired ? '${def.label} *' : def.label;

  String? _requiredValidator(CustomFieldDefinition def, dynamic value) {
    if (!def.isRequired) return null;
    if (value == null) return 'Required';
    if (value is String && value.trim().isEmpty) return 'Required';
    if (value is List && value.isEmpty) return 'Required';
    return null;
  }

  Widget _buildTextField(CustomFieldDefinition def, {required int maxLines}) {
    final controller = _textControllers[def.key]!;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: _labelText(def),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      maxLines: maxLines,
      minLines: maxLines > 1 ? 2 : 1,
      validator: (v) => _requiredValidator(def, v),
      onChanged: (v) => _setValue(def.key, v),
    );
  }

  Widget _buildNumberField(CustomFieldDefinition def) {
    final controller = _textControllers[def.key]!;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: _labelText(def),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: NumericInput.signedKeyboard,
      inputFormatters: NumericInput.signedDecimal,
      validator: (v) {
        final required = _requiredValidator(def, v);
        if (required != null) return required;
        if (v == null || v.trim().isEmpty) return null;
        if (num.tryParse(v.trim()) == null) return 'Must be a number';
        return null;
      },
      onChanged: (v) {
        // Persist the parsed number so the jsonb shape matches what the
        // server-side validation trigger expects (jsonb_typeof = 'number').
        final trimmed = v.trim();
        if (trimmed.isEmpty) {
          _setValue(def.key, null);
        } else {
          final parsed = num.tryParse(trimmed);
          // Keep the raw string when un-parseable so the validator can
          // surface its error on submit; null would suppress it.
          _setValue(def.key, parsed ?? trimmed);
        }
      },
    );
  }

  Widget _buildDateField(CustomFieldDefinition def) {
    final raw = _values[def.key] as String?;
    final display = raw == null || raw.isEmpty ? '' : raw;
    return FormField<String>(
      initialValue: raw,
      validator: (_) =>
          _requiredValidator(def, _values[def.key]),
      builder: (state) => InkWell(
        onTap: () async {
          final initial = DateTime.tryParse(raw ?? '') ?? DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(1900),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            // ISO 8601 date — matches the server-side validation
            // trigger's `jsonb_typeof = 'string'` expectation for the
            // 'date' type.
            final iso =
                '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
            _setValue(def.key, iso);
            state.didChange(iso);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: _labelText(def),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
            errorText: state.errorText,
          ),
          child: Text(
            display.isEmpty ? 'Select a date' : display,
            style: TextStyle(
              color: display.isEmpty ? AppColors.textTertiary : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPicklistField(CustomFieldDefinition def) {
    final current = _values[def.key] as String?;
    final items = def.optionItems;
    return DropdownButtonFormField<String>(
      initialValue: items.contains(current) ? current : null,
      decoration: InputDecoration(
        labelText: _labelText(def),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final opt in items)
          DropdownMenuItem(value: opt, child: Text(opt)),
      ],
      validator: (v) => _requiredValidator(def, v),
      onChanged: (v) => _setValue(def.key, v),
    );
  }

  Widget _buildMultiSelectField(CustomFieldDefinition def) {
    final current = (_values[def.key] as List?)?.cast<String>() ?? <String>[];
    final items = def.optionItems;
    return FormField<List<String>>(
      initialValue: current,
      validator: (_) => _requiredValidator(def, _values[def.key]),
      builder: (state) => InputDecorator(
        decoration: InputDecoration(
          labelText: _labelText(def),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          errorText: state.errorText,
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final opt in items)
              FilterChip(
                label: Text(opt),
                selected: current.contains(opt),
                onSelected: (selected) {
                  final next = List<String>.from(current);
                  if (selected) {
                    next.add(opt);
                  } else {
                    next.remove(opt);
                  }
                  _setValue(def.key, next);
                  state.didChange(next);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxField(CustomFieldDefinition def) {
    final value = _values[def.key] as bool? ?? false;
    return InkWell(
      onTap: () => _setValue(def.key, !value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => _setValue(def.key, v ?? false),
            ),
            Expanded(child: Text(_labelText(def))),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadStub(CustomFieldDefinition def) {
    final raw = _values[def.key] as String?;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: _labelText(def),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Row(
        children: [
          Icon(
            def.type == CustomFieldType.photo
                ? Icons.photo_outlined
                : Icons.attach_file,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              raw ?? 'File upload UI coming soon',
              style: TextStyle(
                color: raw == null
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
                fontStyle: raw == null ? FontStyle.italic : FontStyle.normal,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
