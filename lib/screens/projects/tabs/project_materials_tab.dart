import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/cost_item.dart';
import '../../../models/document_status.dart';
import '../../../models/document_type.dart';
import '../../../models/generated_document.dart';
import '../../../models/inventory/inventory_item.dart';
import '../../../models/inventory/inventory_stock_movement.dart';
import '../../../models/project.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../widgets/common/status_chip.dart';
import '../../../theme/theme.dart';

/// Per-project view of materials issued from inventory stock.
/// Lets the project manager issue stock straight from stores to the job
/// (which writes the matching cost line to financials).
/// Equipment on site (rentals) lives in the Assets sub-tab.
class ProjectMaterialsTab extends StatefulWidget {
  final Project project;
  const ProjectMaterialsTab({super.key, required this.project});

  @override
  State<ProjectMaterialsTab> createState() => _ProjectMaterialsTabState();
}

class _ProjectMaterialsTabState extends State<ProjectMaterialsTab> {
  List<InventoryItem> _items = const [];
  bool _loadingItems = true;

  List<CostItem> _unbilled = const [];
  bool _loadingUnbilled = true;
  final Set<String> _selectedCostIds = {};

  /// Material cost lines for this project keyed by cost-item id, so each issued
  /// stock row can show its billable / invoiced state and we can edit or toggle
  /// the linked cost. Refreshed after every mutation.
  Map<String, CostItem> _costsById = const {};

