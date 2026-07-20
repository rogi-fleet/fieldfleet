/// Bridges Selections ↔ Documents.
///
/// A "Selection Sheet" is a [GeneratedDocument] of type [DocumentType.selections]
/// whose line items are the project's selections (a group per selection, an item
/// per offered option). Signing/approving that document is the customer's act of
/// choosing — on that event [applySignedSelections] approves each selection to
/// the option the document captured, routing through the atomic
/// `approve_selection_and_apply_budget` RPC so the budget impact lands in the
/// same transaction.
///
/// Line items are a SNAPSHOT (lineItemSourceMode = snapshot): once the sheet is
/// created the options are frozen, so a later resync can never re-fire approval
/// or re-create budget impact on an already-approved selection.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/document_line_item.dart';
import '../../models/selection.dart';

class SelectionDocumentService {
  SelectionDocumentService();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Metadata key under which a Selection Sheet stores the chosen option per
  /// selection: `{ selectionId: optionId }`. Pre-selected when the team has a
  /// recommended option; the customer can change it before signing.
  static const metadataKey = 'selection_choices';

  /// Build document line items from selections: one group per selection, one
  /// item per option. The group carries the allowance as its unit price so the
  /// budgeted figure renders; option items carry their own cost and link back
  /// to the same allowance budget_item.
  List<DocumentLineItem> buildLineItems(List<Selection> selections) {
    final items = <DocumentLineItem>[];
    var order = 0;
    for (final s in selections) {
      final groupId = 'sel_${s.id}';
      items.add(DocumentLineItem(
        id: groupId,
        budgetItemId: s.budgetItemId,
        type: DocumentLineItemType.group,
        sortOrder: order++,
        name: s.name,
        description: [s.category, s.location]
            .where((v) => v != null && v.isNotEmpty)
            .join(' · '),
        quantity: 1,
        unitPrice: s.allowanceAmount,
      ));
      for (final opt in s.options) {
        items.add(DocumentLineItem(
          id: 'opt_${opt.id}',
          budgetItemId: s.budgetItemId,
          type: DocumentLineItemType.item,
          parentId: groupId,
          sortOrder: order++,
          name: opt.name,
          description: [opt.vendor, opt.sku, opt.description]
              .where((v) => v != null && v.isNotEmpty)
              .join(' · '),
          quantity: opt.quantity,
          unit: null,
          unitPrice: opt.unitCost,
        ));
      }
    }
    return items;
  }

  /// The default choice map for a fresh sheet: any selection that already has a
  /// chosen/recommended option is pre-filled, otherwise omitted.
  Map<String, String> defaultChoices(List<Selection> selections) {
    final out = <String, String>{};
    for (final s in selections) {
      if (s.selectedOptionId != null) out[s.id] = s.selectedOptionId!;
    }
    return out;
  }

  /// Apply the choices captured on a signed/approved Selection Sheet. Each
  /// (selectionId → optionId) is approved via the atomic RPC. Best-effort per
  /// selection: a failure on one is collected and reported, never aborting the
  /// rest (the document is already signed; we don't want to lose the others).
  ///
  /// Returns the list of selection IDs that failed to apply (empty = all good).
  Future<List<String>> applySignedSelections({
    required Map<String, dynamic>? metadata,
    String? actorName,
  }) async {
    final raw = metadata?[metadataKey];
    if (raw is! Map) return const [];
    final choices = raw.map((k, v) => MapEntry(k.toString(), v?.toString()));

    final failed = <String>[];
    for (final entry in choices.entries) {
      final selectionId = entry.key;
      final optionId = entry.value;
      if (optionId == null || optionId.isEmpty) continue;
      try {
        await _supabase.rpc('approve_selection_and_apply_budget', params: {
          'p_selection_id': selectionId,
          'p_option_id': optionId,
          'p_actor_name': actorName ?? 'Client',
        });
      } catch (_) {
        failed.add(selectionId);
      }
    }
    return failed;
  }
}
