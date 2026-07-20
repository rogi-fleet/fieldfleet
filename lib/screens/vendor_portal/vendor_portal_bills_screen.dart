import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/common/list_skeleton.dart';
import 'vendor_portal_shell.dart';

class VendorPortalBillsScreen extends StatefulWidget {
  const VendorPortalBillsScreen({super.key});

  @override
  State<VendorPortalBillsScreen> createState() =>
      _VendorPortalBillsScreenState();
}

class _VendorPortalBillsScreenState extends State<VendorPortalBillsScreen> {
  final _service = ServiceLocator.vendorPortalService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _pos = [];

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
      final results = await Future.wait([
        _service.getBills(),
        _service.getPurchaseOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _bills = results[0];
        _pos = results[1];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load bills.';
        _loading = false;
      });
    }
  }

  Future<void> _newBill() async {
    if (_pos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No active purchase orders to bill against. Contact the project team.')),
      );
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _SubmitBillDialog(purchaseOrders: _pos),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd();
    return VendorPortalShell(
      title: 'Bills',
      actions: [
        IconButton(
          tooltip: 'Submit Bill',
          icon: const Icon(Icons.add),
          onPressed: _newBill,
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const ListSkeleton()
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    children: [
                      _section(
                          'Open Purchase Orders (${_pos.length})', _buildPos()),
                      const SizedBox(height: 16),
                      _section(
                          'Submitted Bills (${_bills.length})',
                          _bills.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(AppSpacing.base),
                                  child: Text('No bills submitted yet.'),
                                )
                              : Column(
                                  children: _bills
                                      .map((b) => _billTile(b, fmt))
                                      .toList(),
                                )),
                    ],
                  ),
      ),
    );
  }

  Widget _section(String label, Widget child) => Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ),
            const Divider(height: 1),
            child,
          ],
        ),
      );

  Widget _buildPos() {
    if (_pos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.base),
        child: Text('No open POs.'),
      );
    }
    return Column(
      children: _pos.map((po) {
        final total = (po['total'] as num?)?.toDouble() ?? 0;
        final billed = (po['billed_total'] as num?)?.toDouble() ?? 0;
        final remaining = total - billed;
        return ListTile(
          title: Text(po['purchase_order_number'] as String? ?? 'PO'),
          subtitle: Text(
              '${po['project_name'] ?? ""}  ·  \$${remaining.toStringAsFixed(2)} unbilled of \$${total.toStringAsFixed(2)}'),
          trailing: TextButton(
            child: const Text('Bill'),
            onPressed: () async {
              final r = await showDialog<bool>(
                context: context,
                builder: (_) => _SubmitBillDialog(
                  purchaseOrders: _pos,
                  initialPoId: po['id'] as String,
                ),
              );
              if (r == true) _load();
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _billTile(Map<String, dynamic> b, DateFormat fmt) {
    final status = b['status'] as String?;
    final dateStr = b['bill_date'] as String?;
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
    return ListTile(
      title: Text(b['bill_number'] as String? ?? '—'),
      subtitle: Text(
          '${b['project_name'] ?? ""}${date != null ? "  ·  ${fmt.format(date)}" : ""}'),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('\$${(b['total'] as num?)?.toStringAsFixed(2) ?? "0.00"}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text((status ?? '').toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _SubmitBillDialog extends StatefulWidget {
  final List<Map<String, dynamic>> purchaseOrders;
  final String? initialPoId;
  const _SubmitBillDialog({required this.purchaseOrders, this.initialPoId});

  @override
  State<_SubmitBillDialog> createState() => _SubmitBillDialogState();
}

class _SubmitBillDialogState extends State<_SubmitBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _billNumberController = TextEditingController();
  final _notesController = TextEditingController();
  String? _selectedPoId;
  DateTime _billDate = DateTime.now();
  DateTime? _dueDate;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedPoId =
        widget.initialPoId ?? widget.purchaseOrders.first['id'] as String?;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _billNumberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isDueDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isDueDate ? (_dueDate ?? DateTime.now()) : _billDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isDueDate) {
          _dueDate = picked;
        } else {
          _billDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedPoId == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ServiceLocator.vendorPortalService.submitBill(
        purchaseOrderId: _selectedPoId!,
        amount: double.parse(_amountController.text.trim()),
        billNumber: _billNumberController.text.trim().isEmpty
            ? null
            : _billNumberController.text.trim(),
        billDate: _billDate,
        dueDate: _dueDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill submitted')),
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
    final fmt = DateFormat.yMMMd();
    return AlertDialog(
      title: const Text('Submit Bill'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedPoId,
                decoration: const InputDecoration(
                  labelText: 'Purchase Order',
                  border: OutlineInputBorder(),
                ),
                items: widget.purchaseOrders.map((po) {
                  return DropdownMenuItem(
                    value: po['id'] as String,
                    child: Text(
                        '${po['purchase_order_number']} · ${po['project_name'] ?? ""}'),
                  );
                }).toList(),
                validator: (v) => v == null ? 'Select a PO' : null,
                onChanged: (v) => setState(() => _selectedPoId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a positive number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _billNumberController,
                decoration: const InputDecoration(
                  labelText: 'Bill / Invoice number (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Bill date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(fmt.format(_billDate)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Due date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                            _dueDate != null ? fmt.format(_dueDate!) : '—'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Submitting…' : 'Submit'),
        ),
      ],
    );
  }
}
