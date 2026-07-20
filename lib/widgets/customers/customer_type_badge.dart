import 'package:flutter/material.dart';
import '../../models/customer_type_config.dart';
import '../../theme/theme.dart';

class CustomerTypeBadge extends StatelessWidget {
  final String customerType;
  final String? colorHex;
  final bool small;

  /// Global color cache: type name → hex color string.
  /// Populated by any screen that loads [CustomerTypeConfig] from the DB.
  static final Map<String, String> _colorCache = {};

  /// Call this whenever customer/vendor types are loaded from the database
  /// so that badges across the app can pick up the configured colors.
  static void updateColorCache(List<CustomerTypeConfig> types) {
    for (final t in types) {
      _colorCache[t.name] = t.color;
    }
  }

  const CustomerTypeBadge({
    super.key,
    required this.customerType,
    this.colorHex,
    this.small = false,
  });

  Color get _badgeColor {
    // 1. Explicit color passed by caller
    if (colorHex != null) return _parseHexColor(colorHex!);
    // 2. Color from global cache (populated by type management / form screens)
    final cached = _colorCache[customerType];
    if (cached != null) return _parseHexColor(cached);
    // 3. Hardcoded fallback for well-known types
    switch (customerType.toLowerCase()) {
      case 'residential':
        return AppColors.success;
      case 'commercial':
        return AppColors.info;
      case 'government':
        return AppColors.messageAccent;
      default:
        return AppColors.textSecondary;
    }
  }

  static Color _parseHexColor(String hex) {
    try {
      String colorStr = hex.replaceAll('#', '');
      if (colorStr.length == 3) {
        colorStr = colorStr.split('').map((c) => c + c).join();
      }
      if (colorStr.length == 6) {
        return Color(int.parse('FF$colorStr', radix: 16));
      }
      if (colorStr.length == 8) {
        return Color(int.parse(colorStr, radix: 16));
      }
      return AppColors.textSecondary;
    } catch (_) {
      return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: _badgeColor.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: _badgeColor, width: 1),
      ),
      child: Text(
        customerType,
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