  String get _wsId =>
      context.read<AuthProvider>().appUser?.activeWorkspaceId ??
      context.read<AuthProvider>().appUser?.workspaceId ??
      '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadItems();
      _loadUnbilled();
      _loadCosts();
    });
  }

  /// Snapshot this project's material cost lines into [_costsById] so issued
  /// stock rows can resolve their billable / invoiced state.
  Future<void> _loadCosts() async {
    try {
      final costs = await ServiceLocator.costService
          .getCostItemsByType(
            widget.project.id,
            CostItemType.material,
            workspaceId: _wsId,
          )
          .first;
      if (mounted) {
        setState(() {
          _costsById = {for (final c in costs) c.id: c};
        });
      }
    } catch (_) {
      /* leave previous snapshot in place */
    }
  }

  /// Reload the project's billable, not-yet-invoiced costs (the candidates the
  /// "Bill to client" picker selects from).
  Future<void> _loadUnbilled() async {
    if (mounted) setState(() => _loadingUnbilled = true);
    try {
      final costs = await ServiceLocator.costService.getUnbilledBillableCosts(
        widget.project.id,
        workspaceId: _wsId,
        type: CostItemType.material,
      );
      if (mounted) {
        setState(() {
          _unbilled = List<CostItem>.from(costs as List);
          // Drop any selections that are no longer unbilled.
          _selectedCostIds.retainAll(_unbilled.map((c) => c.id).toSet());
          _loadingUnbilled = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUnbilled = false);
    }
  }

  Future<void> _loadItems() async {
    try {
      final svc = ServiceLocator.inventoryItemServiceFor(_wsId);
      final list = await svc.listItems();
      if (mounted) setState(() {
        _items = list;
        _loadingItems = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  String _itemName(String id) => _items
      .firstWhere(
        (i) => i.id == id,
        orElse: () => InventoryItem(
          id: id,
          workspaceId: _wsId,
          name: 'Item ${id.substring(0, 6)}',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      )
      .name;

  Future<void> _openIssueDialog() async {
    if (_loadingItems) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No inventory items to issue yet.')),
      );
      return;
    }
    final result = await showDialog<_IssueResult>(
      context: context,
      builder: (_) => _IssueStockDialog(items: _items),
    );
    if (result == null) return;
    final svc = ServiceLocator.inventoryStockMovementServiceFor(_wsId);
    try {
      await svc.issueToJob(
        inventoryItemId: result.itemId,
        projectId: widget.project.id,
        quantity: result.quantity,
        itemName: _itemName(result.itemId),
        unitCost: result.unitCost,
        unitSalePriceOverride: result.salePrice,
        notes: result.notes,
        billable: result.billable,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock issued and cost line added.')),
        );
      }
      await _loadUnbilled();
      await _loadCosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Issue failed: $e')),
        );
      }
    }
  }

  /// Edit an already-issued material: quantity, internal cost, client bill
  /// rate, notes, and billable flag. The item itself can't be swapped — reverse
  /// and re-issue for that. Blocked once the cost has been billed to an invoice.
  Future<void> _editIssue(InventoryStockMovement m) async {
    if (_loadingItems) return;
    // Resolve the linked cost fresh rather than trusting the (possibly stale or
    // not-yet-loaded) snapshot — seeding the dialog from a missing cost would
    // silently reset the client bill rate to the internal cost on save.
    CostItem? cost =
        m.costItemId == null ? null : _costsById[m.costItemId];
    if (cost == null && m.costItemId != null) {
      try {
        cost = await ServiceLocator.costService.getCostItem(m.costItemId!);
      } catch (_) {
        /* fall through to the guard below */
      }
      if (cost == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't load this material's cost line. "
                  'Check your connection and try again.'),
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final item = _items.firstWhere(
      (i) => i.id == m.inventoryItemId,
      orElse: () => InventoryItem(
        id: m.inventoryItemId,
        workspaceId: _wsId,
        name: _itemName(m.inventoryItemId),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final result = await showDialog<_IssueResult>(
      context: context,
      builder: (_) => _IssueStockDialog(
        items: _items,
        editItem: item,
        initialQuantity: m.quantity,
        initialUnitCost: m.unitCost ?? 0,
        initialSalePrice: cost?.unitPrice,
        initialNotes: m.notes,
        initialBillable: cost?.billable ?? true,
      ),
    );
    if (result == null) return;
    final svc = ServiceLocator.inventoryStockMovementServiceFor(_wsId);
    try {
      await svc.updateIssue(
        movementId: m.id,
        quantity: result.quantity,
        itemName: _itemName(m.inventoryItemId),
        unitCost: result.unitCost,
        unitSalePriceOverride: result.salePrice,
        notes: result.notes,
        billable: result.billable,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Material updated.')),
        );
      }
      await _loadUnbilled();
      await _loadCosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: ${_clean(e)}')),
        );
      }
    }
  }

  /// Flip whether the linked cost line is chargeable to the client. The
  /// billable flag lives on the cost item only, so no movement change needed.
  Future<void> _toggleBillable(CostItem cost) async {
    try {
      await ServiceLocator.costService.setBillable(cost.id, !cost.billable);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cost.billable
                  ? 'Marked internal — excluded from client invoices.'
                  : 'Marked billable to client.',
            ),
          ),
        );
      }
      await _loadUnbilled();
      await _loadCosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: ${_clean(e)}')),
        );
      }
    }
  }

  /// Reverse a mistaken issue: returns the stock and removes the cost line.
  Future<void> _deleteIssue(InventoryStockMovement m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove issued material?'),
        content: Text(
          'This returns ${m.quantity} ${_itemName(m.inventoryItemId)} to stock '
          'and deletes its cost line from Financials. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final svc = ServiceLocator.inventoryStockMovementServiceFor(_wsId);
    try {
      await svc.reverseIssue(m.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Material removed and stock returned.')),
        );
      }
      await _loadUnbilled();
      await _loadCosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove: ${_clean(e)}')),
        );
      }
    }
  }

  /// Strip the `Exception: ` / Postgres prefix noise from a thrown error so the
  /// snackbar shows the human-readable message the RPC raised.
  String _clean(Object e) {
    // RPC calls surface a PostgrestException whose toString() wraps the
    // RAISE-EXCEPTION text in noise; pull the bare message out first.
    if (e is PostgrestException) return e.message;
    final s = e.toString();
    return s.replaceFirst(RegExp(r'^(Exception:\s*)+'), '').trim();
  }

  /// Bill the selected unbilled costs onto a client invoice. Lets the user
  /// pick one of the project's open (un-posted) invoice documents, then calls
  /// the atomic `bill_cost_items_to_document` bridge.
  Future<void> _billSelected() async {
    if (_selectedCostIds.isEmpty) return;
    final doc = await _pickInvoiceDocument();
    if (doc == null) return;
    try {
      final billed = await ServiceLocator.costService.billCostsToDocument(
        documentId: doc.id,
        costItemIds: _selectedCostIds.toList(),
      );
      if (mounted) {
        final label = doc.documentNumber ?? doc.documentType.displayName;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              billed == 0
                  ? 'Nothing to bill — those costs were already invoiced.'
                  : 'Billed $billed cost${billed == 1 ? '' : 's'} to $label.',
            ),
          ),
        );
        _selectedCostIds.clear();
      }
      await _loadUnbilled();
      await _loadCosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not bill costs: $e')),
        );
      }
    }
  }

  /// Pick an open (un-posted) customer-invoice document for this project.
  Future<GeneratedDocument?> _pickInvoiceDocument() async {
    List<GeneratedDocument> docs = const [];
    try {
      docs = await ServiceLocator.documentService
          .getDocuments(_wsId, projectId: widget.project.id)
          .first;
    } catch (_) {}
    final invoices = docs
        .where((d) => d.documentType.isPayableCustomerInvoice)
        .toList();
    if (!mounted) return null;
    if (invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No open invoice for this job yet. Create an invoice first, '
            'then add these costs to it.',
          ),
        ),
      );
      return null;
    }
    return showDialog<GeneratedDocument>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Add costs to invoice'),
        children: [
          for (final d in invoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(d),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long),
                title: Text(
                  d.documentNumber ?? d.documentType.displayName,
                ),
                subtitle: Text(
                  '${d.status.displayName} · \$${d.totalAmount.toStringAsFixed(2)}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movementSvc = ServiceLocator.inventoryStockMovementServiceFor(_wsId);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Materials section
          _SectionHeader(
            title: 'Materials issued from stock',
            subtitle: 'Each issue writes a Material cost line to Financials.',
            actionLabel: 'Issue stock',
            onAction: _openIssueDialog,
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<InventoryStockMovement>>(
            stream: movementSvc.watchMovementsForProject(widget.project.id),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final issues = snap.data!
                  .where((m) => m.movementType == StockMovementType.issue)
                  .toList();
              if (issues.isEmpty) {
                return const _EmptyCard(
                  icon: Icons.inventory_2_outlined,
                  text: 'No materials issued to this job yet.',
                );
              }
              double total = 0;
              for (final m in issues) {
                total += (m.unitCost ?? 0) * m.quantity;
              }
              return Card(
                child: Column(
                  children: [
                    ...issues.map((m) {
                      final cost = (m.unitCost ?? 0) * m.quantity;
                      final costItem =
                          m.costItemId == null ? null : _costsById[m.costItemId];
                      final invoiced = costItem?.isInvoiced ?? false;
                      final billable = costItem?.billable ?? true;
                      return ListTile(
                        leading: const Icon(Icons.outbox),
                        title: Row(
                          children: [
                            Flexible(child: Text(_itemName(m.inventoryItemId))),
                            const SizedBox(width: 8),
                            _StatusChip(
                              invoiced: invoiced,
                              billable: billable,
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${m.quantity} × \$${(m.unitCost ?? 0).toStringAsFixed(2)}'
                          ' · ${_d(m.occurredAt)}'
                          '${(m.notes != null && m.notes!.isNotEmpty) ? ' · ${m.notes}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\$${cost.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (invoiced)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Tooltip(
                                  message:
                                      'Billed to an invoice — edit or remove '
                                      'from the invoice first.',
                                  child: Icon(Icons.lock_outline, size: 18),
                                ),
                              )
                            else
                              PopupMenuButton<String>(
                                tooltip: 'Material actions',
                                onSelected: (v) {
                                  switch (v) {
                                    case 'edit':
                                      _editIssue(m);
                                    case 'billable':
                                      if (costItem != null) {
                                        _toggleBillable(costItem);
                                      }
                                    case 'delete':
                                      _deleteIssue(m);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Edit'),
                                    ),
                                  ),
                                  if (costItem != null)
                                    PopupMenuItem(
                                      value: 'billable',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(billable
                                            ? Icons.money_off
                                            : Icons.attach_money),
                                        title: Text(billable
                                            ? 'Mark internal'
                                            : 'Mark billable'),
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('Remove'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Total materials cost',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '\$${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          _buildBillSection(),
        ],
      ),
    );
  }

  Widget _buildBillSection() {
    final selectedTotal = _unbilled
        .where((c) => _selectedCostIds.contains(c.id))
        .fold<double>(0, (sum, c) => sum + c.totalCost);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Billable to client',
          subtitle:
              'Pull unbilled costs onto a client invoice. Posted invoices are excluded.',
          actionLabel: _selectedCostIds.isEmpty
              ? 'Bill to invoice'
              : 'Bill ${_selectedCostIds.length} to invoice',
          onAction: _selectedCostIds.isEmpty ? null : _billSelected,
        ),
        const SizedBox(height: 8),
        if (_loadingUnbilled)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_unbilled.isEmpty)
          const _EmptyCard(
            icon: Icons.price_check,
            text: 'No unbilled billable costs for this job.',
          )
        else
          Card(
            child: Column(
              children: [
                ..._unbilled.map((c) {
                  final selected = _selectedCostIds.contains(c.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedCostIds.add(c.id);
                      } else {
                        _selectedCostIds.remove(c.id);
                      }
                    }),
                    title: Text(c.description),
                    subtitle: Text(
                      '${c.formattedQuantity} × ${c.formattedUnitPrice} · ${_d(c.date)}',
                    ),
                    secondary: Text(
                      c.formattedTotalCost,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                }),
                if (_selectedCostIds.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_selectedCostIds.length} selected',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '\$${selectedTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onAction,
          icon: const Icon(Icons.add),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// Compact pill showing whether an issued material is locked onto an invoice,
/// billable to the client, or internal-use only.
class _StatusChip extends StatelessWidget {
  final bool invoiced;
  final bool billable;
  const _StatusChip({required this.invoiced, required this.billable});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color fg;
    late final String label;
    if (invoiced) {
      fg = scheme.primary;
      label = 'Invoiced';
    } else if (billable) {
      fg = scheme.tertiary;
      label = 'Billable';
    } else {
      fg = scheme.outline;
      label = 'Internal';
    }
    return StatusChip(label: label, color: fg, size: StatusChipSize.compact);
  }
}

class _IssueResult {
  final String itemId;
  final double quantity;
  final double unitCost;
  final double? salePrice;
  final String? notes;
  final bool billable;
  _IssueResult({
    required this.itemId,
    required this.quantity,
    required this.unitCost,
    this.salePrice,
    this.notes,
    this.billable = true,
  });
}

class _IssueStockDialog extends StatefulWidget {
  final List<InventoryItem> items;

  /// When non-null the dialog edits an existing issue: the item is locked and
  /// the fields below seed the form.
  final InventoryItem? editItem;
  final double? initialQuantity;
  final double? initialUnitCost;
  final double? initialSalePrice;
  final String? initialNotes;
  final bool initialBillable;

  const _IssueStockDialog({
    required this.items,
    this.editItem,
    this.initialQuantity,
    this.initialUnitCost,
    this.initialSalePrice,
    this.initialNotes,
    this.initialBillable = true,
  });

  @override
  State<_IssueStockDialog> createState() => _IssueStockDialogState();
}

class _IssueStockDialogState extends State<_IssueStockDialog> {
  String? _itemId;
  final _qty = TextEditingController(text: '1');
  final _unitCost = TextEditingController(text: '0');
  final _salePrice = TextEditingController();
  final _notes = TextEditingController();
  bool _billable = true;

  bool get _isEdit => widget.editItem != null;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _itemId = widget.editItem!.id;
      _qty.text = _fmt(widget.initialQuantity ?? 1);
      _unitCost.text = _fmt(widget.initialUnitCost ?? 0);
      _salePrice.text =
          widget.initialSalePrice == null ? '' : _fmt(widget.initialSalePrice!);
      _notes.text = widget.initialNotes ?? '';
      _billable = widget.initialBillable;
    } else if (widget.items.isNotEmpty) {
      final i = widget.items.first;
      _itemId = i.id;
      _unitCost.text = i.unitCost.toString();
      _salePrice.text = i.unitSalePrice?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _unitCost.dispose();
    _salePrice.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit issued material' : 'Issue stock to job'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isEdit)
                TextFormField(
                  enabled: false,
                  initialValue: widget.editItem!.name,
                  decoration: const InputDecoration(
                    labelText: 'Item',
                    helperText: 'Reverse and re-issue to change the item.',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _itemId,
                  decoration: const InputDecoration(
                    labelText: 'Item',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.items
                      .map((i) => DropdownMenuItem(
                            value: i.id,
                            child: Text(
                              '${i.name}  (on hand: ${i.onHandQty.toStringAsFixed(2)} ${i.unitOfMeasure})',
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _itemId = v;
                      final i = widget.items.firstWhere((x) => x.id == v);
                      _unitCost.text = i.unitCost.toString();
                      _salePrice.text = i.unitSalePrice?.toString() ?? '';
                    });
                  },
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _unitCost,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Unit cost',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _salePrice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bill rate',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _billable,
                onChanged: (v) => setState(() => _billable = v),
                title: const Text('Billable to client'),
                subtitle: const Text(
                  'Off = internal use; excluded from client invoices.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_itemId == null) return;
            final qty = double.tryParse(_qty.text.trim());
            final cost = double.tryParse(_unitCost.text.trim());
            if (qty == null || qty <= 0 || cost == null) return;
            Navigator.of(context).pop(_IssueResult(
              itemId: _itemId!,
              quantity: qty,
              unitCost: cost,
              salePrice: double.tryParse(_salePrice.text.trim()),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              billable: _billable,
            ));
          },
          child: Text(_isEdit ? 'Save' : 'Issue'),
        ),
      ],
    );
  }
}
