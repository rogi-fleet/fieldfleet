import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/ai/ai_floorplan_plan.dart';
import 'package:taskfleet_ops/services/floorplan/ai_plan_to_scene.dart';
import 'package:taskfleet_ops/services/floorplan/scene_exporter.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  group('SceneExporter.renderSvg', () {
    test('empty scene produces a valid SVG envelope with viewBox', () {
      final scene = buildEmptyScene();
      final svg = SceneExporter.renderSvg(scene);
      expect(svg, startsWith('<svg'));
      expect(svg, contains('viewBox="0 0 2000 2000"'));
      expect(svg, contains('<rect width="100%" height="100%"'));
      expect(svg, endsWith('</svg>\n'));
    });

    test('a single 4m × 3m room emits 4 wall lines + a polygon area', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Living', x: 0, y: 0, width: 400, height: 300),
          ],
        ),
        IdBroker(),
      );
      final svg = SceneExporter.renderSvg(scene);
      expect(
        '<line'.allMatches(svg).length,
        4,
        reason: 'one <line> per wall',
      );
      expect(
        '<polygon'.allMatches(svg).length,
        1,
        reason: 'one <polygon> per area',
      );
      // Room name label is included.
      expect(svg, contains('>Living</text>'));
    });

    test('wall length labels are formatted in the scene unit', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'A', x: 0, y: 0, width: 500, height: 500),
          ],
        ),
        IdBroker(),
      );
      final svg = SceneExporter.renderSvg(scene);
      // Default unit is cm; 500 cm walls show "500 cm" labels.
      expect(svg, contains('>500 cm</text>'));
    });

    test('XML special characters in names get escaped', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(
                name: 'A & B <test>',
                x: 0,
                y: 0,
                width: 400,
                height: 300),
          ],
        ),
        IdBroker(),
      );
      final svg = SceneExporter.renderSvg(scene);
      expect(svg, contains('A &amp; B &lt;test&gt;'));
      expect(svg, isNot(contains('A & B <test>')));
    });

    test('items render as transformed g groups', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Lounge', x: 0, y: 0, width: 600, height: 400),
          ],
          items: [
            AiItem(prototype: 'sofa', room: 'Lounge'),
          ],
        ),
        IdBroker(),
      );
      final svg = SceneExporter.renderSvg(scene);
      expect(svg, contains('translate(300,200)'));
      expect(svg, contains('>sofa</text>'));
    });

    test('includeLabels=false strips text but keeps geometry', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'A', x: 0, y: 0, width: 300, height: 300),
          ],
        ),
        IdBroker(),
      );
      final svg =
          SceneExporter.renderSvg(scene, includeLabels: false);
      expect('<line'.allMatches(svg).length, 4);
      // No room name + no length labels.
      expect(svg, isNot(contains('<text')));
    });
  });
}
