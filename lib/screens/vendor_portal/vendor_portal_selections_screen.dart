import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/common/list_skeleton.dart';
import 'vendor_portal_shell.dart';

/// Read-only view of the client's APPROVED selections for projects the vendor
/// is assigned to (via a work order). Lets crews/subs see final material
/// choices to purchase. Scoping is enforced server-side.
class VendorPortalSelectionsScreen extends StatefulWidget {
  const VendorPortalSelectionsScreen({super.key});

  @override
  State<VendorPortalSelectionsScreen> createState() =>
      _VendorPortalSelectionsScreenState();
}

class _VendorPortalSelectionsScreenState
    extends State<VendorPortalSelectionsScreen> {
  final _service = ServiceLocator.vendorPortalService;
  final _money = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

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
      final rows = await _service.getSelections();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load selections.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VendorPortalShell(
      title: 'Selections',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ListSkeleton();
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No approved selections for your assigned projects yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Group by project.
    final byProject = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      final pn = (r['project_name'] ?? 'Project').toString();
      byProject.putIfAbsent(pn, () => []).add(r);
    }
    final projects = byProject.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (final pn in projects) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
              child: Text(pn,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final r in byProject[pn]!) _row(r),
          ],
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final area = (r['location'] ?? '').toString();
    final chosen = (r['option_name'] ?? '—').toString();
    final vendor = (r['option_vendor'] ?? '').toString();
    final sku = (r['option_sku'] ?? '').toString();
    final qty = (r['option_qty'] as num?)?.toDouble() ?? 1;
    final amount = (r['selected_amount'] as num?)?.toDouble() ?? 0;
    final subtitle = [
      if (vendor.isNotEmpty) vendor,
      if (sku.isNotEmpty) 'SKU $sku',
      if (qty != 1) 'Qty ${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [if (area.isNotEmpty) area, r['name']?.toString() ?? '']
                        .where((e) => e.isNotEmpty)
                        .join(' — '),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 2),
                  Text(chosen,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            Text(_money.format(amount),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
