import 'package:flutter/material.dart';
import '../../models/property_status.dart';

/// A status badge widget for displaying property status.
class PropertyStatusBadge extends StatelessWidget {
  final PropertyStatus status;
  final bool compact;

  const PropertyStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: compact ? null : Icon(status.icon, size: 16, color: status.color),
      label: Text(status.displayName),
      backgroundColor: status.color.withAlpha(25),
      labelStyle: TextStyle(
        color: status.color,
        fontWeight: FontWeight.w500,
        fontSize: compact ? 11 : 12,
      ),
      side: BorderSide(color: status.color.withAlpha(75)),
      padding: compact ? EdgeInsets.zero : null,
      visualDensity: compact ? VisualDensity.compact : null,
    );
  }
}
