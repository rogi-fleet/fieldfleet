import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/budget_item.dart';
import 'package:taskfleet_ops/utils/budget_rollup.dart';

/// Lightweight BudgetItem fixture. The real model has 30+ fields, most of
/// which the rollup doesn't read; this constructor exposes only the ones
/// the predicate touches so each test reads as the scenario it's testing.
BudgetItem _bi({
  required String id,
  required BudgetItemType itemType,
  String? parentId,
  BudgetItemSource sourceType = BudgetItemSource.base,
  String? changeOrderId,
  UpgradeStatus? upgradeStatus,
  double approvedPrice = 0,
  double projectedCost = 0,
  bool isComplete = false,
}) {
  final now = DateTime(2026, 1, 1);
  return BudgetItem(
    id: id,
    workspaceId: 'ws',
    projectId: 'proj',
    parentId: parentId,
    hierarchyLevel: parentId == null ? 0 : 1,
    sortOrder: 0,
    name: id,
    quantity: 1,
    unitCost: 0,
    unitPrice: approvedPrice,
    markup: 0,
    isTaxable: false,
    approvedPrice: approvedPrice,
    projectedCost: projectedCost,
    committedCost: 0,
    finalCost: 0,
    isComplete: isComplete,
    createdAt: now,
    updatedAt: now,
    itemType: itemType,
    sourceType: sourceType,
    changeOrderId: changeOrderId,
    upgradeStatus: upgradeStatus,
  );
}

