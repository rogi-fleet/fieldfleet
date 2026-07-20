/// Transport-layer payload emitted by the native room-scan engine.
///
/// This is intentionally narrow: it is *not* the editor's `Scene`, and it is
/// *not* the legacy `pro_room_scanner` `Plan`. Native code on iOS and Android
/// produces this exact JSON shape; the Dart side runs it through
/// `ScanToScene` to produce a `Scene` for the editor.
///
/// All linear measurements are in **metres**. All angles are radians.
library;

enum ScanSourceEngine {
  /// iOS 16+ on a LiDAR device. Apple RoomPlan returns finished walls,
  /// doors, windows, and objects in one call.
  roomPlan,

  /// iOS ARKit plane detection + manual corner taps. Used on non-LiDAR
  /// iPhones / iOS 13-15.
  arKitPlaneTap,

  /// Android ARCore plane detection + Depth API hit-test.
  arCoreDepth,

  /// Android ARCore plane-only hit-test (no Depth API).
  arCorePlaneTap,
}

ScanSourceEngine _engineFromString(String s) =>
    ScanSourceEngine.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ScanSourceEngine.arKitPlaneTap,
    );

enum OpeningKind { door, window, opening }

OpeningKind _openingKindFromString(String s) => OpeningKind.values.firstWhere(
      (e) => e.name == s,
      orElse: () => OpeningKind.opening,
    );

enum ObjectCategory {
  bed,
  chair,
  sofa,
  table,
  storage,
  refrigerator,
  stove,
  sink,
  toilet,
  bathtub,
  oven,
  dishwasher,
  washer,
  fireplace,
  television,
  stairs,
  other,
}

ObjectCategory _objectCategoryFromString(String s) =>
    ObjectCategory.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ObjectCategory.other,
    );

/// A 2D vector in metres. Right-handed: +x right, +y up looking down at the
/// floor (so the scan world is a top-down view).
class Vec2 {
  final double x;
  final double y;
  const Vec2(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Vec2.fromJson(Map<String, dynamic> j) =>
      Vec2((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
}

class Vec3 {
  final double x;
  final double y;
  final double z;
  const Vec3(this.x, this.y, this.z);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};
  factory Vec3.fromJson(Map<String, dynamic> j) => Vec3(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['z'] as num).toDouble(),
      );
}

/// SE(2) pose in the scan world frame. [yaw] is rotation around the up axis
/// in radians; positive yaw rotates +x toward +y.
class Pose {
  final double x;
  final double y;
  final double yaw;
  const Pose({required this.x, required this.y, required this.yaw});

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'yaw': yaw};
  factory Pose.fromJson(Map<String, dynamic> j) => Pose(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        yaw: (j['yaw'] as num).toDouble(),
      );
}

class ScannedRoom {
  final String id;
  final String? label;

  /// CCW polygon, in metres, in the room's local frame (first vertex at
  /// origin). Wall edges are implicitly the polygon's segments
  /// `(floorPolygonMeters[i], floorPolygonMeters[(i+1) % n])`.
  final List<Vec2> floorPolygonMeters;

  /// Transform that places the room's local frame into the scan world frame.
  final Pose roomToWorld;

  /// Optional per-edge wall heights, in metres, indexed the same as the
  /// edges of [floorPolygonMeters]. Length must equal the polygon's
  /// vertex count when present — entry `i` is the height of the edge
  /// starting at vertex `i`. `null` means "no per-wall data; use the
  /// scene default."
  ///
  /// RoomPlan populates this from `CapturedRoom.walls[*].dimensions.y`.
  /// The tap engines don't measure height and leave it `null`.
  final List<double>? perWallHeightsMeters;

