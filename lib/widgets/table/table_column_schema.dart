import 'package:flutter/material.dart';

class TableColumnSchema {
  final String id;
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final double defaultWidth;
  final double minWidth;
  final double maxWidth;
  final TextAlign align;
  final bool resizable;
  final bool borderLeft;

  const TableColumnSchema({
    required this.id,
    this.label,
    this.icon,
    this.tooltip,
    required this.defaultWidth,
    this.minWidth = 40,
    this.maxWidth = 500,
    this.align = TextAlign.left,
    this.resizable = true,
    this.borderLeft = false,
  });
}

class TableColumnResize {
  final String columnId;
  final double width;

  const TableColumnResize({required this.columnId, required this.width});
}
