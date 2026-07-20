import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/floorplan/units.dart';

void main() {
  group('convertFromCm / convertToCm', () {
    test('cm is identity', () {
      expect(convertFromCm(100, 'cm'), 100);
      expect(convertToCm(100, 'cm'), 100);
    });

    test('m is x100', () {
      expect(convertFromCm(500, 'm'), 5);
      expect(convertToCm(5, 'm'), 500);
    });

    test('mm is /10', () {
      expect(convertFromCm(5, 'mm'), 50);
      expect(convertToCm(50, 'mm'), 5);
    });

    test('ft uses 30.48 cm per ft', () {
      expect(convertFromCm(304.8, 'ft'), closeTo(10, 0.001));
      expect(convertToCm(10, 'ft'), closeTo(304.8, 0.001));
    });

    test('in uses 2.54 cm per in', () {
      expect(convertFromCm(254, 'in'), closeTo(100, 0.001));
      expect(convertToCm(100, 'in'), closeTo(254, 0.001));
    });
  });

  group('formatLengthCm', () {
    test('m formats with 2 decimals', () {
      expect(formatLengthCm(500, 'm'), '5.00 m');
    });

    test('cm formats with 0 decimals', () {
      expect(formatLengthCm(123, 'cm'), '123 cm');
    });

    test('ft formats with 2 decimals', () {
      expect(formatLengthCm(304.8, 'ft'), '10.00 ft');
    });
  });

  group('parseLengthToCm', () {
    test('plain number uses default unit', () {
      expect(parseLengthToCm('5', 'm'), 500);
      expect(parseLengthToCm('100', 'cm'), 100);
    });

    test('explicit unit suffix overrides default', () {
      expect(parseLengthToCm('5m', 'cm'), 500);
      expect(parseLengthToCm('100 cm', 'm'), 100);
      expect(parseLengthToCm('10ft', 'cm'), closeTo(304.8, 0.001));
    });

    test('rejects negatives and non-numbers', () {
      expect(parseLengthToCm('-5', 'cm'), isNull);
      expect(parseLengthToCm('abc', 'cm'), isNull);
      expect(parseLengthToCm('', 'cm'), isNull);
    });
  });
}
