import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared compact dropdown control used in table/list toolbars.
class TableDropdownControl<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hintText;
  final double? width;
  final double height;

  const TableDropdownControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText,
    this.width,
    this.height = 42,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);

    final control = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: chrome.divider),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          borderRadius: AppRadius.cardRadius,
          value: value,
          hint: hintText == null ? null : Text(hintText!),
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, size: 18, color: chrome.text),
          dropdownColor: chrome.surface,
          style: TextStyle(fontSize: 13, color: chrome.textActive),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );

    if (width == null) return control;
    return SizedBox(width: width, child: control);
  }
}
