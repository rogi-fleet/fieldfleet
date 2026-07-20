import 'package:flutter/material.dart';

/// A centered checkbox cell for use in table rows.
class InlineCheckboxCell extends StatelessWidget {
  const InlineCheckboxCell({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Compact density + shrunken tap target so the checkbox fits cleanly
    // inside dense table rows (e.g. budget grid at 36px). Without this,
    // the default Checkbox reserves ~48px of vertical tap area and forces
    // the row taller than intended.
    return Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: Checkbox(
          value: value,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
