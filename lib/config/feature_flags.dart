/// Compile-time feature flags for in-progress features.
///
/// Flip a flag to true to enable the feature locally. Once a feature graduates,
/// remove its flag and the gated branches.
class FeatureFlags {
  FeatureFlags._();

  /// New 12-column responsive grid for the dashboard / project widget system
  /// with drag-to-reposition and corner-handle resize. Set false to fall back
  /// to the legacy arrow-button grid.
  static const bool dashboardGridV3 = true;
}
