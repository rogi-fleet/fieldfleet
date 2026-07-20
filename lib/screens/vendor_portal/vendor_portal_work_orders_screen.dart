import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/common/list_skeleton.dart';
import 'vendor_portal_shell.dart';

class VendorPortalWorkOrdersScreen extends StatefulWidget {
  const VendorPortalWorkOrdersScreen({super.key});

  @override
  State<VendorPortalWorkOrdersScreen> createState() =>
      _VendorPortalWorkOrdersScreenState();
}

class _VendorPortalWorkOrdersScreenState
    extends State<VendorPortalWorkOrdersScreen> {
  final _service = ServiceLocator.vendorPortalService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _wos = [];

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
      final wos = await _service.getWorkOrders();
      if (!mounted) return;
      setState(() {
        _wos = wos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load work orders.';
        _loading = false;
      });
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'in_progress':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'on_hold':
        return AppColors.activityAccent;
      case 'issued':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _acknowledge(Map<String, dynamic> wo) async {
    final result = await showDialog<_AckResult>(
      context: context,
      builder: (_) => _AckDialog(workOrder: wo),
    );
    if (result == null) return;
    try {
      await _service.acknowledgeWorkOrder(
        workOrderId: wo['id'] as String,
        accept: result.accept,
        signerName: result.signerName,
        note: result.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(result.accept ? 'Work order accepted' : 'Work order declined'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Acknowledgement failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return VendorPortalShell(
      title: 'Work Orders',
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const ListSkeleton()
            : _error != null
                ? Center(child: Text(_error!))
                : _wos.isEmpty
                    ? const Center(child: Text('No work orders assigned.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        itemCount: _wos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final w = _wos[i];
                          final status = w['status'] as String?;
                          final start = w['scheduled_start'] as String?;
                          final fmt = DateFormat.yMMMd();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.base),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${w['number']}  ·  ${w['title']}',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                                        decoration: BoxDecoration(
                                          color: _statusColor(status)
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          (status ?? '').toUpperCase(),
                                          style: TextStyle(
                                              color: _statusColor(status),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(w['project_name'] as String? ?? '',
                                      style: const TextStyle(
                                          color: AppColors.textTertiary)),
                                  if ((w['scope_of_work'] as String?)
                                          ?.isNotEmpty ??
                                      false) ...[
                                    const SizedBox(height: 8),
                                    Text(w['scope_of_work'] as String),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    if (start != null)
                                      _meta(Icons.event,
                                          'Start ${fmt.format(DateTime.parse(start).toLocal())}'),
                                    if ((w['location'] as String?)?.isNotEmpty ??
                                        false)
                                      _meta(Icons.place, w['location'] as String),
                                    if ((w['total_amount'] as num?) != null)
                                      _meta(Icons.attach_money,
                                          '\$${(w['total_amount'] as num).toStringAsFixed(2)}'),
                                  ]),
                                  if (status == 'issued' ||
                                      status == 'on_hold') ...[
                                    const Divider(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.close),
                                          label: const Text('Decline'),
                                          onPressed: () => _acknowledge(w),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          icon: const Icon(Icons.check),
                                          label: const Text('Accept'),
                                          onPressed: () => _acknowledge(w),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textTertiary)),
        ]),
      );
}

class _AckResult {
  final bool accept;
  final String? signerName;
  final String? note;
  _AckResult(this.accept, this.signerName, this.note);
}

class _AckDialog extends StatefulWidget {
  final Map<String, dynamic> workOrder;
  const _AckDialog({required this.workOrder});

  @override
  State<_AckDialog> createState() => _AckDialogState();
}

class _AckDialogState extends State<_AckDialog> {
  final _signerController = TextEditingController();
  final _noteController = TextEditingController();
  bool _accept = true;

  @override
  void dispose() {
    _signerController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Acknowledge ${widget.workOrder['number']}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<bool>(
              value: true,
              groupValue: _accept,
              dense: true,
              title: const Text('Accept and start work'),
              onChanged: (v) => setState(() => _accept = v ?? true),
            ),
            RadioListTile<bool>(
              value: false,
              groupValue: _accept,
              dense: true,
              title: const Text('Decline (put on hold)'),
              onChanged: (v) => setState(() => _accept = v ?? false),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _signerController,
              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _AckResult(
              _accept,
              _signerController.text.trim().isEmpty
                  ? null
                  : _signerController.text.trim(),
              _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
            ),
          ),
          child: Text(_accept ? 'Accept' : 'Decline'),
        ),
      ],
    );
  }
}
