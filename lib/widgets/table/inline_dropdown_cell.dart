import 'package:flutter/material.dart';
import '../../theme/app_radius.dart';

/// A generic inline dropdown cell for table rows.
class InlineDropdownCell<T> extends StatelessWidget {
  const InlineDropdownCell({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemBuilder,
    required this.labelBuilder,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final Widget Function(T)? itemBuilder;
  final String Function(T) labelBuilder;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        borderRadius: AppRadius.cardRadius,
        value: value,
        isDense: true,
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: itemBuilder != null
                    ? itemBuilder!(item)
                    : Text(labelBuilder(item)),
              ),
            )
            .toList(growable: false),
        onChanged: (next) {
          if (next != null && next != value) {
            onChanged(next);
          }
        },
      ),
    );
  }
}
