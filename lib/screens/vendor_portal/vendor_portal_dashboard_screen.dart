import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'vendor_portal_shell.dart';

class VendorPortalDashboardScreen extends StatefulWidget {
  const VendorPortalDashboardScreen({super.key});

  @override
  State<VendorPortalDashboardScreen> createState() =>
      _VendorPortalDashboardScreenState();
}

class _VendorPortalDashboardScreenState
    extends State<VendorPortalDashboardScreen> {
  final _service = ServiceLocator.vendorPortalService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _bids = [];
  List<Map<String, dynamic>> _workOrders = [];
  List<Map<String, dynamic>> _bills = [];

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
        _service.getVendors(),
        _service.getBidPackages(),
        _service.getWorkOrders(),
        _service.getBills(),
      ]);
      if (!mounted) return;
      setState(() {
        _vendors = results[0];
        _bids = results[1];
        _workOrders = results[2];
        _bills = results[3];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load your dashboard. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingBids =
        _bids.where((b) => (b['status'] as String?) != 'responded').length;
    final pendingWos = _workOrders
        .where((w) => (w['status'] as String?) == 'issued')
        .length;
    final activeWos = _workOrders
        .where((w) => (w['status'] as String?) == 'in_progress')
        .length;

    return VendorPortalShell(
      title: 'Vendor Portal',
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      if (_vendors.isEmpty)
                        _NoAccessCard(email: _service.getPortalEmail() ?? '')
                      else ...[
                        _VendorHeader(vendors: _vendors),
                        const SizedBox(height: 20),
                        _KpiRow(items: [
                          _Kpi(
                              label: 'Open Bids',
                              value: '$pendingBids',
                              color: AppColors.warning,
                              onTap: () => context.go('/vendor-portal/bids')),
                          _Kpi(
                              label: 'Awaiting Acceptance',
                              value: '$pendingWos',
                              color: AppColors.info,
                              onTap: () =>
                                  context.go('/vendor-portal/work-orders')),
                          _Kpi(
                              label: 'Active WOs',
                              value: '$activeWos',
                              color: AppColors.success,
                              onTap: () =>
                                  context.go('/vendor-portal/work-orders')),
                          _Kpi(
                              label: 'Bills Submitted',
                              value: '${_bills.length}',
                              color: const Color(0xFF6366F1),
                              onTap: () => context.go('/vendor-portal/bills')),
                        ]),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _VendorHeader extends StatelessWidget {
  final List<Map<String, dynamic>> vendors;
  const _VendorHeader({required this.vendors});

  @override
  Widget build(BuildContext context) {
    final names = vendors.map((v) => v['company_name'] as String? ?? '—').toSet();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            const Icon(Icons.business, size: 32, color: Color(0xFF0F766E)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(names.join(' · '),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Signed in to ${vendors.length} vendor record${vendors.length == 1 ? "" : "s"}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final List<_Kpi> items;
  const _KpiRow({required this.items});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth < AppBreakpoints.mobile ? 2 : 4;
      return GridView.count(
        crossAxisCount: cols,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.8,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: items,
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
  const _Kpi(
      {required this.label,
      required this.value,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoAccessCard extends StatelessWidget {
  final String email;
  const _NoAccessCard({required this.email});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(children: [
          const Icon(Icons.info_outline, size: 40, color: AppColors.warning),
          const SizedBox(height: 12),
          const Text('No vendor records linked to your email',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'You are signed in as $email, but no active vendor contact exists '
            'for that address. Ask the project team to add you as a vendor '
            'contact in their workspace, then try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textTertiary),
          ),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.error),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
