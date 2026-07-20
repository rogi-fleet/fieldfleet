import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/layer.dart';
import 'package:taskfleet_ops/models/floorplan/line.dart';
import 'package:taskfleet_ops/models/floorplan/scene.dart';
import 'package:taskfleet_ops/models/floorplan/vertex.dart';

Scene _makeScene({
  double? ceilingHeightCm,
  Map<String, FloorLine> lines = const {},
}) {
  return Scene(
    id: 'scene-1',
    selectedLayerId: 'lyr-1',
    ceilingHeightCm: ceilingHeightCm ?? 240,
    layers: {
      'lyr-1': Layer(
        id: 'lyr-1',
        vertices: const {
          'v1': Vertex(id: 'v1', x: 0, y: 0),
          'v2': Vertex(id: 'v2', x: 500, y: 0),
        },
        lines: lines,
      ),
    },
  );
}

void main() {
  group('Scene.ceilingHeightCm', () {
    test('defaults to 240 when not provided', () {
      final s = Scene(
        id: 's', selectedLayerId: 'lyr', layers: const {'lyr': Layer(id: 'lyr')});
      expect(s.ceilingHeightCm, 240);
    });

    test('round-trips through JSON', () {
      final s = _makeScene(ceilingHeightCm: 275);
      final back = Scene.fromJson(s.toJson());
      expect(back.ceilingHeightCm, 275);
    });

    test('old scenes without ceilingHeightCm field default to 240', () {
      final original = _makeScene();
      final json = original.toJson()..remove('ceilingHeightCm');
      final back = Scene.fromJson(json);
      expect(back.ceilingHeightCm, 240);
    });

    test('copyWith preserves ceilingHeightCm unless overridden', () {
      final s = _makeScene(ceilingHeightCm: 300);
      expect(s.copyWith(name: 'changed').ceilingHeightCm, 300);
      expect(s.copyWith(ceilingHeightCm: 260).ceilingHeightCm, 260);
    });
  });

  group('FloorLine.heightCm', () {
    final wall = const FloorLine(id: 'w', vertexIds: ['v1', 'v2']);

    test('defaults to null (use scene default)', () {
      expect(wall.heightCm, isNull);
    });

    test('effectiveHeightCm falls back to scene ceiling', () {
      expect(wall.effectiveHeightCm(240), 240);
      expect(wall.effectiveHeightCm(300), 300);
    });

    test('effectiveHeightCm respects the override when set', () {
      final w = wall.copyWith(heightCm: 120);
      expect(w.effectiveHeightCm(240), 120);
    });

    test('JSON round-trips when override is null', () {
      final back = FloorLine.fromJson(wall.toJson());
      expect(back.heightCm, isNull);
    });

    test('JSON round-trips when override is set', () {
      final w = wall.copyWith(heightCm: 110);
      final back = FloorLine.fromJson(w.toJson());
      expect(back.heightCm, 110);
    });

    test('absent heightCm key in JSON deserializes to null', () {
      final json = wall.copyWith(heightCm: 110).toJson()..remove('heightCm');
      final back = FloorLine.fromJson(json);
      expect(back.heightCm, isNull);
    });

    test('clearHeight strips the override', () {
      final w = wall.copyWith(heightCm: 100);
      expect(w.copyWith(clearHeight: true).heightCm, isNull);
    });
  });
}
