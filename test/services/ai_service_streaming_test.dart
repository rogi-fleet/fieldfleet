import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/services/ai_service.dart';

void main() {
  group('AiService streaming helpers', () {
    final service = AiService();

    test('extracts stream delta from OpenAI-style chunk', () {
      final delta = service.extractStreamDeltaForTesting({
        'choices': [
          {
            'delta': {'content': 'hello'},
          },
        ],
      });

      expect(delta, 'hello');
    });

    test('extracts stream delta from reasoning chunk', () {
      final delta = service.extractStreamDeltaForTesting({
        'choices': [
          {
            'delta': {'reasoning': 'planning...'},
          },
        ],
      });

      expect(delta, 'planning...');
    });

    test('extracts stream delta from message content chunk', () {
      final delta = service.extractStreamDeltaForTesting({
        'choices': [
          {
            'message': {'content': 'final chunk'},
          },
        ],
      });

      expect(delta, 'final chunk');
    });

    test('parses budget items from fenced JSON content', () {
      final items = service.parseBudgetItemsFromContentForTesting('''
```json
[{"name":"Demo Labor","quantity":8,"unit":"hr","unitCost":50,"unitPrice":80}]
```
''');

      expect(items.length, 1);
      expect(items.first.name, 'Demo Labor');
      expect(items.first.unit, 'hr');
    });

    test('parses task list from JSON array content', () {
      final tasks = service.parseTaskResponseFromContentForTesting('''
[
  {
    "tempId":"task_1",
    "title":"Demo Existing Drywall",
    "taskType":"standard",
    "parentTempId":null,
    "predecessorTempIds":[],
    "estimatedDuration":6,
    "priority":"high",
    "checklistItems":["Protect floors","Remove drywall"],
    "sourceBudgetItemId":"bi_1"
  }
]
''');

      expect(tasks.length, 1);
      expect(tasks.first.title, 'Demo Existing Drywall');
      expect(tasks.first.estimatedDuration, 6);
    });

    test('parses project plan object from JSON content', () {
      final plan = service.parseProjectPlanResponseForTesting('''
{
  "phases": [
    {
      "tempId":"phase_0",
      "name":"Demolition",
      "description":"Remove damaged materials",
      "sortOrder":0,
      "tasks":[
        {
          "tempId":"phase_0_task_0",
          "title":"Remove drywall",
          "description":"Remove damaged drywall sections",
          "predecessorTempIds":[],
          "estimatedDuration":4,
          "priority":"high",
          "checklistItems":["Contain dust","Dispose debris"]
        }
      ],
      "budgetItems":[
        {
          "tempId":"phase_0_bi_0",
          "name":"Demo Labor",
          "quantity":4,
          "unit":"hr",
          "unitCost":60,
          "unitPrice":95
        }
      ]
    }
  ],
  "properties":[]
}
''');

      expect(plan.phases.length, 1);
      expect(plan.phases.first.name, 'Demolition');
      expect(plan.phases.first.tasks.length, 1);
      expect(plan.phases.first.budgetItems.length, 1);
    });

    test(
      'enriches phases-only plan with default child tasks and budget items',
      () {
        final parsed = service.parseProjectPlanResponseForTesting('''
{
  "phases": [
    {
      "tempId":"phase_0",
      "name":"Demolition",
      "description":"Remove damaged materials",
      "sortOrder":0
    }
  ],
  "properties":[]
}
''');

        final enriched = service.enrichProjectPlanForTesting(parsed);
        expect(enriched.phases.length, 1);
        expect(enriched.phases.first.tasks, isNotEmpty);
        expect(enriched.phases.first.budgetItems, isNotEmpty);
      },
    );
  });
}
