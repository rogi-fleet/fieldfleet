import 'floor_plan_scan_result.dart' show ScanSourceEngine;

/// What the native plugin can do on this device. Reported by the
/// `getCapabilities` MethodChannel call before the scan view is mounted.
class RoomScanCapabilities {
  /// `null` means the plugin reported no engine — show the unsupported screen.
  final ScanSourceEngine? engine;

  /// Whether the engine supports a single capture session that walks through
  /// multiple rooms (RoomPlan only on day one).
  final bool supportsMultiRoom;

  /// Whether a LiDAR / Depth sensor was detected. Surfaces in UI ("LiDAR
  /// scan" vs "tap-measured plan").
  final bool hasDepthSensor;

  /// Human-readable reason when [engine] is null. e.g. "ARCore not installed"
  /// or "iOS 16 required".
  final String? unsupportedReason;

  const RoomScanCapabilities({
    required this.engine,
    this.supportsMultiRoom = false,
    this.hasDepthSensor = false,
    this.unsupportedReason,
  });

  bool get isSupported => engine != null;

  factory RoomScanCapabilities.unsupported(String reason) =>
      RoomScanCapabilities(engine: null, unsupportedReason: reason);

  factory RoomScanCapabilities.fromMap(Map<dynamic, dynamic> raw) {
    final engineName = raw['engine'] as String?;
    return RoomScanCapabilities(
      engine: engineName == null || engineName == 'none'
          ? null
          : ScanSourceEngine.values.firstWhere(
              (e) => e.name == engineName,
              orElse: () => ScanSourceEngine.arKitPlaneTap,
            ),
      supportsMultiRoom: raw['supportsMultiRoom'] as bool? ?? false,
      hasDepthSensor: raw['hasDepthSensor'] as bool? ?? false,
      unsupportedReason: raw['unsupportedReason'] as String?,
    );
  }
}
