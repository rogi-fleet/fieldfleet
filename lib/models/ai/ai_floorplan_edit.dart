// One operation the AI returns when asked to modify an existing
// floorplan. Sealed so the applier in `ai_edit_to_scene.dart` can
// exhaustively switch on the op kind.
//
// Coordinates / sizes are normalized to cm at parse time — the
// model can declare its preferred unit on the wrapping
// AiFloorplanEditBatch.

sealed class AiFloorplanEdit {
  const AiFloorplanEdit();

  static AiFloorplanEdit? fromJson(
    Map<String, dynamic> json,
    double factor,
  ) {
    final op = (json['op'] as String?)?.toLowerCase();
    return switch (op) {
      'add_room' => AddRoomEdit.fromJson(json, factor),
      'remove_room' => RemoveRoomEdit.fromJson(json),
      'rename_room' => RenameRoomEdit.fromJson(json),
      'add_door' => AddDoorEdit.fromJson(json, factor),
      'remove_door' => RemoveDoorEdit.fromJson(json),
      'add_window' => AddWindowEdit.fromJson(json, factor),
      'add_item' => AddItemEdit.fromJson(json),
      'remove_item' => RemoveItemEdit.fromJson(json),
      _ => null,
    };
  }
}

class AddRoomEdit extends AiFloorplanEdit {
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;

  const AddRoomEdit({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory AddRoomEdit.fromJson(Map<String, dynamic> json, double factor) =>
      AddRoomEdit(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : 'Room',
        x: ((json['x'] as num?) ?? 0).toDouble() * factor,
        y: ((json['y'] as num?) ?? 0).toDouble() * factor,
        width: ((json['width'] as num?) ?? 100).toDouble() * factor,
        height: ((json['height'] as num?) ?? 100).toDouble() * factor,
      );
}

class RemoveRoomEdit extends AiFloorplanEdit {
  final String name;
  const RemoveRoomEdit({required this.name});
  factory RemoveRoomEdit.fromJson(Map<String, dynamic> json) =>
      RemoveRoomEdit(name: (json['name'] as String?) ?? '');
}

class RenameRoomEdit extends AiFloorplanEdit {
  final String from;
  final String to;
  const RenameRoomEdit({required this.from, required this.to});
  factory RenameRoomEdit.fromJson(Map<String, dynamic> json) =>
      RenameRoomEdit(
        from: (json['from'] as String?) ?? '',
        to: (json['to'] as String?) ?? '',
      );
}

class AddDoorEdit extends AiFloorplanEdit {
  final String fromRoom;
  final String? toRoom;
  final double offset;
  final double width;

  const AddDoorEdit({
    required this.fromRoom,
    this.toRoom,
    this.offset = 0.5,
    this.width = 90,
  });

  factory AddDoorEdit.fromJson(Map<String, dynamic> json, double factor) =>
      AddDoorEdit(
        fromRoom: (json['from_room'] as String?) ??
            (json['fromRoom'] as String?) ??
            '',
        toRoom: (json['to_room'] as String?) ??
            (json['toRoom'] as String?),
        offset:
            ((json['offset'] as num?) ?? 0.5).toDouble().clamp(0.05, 0.95),
        width: ((json['width'] as num?) ?? 90).toDouble() * factor,
      );
}

class RemoveDoorEdit extends AiFloorplanEdit {
  final String fromRoom;
  final String? toRoom;
  const RemoveDoorEdit({required this.fromRoom, this.toRoom});
  factory RemoveDoorEdit.fromJson(Map<String, dynamic> json) =>
      RemoveDoorEdit(
        fromRoom: (json['from_room'] as String?) ??
            (json['fromRoom'] as String?) ??
            '',
        toRoom: (json['to_room'] as String?) ??
            (json['toRoom'] as String?),
      );
}

class AddWindowEdit extends AiFloorplanEdit {
  final String room;
  final String wall;
  final double offset;
  final double width;
  const AddWindowEdit({
    required this.room,
    required this.wall,
    this.offset = 0.5,
    this.width = 120,
  });

  factory AddWindowEdit.fromJson(
    Map<String, dynamic> json,
    double factor,
  ) =>
      AddWindowEdit(
        room: (json['room'] as String?) ?? '',
        wall: (json['wall'] as String?)?.toLowerCase() ?? 'north',
        offset:
            ((json['offset'] as num?) ?? 0.5).toDouble().clamp(0.05, 0.95),
        width: ((json['width'] as num?) ?? 120).toDouble() * factor,
      );
}

class AddItemEdit extends AiFloorplanEdit {
  final String prototype;
  final String room;
  final String position;
  final double rotation;

  const AddItemEdit({
    required this.prototype,
    required this.room,
    this.position = 'center',
    this.rotation = 0,
  });

  factory AddItemEdit.fromJson(Map<String, dynamic> json) => AddItemEdit(
        prototype: (json['prototype'] as String?)?.toLowerCase() ?? '',
        room: (json['room'] as String?) ?? '',
        position:
            (json['position'] as String?)?.toLowerCase() ?? 'center',
        rotation: ((json['rotation'] as num?) ?? 0).toDouble(),
      );
}

class RemoveItemEdit extends AiFloorplanEdit {
  final String prototype;
  final String? room;
  const RemoveItemEdit({required this.prototype, this.room});
  factory RemoveItemEdit.fromJson(Map<String, dynamic> json) =>
      RemoveItemEdit(
        prototype: (json['prototype'] as String?)?.toLowerCase() ?? '',
        room: (json['room'] as String?),
      );
}

/// Wrapper for the AI's response to an edit prompt.
class AiFloorplanEditBatch {
  final List<AiFloorplanEdit> operations;
  const AiFloorplanEditBatch({this.operations = const []});

  factory AiFloorplanEditBatch.fromJson(Map<String, dynamic> json) {
    final unit = (json['unit'] as String?)?.toLowerCase() ?? 'cm';
    final factor = switch (unit) {
      'mm' => 0.1,
      'cm' => 1.0,
      'm' => 100.0,
      'ft' => 30.48,
      'in' => 2.54,
      _ => 1.0,
    };
    return AiFloorplanEditBatch(
      operations: ((json['operations'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => AiFloorplanEdit.fromJson(
                m.cast<String, dynamic>(),
                factor,
              ))
          .whereType<AiFloorplanEdit>()
          .toList(),
    );
  }
}
