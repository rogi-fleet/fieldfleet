import 'package:flutter/material.dart';

/// A workspace-configurable asset category.
///
/// Lives in the `asset_categories` table. The hardcoded [AssetCategory]
/// enum (lib/models/asset_category.dart) now serves only as a fallback
/// for icon/color when a workspace doesn't have its own category yet —
/// new workspaces are seeded by trigger so this rarely fires in
/// practice.
class AssetCategoryConfig {
  final String id;
  final String workspaceId;
  final String name;
  final String color; // Hex like '#2196F3'
  final String iconName; // Material icon identifier
  final int sortOrder;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssetCategoryConfig({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.color,
    required this.iconName,
    required this.sortOrder,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AssetCategoryConfig.fromJson(Map<String, dynamic> json) {
    return AssetCategoryConfig(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#9E9E9E',
      iconName: json['icon'] as String? ?? 'category_outlined',
      sortOrder: json['sort_order'] as int? ?? 0,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Resolved [Color] for rendering. Falls back to gray for malformed
  /// hex so the UI never crashes on bad data.
  Color get colorValue {
    final hex = color.replaceFirst('#', '').padLeft(6, '0');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return const Color(0xFF9E9E9E);
    return Color(0xFF000000 | parsed);
  }

  /// Resolve [iconName] to an [IconData]. Unknown names fall back to a
  /// generic category icon so user-typed garbage never throws.
  IconData get icon => _iconLookup[iconName] ?? Icons.category_outlined;

  AssetCategoryConfig copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? color,
    String? iconName,
    int? sortOrder,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AssetCategoryConfig(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      color: color ?? this.color,
      iconName: iconName ?? this.iconName,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Curated icon name → [IconData] map. Keep aligned with the seed list
/// in `seed_asset_categories_for_workspace`. Adding a new icon here
/// also makes it available in the settings picker.
const Map<String, IconData> _iconLookup = {
  'category_outlined': Icons.category_outlined,
  'electric_bolt': Icons.electric_bolt,
  'handyman_outlined': Icons.handyman_outlined,
  'precision_manufacturing_outlined': Icons.precision_manufacturing_outlined,
  'height': Icons.height,
  'health_and_safety_outlined': Icons.health_and_safety_outlined,
  'devices_outlined': Icons.devices_outlined,
  'chair_outlined': Icons.chair_outlined,
  'rv_hookup_outlined': Icons.rv_hookup_outlined,
  'construction_outlined': Icons.construction_outlined,
  'inventory_2_outlined': Icons.inventory_2_outlined,
  'build_outlined': Icons.build_outlined,
  'agriculture_outlined': Icons.agriculture_outlined,
  'hardware_outlined': Icons.hardware_outlined,
  'plumbing_outlined': Icons.plumbing_outlined,
  'electrical_services_outlined': Icons.electrical_services_outlined,
  'cleaning_services_outlined': Icons.cleaning_services_outlined,
  'water_drop_outlined': Icons.water_drop_outlined,
  'local_fire_department_outlined': Icons.local_fire_department_outlined,
  'computer_outlined': Icons.computer_outlined,
};

/// Picker list — every entry is a valid `iconName` for the settings UI.
List<MapEntry<String, IconData>> assetCategoryIconPicker() =>
    _iconLookup.entries.toList();
