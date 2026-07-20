import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/common/list_skeleton.dart';
import 'vendor_portal_shell.dart';

class VendorPortalBidsScreen extends StatefulWidget {
  const VendorPortalBidsScreen({super.key});

  @override
  State<VendorPortalBidsScreen> createState() => _VendorPortalBidsScreenState();
}

class _VendorPortalBidsScreenState extends State<VendorPortalBidsScreen> {
  final _service = ServiceLocator.vendorPortalService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bids = [];

  @override
  void initState() {
    super.initState();
    if (!_service.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/vendor-portal');
      });
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bids = await _service.getBidPackages();
      if (!mounted) return;
      setState(() {
        _bids = bids;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load bids.';
        _loading = false;
      });
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'responded':
        return AppColors.success;
      case 'viewed':
        return AppColors.warning;
      case 'sent':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return VendorPortalShell(
      title: 'Bid Requests',
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const ListSkeleton()
            : _error != null
                ? Center(child: Text(_error!))
                : _bids.isEmpty
                    ? const Center(child: Text('No bid requests yet.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        itemCount: _bids.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final b = _bids[i];
                          final status = b['status'] as String?;
                          return Card(
                            child: ListTile(
                              title: Text(
                                  b['template_name'] as String? ?? 'Bid Request'),
                              subtitle: Text(
                                  b['project_name'] as String? ?? 'Project'),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  (status ?? 'draft').toUpperCase(),
                                  style: TextStyle(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11),
                                ),
                              ),
                              onTap: () async {
                                final updated = await Navigator.of(context).push(
                                  MaterialPageRoute<bool>(
                                    builder: (_) =>
                                        VendorBidRespondScreen(bid: b),
                                  ),
                                );
                                if (updated == true) _load();
                              },
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

/// Bid response form: vendor enters a price per line item and an overall note.
class VendorBidRespondScreen extends StatefulWidget {
  final Map<String, dynamic> bid;
  const VendorBidRespondScreen({super.key, required this.bid});

  @override
  State<VendorBidRespondScreen> createState() => _VendorBidRespondScreenState();
}

class _VendorBidRespondScreenState extends State<VendorBidRespondScreen> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, TextEditingController> _noteControllers = {};
  bool _submitting = false;
  String? _error;

  List<Map<String, dynamic>> get _lineItems {
    final raw = widget.bid['line_items'];
    if (raw is List) {
      return raw
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((m) =>
              (m['id'] as String?) != null &&
              (m['type'] as String? ?? 'item') == 'item')
          .toList();
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    for (final li in _lineItems) {
      final id = li['id'] as String;
      _priceControllers[id] = TextEditingController(
        text: (li['vendorBidPrice'] as num?)?.toString() ?? '',
      );
      _noteControllers[id] = TextEditingController(
        text: (li['vendorBidNote'] as String?) ?? '',
      );
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    for (final c in _priceControllers.values) c.dispose();
    for (final c in _noteControllers.values) c.dispose();
    super.dispose();
  }

  double get _runningTotal {
    double t = 0;
    for (final li in _lineItems) {
      final qty = (li['quantity'] as num?)?.toDouble() ?? 1;
      final txt = _priceControllers[li['id']]?.text.trim() ?? '';
      final price = double.tryParse(txt);
      if (price != null) t += qty * price;
    }
    return t;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final bids = <Map<String, dynamic>>[];
      for (final li in _lineItems) {
        final id = li['id'] as String;
        final priceText = _priceControllers[id]!.text.trim();
        final noteText = _noteControllers[id]!.text.trim();
        if (priceText.isEmpty && noteText.isEmpty) continue;
        bids.add({
          'id': id,
          if (priceText.isNotEmpty)
            'vendorBidPrice': double.tryParse(priceText),
          if (noteText.isNotEmpty) 'vendorBidNote': noteText,
        });
      }
      if (bids.isEmpty) {
        setState(() {
          _error = 'Enter at least one line item price.';
          _submitting = false;
        });
        return;
      }
      await ServiceLocator.vendorPortalService.submitBid(
        documentId: widget.bid['id'] as String,
        lineItemBids: bids,
        overallNote: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bid submitted')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Submit failed: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respond to Bid')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        widget.bid['template_name'] as String? ?? 'Bid Request',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(widget.bid['project_name'] as String? ?? '',
                        style:
                            const TextStyle(color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_lineItems.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.base),
                  child: Text('No line items on this bid request.'),
                ),
              )
            else
              ..._lineItems.map((li) => _buildLineItemCard(li)),
            const SizedBox(height: 12),
            Card(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    const Text('Bid Total',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('\$${_runningTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Overall note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 8),
            ],
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Submitting…' : 'Submit Bid'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemCard(Map<String, dynamic> li) {
    final id = li['id'] as String;
    final desc = li['description'] as String? ?? '';
    final qty = (li['quantity'] as num?)?.toDouble() ?? 1;
    final unit = li['unit'] as String? ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(desc, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Qty: $qty${unit.isNotEmpty ? " $unit" : ""}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textTertiary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceControllers[id],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Unit price',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _noteControllers[id],
                    decoration: const InputDecoration(
                      labelText: 'Line note',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