void main() {
  group('BudgetRollup — base items', () {
    test('sums approvedPrice + projectedCost across all base leaf items', () {
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'a',
              itemType: BudgetItemType.item,
              approvedPrice: 1000,
              projectedCost: 700),
          _bi(
              id: 'b',
              itemType: BudgetItemType.item,
              approvedPrice: 500,
              projectedCost: 300),
        ],
        coStatusesByDocumentId: const {},
      );
      expect(totals.totalApprovedPrice, 1500);
      expect(totals.totalProjectedCost, 1000);
    });

    test('excludes group containers from the sum', () {
      // A group with two children should sum the children's prices only —
      // adding the group itself would double-count. Mirrors how the
      // budget UI displays hierarchical roll-ups.
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'g',
              itemType: BudgetItemType.group,
              approvedPrice: 9999,
              projectedCost: 9999),
          _bi(
              id: 'g-a',
              parentId: 'g',
              itemType: BudgetItemType.item,
              approvedPrice: 100,
              projectedCost: 60),
          _bi(
              id: 'g-b',
              parentId: 'g',
              itemType: BudgetItemType.item,
              approvedPrice: 200,
              projectedCost: 120),
        ],
        coStatusesByDocumentId: const {},
      );
      expect(totals.totalApprovedPrice, 300);
      expect(totals.totalProjectedCost, 180);
    });

    test('parent items with children are excluded — only true leaves count',
        () {
      // An item-type row that has been turned into a parent (because
      // children point to it via parent_id) is no longer a leaf — its
      // approvedPrice should drop out so children carry the totals.
      // This is the scenario CO application produces today: the top
      // group is `item_type=group` but the safety net also handles
      // accidental `item_type=item` rows with children.
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'parent',
              itemType: BudgetItemType.item,
              approvedPrice: 999,
              projectedCost: 999),
          _bi(
              id: 'child',
              parentId: 'parent',
              itemType: BudgetItemType.item,
              approvedPrice: 50,
              projectedCost: 30),
        ],
        coStatusesByDocumentId: const {},
      );
      expect(totals.totalApprovedPrice, 50);
      expect(totals.totalProjectedCost, 30);
    });
  });

  group('BudgetRollup — change orders', () {
    test('counts CO items only when their CO document is approved', () {
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'base',
              itemType: BudgetItemType.item,
              approvedPrice: 1000,
              projectedCost: 700),
          _bi(
              id: 'co-line',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.changeOrder,
              changeOrderId: 'co-1',
              approvedPrice: 250,
              projectedCost: 150),
        ],
        coStatusesByDocumentId: const {'co-1': 'Approved'},
      );
      expect(totals.totalApprovedPrice, 1250);
      expect(totals.totalProjectedCost, 850);
    });

    test('counts signed CO and completed CO items the same as approved', () {
      // Signed (customer signature captured) and Completed (work
      // executed) are both terminal-positive states for a CO. The
      // rollup must include all three so a CO that's been signed but
      // not "approved" by a workspace member still affects the
      // contract total — otherwise a signed CO would silently fall out
      // until someone manually clicks Approve.
      for (final status in ['Signed', 'Completed']) {
        final totals = BudgetRollup.computeApprovedTotals(
          allItems: [
            _bi(
                id: 'co',
                itemType: BudgetItemType.item,
                sourceType: BudgetItemSource.changeOrder,
                changeOrderId: 'co-1',
                approvedPrice: 100,
                projectedCost: 60),
          ],
          coStatusesByDocumentId: {'co-1': status},
        );
        expect(totals.totalApprovedPrice, 100,
            reason: 'CO status $status should count');
      }
    });

    test('drops CO items when their CO document is declined', () {
      // The decline reconciler in document_service deletes the budget
      // rows for a declined CO, but even when those rows still exist
      // (e.g. portal denial that bypasses the Dart reconciler) the
      // rollup must still drop them — defence in depth so a declined
      // CO never inflates the contract total.
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'base',
              itemType: BudgetItemType.item,
              approvedPrice: 1000,
              projectedCost: 700),
          _bi(
              id: 'co-line',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.changeOrder,
              changeOrderId: 'co-1',
              approvedPrice: 250,
              projectedCost: 150),
        ],
        coStatusesByDocumentId: const {'co-1': 'Denied'},
      );
      expect(totals.totalApprovedPrice, 1000);
      expect(totals.totalProjectedCost, 700);
    });

    test('drops CO items when their CO document is still a draft', () {
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'co-line',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.changeOrder,
              changeOrderId: 'co-1',
              approvedPrice: 250,
              projectedCost: 150),
        ],
        coStatusesByDocumentId: const {'co-1': 'Draft'},
      );
      expect(totals.totalApprovedPrice, 0);
    });

    test('drops orphan CO items whose CO document is missing entirely', () {
      // If a CO row is deleted but its budget items somehow remain
      // (data integrity bug, manual delete), the rollup should not
      // count them — we can't verify the contract change actually
      // happened.
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'orphan',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.changeOrder,
              changeOrderId: 'gone',
              approvedPrice: 250),
        ],
        coStatusesByDocumentId: const {},
      );
      expect(totals.totalApprovedPrice, 0);
    });
  });

  group('BudgetRollup — upgrades', () {
    test('counts only accepted upgrades, ignores offered/declined', () {
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'base',
              itemType: BudgetItemType.item,
              approvedPrice: 1000),
          _bi(
              id: 'up-accept',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.upgrade,
              upgradeStatus: UpgradeStatus.accepted,
              approvedPrice: 250,
              projectedCost: 150),
          _bi(
              id: 'up-offer',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.upgrade,
              upgradeStatus: UpgradeStatus.offered,
              approvedPrice: 999),
          _bi(
              id: 'up-decline',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.upgrade,
              upgradeStatus: UpgradeStatus.declined,
              approvedPrice: 999),
        ],
        coStatusesByDocumentId: const {},
      );
      expect(totals.totalApprovedPrice, 1250);
      expect(totals.totalProjectedCost, 150);
    });

    test('a null upgradeStatus on an upgrade row is treated as not accepted',
        () {
      // The DB schema technically allows `upgrade_status = null`. A
      // null is not the same as `accepted`, so the upgrade must not
      // count. Without this guard a corrupted row would silently
      // inflate the budget.
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'up',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.upgrade,
              approvedPrice: 500),
        ],
        coStatusesByDocumentId: const {},
      );
      expect(totals.totalApprovedPrice, 0);
    });
  });

  group('BudgetRollup — end-to-end project lifecycle', () {
    test(
        'a realistic project — base + accepted upgrade + approved CO + '
        'declined CO — totals match the user-facing contract value', () {
      // Walks through the happy-path lifecycle:
      //   1. The GC builds a budget of $10,000 (one base item).
      //   2. Customer accepts a $1,500 upgrade.
      //   3. Mid-project, CO-1 is approved for $2,000.
      //   4. CO-2 is drafted for $5,000 but declined.
      // The contract value the customer is on the hook for is:
      //     10,000 + 1,500 + 2,000 = $13,500.
      // The $5,000 declined CO must not appear.
      const co1 = 'co-1';
      const co2 = 'co-2';
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: [
          _bi(
              id: 'base',
              itemType: BudgetItemType.item,
              approvedPrice: 10000,
              projectedCost: 7000),
          _bi(
              id: 'upgrade',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.upgrade,
              upgradeStatus: UpgradeStatus.accepted,
              approvedPrice: 1500,
              projectedCost: 900),
          _bi(
              id: 'co1-line',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.changeOrder,
              changeOrderId: co1,
              approvedPrice: 2000,
              projectedCost: 1200),
          _bi(
              id: 'co2-line',
              itemType: BudgetItemType.item,
              sourceType: BudgetItemSource.changeOrder,
              changeOrderId: co2,
              approvedPrice: 5000,
              projectedCost: 3000),
        ],
        coStatusesByDocumentId: const {
          co1: 'Approved',
          co2: 'Denied',
        },
      );
      expect(totals.totalApprovedPrice, 13500);
      expect(totals.totalProjectedCost, 9100);
    });

    test('isEmpty is true on a brand-new project with no budget', () {
      final totals = BudgetRollup.computeApprovedTotals(
        allItems: const [],
        coStatusesByDocumentId: const {},
      );
      expect(totals.isEmpty, isTrue);
    });
  });
}
