import 'package:flutter/material.dart';
import '../../models/form_field_definition.dart';
import '../../models/form_field_type.dart';
import '../../theme/theme.dart';

/// A static, non-interactive preview of a single form field input.
/// Wraps the rendered widget in [AbsorbPointer] so it can be dropped into
/// either the builder canvas or the form-detail read-only preview.
class FormFieldPreview extends StatelessWidget {
  final FormFieldDefinition field;

  /// When true (default) renders with compact/dense padding suitable for the
  /// builder canvas. When false, uses slightly more padding for display views.
  final bool dense;

  const FormFieldPreview({
    super.key,
    required this.field,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(child: _buildInput());
  }

  Widget _buildInput() {
    switch (field.type) {
      case FormFieldType.text:
      case FormFieldType.email:
      case FormFieldType.phone:
        return TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: _hint(),
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? 10 : 12,
            ),
            isDense: dense,
          ),
        );

      case FormFieldType.textarea:
        return TextField(
          enabled: false,
          maxLines: dense ? 3 : 4,
          decoration: InputDecoration(
            hintText: 'Enter your response...',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.all(AppSpacing.md),
            isDense: dense,
          ),
        );

      case FormFieldType.number:
        return TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: 'Enter a number',
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? 10 : 12,
            ),
            isDense: dense,
          ),
          keyboardType: TextInputType.number,
        );

      case FormFieldType.date:
        return TextField(
          enabled: false,
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'Select a date',
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? 10 : 12,
            ),
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
            isDense: dense,
          ),
        );

      case FormFieldType.datetime:
        return TextField(
          enabled: false,
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'Select date and time',
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? 10 : 12,
            ),
            suffixIcon: const Icon(Icons.schedule, size: 18),
            isDense: dense,
          ),
        );

      case FormFieldType.select:
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? 10 : 12,
            ),
            isDense: dense,
          ),
          hint: const Text('Select an option'),
          items: (field.options ?? [])
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: null,
        );

      case FormFieldType.multiSelect:
        final options = field.options ?? [];
        if (options.isEmpty) {
          return Text(
            'No options added yet',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          );
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options
              .map(
                (o) => FilterChip(
                  label: Text(o),
                  selected: false,
                  onSelected: null,
                ),
              )
              .toList(),
        );

      case FormFieldType.checkbox:
        return Row(
          children: [
            Checkbox(value: false, onChanged: null),
            const SizedBox(width: 8),
            const Text('Yes'),
          ],
        );

      case FormFieldType.file:
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Choose File'),
        );

      case FormFieldType.photo:
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.photo_camera, size: 18),
          label: const Text('Add Photo'),
        );

      case FormFieldType.address:
        return TextField(
          enabled: false,
          maxLines: dense ? 2 : 3,
          decoration: InputDecoration(
            hintText: 'Enter address...',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.all(AppSpacing.md),
            isDense: dense,
          ),
        );

      case FormFieldType.inspectionItem:
        return SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'pass',
              label: Text('Pass'),
              icon: Icon(Icons.check_circle_outline),
            ),
            ButtonSegment(
              value: 'fail',
              label: Text('Fail'),
              icon: Icon(Icons.cancel_outlined),
            ),
            ButtonSegment(
              value: 'na',
              label: Text('N/A'),
              icon: Icon(Icons.remove_circle_outline),
            ),
          ],
          selected: const {},
          emptySelectionAllowed: true,
          onSelectionChanged: null,
        );

      case FormFieldType.rating:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            5,
            (_) => const Icon(
              Icons.star_border,
              color: AppColors.textTertiary,
            ),
          ),
        );

      case FormFieldType.section:
        return const Divider();

      case FormFieldType.table:
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('Table'),
        );

      case FormFieldType.time:
        return TextField(
          enabled: false,
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'Select time',
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? 10 : 12,
            ),
            suffixIcon: const Icon(Icons.access_time, size: 18),
            isDense: dense,
          ),
        );
    }
  }

  String _hint() => switch (field.type) {
        FormFieldType.email => 'email@example.com',
        FormFieldType.phone => '(555) 123-4567',
        _ => 'Enter your response',
      };
}
