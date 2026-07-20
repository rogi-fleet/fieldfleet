import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/floorplan/geometry.dart';
import 'package:taskfleet_ops/utils/floorplan/units.dart';

void main() {
  group('polygonArea', () {
    test('axis-aligned 5×4 rectangle = 20', () {
      final r = <Offset>[
        const Offset(0, 0),
        const Offset(5, 0),
        const Offset(5, 4),
        const Offset(0, 4),
      ];
      expect(polygonArea(r), closeTo(20, 1e-9));
    });

    test('returns the same |area| regardless of vertex order', () {
      final ccw = <Offset>[
        const Offset(0, 0),
        const Offset(5, 0),
        const Offset(5, 4),
        const Offset(0, 4),
      ];
      final cw = ccw.reversed.toList();
      expect(polygonArea(ccw), polygonArea(cw));
    });

    test('returns 0 for fewer than 3 vertices', () {
      expect(polygonArea(<Offset>[]), 0);
      expect(polygonArea(const [Offset(0, 0)]), 0);
      expect(polygonArea(const [Offset(0, 0), Offset(1, 0)]), 0);
    });

    test('right triangle 3-4-5 has area 6', () {
      final t = <Offset>[
        const Offset(0, 0),
        const Offset(3, 0),
        const Offset(0, 4),
      ];
      expect(polygonArea(t), closeTo(6, 1e-9));
    });
  });

  group('polygonPerimeter', () {
    test('axis-aligned 5×4 rectangle = 18', () {
      final r = <Offset>[
        const Offset(0, 0),
        const Offset(5, 0),
        const Offset(5, 4),
        const Offset(0, 4),
      ];
      expect(polygonPerimeter(r), closeTo(18, 1e-9));
    });

    test('triangle 3-4-5 perimeter = 12', () {
      final t = <Offset>[
        const Offset(0, 0),
        const Offset(3, 0),
        const Offset(0, 4),
      ];
      expect(polygonPerimeter(t), closeTo(12, 1e-9));
    });

    test('returns 0 for fewer than 2 vertices', () {
      expect(polygonPerimeter(<Offset>[]), 0);
      expect(polygonPerimeter(const [Offset(1, 2)]), 0);
    });
  });

  group('formatAreaCm2', () {
    test('m / cm / mm units yield m² display', () {
      // 80 000 cm² = 8 m² (the bedroom-sized room from §2 of the doc).
      expect(formatAreaCm2(80000, 'm'), '8.00 m²');
      expect(formatAreaCm2(80000, 'cm'), '8.00 m²');
      expect(formatAreaCm2(80000, 'mm'), '8.00 m²');
    });

    test('ft / in units yield sq ft display', () {
      // 100 ft² ≈ 92903 cm². formatAreaCm2(92903, 'ft') ≈ '100.0 sq ft'.
      expect(formatAreaCm2(92903, 'ft'), '100.0 sq ft');
      expect(formatAreaCm2(92903, 'in'), '100.0 sq ft');
    });

    test('small areas keep two decimals in m²', () {
      // 1.25 m² = 12500 cm².
      expect(formatAreaCm2(12500, 'm'), '1.25 m²');
    });
  });
}
