import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import 'package:intl/intl.dart';

import '../../services/supabase/holdback_service.dart';
import '../../utils/numeric_input.dart';

/// Shows a dialog that lets the user stamp a holdback % onto an existing
/// invoice (generated_documents row). Returns `true` if the invoice was
/// updated.
Future<bool?> showApplyHoldbackDialog(
  BuildContext context, {
  required String invoiceId,
  required double invoiceSubtotal,
  String? invoiceNumber,
  double currentPercent = 0,
  double? defaultPercent,
}) {
  return showFormPopup<bool>(
    context,
    icon: Icons.account_balance_wallet,
    title: 'Apply Holdback to Invoice',
    width: 380,
    builder: (ctx, scrollController) => _ApplyHoldbackContent(
      invoiceId: invoiceId,
      invoiceSubtotal: invoiceSubtotal,
      invoiceNumber: invoiceNumber,
      currentPercent: currentPercent,
      defaultPercent: defaultPercent,
      scrollController: scrollController,
    ),
  );
}

class _ApplyHoldbackContent extends StatefulWidget {
  final String invoiceId;
  final String? invoiceNumber;
  final double invoiceSubtotal;
  final double currentPercent;
  final double? defaultPercent;
  final ScrollController? scrollController;

  const _ApplyHoldbackContent({
    required this.invoiceId,
    required this.invoiceSubtotal,
    this.invoiceNumber,
    this.currentPercent = 0,
    this.defaultPercent,
    this.scrollController,
  });

  @override
  State<_ApplyHoldbackContent> createState() => _ApplyHoldbackContentState();
}

class _ApplyHoldbackContentState extends State<_ApplyHoldbackContent> {
  final _svc = HoldbackService();
  final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

  late final TextEditingController _pctCtl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.currentPercent > 0
        ? widget.currentPercent
        : (widget.defaultPercent ?? 10);
    _pctCtl = TextEditingController(text: initial.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _pctCtl.dispose();
    super.dispose();
  }

  double get _percent => double.tryParse(_pctCtl.text.trim()) ?? 0;
  double get _amount => widget.invoiceSubtotal * _percent / 100;

  Future<void> _save() async {
    if (_percent < 0 || _percent > 100) {
      setState(() => _error = 'Percent must be between 0 and 100.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _svc.applyHoldbackToInvoice(
        invoiceId: widget.invoiceId,
        percent: _percent,
        amount: _amount,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to apply holdback: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.invoiceNumber == null
                      ? 'Invoice subtotal: ${_money.format(widget.invoiceSubtotal)}'
                      : 'Invoice ${widget.invoiceNumber} · ${_money.format(widget.invoiceSubtotal)}',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pctCtl,
                  keyboardType: NumericInput.keyboard,
                  inputFormatters: NumericInput.percent(signed: false),
                  decoration: const InputDecoration(
                    labelText: 'Holdback %',
                    border: OutlineInputBorder(),
                    suffixText: '%',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Holdback withheld:',
                          style: TextStyle(fontSize: 13)),
                      Text(_money.format(_amount),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        FormPopupFooter(
          onCancel:
              _saving ? null : () => Navigator.of(context).pop(false),
          onSubmit: _saving ? null : _save,
          submitLabel: 'Apply',
          busy: _saving,
        ),
      ],
    );
  }
}
