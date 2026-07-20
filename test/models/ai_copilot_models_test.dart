import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/ai_copilot_models.dart';

void main() {
  group('Ai copilot models', () {
    test('parses risk assessment', () {
      final model = AiProjectRiskAssessment.fromJson({
        'project_id': 'p1',
        'project_name': 'Demo',
        'risk_score': 67,
        'risk_level': 'high',
        'confidence': 0.7,
        'drivers': [
          {
            'key': 'overdue_tasks',
            'label': 'Overdue tasks',
            'severity': 80,
            'detail': '4 task(s) are overdue.',
          },
        ],
        'recommended_actions': ['Reschedule overdue tasks first.'],
        'metrics': {'overdue_tasks': 4},
      });

      expect(model.projectId, 'p1');
      expect(model.riskScore, 67);
      expect(model.drivers.length, 1);
      expect(model.recommendedActions.first, contains('Reschedule'));
    });

    test('parses schedule optimization result', () {
      final result = AiScheduleOptimizationResult.fromJson({
        'suggestion_count': 1,
        'suggestions': [
          {
            'id': 's1',
            'title': 'Order tasks',
            'impact_summary': 'Reduce blockers',
            'estimated_days_saved': 2,
            'risk_notes': ['Low confidence'],
            'changes': [
              {'task_id': 't2', 'add_predecessor_id': 't1'},
            ],
          },
        ],
      });

      expect(result.suggestionCount, 1);
      expect(result.suggestions.first.changes.first.addPredecessorId, 't1');
    });

    test('parses weekly digest', () {
      final digest = AiWeeklyProjectDigest.fromJson({
        'project_id': 'p1',
        'week_start_date': '2026-02-09',
        'week_end_date': '2026-02-15',
        'overview': '2 overdue tasks remain.',
        'digest_markdown': '- Demo digest',
        'highlights': ['risk 40'],
        'risks': ['overdue tasks'],
        'next_week_priorities': ['clear blockers'],
        'highlight_items': [
          {
            'title': 'Risk improved',
            'detail': 'Down 4 points',
            'href': '/projects/p1',
            'badge': 'Improving',
          },
        ],
        'risk_items': [
          {
            'title': 'Inspect task',
            'detail': 'Overdue by 2d',
            'href': '/projects/p1?tab=tasks&taskId=t1',
            'badge': 'Overdue',
          },
        ],
        'priority_items': [
          {'title': 'Clear blockers', 'detail': 'Resolve owner handoff'},
        ],
        'watch_items': [
          {'title': 'Due soon task', 'detail': 'Due in 3d'},
        ],
      });

      expect(digest.projectId, 'p1');
      expect(digest.overview, contains('overdue'));
      expect(digest.digestMarkdown, contains('digest'));
      expect(digest.nextWeekPriorities.length, 1);
      expect(digest.highlightItems.first.href, '/projects/p1');
      expect(digest.riskItems.first.badge, 'Overdue');
    });
  });
}
