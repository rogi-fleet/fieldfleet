import 'package:flutter/material.dart';

class EntityActionItem {
  final String value;
  final String label;
  final IconData icon;
  final bool isDestructive;

  const EntityActionItem({
    required this.value,
    required this.label,
    required this.icon,
    this.isDestructive = false,
  });
}
