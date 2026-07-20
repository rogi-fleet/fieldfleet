import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/file_markup.dart';

void main() {
  group('MarkupShape JSON round-trip', () {
    test('FreeDrawShape', () {
      final shape = FreeDrawShape(
        id: 'a',
        color: '#FF0000',
        width: 4,
        points: const [Offset(0.1, 0.2), Offset(0.5, 0.5)],
      );
      final round = MarkupShape.fromJson(shape.toJson()) as FreeDrawShape;
      expect(round.id, 'a');
      expect(round.color, '#FF0000');
      expect(round.width, 4);
      expect(round.points, shape.points);
    });

    test('ArrowShape', () {
      final shape = ArrowShape(
        id: 'a',
        color: '#00FF00',
        from: const Offset(0.1, 0.2),
        to: const Offset(0.8, 0.9),
        width: 3,
      );
      final round = MarkupShape.fromJson(shape.toJson()) as ArrowShape;
      expect(round.from, shape.from);
      expect(round.to, shape.to);
      expect(round.width, 3);
    });

    test('CalloutShape — single + multi-arrow', () {
      final single = CalloutShape(
        id: 'c1',
        color: '#000000',
        anchor: const Offset(0.3, 0.3),
        tails: const [Offset(0.5, 0.5)],
        text: 'hi',
      );
      final multi = CalloutShape(
        id: 'c2',
        color: '#000000',
        anchor: const Offset(0.3, 0.3),
        tails: const [
          Offset(0.5, 0.5),
          Offset(0.2, 0.8),
          Offset(0.9, 0.1),
        ],
        text: 'multi',
        fontSize: 16,
      );
      expect(single.isMultiArrow, isFalse);
      expect(multi.isMultiArrow, isTrue);
      expect(
        (MarkupShape.fromJson(multi.toJson()) as CalloutShape)
            .tails
            .length,
        3,
      );
      expect(
        (MarkupShape.fromJson(multi.toJson()) as CalloutShape).fontSize,
        16,
      );
    });

    test('PolylineShape + TextShape + TimestampShape round-trip', () {
      final poly = PolylineShape(
        id: 'p',
        color: '#123456',
        points: const [Offset(0, 0), Offset(0.5, 0.5), Offset(1, 1)],
      );
      final text = TextShape(
        id: 't',
        color: '#FF00FF',
        at: const Offset(0.5, 0.5),
        text: 'hello',
        fontSize: 22,
      );
      final stamp = TimestampShape(
        id: 's',
        color: '#00FFFF',
        at: const Offset(0.9, 0.1),
        capturedAt: DateTime.utc(2026, 4, 20, 10, 0, 0),
      );
      expect(
        (MarkupShape.fromJson(poly.toJson()) as PolylineShape).points.length,
        3,
      );
      expect(
        (MarkupShape.fromJson(text.toJson()) as TextShape).text,
        'hello',
      );
      final roundStamp = MarkupShape.fromJson(stamp.toJson()) as TimestampShape;
      expect(roundStamp.capturedAt.toUtc(), stamp.capturedAt);
    });

    test('unknown shape type throws FormatException (no silent data loss)', () {
      expect(
        () => MarkupShape.fromJson({
          'id': 'x',
          'type': 'not_a_type',
          'color': '#000000',
        }),
        throwsFormatException,
      );
    });
  });

  group('MarkupLayer', () {
    final isoNow = DateTime.utc(2026, 4, 20, 10).toIso8601String();

    test('fromSupabase — defaults to no-crop / no-rotate / no-flip', () {
      final layer = MarkupLayer.fromSupabase({
        'id': 'l',
        'workspace_id': 'w',
        'file_attachment_id': 'f',
        'shapes': <Map<String, dynamic>>[],
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(layer.shapes, isEmpty);
      expect(layer.rotation, 0);
      expect(layer.flipHorizontal, isFalse);
      expect(layer.flipVertical, isFalse);
      expect(layer.cropRect, const Rect.fromLTWH(0, 0, 1, 1));
      expect(layer.hasCrop, isFalse);
    });

    test('fromSupabase — full transform stack', () {
      final layer = MarkupLayer.fromSupabase({
        'id': 'l',
        'workspace_id': 'w',
        'file_attachment_id': 'f',
        'shapes': <Map<String, dynamic>>[],
        'rotation': 90,
        'flip_horizontal': true,
        'flip_vertical': false,
        'crop_x': 0.2,
        'crop_y': 0.1,
        'crop_width': 0.5,
        'crop_height': 0.8,
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(layer.rotation, 90);
      expect(layer.flipHorizontal, isTrue);
      expect(layer.flipVertical, isFalse);
      expect(layer.cropRect, const Rect.fromLTWH(0.2, 0.1, 0.5, 0.8));
      expect(layer.hasCrop, isTrue);
    });

    test('fromSupabase — shapes can arrive pre-encoded as a JSON string', () {
      // Some Postgres clients return jsonb columns as already-decoded
      // List/Map; others hand back the raw string. The factory tolerates
      // both — this test covers the string path.
      final layer = MarkupLayer.fromSupabase({
        'id': 'l',
        'workspace_id': 'w',
        'file_attachment_id': 'f',
        'shapes': '[{"id":"a","type":"arrow","color":"#000000",'
            '"width":2,"from":[0,0],"to":[1,1]}]',
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(layer.shapes, hasLength(1));
      expect(layer.shapes.single, isA<ArrowShape>());
    });

    test('copyWith preserves identity when called with no args', () {
      final layer = MarkupLayer(
        id: 'l',
        workspaceId: 'w',
        fileAttachmentId: 'f',
        shapes: const [],
        rotation: 180,
        flipHorizontal: true,
        cropRect: const Rect.fromLTWH(0.1, 0.1, 0.5, 0.5),
        updatedAt: _epoch,
        createdAt: _epoch,
      );
      final copy = layer.copyWith();
      expect(copy.rotation, 180);
      expect(copy.flipHorizontal, isTrue);
      expect(copy.cropRect, const Rect.fromLTWH(0.1, 0.1, 0.5, 0.5));
    });
  });
}

final _epoch = DateTime.utc(2000, 1, 1);
