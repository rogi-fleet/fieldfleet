import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/calendar_event.dart';

/// Aggregates calendar events from all modules in the workspace.
/// Each fetch method is wrapped in try-catch so a single failing query
/// never blocks the rest of the calendar from loading.
class CalendarAggregatorService {
  /// Day-aware "past due": date-only values (stored at exactly midnight)
  /// mean "due that day" and only become overdue once the day ends.
  /// Mirrors Task.isOverdue().
  static bool _pastDue(DateTime due, DateTime now) {
    final hasTime = due.hour != 0 || due.minute != 0 || due.second != 0;
    if (hasTime) return due.isBefore(now);
    final endOfDay =
        DateTime(due.year, due.month, due.day).add(const Duration(days: 1));
    return !now.isBefore(endOfDay);
  }

  final SupabaseClient _db = Supabase.instance.client;
  final String workspaceId;

  CalendarAggregatorService({required this.workspaceId});

  Future<List<CalendarEvent>> fetchEvents() async {
    final results = await Future.wait(
      [
        _fetchTasks(),
        _fetchProjects(),
        _fetchInvoices(),
        _fetchBills(),
        _fetchBidPackages(),
        _fetchRentals(),
        _fetchPurchaseOrders(),
      ],
      eagerError: false,
    );

    final events = <CalendarEvent>[];
    for (final list in results) {
      events.addAll(list);
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Combine the flat customer-style address fields into a single line.
  String? _composeAddress({
    String? line,
    String? city,
    String? state,
    String? zip,
    String? country,
  }) {
    final parts = <String>[];
    if (line != null && line.trim().isNotEmpty) parts.add(line.trim());
    final cityState = [
      if (city != null && city.trim().isNotEmpty) city.trim(),
      if (state != null && state.trim().isNotEmpty) state.trim(),
    ].join(', ');
    if (cityState.isNotEmpty) parts.add(cityState);
    if (zip != null && zip.trim().isNotEmpty) parts.add(zip.trim());
    if (country != null && country.trim().isNotEmpty) parts.add(country.trim());
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  /// Returns null if the value is null OR empty/whitespace.
  String? _nz(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// Pull job#/customer/address from a nested `project` select payload.
  ({
    String? jobNumber,
    String? jobName,
    String? customerName,
    String? customerAddress,
  }) _extractProject(dynamic projectField) {
    if (projectField is! Map) {
      return (
        jobNumber: null,
        jobName: null,
        customerName: null,
        customerAddress: null,
      );
    }
    final p = projectField.cast<String, dynamic>();
    final serial = _nz(p['serial_number']);
    final jobNum = serial != null ? '#$serial' : null;
    final jobName = _nz(p['name']);
    String? customerName = _nz(p['customer_name']);
    String? address = _nz(p['address']);

    // If project has no cached customer/address, try the joined client.
    final client = p['client'];
    if (client is Map) {
      final c = client.cast<String, dynamic>();
      customerName ??= _nz(c['company_name']);
      address ??= _composeAddress(
        line: _nz(c['address']),
        city: _nz(c['city']),
        state: _nz(c['state']),
        zip: _nz(c['zip_code']),
        country: _nz(c['country']),
      );
    }
    return (
      jobNumber: jobNum,
      jobName: jobName,
      customerName: customerName,
      customerAddress: address,
    );
  }

  // ---------------------------------------------------------------------------
  // Per-source fetchers
  // ---------------------------------------------------------------------------

  Future<List<CalendarEvent>> _fetchTasks() async {
    try {
      final rows = await _db
          .from('tasks')
          .select(
              'id, title, description, due_date, status, priority, '
              'project:projects(serial_number, name, customer_name, address, '
              'client:customers(company_name, address, city, state, zip_code, country))')
          .eq('workspace_id', workspaceId)
          .not('due_date', 'is', null)
          .neq('status', 'done');
      final now = DateTime.now();
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final dueDate =
            DateTime.tryParse(r['due_date'] as String? ?? '') ?? now;
        final p = _extractProject(r['project']);
        final extras = <String, String>{};
        final priority = r['priority'] as String?;
        if (priority != null && priority.isNotEmpty) {
          extras['Priority'] = priority;
        }
        final desc = r['description'] as String?;
        if (desc != null && desc.trim().isNotEmpty) {
          extras['Description'] = desc;
        }
        return CalendarEvent(
          id: r['id'] as String? ?? 'task_$dueDate',
          title: r['title'] as String? ?? 'Task',
          subtitle: r['status'] as String?,
          date: dueDate,
          type: CalendarEventType.task,
          route: '/tasks',
          isOverdue: _pastDue(dueDate, now),
          status: r['status'] as String?,
          jobNumber: p.jobNumber,
            jobName: p.jobName,
          customerName: p.customerName,
          customerAddress: p.customerAddress,
          extraDetails: extras.isEmpty ? null : extras,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<CalendarEvent>> _fetchProjects() async {
    try {
      final rows = await _db
          .from('projects')
          .select(
              'id, name, start_date, target_completion_date, status, '
              'serial_number, customer_name, address, '
              'client:customers(company_name, address, city, state, zip_code, country)')
          .eq('workspace_id', workspaceId);
      final events = <CalendarEvent>[];
      final now = DateTime.now();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final title = r['name'] as String? ?? 'Project';
        final status = r['status'] as String?;
        if (status == 'archived') continue;
        final id = r['id'] as String? ?? '';
        // The project itself is the project payload.
        final p = _extractProject(r);
        if (r['start_date'] != null) {
          events.add(CalendarEvent(
            id: '${id}_start',
            title: title,
            subtitle: 'Project start',
            date: DateTime.parse(r['start_date'] as String),
            type: CalendarEventType.project,
            route: '/projects/$id',
            status: status,
            jobNumber: p.jobNumber,
            jobName: p.jobName,
            customerName: p.customerName,
            customerAddress: p.customerAddress,
          ));
        }
        if (r['target_completion_date'] != null) {
          final deadline =
              DateTime.parse(r['target_completion_date'] as String);
          events.add(CalendarEvent(
            id: '${id}_end',
            title: title,
            subtitle: 'Deadline',
            date: deadline,
            type: CalendarEventType.project,
            route: '/projects/$id',
            isOverdue: _pastDue(deadline, now),
            status: status,
            jobNumber: p.jobNumber,
            jobName: p.jobName,
            customerName: p.customerName,
            customerAddress: p.customerAddress,
          ));
        }
      }
      return events;
    } catch (_) {
      return [];
    }
  }

  Future<List<CalendarEvent>> _fetchInvoices() async {
    try {
      final rows = await _db
          .from('generated_documents')
          .select(
              'id, document_number, customer_name, due_date, status, '
              'total_amount, paid_date, '
              'project:projects(serial_number, name, customer_name, address, '
              'client:customers(company_name, address, city, state, zip_code, country))')
          .eq('workspace_id', workspaceId)
          .inFilter('document_type',
              ['invoice', 'progress_invoice', 'aia_pay_app', 'deposit'])
          .not('due_date', 'is', null);
      final now = DateTime.now();
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final dueDate = DateTime.parse(r['due_date'] as String);
        final status = r['status'] as String?;
        final paid = r['paid_date'] != null;
        final p = _extractProject(r['project']);
        final custName = _nz(r['customer_name']) ?? p.customerName;
        final extras = <String, String>{};
        final total = r['total_amount'];
        if (total != null) {
          extras['Amount'] = '\$${total.toString()}';
        }
        final invoiceNo = _nz(r['document_number']);
        return CalendarEvent(
          id: r['id'] as String? ?? 'inv_$dueDate',
          title: invoiceNo != null ? 'Invoice $invoiceNo' : 'Invoice',
          subtitle: custName,
          date: dueDate,
          type: CalendarEventType.invoice,
          route: '/financials',
          isOverdue: _pastDue(dueDate, now) && !paid,
          status: status,
          jobNumber: p.jobNumber,
          jobName: p.jobName,
          customerName: custName,
          customerAddress: p.customerAddress,
          extraDetails: extras.isEmpty ? null : extras,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<CalendarEvent>> _fetchBills() async {
    try {
      final rows = await _db
          .from('generated_documents')
          .select(
              'id, document_number, due_date, status, total_amount, '
              'paid_date, vendor:vendors(name), '
              'project:projects(serial_number, name, customer_name, address, '
              'client:customers(company_name, address, city, state, zip_code, country))')
          .eq('workspace_id', workspaceId)
          .inFilter('document_type', ['bill', 'expense'])
          .not('due_date', 'is', null);
      final now = DateTime.now();
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final dueDate = DateTime.parse(r['due_date'] as String);
        final status = r['status'] as String?;
        final paid = r['paid_date'] != null;
        final p = _extractProject(r['project']);
        String? vendor;
        final v = r['vendor'];
        if (v is Map) vendor = _nz(v.cast<String, dynamic>()['name']);
        final extras = <String, String>{};
        final total = r['total_amount'];
        if (total != null) {
          extras['Amount'] = '\$${total.toString()}';
        }
        if (p.customerName != null) {
          extras['Project Customer'] = p.customerName!;
        }
        final billNo = _nz(r['document_number']);
        return CalendarEvent(
          id: r['id'] as String? ?? 'bill_$dueDate',
          title: billNo != null ? 'Bill $billNo' : 'Bill',
          subtitle: vendor ?? 'Bill due',
          date: dueDate,
          type: CalendarEventType.bill,
          route: '/financials',
          isOverdue: _pastDue(dueDate, now) && !paid,
          status: status,
          jobNumber: p.jobNumber,
          jobName: p.jobName,
          customerName: p.customerName,
          customerAddress: p.customerAddress,
          extraDetails: extras.isEmpty ? null : extras,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<CalendarEvent>> _fetchBidPackages() async {
    try {
      final rows = await _db
          .from('bid_packages')
          .select(
              'id, name, due_date, status, '
              'project:projects(serial_number, name, customer_name, address, '
              'client:customers(company_name, address, city, state, zip_code, country))')
          .eq('workspace_id', workspaceId)
          .not('due_date', 'is', null);
      final now = DateTime.now();
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final dueDate = DateTime.parse(r['due_date'] as String);
        final p = _extractProject(r['project']);
        return CalendarEvent(
          id: r['id'] as String? ?? 'bid_$dueDate',
          title: r['name'] as String? ?? 'Bid Package',
          subtitle: 'Bid deadline',
          date: dueDate,
          type: CalendarEventType.bidPackage,
          isOverdue: _pastDue(dueDate, now),
          status: r['status'] as String?,
          jobNumber: p.jobNumber,
            jobName: p.jobName,
          customerName: p.customerName,
          customerAddress: p.customerAddress,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<CalendarEvent>> _fetchRentals() async {
    try {
      final rows = await _db
          .from('equipment_rentals')
          .select(
              'id, start_date, end_date, project_id, '
              'project:projects(serial_number, name, customer_name, address, '
              'client:customers(company_name, address, city, state, zip_code, country)), '
              'asset:assets(name, serial_number)')
          .eq('workspace_id', workspaceId);
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final endRaw = r['end_date'] as String?;
        final p = _extractProject(r['project']);
        final extras = <String, String>{};
        final asset = r['asset'];
        if (asset is Map) {
          final a = asset.cast<String, dynamic>();
          final assetName = a['name'] as String?;
          // assets has `serial_number`, not `asset_tag` — use that as the
          // visible identifier in the calendar popup.
          final tag = a['serial_number'] as String?;
          if (assetName != null) {
            extras['Asset'] = tag != null ? '$assetName ($tag)' : assetName;
          }
        }
        String title = 'Equipment On Site';
        if (r['project'] is Map) {
          final pname = (r['project'] as Map)['name'] as String?;
          if (pname != null && pname.isNotEmpty) title = pname;
        }
        return CalendarEvent(
          id: r['id'] as String? ?? 'rental',
          title: title,
          subtitle: endRaw == null ? 'No return date set' : 'Return scheduled',
          date: DateTime.parse(r['start_date'] as String),
          endDate: endRaw != null ? DateTime.parse(endRaw) : null,
          type: CalendarEventType.rental,
          route: '/inventory',
          jobNumber: p.jobNumber,
            jobName: p.jobName,
          customerName: p.customerName,
          customerAddress: p.customerAddress,
          extraDetails: extras.isEmpty ? null : extras,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<CalendarEvent>> _fetchPurchaseOrders() async {
    try {
      final rows = await _db
          .from('inventory_purchase_orders')
          .select(
              'id, po_number, expected_date, status, '
              'project:projects(serial_number, name, customer_name, address, '
              'client:customers(company_name, address, city, state, zip_code, country)), '
              'supplier:inventory_suppliers(name)')
          .eq('workspace_id', workspaceId)
          .not('expected_date', 'is', null);
      final now = DateTime.now();
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final expected = DateTime.parse(r['expected_date'] as String);
        final status = r['status'] as String?;
        final p = _extractProject(r['project']);
        String? supplierName;
        final sup = r['supplier'];
        if (sup is Map) {
          supplierName = _nz((sup.cast<String, dynamic>())['name']);
        }
        final extras = <String, String>{};
        if (p.customerName != null) {
          extras['Project Customer'] = p.customerName!;
        }
        return CalendarEvent(
          id: r['id'] as String? ?? 'po_$expected',
          title: 'PO ${r['po_number'] ?? ''}'.trim(),
          subtitle: supplierName ?? 'Expected delivery',
          date: expected,
          type: CalendarEventType.purchaseOrder,
          route: '/inventory',
          isOverdue: _pastDue(expected, now) && status != 'received',
          status: status,
          jobNumber: p.jobNumber,
            jobName: p.jobName,
          // For POs, the counterparty is the supplier.
          customerName: supplierName,
          customerAddress: p.customerAddress,
          extraDetails: extras.isEmpty ? null : extras,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

}
