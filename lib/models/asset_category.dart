import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Soft enum for asset categories. The DB column is TEXT so the list can
/// grow without a migration; this file owns the canonical metadata
/// (label, icon, accent color) used to render and filter.
enum AssetCategory {
  powerTool('power_tool', 'Power tool', Icons.electric_bolt, AppColors.info),
  handTool('hand_tool', 'Hand tool', Icons.handyman_outlined, AppColors.warning),
  heavyEquipment(
    'heavy_equipment',
    'Heavy equipment',
    Icons.precision_manufacturing_outlined,
    AppColors.warningDark,
  ),
  ladder('ladder', 'Ladder', Icons.height, AppColors.error),
  safety('safety', 'Safety gear', Icons.health_and_safety_outlined, AppColors.success),
  electronics('electronics', 'Electronics', Icons.devices_outlined, AppColors.primary),
  furniture('furniture', 'Furniture', Icons.chair_outlined, AppColors.textSecondary),
  vehicleAttachment(
    'vehicle_attachment',
    'Vehicle attachment',
    Icons.rv_hookup_outlined,
    AppColors.info,
  ),
  other('other', 'Other', Icons.category_outlined, AppColors.textTertiary);

  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const AssetCategory(this.id, this.label, this.icon, this.color);

  /// Look up by id; falls back to [AssetCategory.other] when the stored
  /// value is unknown (forward compatibility — DB can carry future ids
  /// the client doesn't recognise yet).
  static AssetCategory fromId(String? id) {
    if (id == null || id.isEmpty) return AssetCategory.other;
    return AssetCategory.values.firstWhere(
      (c) => c.id == id,
      orElse: () => AssetCategory.other,
    );
  }

  /// Fallback lookup by display name. Used when the workspace's
  /// configured categories haven't loaded yet, or when an asset
  /// references a category name that no longer exists in the
  /// workspace's [asset_categories] table — we still want to render
  /// *something* sensible instead of a blank tile.
  static AssetCategory fromName(String? name) {
    if (name == null || name.isEmpty) return AssetCategory.other;
    final normalized = name.toLowerCase();
    return AssetCategory.values.firstWhere(
      (c) => c.label.toLowerCase() == normalized,
      orElse: () => AssetCategory.other,
    );
  }
}
