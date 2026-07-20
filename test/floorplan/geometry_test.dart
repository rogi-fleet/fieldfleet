import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/floorplan/geometry.dart';

void main() {
  group('pointsDistance', () {
    test('zero distance for identical points', () {
      expect(pointsDistance(const Offset(3, 4), const Offset(3, 4)), 0);
    });

    test('3-4-5 triangle', () {
      expect(pointsDistance(const Offset(0, 0), const Offset(3, 4)), 5);
    });
  });

  group('closestPointOnSegment', () {
    test('clamps beyond start to a', () {
      final a = const Offset(0, 0);
      final b = const Offset(10, 0);
      expect(closestPointOnSegment(a, b, const Offset(-5, 0)), a);
    });

    test('clamps beyond end to b', () {
      final a = const Offset(0, 0);
      final b = const Offset(10, 0);
      expect(closestPointOnSegment(a, b, const Offset(15, 0)), b);
    });

    test('projects perpendicular point', () {
      final result = closestPointOnSegment(
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(4, 7),
      );
      expect(result.dx, closeTo(4, kEpsilon));
      expect(result.dy, closeTo(0, kEpsilon));
    });

    test('degenerate segment returns a', () {
      final a = const Offset(5, 5);
      expect(closestPointOnSegment(a, a, const Offset(7, 9)), a);
    });
  });

  group('pointPositionOnSegment', () {
    test('returns 0 at start', () {
      expect(
        pointPositionOnSegment(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(0, 0),
        ),
        closeTo(0, kEpsilon),
      );
    });

    test('returns 1 at end', () {
      expect(
        pointPositionOnSegment(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(10, 0),
        ),
        closeTo(1, kEpsilon),
      );
    });

    test('returns 0.5 at midpoint', () {
      expect(
        pointPositionOnSegment(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(5, 0),
        ),
        closeTo(0.5, kEpsilon),
      );
    });

    test('clamps points outside the segment', () {
      expect(
        pointPositionOnSegment(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(-3, 0),
        ),
        0,
      );
      expect(
        pointPositionOnSegment(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(20, 0),
        ),
        1,
      );
    });
  });

  group('twoLinesIntersection', () {
    test('returns null for parallel lines', () {
      expect(
        twoLinesIntersection(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(0, 5),
          const Offset(10, 5),
        ),
        isNull,
      );
    });

    test('finds perpendicular intersection at origin', () {
      final r = twoLinesIntersection(
        const Offset(-5, 0),
        const Offset(5, 0),
        const Offset(0, -5),
        const Offset(0, 5),
      )!;
      expect(r.dx, closeTo(0, kEpsilon));
      expect(r.dy, closeTo(0, kEpsilon));
    });
  });

  group('snapToGrid', () {
    test('rounds to nearest grid step', () {
      expect(snapToGrid(const Offset(13, 27), 10), const Offset(10, 30));
    });

    test('returns input when step is zero', () {
      expect(snapToGrid(const Offset(13, 27), 0), const Offset(13, 27));
    });
  });

  group('samePoints', () {
    test('true within epsilon', () {
      expect(
        samePoints(const Offset(1, 1), const Offset(1 + kEpsilon / 2, 1)),
        isTrue,
      );
    });

    test('false outside epsilon', () {
      expect(
        samePoints(const Offset(1, 1), const Offset(1.1, 1)),
        isFalse,
      );
    });
  });
}
