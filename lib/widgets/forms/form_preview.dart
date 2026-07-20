import 'package:flutter/material.dart';
import '../../models/form_field_definition.dart';
import '../../theme/theme.dart';
import 'form_field_preview.dart';

class FormPreview extends StatelessWidget {
  final List<FormFieldDefinition> fields;

  // readOnly kept for API compatibility — FormFieldPreview is always static.
  // ignore: avoid_unused_constructor_parameters
  const FormPreview({
    super.key,
    required this.fields,
    bool readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.drag_indicator,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Drag fields here to build your form',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields.map((field) => _buildField(context, field)).toList(),
    );
  }

  Widget _buildField(BuildContext context, FormFieldDefinition field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                field.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (field.isRequired)
                const Text(
                  ' *',
                  style: TextStyle(color: AppColors.error),
                ),
            ],
          ),
          if (field.description != null && field.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              field.description!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          FormFieldPreview(field: field, dense: false),
        ],
      ),
    );
  }

}