  const ScannedRoom({
    required this.id,
    this.label,
    required this.floorPolygonMeters,
    required this.roomToWorld,
    this.perWallHeightsMeters,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        if (label != null) 'label': label,
        'floorPolygonMeters':
            floorPolygonMeters.map((v) => v.toJson()).toList(),
        'roomToWorld': roomToWorld.toJson(),
        if (perWallHeightsMeters != null)
          'perWallHeightsMeters': perWallHeightsMeters,
      };

  factory ScannedRoom.fromJson(Map<String, dynamic> j) => ScannedRoom(
        id: j['id'] as String,
        label: j['label'] as String?,
        floorPolygonMeters: (j['floorPolygonMeters'] as List)
            .map((e) => Vec2.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        roomToWorld:
            Pose.fromJson((j['roomToWorld'] as Map).cast<String, dynamic>()),
        perWallHeightsMeters: (j['perWallHeightsMeters'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
      );
}

class ScannedOpening {
  final OpeningKind kind;

  /// The host room.
  final String roomId;

  /// Index into [ScannedRoom.floorPolygonMeters] — the opening sits on the
  /// edge starting at vertex [wallEdgeIndex] and ending at the next vertex.
  final int wallEdgeIndex;

  /// Distance in metres from the edge start vertex, along the edge, to the
  /// centre of the opening.
  final double offsetAlongWall;

  final double widthMeters;
  final double heightMeters;

  /// Distance from the floor to the bottom of the opening. 0 for doors.
  final double sillHeightMeters;

  const ScannedOpening({
    required this.kind,
    required this.roomId,
    required this.wallEdgeIndex,
    required this.offsetAlongWall,
    required this.widthMeters,
    required this.heightMeters,
    this.sillHeightMeters = 0,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'roomId': roomId,
        'wallEdgeIndex': wallEdgeIndex,
        'offsetAlongWall': offsetAlongWall,
        'widthMeters': widthMeters,
        'heightMeters': heightMeters,
        'sillHeightMeters': sillHeightMeters,
      };

  factory ScannedOpening.fromJson(Map<String, dynamic> j) => ScannedOpening(
        kind: _openingKindFromString(j['kind'] as String),
        roomId: j['roomId'] as String,
        wallEdgeIndex: (j['wallEdgeIndex'] as num).toInt(),
        offsetAlongWall: (j['offsetAlongWall'] as num).toDouble(),
        widthMeters: (j['widthMeters'] as num).toDouble(),
        heightMeters: (j['heightMeters'] as num).toDouble(),
        sillHeightMeters: (j['sillHeightMeters'] as num?)?.toDouble() ?? 0,
      );
}

/// Detected furniture / fixture. Only RoomPlan produces these on day one.
class ScannedObject {
  final String id;
  final ObjectCategory category;
  final Pose pose;
  final Vec3 sizeMeters;

  const ScannedObject({
    required this.id,
    required this.category,
    required this.pose,
    required this.sizeMeters,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'pose': pose.toJson(),
        'sizeMeters': sizeMeters.toJson(),
      };

  factory ScannedObject.fromJson(Map<String, dynamic> j) => ScannedObject(
        id: j['id'] as String,
        category: _objectCategoryFromString(j['category'] as String),
        pose: Pose.fromJson((j['pose'] as Map).cast<String, dynamic>()),
        sizeMeters:
            Vec3.fromJson((j['sizeMeters'] as Map).cast<String, dynamic>()),
      );
}

class FloorPlanScanResult {
  /// Stable identifier the native side generates per capture session.
  final String captureId;

  /// Which engine produced this result. Surface this in the review UI so
  /// the user knows the confidence level to expect.
  final ScanSourceEngine engine;

  /// 0..1. Meaningful for RoomPlan (we pass through Apple's confidence
  /// classifications, averaged). Synthetic 0.5 for manual-tap engines.
  final double confidence;

  final List<ScannedRoom> rooms;
  final List<ScannedOpening> openings;
  final List<ScannedObject> objects;

  /// Average ceiling height in metres, if the engine reported one.
  final double? ceilingHeightMeters;

  final DateTime capturedAt;

  /// Base64-encoded PNG of a top-down preview, rendered native-side.
  /// Optional — `null` if the platform did not produce a thumbnail.
  final String? thumbnailPngBase64;

  const FloorPlanScanResult({
    required this.captureId,
    required this.engine,
    required this.confidence,
    required this.rooms,
    this.openings = const [],
    this.objects = const [],
    this.ceilingHeightMeters,
    required this.capturedAt,
    this.thumbnailPngBase64,
  });

  Map<String, dynamic> toJson() => {
        'captureId': captureId,
        'engine': engine.name,
        'confidence': confidence,
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'openings': openings.map((o) => o.toJson()).toList(),
        'objects': objects.map((o) => o.toJson()).toList(),
        if (ceilingHeightMeters != null)
          'ceilingHeightMeters': ceilingHeightMeters,
        'capturedAt': capturedAt.toIso8601String(),
        if (thumbnailPngBase64 != null) 'thumbnailPngBase64': thumbnailPngBase64,
      };

  factory FloorPlanScanResult.fromJson(Map<String, dynamic> j) =>
      FloorPlanScanResult(
        captureId: j['captureId'] as String,
        engine: _engineFromString(j['engine'] as String),
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
        rooms: (j['rooms'] as List)
            .map((e) => ScannedRoom.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        openings: ((j['openings'] as List?) ?? const [])
            .map((e) =>
                ScannedOpening.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        objects: ((j['objects'] as List?) ?? const [])
            .map((e) =>
                ScannedObject.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        ceilingHeightMeters:
            (j['ceilingHeightMeters'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(j['capturedAt'] as String),
        thumbnailPngBase64: j['thumbnailPngBase64'] as String?,
      );
}

/// Why a scan stopped before producing a result.
enum ScanFailureKind {
  permissionDenied,
  cameraUnavailable,
  trackingLost,
  insufficientFeatures,
  unsupportedDevice,
  cancelled,
  unknown,
}

ScanFailureKind scanFailureKindFromString(String s) =>
    ScanFailureKind.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ScanFailureKind.unknown,
    );

class ScanFailure implements Exception {
  final ScanFailureKind kind;
  final String? message;
  const ScanFailure(this.kind, [this.message]);

  @override
  String toString() =>
      'ScanFailure(${kind.name}${message != null ? ': $message' : ''})';
}
