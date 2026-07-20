import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/screens/projects/tabs/project_selections_tab.dart';

/// Unit tests for [selectionAllowanceDelta] — the single source of truth for
/// the over/under-allowance badge shown on option cards AND on the new
/// single-step create flow's draft rows. Tested directly (no widget pump)
/// because Playwright can't reliably drive Flutter dialog buttons in this repo.
void main() {
  group('selectionAllowanceDelta', () {
    test('returns null when no allowance is set', () {
      expect(selectionAllowanceDelta(500, 0), isNull);
      expect(selectionAllowanceDelta(0, 0), isNull);
      expect(selectionAllowanceDelta(500, -10), isNull);
    });

    test('returns null when the option exactly matches the allowance', () {
      expect(selectionAllowanceDelta(1000, 1000), isNull);
    });

    test('flags an over-allowance option with the positive difference', () {
      final d = selectionAllowanceDelta(1200, 1000);
      expect(d, isNotNull);
      expect(d!.over, isTrue);
      expect(d.amount, 200);
    });

    test('flags an under-allowance option with the absolute difference', () {
      final d = selectionAllowanceDelta(750, 1000);
      expect(d, isNotNull);
      expect(d!.over, isFalse);
      expect(d.amount, 250);
    });

    test('amount is always non-negative regardless of direction', () {
      expect(selectionAllowanceDelta(1200, 1000)!.amount, greaterThan(0));
      expect(selectionAllowanceDelta(800, 1000)!.amount, greaterThan(0));
    });
  });
}
