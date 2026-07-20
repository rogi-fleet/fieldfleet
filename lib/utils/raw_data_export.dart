import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'budget_export_io.dart' if (dart.library.html) 'budget_export_web.dart'
    as platform_export;

enum RawDataExportType {
  projects,
  budgets,
  catalog,
  tasks,
  customers,
  invoices,
  timeEntries,
}

extension RawDataExportTypeX on RawDataExportType {
  String get label {
    switch (this) {
      case RawDataExportType.projects:
        return 'Projects';
      case RawDataExportType.budgets:
        return 'Budgets';
      case RawDataExportType.catalog:
        return 'Catalog';
      case RawDataExportType.tasks:
        return 'Tasks';
      case RawDataExportType.customers:
        return 'Customers';
      case RawDataExportType.invoices:
        return 'Invoices';
      case RawDataExportType.timeEntries:
        return 'Time Entries';
    }
  }

  String get filePrefix {
    switch (this) {
      case RawDataExportType.projects:
        return 'projects_raw';
      case RawDataExportType.budgets:
        return 'budgets_raw';
      case RawDataExportType.catalog:
        return 'catalog_raw';
      case RawDataExportType.tasks:
        return 'tasks_raw';
      case RawDataExportType.customers:
        return 'customers_raw';
      case RawDataExportType.invoices:
        return 'invoices_raw';
      case RawDataExportType.timeEntries:
        return 'time_entries_raw';
    }
  }

  String get templateFilePrefix {
    switch (this) {
      case RawDataExportType.projects:
        return 'projects_import_template';
      case RawDataExportType.budgets:
        return 'budgets_import_template';
      case RawDataExportType.catalog:
        return 'catalog_import_template';
      case RawDataExportType.tasks:
        return 'tasks_import_template';
      case RawDataExportType.customers:
        return 'customers_import_template';
      case RawDataExportType.invoices:
        return 'invoices_import_template';
      case RawDataExportType.timeEntries:
        return 'time_entries_import_template';
    }
  }
}

