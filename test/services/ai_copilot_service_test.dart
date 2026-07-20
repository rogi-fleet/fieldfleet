import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/services/supabase/ai_copilot_service.dart';

void main() {
  group('SupabaseAiCopilotService.wouldCreateCircularDependency', () {
    test('returns true for self dependency', () {
      final result = SupabaseAiCopilotService.wouldCreateCircularDependency(
        predecessorGraph: {'a': <String>[]},
        taskId: 'a',
        newPredecessorId: 'a',
      );

      expect(result, isTrue);
    });

    test('returns true when dependency chain reaches task', () {
      final result = SupabaseAiCopilotService.wouldCreateCircularDependency(
        predecessorGraph: {
          'a': <String>['b'],
          'b': <String>['c'],
          'c': <String>[],
        },
        taskId: 'c',
        newPredecessorId: 'a',
      );

      expect(result, isTrue);
    });

    test('returns false when no cycle is introduced', () {
      final result = SupabaseAiCopilotService.wouldCreateCircularDependency(
        predecessorGraph: {
          'a': <String>[],
          'b': <String>['a'],
          'c': <String>[],
        },
        taskId: 'c',
        newPredecessorId: 'b',
      );

      expect(result, isFalse);
    });
  });
}
