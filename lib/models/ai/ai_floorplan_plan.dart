// High-level DSL the AI emits when asked to design a floorplan.
//
// We deliberately keep this much smaller than the editor's `Scene`
// model — the model produces rooms / doors / windows / items rather
// than vertex IDs and back-references, and an adapter
// (`ai_plan_to_scene.dart`) walks this DSL through the existing
// SceneBuilder / RoomOps / HoleOps code to assemble a valid scene.
// That keeps every geometric invariant under tested code, and gives
// the model a tiny target schema it can hit reliably.
//
// All measurements are stored in cm post-parse (the JSON's `unit`
// field is honored on read and converted at parse time).

class AiFloorplanPlan {
  /// Source unit declared by the model. Always converted to cm
  /// internally — kept here for debugging / audit only.
  final String sourceUnit;

  final List<AiRoom> rooms;
  final List<AiDoor> doors;
  final List<AiWindow> windows;
  final List<AiItem> items;

  const AiFloorplanPlan({
    this.sourceUnit = 'cm',
    this.rooms = const [],
    this.doors = const [],
    this.windows = const [],
    this.items = const [],
  });

  String? get firstRoomName => rooms.isEmpty ? null : rooms.first.name;

  /// Parse from the model's raw JSON. Coordinates / sizes are converted
  /// to cm based on [unitFactor] (1 for cm, 100 for m, 30.48 for ft).
  factory AiFloorplanPlan.fromJson(Map<String, dynamic> json) {
    final unit = (json['unit'] as String?)?.toLowerCase() ?? 'cm';
    final factor = _factorToCm(unit);
    return AiFloorplanPlan(
      sourceUnit: unit,
      rooms: ((json['rooms'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) =>
              AiRoom.fromJson(m.cast<String, dynamic>(), factor))
          .toList(),
      doors: ((json['doors'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) =>
              AiDoor.fromJson(m.cast<String, dynamic>(), factor))
          .toList(),
      windows: ((json['windows'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) =>
              AiWindow.fromJson(m.cast<String, dynamic>(), factor))
          .toList(),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) =>
              AiItem.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }

  static double _factorToCm(String unit) => switch (unit) {
        'mm' => 0.1,
        'cm' => 1.0,
        'm' => 100.0,
        'ft' => 30.48,
        'in' => 2.54,
        _ => 1.0,
      };
}

class AiRoom {
  final String name;
  final double x;       // top-left in cm
  final double y;
  final double width;
  final double height;

  const AiRoom({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory AiRoom.fromJson(Map<String, dynamic> json, double factor) {
    return AiRoom(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Room',
      x: ((json['x'] as num?) ?? 0).toDouble() * factor,
      y: ((json['y'] as num?) ?? 0).toDouble() * factor,
      width: ((json['width'] as num?) ?? 100).toDouble() * factor,
      height: ((json['height'] as num?) ?? 100).toDouble() * factor,
    );
  }
}

class AiDoor {
  final String fromRoom;

  /// Null = exterior door (door on the perimeter, not between rooms).
  final String? toRoom;

  /// Normalized 0..1 along the host wall.
  final double offset;

  /// Door width in cm.
  final double width;

  const AiDoor({
    required this.fromRoom,
    this.toRoom,
    this.offset = 0.5,
    this.width = 90,
  });

  factory AiDoor.fromJson(Map<String, dynamic> json, double factor) {
    return AiDoor(
      fromRoom: (json['from_room'] as String?) ??
          (json['fromRoom'] as String?) ??
          (json['between'] is List
              ? ((json['between'] as List).first as String?)
              : null) ??
          '',
      toRoom: (json['to_room'] as String?) ??
          (json['toRoom'] as String?) ??
          (json['between'] is List && (json['between'] as List).length > 1
              ? ((json['between'] as List)[1] as String?)
              : null),
      offset:
          ((json['offset'] as num?) ?? 0.5).toDouble().clamp(0.05, 0.95),
      width: ((json['width'] as num?) ?? 90).toDouble() * factor,
    );
  }
}

class AiWindow {
  final String room;

  /// One of: 'north', 'south', 'east', 'west'.
  final String wall;

  /// Normalized 0..1 along the chosen wall.
  final double offset;

  /// Window width in cm.
  final double width;

  const AiWindow({
    required this.room,
    required this.wall,
    this.offset = 0.5,
    this.width = 120,
  });

  factory AiWindow.fromJson(Map<String, dynamic> json, double factor) {
    return AiWindow(
      room: (json['room'] as String?) ?? '',
      wall: (json['wall'] as String?)?.toLowerCase() ?? 'north',
      offset:
          ((json['offset'] as num?) ?? 0.5).toDouble().clamp(0.05, 0.95),
      width: ((json['width'] as num?) ?? 120).toDouble() * factor,
    );
  }
}

class AiItem {
  /// Catalog prototype (e.g. 'sofa', 'bed', 'sink'). Unknowns dropped
  /// at adapter time.
  final String prototype;

  /// Room name to place the item in.
  final String room;

  /// One of: 'center', 'north', 'south', 'east', 'west' (relative to
  /// the room's interior). Falls back to 'center'.
  final String position;

  final double rotation;

  const AiItem({
    required this.prototype,
    required this.room,
    this.position = 'center',
    this.rotation = 0,
  });

  factory AiItem.fromJson(Map<String, dynamic> json) {
    return AiItem(
      prototype: (json['prototype'] as String?)?.toLowerCase() ?? '',
      room: (json['room'] as String?) ?? '',
      position:
          (json['position'] as String?)?.toLowerCase() ?? 'center',
      rotation: ((json['rotation'] as num?) ?? 0).toDouble(),
    );
  }
}
