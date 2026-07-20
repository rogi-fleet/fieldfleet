/// Dashboard widget configuration model (v2).
///
/// Stored as the `dashboard_widget_config` JSONB key in user preferences.
/// Migrates transparently from v1 (missing fields get defaults).
class DashboardWidgetConfig {
  static const int currentVersion = 2;

  final int version;
  final List<String> order;
  final List<String> hidden;
  final Map<String, String> sizes; // widget id → "half" | "full"
  final List<String> collapsed;
  final DateTime? updatedAt;

  const DashboardWidgetConfig({
    this.version = currentVersion,
    this.order = const [],
    this.hidden = const [],
    this.sizes = const {},
    this.collapsed = const [],
    this.updatedAt,
  });

  /// Creates a config from JSON, migrating v1 data automatically.
  factory DashboardWidgetConfig.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return const DashboardWidgetConfig();

    return DashboardWidgetConfig(
      version: currentVersion,
      order: (json['order'] is List)
          ? List<String>.from(json['order'] as List)
          : const [],
      hidden: (json['hidden'] is List)
          ? List<String>.from(json['hidden'] as List)
          : const [],
      sizes: (json['sizes'] is Map)
          ? Map<String, String>.from(json['sizes'] as Map)
          : const {},
      collapsed: (json['collapsed'] is List)
          ? List<String>.from(json['collapsed'] as List)
          : const [],
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'order': order,
        'hidden': hidden,
        'sizes': sizes,
        'collapsed': collapsed,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  /// Returns the size for a widget, defaulting to "half".
  String sizeOf(String widgetId) => sizes[widgetId] ?? 'half';

  bool isCollapsed(String widgetId) => collapsed.contains(widgetId);

  bool isHidden(String widgetId) => hidden.contains(widgetId);

  DashboardWidgetConfig copyWith({
    List<String>? order,
    List<String>? hidden,
    Map<String, String>? sizes,
    List<String>? collapsed,
  }) {
    return DashboardWidgetConfig(
      version: currentVersion,
      order: order ?? this.order,
      hidden: hidden ?? this.hidden,
      sizes: sizes ?? this.sizes,
      collapsed: collapsed ?? this.collapsed,
      updatedAt: DateTime.now(),
    );
  }
}