class RawDataExportService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _pageSize = 1000;

  Future<void> exportType({
    required RawDataExportType type,
    required String workspaceId,
  }) async {
    final csv = await _buildCsv(type: type, workspaceId: workspaceId);
    await platform_export.exportCsv(
      csv.content,
      csv.fileName,
      'FieldFleet ${type.label} Export',
    );
  }

  Future<void> exportAll(String workspaceId) async {
    final files = <MapEntry<String, String>>[];
    for (final type in RawDataExportType.values) {
      final csv = await _buildCsv(type: type, workspaceId: workspaceId);
      files.add(MapEntry(csv.fileName, csv.content));
    }

    await platform_export.exportMultipleCsv(
      files,
      'FieldFleet Raw Data Export',
      'Raw CSV exports for projects, budgets, catalog, tasks, customers, invoices, and time entries.',
    );
  }

  Future<void> exportTemplateType(RawDataExportType type) async {
    final csv = _buildTemplateCsv(type);
    await platform_export.exportCsv(
      csv.content,
      csv.fileName,
      'FieldFleet ${type.label} Import Template',
    );
  }

  Future<void> exportAllTemplates() async {
    final files = <MapEntry<String, String>>[];
    for (final type in RawDataExportType.values) {
      final csv = _buildTemplateCsv(type);
      files.add(MapEntry(csv.fileName, csv.content));
    }
    await platform_export.exportMultipleCsv(
      files,
      'FieldFleet Import Templates',
      'CSV templates with headers and sample rows for projects, budgets, catalog, tasks, customers, invoices, and time entries.',
    );
  }

  List<CsvColumnGuide> getColumnGuide(RawDataExportType type) {
    switch (type) {
      case RawDataExportType.projects:
        return const [
          CsvColumnGuide('id', 'Unique project identifier in FieldFleet.'),
          CsvColumnGuide('name', 'Project name shown in the app.'),
          CsvColumnGuide(
            'status',
            'Project stage (bidding, active, complete).',
          ),
          CsvColumnGuide('customer_id', 'Linked customer ID (client_id).'),
          CsvColumnGuide('customer_name', 'Readable customer/company name.'),
          CsvColumnGuide('address', 'Project site address.'),
          CsvColumnGuide(
            'start_date',
            'Planned project start date/time (ISO).',
          ),
          CsvColumnGuide(
            'target_completion_date',
            'Planned target completion date/time (ISO).',
          ),
          CsvColumnGuide('estimated_budget', 'Estimated budget amount.'),
          CsvColumnGuide(
            'contract_amount',
            'Contract amount for fixed-price jobs.',
          ),
          CsvColumnGuide('created_at', 'Record creation timestamp (ISO UTC).'),
          CsvColumnGuide('updated_at', 'Last update timestamp (ISO UTC).'),
        ];
      case RawDataExportType.budgets:
        return const [
          CsvColumnGuide('id', 'Unique budget line item identifier.'),
          CsvColumnGuide(
            'project_id',
            'Parent project ID for the budget line.',
          ),
          CsvColumnGuide('project_name', 'Readable project name.'),
          CsvColumnGuide('parent_id', 'Parent budget line ID for hierarchy.'),
          CsvColumnGuide('hierarchy_level', 'Hierarchy level (0,1,2...).'),
          CsvColumnGuide('item_type', 'Type of line item/group.'),
          CsvColumnGuide('name', 'Budget line title.'),
          CsvColumnGuide('description', 'Line item notes/description.'),
          CsvColumnGuide('quantity', 'Planned quantity.'),
          CsvColumnGuide('unit', 'Unit label (ea, hr, ft, etc).'),
          CsvColumnGuide('unit_cost', 'Base cost per unit.'),
          CsvColumnGuide('markup_pct', 'Markup percentage.'),
          CsvColumnGuide('approved_price', 'Approved sell price.'),
          CsvColumnGuide('projected_cost', 'Projected cost amount.'),
          CsvColumnGuide('committed_cost', 'Committed cost amount.'),
          CsvColumnGuide('final_cost', 'Final cost once completed.'),
          CsvColumnGuide('is_complete', 'Whether line is complete.'),
          CsvColumnGuide('created_at', 'Record creation timestamp (ISO UTC).'),
          CsvColumnGuide('updated_at', 'Last update timestamp (ISO UTC).'),
        ];
      case RawDataExportType.catalog:
        return const [
          CsvColumnGuide('id', 'Unique catalog item identifier.'),
          CsvColumnGuide('name', 'Catalog item name.'),
          CsvColumnGuide('description', 'Catalog item description.'),
          CsvColumnGuide('sku', 'SKU/code used for lookup.'),
          CsvColumnGuide('category', 'Catalog category label.'),
          CsvColumnGuide('unit', 'Unit label for pricing.'),
          CsvColumnGuide('base_cost', 'Default cost per unit.'),
          CsvColumnGuide('default_price', 'Default sell price per unit.'),
          CsvColumnGuide('markup', 'Markup percentage for this item.'),
          CsvColumnGuide('margin', 'Margin percentage for this item.'),
          CsvColumnGuide('taxable', 'Whether item is taxable (true/false).'),
          CsvColumnGuide(
            'cost_type_name',
            'Optional internal cost type label.',
          ),
          CsvColumnGuide(
            'cost_code_name',
            'Optional internal cost code label.',
          ),
          CsvColumnGuide('image_url', 'Optional image reference URL.'),
          CsvColumnGuide('item_type', 'Hierarchy item type.'),
          CsvColumnGuide('parent_id', 'Parent catalog item ID.'),
          CsvColumnGuide('hierarchy_level', 'Catalog hierarchy depth.'),
          CsvColumnGuide(
            'sort_order',
            'Sibling order within the parent group.',
          ),
          CsvColumnGuide('created_at', 'Record creation timestamp (ISO UTC).'),
          CsvColumnGuide('updated_at', 'Last update timestamp (ISO UTC).'),
        ];
      case RawDataExportType.tasks:
        return const [
          CsvColumnGuide('id', 'Unique task identifier.'),
          CsvColumnGuide('project_id', 'Parent project ID.'),
          CsvColumnGuide('project_name', 'Readable project name.'),
          CsvColumnGuide('title', 'Task title.'),
          CsvColumnGuide(
            'status',
            'Task status (not_started, working_on_it, done, stuck).',
          ),
          CsvColumnGuide('priority', 'Task priority (low, medium, high).'),
          CsvColumnGuide('assignee_id', 'Primary assigned user ID.'),
          CsvColumnGuide('assignee_name', 'Primary assigned user name/email.'),
          CsvColumnGuide('due_date', 'Task due date/time (ISO).'),
          CsvColumnGuide('start_date', 'Task start date/time (ISO).'),
          CsvColumnGuide('completed_at', 'Task completion timestamp (ISO).'),
          CsvColumnGuide('progress', 'Task completion percent (0-100).'),
          CsvColumnGuide('estimated_hours', 'Estimated duration in hours.'),
          CsvColumnGuide('created_at', 'Record creation timestamp (ISO UTC).'),
          CsvColumnGuide('updated_at', 'Last update timestamp (ISO UTC).'),
        ];
      case RawDataExportType.customers:
        return const [
          CsvColumnGuide('id', 'Unique customer identifier.'),
          CsvColumnGuide('company_name', 'Customer company name.'),
          CsvColumnGuide('customer_type', 'Customer type classification.'),
          CsvColumnGuide('primary_contact_name', 'Primary contact full name.'),
          CsvColumnGuide(
            'primary_contact_email',
            'Primary contact email address.',
          ),
          CsvColumnGuide(
            'primary_contact_phone',
            'Primary contact phone number.',
          ),
          CsvColumnGuide('address', 'Street address.'),
          CsvColumnGuide('city', 'City.'),
          CsvColumnGuide('state', 'State or province.'),
          CsvColumnGuide('zip_code', 'Postal/ZIP code.'),
          CsvColumnGuide('is_active', 'Customer active flag (true/false).'),
          CsvColumnGuide('created_at', 'Record creation timestamp (ISO UTC).'),
          CsvColumnGuide('updated_at', 'Last update timestamp (ISO UTC).'),
        ];
      case RawDataExportType.invoices:
        return const [
          CsvColumnGuide('id', 'Unique invoice identifier.'),
          CsvColumnGuide('project_id', 'Related project ID.'),
          CsvColumnGuide('project_name', 'Readable project name.'),
          CsvColumnGuide('invoice_number', 'Invoice number shown to clients.'),
          CsvColumnGuide('status', 'Invoice status (draft, sent, paid, etc).'),
          CsvColumnGuide(
            'issue_date',
            'Invoice issue timestamp (uses created_at).',
          ),
          CsvColumnGuide('due_date', 'Invoice due timestamp (ISO).'),
          CsvColumnGuide('paid_date', 'Invoice paid timestamp (ISO).'),
          CsvColumnGuide('subtotal', 'Subtotal before taxes.'),
          CsvColumnGuide('tax', 'Tax amount.'),
          CsvColumnGuide('total', 'Invoice total amount.'),
          CsvColumnGuide('created_at', 'Record creation timestamp (ISO UTC).'),
          CsvColumnGuide('updated_at', 'Last update timestamp (ISO UTC).'),
        ];
      case RawDataExportType.timeEntries:
        return const [
          CsvColumnGuide('id', 'Unique time entry identifier.'),
          CsvColumnGuide('project_id', 'Related project ID.'),
          CsvColumnGuide('project_name', 'Readable project name.'),
          CsvColumnGuide('worker_id', 'User ID for worker.'),
          CsvColumnGuide('worker_name', 'Worker display name/email.'),
          CsvColumnGuide('date', 'Work date (ISO).'),
          CsvColumnGuide('regular_hours', 'Regular hours worked.'),
          CsvColumnGuide('overtime_hours', 'Overtime hours worked.'),
          CsvColumnGuide('doubletime_hours', 'Double-time hours worked.'),
          CsvColumnGuide('hourly_rate', 'Hourly rate used for costing.'),
          CsvColumnGuide('total_cost', 'Total labor cost for entry.'),
          CsvColumnGuide(
            'status',
            'Approval status (draft, submitted, approved, rejected).',
          ),
          CsvColumnGuide('created_at', 'Record creation timestamp (ISO UTC).'),
          CsvColumnGuide('updated_at', 'Last update timestamp (ISO UTC).'),
        ];
    }
  }

  List<RawDataExportType> get exportTypes => RawDataExportType.values;

  Future<_CsvExport> _buildCsv({
    required RawDataExportType type,
    required String workspaceId,
  }) async {
    switch (type) {
      case RawDataExportType.projects:
        return _buildProjectsCsv(workspaceId);
      case RawDataExportType.budgets:
        return _buildBudgetsCsv(workspaceId);
      case RawDataExportType.catalog:
        return _buildCatalogCsv(workspaceId);
      case RawDataExportType.tasks:
        return _buildTasksCsv(workspaceId);
      case RawDataExportType.customers:
        return _buildCustomersCsv(workspaceId);
      case RawDataExportType.invoices:
        return _buildInvoicesCsv(workspaceId);
      case RawDataExportType.timeEntries:
        return _buildTimeEntriesCsv(workspaceId);
    }
  }

  _CsvExport _buildTemplateCsv(RawDataExportType type) {
    final headers = getColumnGuide(type).map((c) => c.column).toList();
    final sample = _sampleTemplateRow(type);
    final rows = <List<dynamic>>[headers, sample];

    return _CsvExport(
      fileName: '${type.templateFilePrefix}_${_timestampTag()}.csv',
      content: const ListToCsvConverter().convert(rows),
    );
  }

  Future<_CsvExport> _buildProjectsCsv(String workspaceId) async {
    final rows = await _fetchWorkspaceRows(
      table: 'projects',
      workspaceId: workspaceId,
      select:
          'id,name,status,client_id,customer_name,address,start_date,target_completion_date,estimated_budget,contract_amount,created_at,updated_at',
      orderBy: const ['updated_at'],
    );

    const headers = [
      'id',
      'name',
      'status',
      'customer_id',
      'customer_name',
      'address',
      'start_date',
      'target_completion_date',
      'estimated_budget',
      'contract_amount',
      'created_at',
      'updated_at',
    ];

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map(
        (row) => [
          _csvValue(row['id']),
          _csvValue(row['name']),
          _csvValue(row['status']),
          _csvValue(row['client_id']),
          _csvValue(row['customer_name']),
          _csvValue(row['address']),
          _csvValue(row['start_date']),
          _csvValue(row['target_completion_date']),
          _csvValue(row['estimated_budget']),
          _csvValue(row['contract_amount']),
          _csvValue(row['created_at']),
          _csvValue(row['updated_at']),
        ],
      ),
    ];

    return _CsvExport(
      fileName: _fileNameFor(RawDataExportType.projects),
      content: const ListToCsvConverter().convert(csvRows),
    );
  }

  Future<_CsvExport> _buildBudgetsCsv(String workspaceId) async {
    final projectNames = await _fetchProjectNameMap(workspaceId);
    final rows = await _fetchWorkspaceRows(
      table: 'budget_items',
      workspaceId: workspaceId,
      select:
          'id,project_id,parent_id,hierarchy_level,item_type,name,description,quantity,unit,unit_cost,markup,approved_price,projected_cost,committed_cost,final_cost,is_complete,created_at,updated_at',
      orderBy: const ['project_id', 'hierarchy_level', 'name'],
    );

    const headers = [
      'id',
      'project_id',
      'project_name',
      'parent_id',
      'hierarchy_level',
      'item_type',
      'name',
      'description',
      'quantity',
      'unit',
      'unit_cost',
      'markup_pct',
      'approved_price',
      'projected_cost',
      'committed_cost',
      'final_cost',
      'is_complete',
      'created_at',
      'updated_at',
    ];

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map((row) {
        final projectId = row['project_id']?.toString() ?? '';
        return [
          _csvValue(row['id']),
          projectId,
          _csvValue(projectNames[projectId]),
          _csvValue(row['parent_id']),
          _csvValue(row['hierarchy_level']),
          _csvValue(row['item_type']),
          _csvValue(row['name']),
          _csvValue(row['description']),
          _csvValue(row['quantity']),
          _csvValue(row['unit']),
          _csvValue(row['unit_cost']),
          _csvValue(row['markup']),
          _csvValue(row['approved_price']),
          _csvValue(row['projected_cost']),
          _csvValue(row['committed_cost']),
          _csvValue(row['final_cost']),
          _csvValue(row['is_complete']),
          _csvValue(row['created_at']),
          _csvValue(row['updated_at']),
        ];
      }),
    ];

    return _CsvExport(
      fileName: _fileNameFor(RawDataExportType.budgets),
      content: const ListToCsvConverter().convert(csvRows),
    );
  }

  Future<_CsvExport> _buildCatalogCsv(String workspaceId) async {
    final rows = await _fetchWorkspaceRows(
      table: 'catalog_items',
      workspaceId: workspaceId,
      select:
          'id,name,description,sku,category,unit,unit_cost,unit_price,markup,margin,is_taxable,cost_type_name,cost_code_name,image_url,item_type,parent_id,hierarchy_level,sort_order,created_at,updated_at',
      orderBy: const ['parent_id', 'sort_order', 'name'],
    );

    const headers = [
      'id',
      'name',
      'description',
      'sku',
      'category',
      'unit',
      'base_cost',
      'default_price',
      'markup',
      'margin',
      'taxable',
      'cost_type_name',
      'cost_code_name',
      'image_url',
      'item_type',
      'parent_id',
      'hierarchy_level',
      'sort_order',
      'created_at',
      'updated_at',
    ];

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map(
        (row) => [
          _csvValue(row['id']),
          _csvValue(row['name']),
          _csvValue(row['description']),
          _csvValue(row['sku']),
          _csvValue(row['category']),
          _csvValue(row['unit']),
          _csvValue(row['unit_cost']),
          _csvValue(row['unit_price']),
          _csvValue(row['markup']),
          _csvValue(row['margin']),
          _csvValue(row['is_taxable']),
          _csvValue(row['cost_type_name']),
          _csvValue(row['cost_code_name']),
          _csvValue(row['image_url']),
          _csvValue(row['item_type']),
          _csvValue(row['parent_id']),
          _csvValue(row['hierarchy_level']),
          _csvValue(row['sort_order']),
          _csvValue(row['created_at']),
          _csvValue(row['updated_at']),
        ],
      ),
    ];

    return _CsvExport(
      fileName: _fileNameFor(RawDataExportType.catalog),
      content: const ListToCsvConverter().convert(csvRows),
    );
  }

  Future<_CsvExport> _buildTasksCsv(String workspaceId) async {
    final projectNames = await _fetchProjectNameMap(workspaceId);
    final rows = await _fetchWorkspaceRows(
      table: 'tasks',
      workspaceId: workspaceId,
      select:
          'id,project_id,title,status,priority,assigned_to_ids,start_date,due_date,completed_at,progress,estimated_duration,is_complete,created_at,updated_at',
      orderBy: const ['updated_at'],
    );

    final assignedIds = <String>{};
    for (final row in rows) {
      final ids = row['assigned_to_ids'];
      if (ids is List) {
        for (final id in ids) {
          if (id != null && id.toString().isNotEmpty) {
            assignedIds.add(id.toString());
          }
        }
      }
    }
    final userNames = await _fetchUserNameMap(assignedIds.toList());

    const headers = [
      'id',
      'project_id',
      'project_name',
      'title',
      'status',
      'priority',
      'assignee_id',
      'assignee_name',
      'due_date',
      'start_date',
      'completed_at',
      'progress',
      'estimated_hours',
      'created_at',
      'updated_at',
    ];

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map((row) {
        final projectId = row['project_id']?.toString() ?? '';
        final assigneeId = _firstAssignedId(row['assigned_to_ids']);
        return [
          _csvValue(row['id']),
          projectId,
          _csvValue(projectNames[projectId]),
          _csvValue(row['title']),
          _csvValue(row['status']),
          _csvValue(row['priority']),
          assigneeId,
          _csvValue(userNames[assigneeId]),
          _csvValue(row['due_date']),
          _csvValue(row['start_date']),
          _csvValue(row['completed_at']),
          _csvValue(row['progress']),
          _csvValue(row['estimated_duration']),
          _csvValue(row['created_at']),
          _csvValue(row['updated_at']),
        ];
      }),
    ];

    return _CsvExport(
      fileName: _fileNameFor(RawDataExportType.tasks),
      content: const ListToCsvConverter().convert(csvRows),
    );
  }

  Future<_CsvExport> _buildCustomersCsv(String workspaceId) async {
    final rows = await _fetchWorkspaceRows(
      table: 'customers',
      workspaceId: workspaceId,
      select:
          'id,company_name,customer_type,address,city,state,zip_code,is_active,created_at,updated_at',
      orderBy: const ['updated_at'],
    );

    final contactsByCustomer = await _fetchPrimaryContacts(
      rows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
    );

    const headers = [
      'id',
      'company_name',
      'customer_type',
      'primary_contact_name',
      'primary_contact_email',
      'primary_contact_phone',
      'address',
      'city',
      'state',
      'zip_code',
      'is_active',
      'created_at',
      'updated_at',
    ];

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map((row) {
        final id = row['id']?.toString() ?? '';
        final contact = contactsByCustomer[id];
        return [
          _csvValue(id),
          _csvValue(row['company_name']),
          _csvValue(row['customer_type']),
          _csvValue(contact?['name']),
          _csvValue(contact?['email']),
          _csvValue(contact?['phone']),
          _csvValue(row['address']),
          _csvValue(row['city']),
          _csvValue(row['state']),
          _csvValue(row['zip_code']),
          _csvValue(row['is_active']),
          _csvValue(row['created_at']),
          _csvValue(row['updated_at']),
        ];
      }),
    ];

    return _CsvExport(
      fileName: _fileNameFor(RawDataExportType.customers),
      content: const ListToCsvConverter().convert(csvRows),
    );
  }

  Future<_CsvExport> _buildInvoicesCsv(String workspaceId) async {
    final projectNames = await _fetchProjectNameMap(workspaceId);
    final rows = await _fetchWorkspaceRows(
      table: 'invoices',
      workspaceId: workspaceId,
      select:
          'id,project_id,invoice_number,status,created_at,due_date,paid_date,subtotal,tax_amount,total,updated_at',
      orderBy: const ['created_at'],
    );

    const headers = [
      'id',
      'project_id',
      'project_name',
      'invoice_number',
      'status',
      'issue_date',
      'due_date',
      'paid_date',
      'subtotal',
      'tax',
      'total',
      'created_at',
      'updated_at',
    ];

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map((row) {
        final projectId = row['project_id']?.toString() ?? '';
        return [
          _csvValue(row['id']),
          projectId,
          _csvValue(projectNames[projectId]),
          _csvValue(row['invoice_number']),
          _csvValue(row['status']),
          _csvValue(row['created_at']),
          _csvValue(row['due_date']),
          _csvValue(row['paid_date']),
          _csvValue(row['subtotal']),
          _csvValue(row['tax_amount']),
          _csvValue(row['total']),
          _csvValue(row['created_at']),
          _csvValue(row['updated_at']),
        ];
      }),
    ];

    return _CsvExport(
      fileName: _fileNameFor(RawDataExportType.invoices),
      content: const ListToCsvConverter().convert(csvRows),
    );
  }

  Future<_CsvExport> _buildTimeEntriesCsv(String workspaceId) async {
    final projectNames = await _fetchProjectNameMap(workspaceId);
    final rows = await _fetchWorkspaceRows(
      table: 'time_entries',
      workspaceId: workspaceId,
      select:
          'id,project_id,worker_id,date,regular_hours,overtime_hours,double_time_hours,hourly_rate,total_cost,status,created_at,updated_at',
      orderBy: const ['date'],
    );

    final workerIds = rows
        .map((row) => row['worker_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final userNames = await _fetchUserNameMap(workerIds);

    const headers = [
      'id',
      'project_id',
      'project_name',
      'worker_id',
      'worker_name',
      'date',
      'regular_hours',
      'overtime_hours',
      'doubletime_hours',
      'hourly_rate',
      'total_cost',
      'status',
      'created_at',
      'updated_at',
    ];

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map((row) {
        final projectId = row['project_id']?.toString() ?? '';
        final workerId = row['worker_id']?.toString() ?? '';
        return [
          _csvValue(row['id']),
          projectId,
          _csvValue(projectNames[projectId]),
          workerId,
          _csvValue(userNames[workerId]),
          _csvValue(row['date']),
          _csvValue(row['regular_hours']),
          _csvValue(row['overtime_hours']),
          _csvValue(row['double_time_hours']),
          _csvValue(row['hourly_rate']),
          _csvValue(row['total_cost']),
          _csvValue(row['status']),
          _csvValue(row['created_at']),
          _csvValue(row['updated_at']),
        ];
      }),
    ];

    return _CsvExport(
      fileName: _fileNameFor(RawDataExportType.timeEntries),
      content: const ListToCsvConverter().convert(csvRows),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchWorkspaceRows({
    required String table,
    required String workspaceId,
    required String select,
    List<String> orderBy = const [],
  }) async {
    final allRows = <Map<String, dynamic>>[];
    var from = 0;

    while (true) {
      dynamic query =
          _supabase.from(table).select(select).eq('workspace_id', workspaceId);

      for (final col in orderBy) {
        query = query.order(col);
      }

      final batch = await query.range(from, from + _pageSize - 1);
      final rows = (batch as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      allRows.addAll(rows);
      if (rows.length < _pageSize) {
        break;
      }
      from += _pageSize;
    }

    return allRows;
  }

  Future<Map<String, String>> _fetchProjectNameMap(String workspaceId) async {
    final rows = await _fetchWorkspaceRows(
      table: 'projects',
      workspaceId: workspaceId,
      select: 'id,name',
      orderBy: const ['name'],
    );

    final map = <String, String>{};
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      map[id] = row['name']?.toString() ?? '';
    }
    return map;
  }

  Future<Map<String, String>> _fetchUserNameMap(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final map = <String, String>{};

    for (var i = 0; i < userIds.length; i += 100) {
      final end = (i + 100 < userIds.length) ? i + 100 : userIds.length;
      final chunk = userIds.sublist(i, end);

      final response = await _supabase
          .from('users')
          .select('id,display_name,email')
          .inFilter('id', chunk);

      for (final row in response) {
        final r = Map<String, dynamic>.from(row);
        final id = r['id']?.toString();
        if (id == null || id.isEmpty) continue;
        map[id] = r['display_name']?.toString() ??
            r['email']?.toString() ??
            'Unknown User';
      }
    }

    return map;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchPrimaryContacts(
    List<String> customerIds,
  ) async {
    if (customerIds.isEmpty) return {};
    final byCustomer = <String, List<Map<String, dynamic>>>{};

    for (var i = 0; i < customerIds.length; i += 100) {
      final end = (i + 100 < customerIds.length) ? i + 100 : customerIds.length;
      final chunk = customerIds.sublist(i, end);

      final response = await _supabase
          .from('customer_contacts')
          .select('customer_id,name,email,phone,is_primary,created_at')
          .inFilter('customer_id', chunk);

      for (final row in response) {
        final r = Map<String, dynamic>.from(row);
        final customerId = r['customer_id']?.toString();
        if (customerId == null || customerId.isEmpty) continue;
        byCustomer.putIfAbsent(customerId, () => []).add(r);
      }
    }

    final primary = <String, Map<String, dynamic>>{};
    byCustomer.forEach((customerId, contacts) {
      contacts.sort((a, b) {
        final aPrimary = a['is_primary'] == true ? 0 : 1;
        final bPrimary = b['is_primary'] == true ? 0 : 1;
        if (aPrimary != bPrimary) return aPrimary.compareTo(bPrimary);
        final aCreated = a['created_at']?.toString() ?? '';
        final bCreated = b['created_at']?.toString() ?? '';
        return aCreated.compareTo(bCreated);
      });
      primary[customerId] = contacts.first;
    });

    return primary;
  }

  String _firstAssignedId(dynamic value) {
    if (value is List && value.isNotEmpty) {
      return value.first?.toString() ?? '';
    }
    return '';
  }

  String _csvValue(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value.map((v) => v?.toString() ?? '').join(';');
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return value.toString();
  }

  String _fileNameFor(RawDataExportType type) =>
      '${type.filePrefix}_${_timestampTag()}.csv';

  List<String> _sampleTemplateRow(RawDataExportType type) {
    switch (type) {
      case RawDataExportType.projects:
        return [
          'proj_001',
          'Emergency Water Mitigation - Main St',
          'active',
          'cust_001',
          'Acme Property Mgmt',
          '123 Main St, Austin, TX 78701',
          '2026-02-01T08:00:00Z',
          '2026-03-15T17:00:00Z',
          '25000',
          '32000',
          '2026-02-01T08:00:00Z',
          '2026-02-20T15:30:00Z',
        ];
      case RawDataExportType.budgets:
        return [
          'bud_001',
          'proj_001',
          'Emergency Water Mitigation - Main St',
          '',
          '0',
          'group',
          'Drywall Replacement',
          'Remove and replace wet drywall in affected rooms',
          '1',
          'lot',
          '4500',
          '25',
          '5625',
          '4500',
          '0',
          '0',
          'false',
          '2026-02-01T08:00:00Z',
          '2026-02-20T15:30:00Z',
        ];
      case RawDataExportType.catalog:
        return [
          'cat_001',
          'Drywall 1/2 in',
          'Standard gypsum board 4x8',
          'DW-120',
          'Materials',
          'sheet',
          '14.50',
          '22.00',
          '51.72',
          '34.09',
          'true',
          'Material',
          '09-29-00',
          '',
          'item',
          '',
          '0',
          '0',
          '2026-02-01T08:00:00Z',
          '2026-02-20T15:30:00Z',
        ];
      case RawDataExportType.tasks:
        return [
          'task_001',
          'proj_001',
          'Emergency Water Mitigation - Main St',
          'Set up drying equipment',
          'working_on_it',
          'high',
          'user_001',
          'Jane Foreman',
          '2026-02-05T17:00:00Z',
          '2026-02-04T08:00:00Z',
          '',
          '35',
          '6',
          '2026-02-04T08:00:00Z',
          '2026-02-04T10:30:00Z',
        ];
      case RawDataExportType.customers:
        return [
          'cust_001',
          'Acme Property Mgmt',
          'commercial',
          'Jordan Smith',
          'jordan.smith@example.com',
          '+1-555-123-4567',
          '500 5th Ave',
          'New York',
          'NY',
          '10036',
          'true',
          '2026-01-10T12:00:00Z',
          '2026-02-20T15:30:00Z',
        ];
      case RawDataExportType.invoices:
        return [
          'inv_001',
          'proj_001',
          'Emergency Water Mitigation - Main St',
          'INV-2026-0001',
          'sent',
          '2026-02-10T12:00:00Z',
          '2026-03-10T12:00:00Z',
          '',
          '10000',
          '825',
          '10825',
          '2026-02-10T12:00:00Z',
          '2026-02-10T12:00:00Z',
        ];
      case RawDataExportType.timeEntries:
        return [
          'te_001',
          'proj_001',
          'Emergency Water Mitigation - Main St',
          'user_001',
          'Jane Foreman',
          '2026-02-04T00:00:00Z',
          '8',
          '1.5',
          '0',
          '42.50',
          '403.75',
          'approved',
          '2026-02-04T18:00:00Z',
          '2026-02-05T09:15:00Z',
        ];
    }
  }

  String _timestampTag() {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${pad(now.month)}${pad(now.day)}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
  }
}

class _CsvExport {
  final String fileName;
  final String content;

  _CsvExport({required this.fileName, required this.content});
}

class CsvColumnGuide {
  final String column;
  final String description;

  const CsvColumnGuide(this.column, this.description);
}
