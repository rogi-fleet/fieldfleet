import 'package:flutter/material.dart';

/// Quick Action configuration model.
class QuickActionConfig {
  final List<QuickAction> actions;
  final DateTime? updatedAt;

  const QuickActionConfig({
    required this.actions,
    this.updatedAt,
  });

  factory QuickActionConfig.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return const QuickActionConfig(actions: []);

    return QuickActionConfig(
      actions: (json['actions'] as List? ?? [])
          .map((action) => QuickAction.fromJson(action as Map<String, dynamic>))
          .toList(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'actions': actions.map((action) => action.toJson()).toList(),
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  QuickActionConfig copyWith({
    List<QuickAction>? actions,
    DateTime? updatedAt,
  }) {
    return QuickActionConfig(
      actions: actions ?? this.actions,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// Represents a single quick action.
class QuickAction {
  final String label;
  final IconData icon;
  final String route;
  final bool showPopup;

  const QuickAction({
    required this.label,
    required this.icon,
    required this.route,
    this.showPopup = false,
  });

  factory QuickAction.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as String;
    final label = json['label'] as String;
    return QuickAction(
      label: label,
      icon: _iconFromJson(
        json['icon'],
        route: route,
        label: label,
      ),
      route: route,
      showPopup: json['showPopup'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'icon': _iconKeyFor(icon),
        'route': route,
        'showPopup': showPopup,
      };
}

IconData _iconFromJson(
  dynamic rawIcon, {
  required String route,
  required String label,
}) {
  if (rawIcon is String) {
    final mapped = _iconByKey[rawIcon];
    if (mapped != null) return mapped;
  }

  if (rawIcon is int) {
    final mapped = _legacyIconByCodePoint[rawIcon];
    if (mapped != null) return mapped;
  }

  return _defaultIconFor(route: route, label: label);
}

String _iconKeyFor(IconData icon) {
  return _iconKeyByCodePoint[icon.codePoint] ?? 'add_business';
}

IconData _defaultIconFor({
  required String route,
  required String label,
}) {
  if (route == '/projects/new' || label == 'New Project') return Icons.add_business;
  if (route == '/tasks' || label == 'New Task') return Icons.add_task;
  if (route == '/messages/new' || label == 'New Message') return Icons.chat;
  if (route == '/documents/create' || label == 'New Document') return Icons.note_add;
  return Icons.add_business;
}

const Map<String, IconData> _iconByKey = {
  'add_business': Icons.add_business,
  'add_task': Icons.add_task,
  'chat': Icons.chat,
  'note_add': Icons.note_add,
};

const Map<int, IconData> _legacyIconByCodePoint = {
  0xe729: Icons.add_business,
  0xf23a: Icons.add_task,
  0xe0b7: Icons.chat,
  0xe89c: Icons.note_add,
};

const Map<int, String> _iconKeyByCodePoint = {
  0xe729: 'add_business',
  0xf23a: 'add_task',
  0xe0b7: 'chat',
  0xe89c: 'note_add',
};
