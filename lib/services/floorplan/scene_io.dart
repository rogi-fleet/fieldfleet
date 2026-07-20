import 'dart:convert';

import '../../models/floorplan/layer.dart';
import '../../models/floorplan/scene.dart';
import '../../utils/floorplan/id_broker.dart';

/// Round-trip helpers for the [Scene] model and the `scene_json` JSONB column
/// on `floorplan_scenes`. Wraps Dart `jsonEncode`/`jsonDecode` with the
/// `Scene.toJson` / `Scene.fromJson` glue and a current schema version so old
/// scenes can be migrated forward later.
class SceneIO {
  static const int currentSchemaVersion = 1;

  static Map<String, dynamic> toRow(Scene scene) => {
        'schemaVersion': currentSchemaVersion,
        'scene': scene.toJson(),
      };

  static Scene fromRow(Map<String, dynamic> row) {
    final scene = row['scene'] as Map?;
    if (scene == null) {
      throw const FormatException('scene_json missing "scene" field');
    }
    return Scene.fromJson(scene.cast<String, dynamic>());
  }

  static String toJsonString(Scene scene) => jsonEncode(toRow(scene));

  static Scene fromJsonString(String raw) =>
      fromRow((jsonDecode(raw) as Map).cast<String, dynamic>());
}

/// Build a fresh empty scene with one default layer.
Scene buildEmptyScene({IdBroker? ids, String name = 'Untitled Floorplan'}) {
  final broker = ids ?? IdBroker();
  final layerId = broker.layer();
  return Scene(
    id: broker.scene(),
    name: name,
    selectedLayerId: layerId,
    layers: {
      layerId: Layer(id: layerId, name: 'Default', order: 0),
    },
  );
}
