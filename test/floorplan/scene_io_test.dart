import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/annotation.dart';
import 'package:taskfleet_ops/models/floorplan/area.dart';
import 'package:taskfleet_ops/models/floorplan/background_pdf.dart';
import 'package:taskfleet_ops/models/floorplan/element_kind.dart';
import 'package:taskfleet_ops/models/floorplan/hole.dart';
import 'package:taskfleet_ops/models/floorplan/item.dart';
import 'package:taskfleet_ops/models/floorplan/line.dart';
import 'package:taskfleet_ops/models/floorplan/vertex.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  group('buildEmptyScene', () {
    test('creates a scene with one default layer', () {
      final scene = buildEmptyScene();
      expect(scene.layers, hasLength(1));
      expect(scene.selectedLayer.vertices, isEmpty);
      expect(scene.selectedLayer.lines, isEmpty);
    });
  });

  group('SceneIO round-trip', () {
    test('empty scene survives JSON round trip', () {
      final scene = buildEmptyScene(name: 'Test');
      final restored =
          SceneIO.fromJsonString(SceneIO.toJsonString(scene));
      expect(restored.id, scene.id);
      expect(restored.name, 'Test');
      expect(restored.layers, hasLength(1));
      expect(restored.selectedLayerId, scene.selectedLayerId);
    });

    test('scene with all element kinds round-trips losslessly', () {
      final ids = IdBroker();
      final base = buildEmptyScene(ids: ids);
      final layer = base.selectedLayer;
      final v1 = Vertex(id: ids.vertex(), x: 0, y: 0, lineIds: {'l1'});
      final v2 = Vertex(id: ids.vertex(), x: 100, y: 0, lineIds: {'l1'});
      final line = FloorLine(
        id: 'l1',
        vertexIds: [v1.id, v2.id],
        holeIds: ['h1'],
        thickness: 15,
        properties: {'color': '#333'},
      );
      final hole = Hole(
        id: 'h1',
        prototype: 'door',
        lineId: 'l1',
        offset: 0.5,
        width: 90,
      );
      final area = Area(id: 'a1', vertexIds: [v1.id, v2.id]);
      final item = Item(
        id: ids.item(),
        prototype: 'sofa',
        x: 50,
        y: 80,
        rotation: 1.57,
      );
      final text = TextAnnotation(
        id: ids.annotation(),
        color: '#FF0000',
        x: 10,
        y: 20,
        text: 'Living room',
      );
      final arrow = ArrowAnnotation(
        id: ids.annotation(),
        color: '#00FF00',
        fromX: 0,
        fromY: 0,
        toX: 30,
        toY: 30,
      );
      final dim = DimensionAnnotation(
        id: ids.annotation(),
        color: '#0000FF',
        fromX: 0,
        fromY: 0,
        toX: 100,
        toY: 0,
        unit: 'cm',
      );

      final populated = base.withSelectedLayer(layer.copyWith(
        vertices: {v1.id: v1, v2.id: v2},
        lines: {line.id: line},
        holes: {hole.id: hole},
        areas: {area.id: area},
        items: {item.id: item},
        annotations: {text.id: text, arrow.id: arrow, dim.id: dim},
        selected:
            layer.selected.withSelection(ElementKind.line, line.id),
      ));

      final restored =
          SceneIO.fromJsonString(SceneIO.toJsonString(populated));
      final rl = restored.selectedLayer;

      expect(rl.vertices.values.map((v) => v.x).toList()..sort(),
          [0.0, 100.0]);
      expect(rl.lines[line.id]!.thickness, 15);
      expect(rl.lines[line.id]!.holeIds, ['h1']);
      expect((rl.holes[hole.id] as Hole).offset, 0.5);
      expect(rl.areas[area.id]!.vertexIds, [v1.id, v2.id]);
      expect(rl.items[item.id]!.prototype, 'sofa');
      expect((rl.annotations[text.id] as TextAnnotation).text,
          'Living room');
      expect((rl.annotations[arrow.id] as ArrowAnnotation).toX, 30);
      expect((rl.annotations[dim.id] as DimensionAnnotation).unit, 'cm');
      expect(rl.selected.lines, {line.id});
    });

    test('background pdf round-trips', () {
      final scene = buildEmptyScene().copyWith(
        background: const BackgroundPdf(
          fileUrl: 'https://example.com/plan.pdf',
          pageIndex: 2,
          opacity: 0.5,
        ),
      );
      final restored =
          SceneIO.fromJsonString(SceneIO.toJsonString(scene));
      expect(restored.background, isNotNull);
      expect(restored.background!.fileUrl, 'https://example.com/plan.pdf');
      expect(restored.background!.pageIndex, 2);
      expect(restored.background!.opacity, 0.5);
    });

    test('schemaVersion is preserved in row form', () {
      final scene = buildEmptyScene();
      final row = SceneIO.toRow(scene);
      expect(row['schemaVersion'], SceneIO.currentSchemaVersion);
    });
  });
}
