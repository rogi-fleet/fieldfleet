import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/services/floorplan/presets.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  group('preset builders', () {
    for (final preset in defaultPresets) {
      test('${preset.id} builds a scene that round-trips through JSON', () {
        final scene = preset.build(IdBroker(), 'Test');
        // Each preset should produce a valid scene with a default layer.
        expect(scene.layers, isNotEmpty);
        expect(scene.selectedLayer, isNotNull);

        // And serializing + deserializing must be lossless.
        final restored =
            SceneIO.fromJsonString(SceneIO.toJsonString(scene));
        expect(restored.layers.length, scene.layers.length);
        expect(
          restored.selectedLayer.lines.length,
          scene.selectedLayer.lines.length,
        );
        expect(
          restored.selectedLayer.holes.length,
          scene.selectedLayer.holes.length,
        );
        expect(
          restored.selectedLayer.items.length,
          scene.selectedLayer.items.length,
        );
      });
    }

    test('non-blank presets contain at least one wall + auto-area', () {
      // These presets are special: their build() is unused because the
      // picker recognises them by id and runs an external flow (AI
      // generation, native scan). They legitimately build to an empty
      // scene as a fallback.
      const buildlessPresetIds = {
        'blank', 'ai', 'ai_image', 'ai_pdf', 'scan',
      };
      for (final preset in defaultPresets) {
        if (buildlessPresetIds.contains(preset.id)) continue;
        final scene = preset.build(IdBroker(), 'Test');
        expect(
          scene.selectedLayer.lines,
          isNotEmpty,
          reason: '${preset.id} should have walls',
        );
        expect(
          scene.selectedLayer.areas,
          isNotEmpty,
          reason: '${preset.id} should have at least one auto-detected area',
        );
      }
    });
  });
}
