import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/document_template.dart';
import 'package:taskfleet_ops/models/document_type.dart';
import 'package:taskfleet_ops/utils/document_template_renderer.dart';

void main() {
  group('DocumentTemplateRenderer', () {
    test('resolves nested fields from the first item in a list', () {
      final rendered = DocumentTemplateRenderer.render(
        'Primary equipment: {{equipment.name}}',
        {
          'equipment': [
            {'name': 'Roof Pump'},
            {'name': 'Backup Pump'},
          ],
        },
      );

      expect(rendered, 'Primary equipment: Roof Pump');
    });

    test('renders maintenance work order list placeholders', () {
      final template = DocumentTemplate.getDefaultTemplate(
        DocumentType.workOrderMaintenance,
      );
      final rendered = DocumentTemplateRenderer.render(template, {
        'workOrder': {
          'number': 'WO-1',
          'scheduledDate': '05/03/2026',
          'notes': 'Check filters',
          'nextScheduled': '06/03/2026',
        },
        'equipment': [
          {'name': 'Air Handler'},
        ],
        'maintenanceItems': [
          {'item': 'Replace filter', 'status': 'Open'},
        ],
        'parts': [
          {'name': 'Filter', 'quantity': '1'},
        ],
        'technician': {'name': 'Dana'},
      });

      expect(rendered, contains('**Equipment/System:** Air Handler'));
      expect(rendered, contains('- [ ] Replace filter - Open'));
      expect(rendered, contains('| Filter | 1 |'));
    });

    test('renders emergency work order action placeholders', () {
      final template = DocumentTemplate.getDefaultTemplate(
        DocumentType.workOrderEmergency,
      );
      final rendered = DocumentTemplateRenderer.render(template, {
        'workOrder': {
          'number': 'WO-2',
          'timeReceived': '08:00 AM',
          'emergencyDescription': 'Water leak',
          'dispatchTime': '08:15 AM',
          'completionNotes': '',
        },
        'actions': [
          {'action': 'Shut off water'},
        ],
        'technician': {'name': 'Lee'},
      });

      expect(rendered, contains('- [ ] Shut off water'));
    });
  });
}
