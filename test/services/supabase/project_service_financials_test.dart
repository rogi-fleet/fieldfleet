import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/services/supabase/project_service.dart';

void main() {
  group('SupabaseProjectService financial helpers', () {
    test(
      'includes paid progress invoices in collected revenue document types',
      () {
        expect(
          SupabaseProjectService.collectedRevenueDocumentTypes,
          containsAll(<String>['invoice', 'progress_invoice']),
        );
      },
    );

    test(
      'uses only eligible leaf budget rows in project financial summaries',
      () {
        final rows = <Map<String, dynamic>>[
          {
            'id': 'group-base',
            'parent_id': null,
            'item_type': 'group',
            'source_type': 'base',
            'approved_price': 0,
            'projected_cost': 0,
            'final_cost': 0,
            'is_complete': false,
          },
          {
            'id': 'base-leaf',
            'parent_id': 'group-base',
            'item_type': 'item',
            'source_type': 'base',
            'approved_price': 100,
            'projected_cost': 60,
            'final_cost': 80,
            'is_complete': true,
          },
          {
            'id': 'co-approved',
            'parent_id': null,
            'item_type': 'item',
            'source_type': 'change_order',
            'change_order_id': 'co-1',
            'approved_price': 50,
            'projected_cost': 25,
            'final_cost': 0,
            'is_complete': false,
          },
          {
            'id': 'co-pending',
            'parent_id': null,
            'item_type': 'item',
            'source_type': 'change_order',
            'change_order_id': 'co-2',
            'approved_price': 75,
            'projected_cost': 35,
            'final_cost': 0,
            'is_complete': false,
          },
          {
            'id': 'upgrade-accepted',
            'parent_id': null,
            'item_type': 'item',
            'source_type': 'upgrade',
            'upgrade_status': 'accepted',
            'approved_price': 40,
            'projected_cost': 20,
            'final_cost': 0,
            'is_complete': false,
          },
          {
            'id': 'upgrade-offered',
            'parent_id': null,
            'item_type': 'item',
            'source_type': 'upgrade',
            'upgrade_status': 'offered',
            'approved_price': 30,
            'projected_cost': 10,
            'final_cost': 0,
            'is_complete': false,
          },
          {
            'id': 'parent-item',
            'parent_id': null,
            'item_type': 'item',
            'source_type': 'base',
            'approved_price': 999,
            'projected_cost': 999,
            'final_cost': 999,
            'is_complete': true,
          },
          {
            'id': 'child-item',
            'parent_id': 'parent-item',
            'item_type': 'item',
            'source_type': 'base',
            'approved_price': 120,
            'projected_cost': 70,
            'final_cost': 0,
            'is_complete': false,
          },
        ];

        final eligible =
            SupabaseProjectService.eligibleBudgetRowsForFinancialSummary(
              rows,
              changeOrderStatuses: const <String, String>{
                'co-1': 'signed',
                'co-2': 'pending',
              },
            );

        expect(
          eligible.map((row) => row['id']),
          orderedEquals(<String>[
            'base-leaf',
            'co-approved',
            'upgrade-accepted',
            'child-item',
          ]),
        );
        expect(
          SupabaseProjectService.sumCostToCompleteFromBudgetRows(eligible),
          80 + 25 + 20 + 70,
        );
      },
    );
  });
}
