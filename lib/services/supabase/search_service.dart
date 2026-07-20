import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/task.dart';
import '../../models/customer.dart';
import '../../models/document_type.dart';
import '../../utils/address_formatter.dart';
import '../../utils/project_terminology.dart';

/// Represents a search result from any entity type
class SearchResult {
  final String id;
  final String title;
  final String? subtitle;
  final SearchResultType type;
  final String? parentId; // For tasks, this is the project ID
  final String? parentName; // For display purposes
  final Map<String, dynamic>? metadata;

  SearchResult({
    required this.id,
    required this.title,
    this.subtitle,
    required this.type,
    this.parentId,
    this.parentName,
    this.metadata,
  });

  /// Get the route to navigate to this result
  String get route {
    switch (type) {
      case SearchResultType.project:
        return '/projects/$id';
      case SearchResultType.task:
        return '/projects/$parentId/schedule';
      case SearchResultType.customer:
        return '/customers/$id';
      case SearchResultType.vendor:
        return '/vendors/$id';
      case SearchResultType.document:
        return '/documents/$id';
      case SearchResultType.opportunity:
        return '/opportunities/$id';
      case SearchResultType.asset:
        return '/equipment/$id';
      case SearchResultType.catalogItem:
        return '/catalog/item/$id';
      case SearchResultType.teamMember:
        return '/profile/$id';
      case SearchResultType.aiSuggestion:
        return ''; // AI suggestions are actions, not routes
    }
  }
}

enum SearchResultType {
  project,
  task,
  customer,
  vendor,
  document,
  opportunity,
  asset,
  catalogItem,
  teamMember,
  aiSuggestion,
}

/// AI-detected intent from the search query
class SearchIntent {
  final SearchIntentType type;
  final String? entityType; // project, task, customer, etc.
  final String? action; // create, find, show, update
  final Map<String, String> parameters;
  final String originalQuery;

  SearchIntent({
    required this.type,
    this.entityType,
    this.action,
    this.parameters = const {},
    required this.originalQuery,
  });
}

enum SearchIntentType {
  search, // Regular search
  question, // Asking a question
  command, // Requesting an action
  navigation, // Go to somewhere
}

/// Supabase implementation of SearchService
class SupabaseSearchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Search across all entity types
  Future<List<SearchResult>> search(
    String query,
    String workspaceId, {
    int limit = 20,
    List<SearchResultType>? types,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final queryLower = query.toLowerCase().trim();
    final results = <SearchResult>[];
    final typesToSearch =
        types ??
        SearchResultType.values
            .where((t) => t != SearchResultType.aiSuggestion)
            .toList();

    // Per-entity result cap. We over-fetch a few candidates per type, then
    // sort the merged set by relevance and trim to [limit] below. Keeping
    // this a small constant (rather than `limit ~/ typeCount`) means each
    // entity still contributes a handful of candidates even as the number of
    // searched modules grows.
    const perType = 5;

    // Registry of searchers. Adding a module to global search is a single
    // `add(...)` entry here plus a row -> SearchResult mapper below — no new
    // fan-out plumbing required.
    final searchers = <Future<List<SearchResult>> Function()>[];
    void add(SearchResultType type, Future<List<SearchResult>> Function() run) {
      if (typesToSearch.contains(type)) searchers.add(run);
    }

    add(SearchResultType.project,
        () => _searchProjects(queryLower, workspaceId, limit: perType));
    add(SearchResultType.task,
        () => _searchTasks(queryLower, workspaceId, limit: perType));
    add(SearchResultType.customer,
        () => _searchCustomers(queryLower, workspaceId, limit: perType));
    add(SearchResultType.vendor,
        () => _searchVendors(queryLower, workspaceId, limit: perType));
    add(SearchResultType.document,
        () => _searchDocuments(queryLower, workspaceId, limit: perType));
    add(SearchResultType.opportunity,
        () => _searchOpportunities(queryLower, workspaceId, limit: perType));
    add(SearchResultType.asset,
        () => _searchAssets(queryLower, workspaceId, limit: perType));
    add(SearchResultType.catalogItem,
        () => _searchCatalogItems(queryLower, workspaceId, limit: perType));
    add(SearchResultType.teamMember,
        () => _searchTeamMembers(queryLower, workspaceId, limit: perType));

    // Run the searchers with bounded concurrency so a wide search doesn't fire
    // a dozen simultaneous PostgREST requests on every (debounced) keystroke.
    for (final batch in await _runPooled(searchers, concurrency: 5)) {
      results.addAll(batch);
    }

    // Sort by relevance (exact matches first, then partial matches)
    results.sort((a, b) {
      final aExact = a.title.toLowerCase() == queryLower;
      final bExact = b.title.toLowerCase() == queryLower;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      final aStarts = a.title.toLowerCase().startsWith(queryLower);
      final bStarts = b.title.toLowerCase().startsWith(queryLower);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;

      return a.title.compareTo(b.title);
    });

    return results.take(limit).toList();
  }

  Future<List<SearchResult>> _searchProjects(
    String query,
    String workspaceId, {
    int limit = 5,
  }) async {
    try {
      final response = await _supabase
          .from('projects')
          .select('''
            id,
            name,
            address,
            status,
            customer_name,
            description,
            primary_contact_name,
            purchase_order_number,
            serial_number,
            updated_at
          ''')
          .eq('workspace_id', workspaceId)
          .or(
            'name.ilike.%$query%,address.ilike.%$query%,description.ilike.%$query%,customer_name.ilike.%$query%,primary_contact_name.ilike.%$query%,purchase_order_number.ilike.%$query%,serial_number.ilike.%$query%',
          )
          .order('updated_at', ascending: false)
          .limit(limit);

      final results = <SearchResult>[];
      for (final row in response) {
        final name = _stringValue(row['name']);
        if (name.isEmpty) continue;

        final address = _stringValue(row['address']);
        final customerName = _stringValue(row['customer_name']);
        final primaryContactName = _stringValue(row['primary_contact_name']);
        final purchaseOrderNumber = _stringValue(row['purchase_order_number']);
        final serialNumber = _stringValue(row['serial_number']);
        final status = _stringValue(row['status']);

        final subtitleCandidates = [
          if (address.isNotEmpty) AddressFormatter.condense(address),
          if (customerName.isNotEmpty) customerName,
          if (primaryContactName.isNotEmpty) primaryContactName,
          if (purchaseOrderNumber.isNotEmpty) 'PO $purchaseOrderNumber',
          if (serialNumber.isNotEmpty) '#$serialNumber',
        ];

        results.add(
          SearchResult(
            id: row['id'] as String,
            title: name,
            subtitle: subtitleCandidates.isEmpty ? null : subtitleCandidates.first,
            type: SearchResultType.project,
            metadata: {
              'status': status,
              'customerName': customerName.isEmpty ? null : customerName,
              'primaryContactName': primaryContactName.isEmpty
                  ? null
                  : primaryContactName,
              'purchaseOrderNumber': purchaseOrderNumber.isEmpty
                  ? null
                  : purchaseOrderNumber,
              'serialNumber': serialNumber.isEmpty ? null : serialNumber,
            },
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('Error searching projects: $e');
      return [];
    }
  }

  Future<List<SearchResult>> _searchTasks(
    String query,
    String workspaceId, {
    int limit = 5,
  }) async {
    try {
      final response = await _supabase
          .from('tasks')
          .select()
          .eq('workspace_id', workspaceId)
          .or('title.ilike.%$query%,description.ilike.%$query%')
          .order('updated_at', ascending: false)
          .limit(limit * 2); // Fetch extra to allow for project name lookup

      final results = <SearchResult>[];

      // Get project names for context in a single batched query (not one
      // round-trip per task — that was an N+1 that made task search scale
      // linearly with the number of matches).
      final projectIds = response
          .map((row) => row['project_id'] as String?)
          .whereType<String>()
          .toSet();

      final projectNames = <String, String>{};
      if (projectIds.isNotEmpty) {
        try {
          final projectResponse = await _supabase
              .from('projects')
              .select('id, name')
              .inFilter('id', projectIds.toList());
          for (final row in projectResponse) {
            projectNames[row['id'] as String] =
                row['name'] as String? ?? 'Unknown Project';
          }
        } catch (_) {}
      }

      for (final row in response) {
        final task = Task.fromJson(_toTaskFirestoreFormat(row), row['id']);
        results.add(
          SearchResult(
            id: task.id,
            title: task.title,
            subtitle:
                task.description ??
                (task.isComplete ? 'Completed' : 'In Progress'),
            type: SearchResultType.task,
            parentId: task.projectId,
            parentName: projectNames[task.projectId],
            metadata: {'status': task.status, 'isComplete': task.isComplete},
          ),
        );

        if (results.length >= limit) break;
      }

      return results;
    } catch (e) {
      debugPrint('Error searching tasks: $e');
      return [];
    }
  }

  Future<List<SearchResult>> _searchCustomers(
    String query,
    String workspaceId, {
    int limit = 5,
  }) async {
    try {
      const select = '''
        *,
        customer_contacts(name, email, phone, is_primary, is_active)
      ''';

      // Two bounded queries instead of fetching a wide slice of the table and
      // filtering in Dart: (A) matches on the customer's own columns, and
      // (B) matches on an embedded contact (name/email/phone). Each is capped
      // at [limit]; we merge and de-dupe by id.
      final byCustomer = _supabase
          .from('customers')
          .select(select)
          .eq('workspace_id', workspaceId)
          .or(
            'company_name.ilike.%$query%,business_email.ilike.%$query%,business_phone.ilike.%$query%,address.ilike.%$query%,city.ilike.%$query%',
          )
          .limit(limit);

      final byContact = _supabase
          .from('customers')
          .select('''
            *,
            customer_contacts!inner(name, email, phone, is_primary, is_active)
          ''')
          .eq('workspace_id', workspaceId)
          .or(
            'name.ilike.%$query%,email.ilike.%$query%,phone.ilike.%$query%',
            referencedTable: 'customer_contacts',
          )
          .limit(limit);

      final responses = await Future.wait([byCustomer, byContact]);

      final results = <SearchResult>[];
      final seen = <String>{};
      for (final response in responses) {
        for (final row in response) {
          final id = row['id'] as String;
          if (!seen.add(id)) continue;
          final customer = Customer.fromJson(
            _toCustomerFirestoreFormat(row),
            id,
          );
          results.add(
            SearchResult(
              id: customer.id,
              title: customer.name,
              subtitle: customer.email ?? customer.phone ?? customer.address,
              type: SearchResultType.customer,
              metadata: {'email': customer.email, 'phone': customer.phone},
            ),
          );
          if (results.length >= limit) break;
        }
        if (results.length >= limit) break;
      }

      return results;
    } catch (e) {
      debugPrint('Error searching customers: $e');
      return [];
    }
  }

  Future<List<SearchResult>> _searchVendors(
    String query,
    String workspaceId, {
    int limit = 5,
  }) async {
    try {
      final response = await _supabase
          .from('vendors')
          .select('''
            id,
            company_name,
            vendor_contacts(email, phone, is_primary, is_active)
          ''')
          .eq('workspace_id', workspaceId)
          .or('company_name.ilike.%$query%')
          .limit(limit);

      final results = <SearchResult>[];
      for (final row in response) {
        final contacts =
            (row['vendor_contacts'] as List<dynamic>? ?? const <dynamic>[])
                .cast<Map<String, dynamic>>();
        final activeContacts = contacts
            .where((c) => c['is_active'] as bool? ?? true)
            .toList();
        final primaryContact = activeContacts.firstWhere(
          (c) => c['is_primary'] as bool? ?? false,
          orElse: () => activeContacts.isNotEmpty
              ? activeContacts.first
              : <String, dynamic>{},
        );

        final name = row['company_name'] as String? ?? '';
        final email = primaryContact['email'] as String?;
        final phone = primaryContact['phone'] as String?;

        results.add(
          SearchResult(
            id: row['id'],
            title: name,
            subtitle: email ?? phone,
            type: SearchResultType.vendor,
            metadata: {'email': email, 'phone': phone},
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('Error searching vendors: $e');
      return [];
    }
  }

  Future<List<SearchResult>> _searchDocuments(
    String query,
    String workspaceId, {
    int limit = 5,
  }) {
    return _searchSimple(
      table: 'generated_documents',
      select:
          'id, document_number, template_name, customer_name, document_type, status, project_id, updated_at',
      searchColumns: const [
        'document_number',
        'template_name',
        'customer_name',
      ],
      query: query,
      workspaceId: workspaceId,
      limit: limit,
      map: (row) {
        final number = _stringValue(row['document_number']);
        final templateName = _stringValue(row['template_name']);
        final docType = _documentTypeLabel(_stringValue(row['document_type']));
        final title = number.isNotEmpty
            ? '$docType $number'.trim()
            : (templateName.isNotEmpty ? templateName : docType);
        if (title.isEmpty) return null;
        final customerName = _stringValue(row['customer_name']);
        return SearchResult(
          id: row['id'] as String,
          title: title,
          subtitle: customerName.isEmpty
              ? (templateName.isEmpty ? null : templateName)
              : customerName,
          type: SearchResultType.document,
          parentId: row['project_id'] as String?,
          metadata: {
            'documentType': row['document_type'],
            'status': row['status'],
          },
        );
      },
    );
  }

  Future<List<SearchResult>> _searchOpportunities(
    String query,
    String workspaceId, {
    int limit = 5,
  }) {
    return _searchSimple(
      table: 'opportunities',
      select: 'id, name, description, source, stage, updated_at',
      searchColumns: const ['name', 'description', 'source'],
      query: query,
      workspaceId: workspaceId,
      limit: limit,
      map: (row) {
        final name = _stringValue(row['name']);
        if (name.isEmpty) return null;
        final stage = _stringValue(row['stage']);
        final source = _stringValue(row['source']);
        return SearchResult(
          id: row['id'] as String,
          title: name,
          subtitle: stage.isNotEmpty
              ? stage
              : (source.isEmpty ? null : source),
          type: SearchResultType.opportunity,
          metadata: {'stage': row['stage']},
        );
      },
    );
  }

  Future<List<SearchResult>> _searchAssets(
    String query,
    String workspaceId, {
    int limit = 5,
  }) {
    return _searchSimple(
      table: 'assets',
      select:
          'id, name, description, serial_number, qr_code, location, category, status, updated_at',
      searchColumns: const [
        'name',
        'description',
        'serial_number',
        'qr_code',
        'location',
        'category',
      ],
      query: query,
      workspaceId: workspaceId,
      limit: limit,
      map: (row) {
        final name = _stringValue(row['name']);
        if (name.isEmpty) return null;
        final serial = _stringValue(row['serial_number']);
        final category = _stringValue(row['category']);
        final location = _stringValue(row['location']);
        final parts = [
          if (category.isNotEmpty) category,
          if (serial.isNotEmpty) '#$serial',
          if (location.isNotEmpty) location,
        ];
        return SearchResult(
          id: row['id'] as String,
          title: name,
          subtitle: parts.isEmpty ? null : parts.join(' · '),
          type: SearchResultType.asset,
          metadata: {'status': row['status']},
        );
      },
    );
  }

  Future<List<SearchResult>> _searchCatalogItems(
    String query,
    String workspaceId, {
    int limit = 5,
  }) {
    return _searchSimple(
      table: 'catalog_items',
      select: 'id, name, description, sku, category, barcode, updated_at',
      searchColumns: const ['name', 'description', 'sku', 'category', 'barcode'],
      query: query,
      workspaceId: workspaceId,
      limit: limit,
      map: (row) {
        final name = _stringValue(row['name']);
        if (name.isEmpty) return null;
        final sku = _stringValue(row['sku']);
        final category = _stringValue(row['category']);
        final parts = [
          if (sku.isNotEmpty) 'SKU $sku',
          if (category.isNotEmpty) category,
        ];
        return SearchResult(
          id: row['id'] as String,
          title: name,
          subtitle: parts.isEmpty ? null : parts.join(' · '),
          type: SearchResultType.catalogItem,
        );
      },
    );
  }

  /// Search workspace members by the joined user's name/email/title. The
  /// searchable text lives on `users`, so we inner-join and filter the
  /// embedded resource — dropping members whose user doesn't match.
  Future<List<SearchResult>> _searchTeamMembers(
    String query,
    String workspaceId, {
    int limit = 5,
  }) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select(
            'user_id, users!inner(id, display_name, email, job_title, phone_number)',
          )
          .eq('workspace_id', workspaceId)
          .or(
            'display_name.ilike.%$query%,email.ilike.%$query%,job_title.ilike.%$query%,phone_number.ilike.%$query%',
            referencedTable: 'users',
          )
          .limit(limit);

      final results = <SearchResult>[];
      for (final row in response) {
        final user = row['users'] as Map<String, dynamic>?;
        if (user == null) continue;
        final name = _stringValue(user['display_name']);
        final email = _stringValue(user['email']);
        final title = name.isNotEmpty ? name : email;
        if (title.isEmpty) continue;
        final jobTitle = _stringValue(user['job_title']);
        results.add(
          SearchResult(
            id: (user['id'] ?? row['user_id']) as String,
            title: title,
            subtitle: jobTitle.isNotEmpty
                ? jobTitle
                : (email.isEmpty ? null : email),
            type: SearchResultType.teamMember,
            metadata: {'email': user['email']},
          ),
        );
      }
      return results;
    } catch (e) {
      debugPrint('Error searching team members: $e');
      return [];
    }
  }

  /// Generic case-insensitive ILIKE search across [searchColumns] of a
  /// workspace-scoped table. Covers the common "match a few text columns,
  /// order by recency" shape so each module's searcher is just a row mapper.
  Future<List<SearchResult>> _searchSimple({
    required String table,
    required String select,
    required List<String> searchColumns,
    required String query,
    required String workspaceId,
    required int limit,
    required SearchResult? Function(Map<String, dynamic> row) map,
    String orderColumn = 'updated_at',
  }) async {
    try {
      final orFilter = searchColumns.map((c) => '$c.ilike.%$query%').join(',');
      final response = await _supabase
          .from(table)
          .select(select)
          .eq('workspace_id', workspaceId)
          .or(orFilter)
          .order(orderColumn, ascending: false)
          .limit(limit);
      return response
          .map((row) => map(Map<String, dynamic>.from(row)))
          .whereType<SearchResult>()
          .toList();
    } catch (e) {
      debugPrint('Error searching $table: $e');
      return [];
    }
  }

  /// Run [tasks] with at most [concurrency] in flight at a time, preserving
  /// input order in the returned lists. Each task already swallows its own
  /// errors; this is an extra guard so one failing table can't reject the set.
  Future<List<List<SearchResult>>> _runPooled(
    List<Future<List<SearchResult>> Function()> tasks, {
    int concurrency = 5,
  }) async {
    final results = List<List<SearchResult>>.filled(
      tasks.length,
      const <SearchResult>[],
    );
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++; // synchronous; safe between await points
        if (i >= tasks.length) break;
        try {
          results[i] = await tasks[i]();
        } catch (_) {
          results[i] = const <SearchResult>[];
        }
      }
    }

    final workerCount = concurrency < tasks.length ? concurrency : tasks.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results;
  }

  /// Turn a stored document_type (snake_case or camelCase) into a label, e.g.
  /// `purchase_order` / `purchaseOrder` -> "Purchase Order".
  String _documentTypeLabel(String raw) {
    if (raw.isEmpty) return 'Document';
    final spaced = raw
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Detect the intent of a search query
  SearchIntent detectIntent(String query) {
    final queryLower = query.toLowerCase().trim();

    // Check for commands (starting with /)
    if (queryLower.startsWith('/')) {
      return _parseCommand(queryLower);
    }

    // Check for questions
    if (_isQuestion(queryLower)) {
      return SearchIntent(
        type: SearchIntentType.question,
        originalQuery: query,
        parameters: _extractQuestionParameters(queryLower),
      );
    }

    // Check for navigation intent
    if (_isNavigationIntent(queryLower)) {
      return SearchIntent(
        type: SearchIntentType.navigation,
        originalQuery: query,
        parameters: _extractNavigationParameters(queryLower),
      );
    }

    // Default to search
    return SearchIntent(type: SearchIntentType.search, originalQuery: query);
  }

  bool _isQuestion(String query) {
    final questionStarters = [
      'what',
      'when',
      'where',
      'who',
      'why',
      'how',
      'is there',
      'are there',
      'do we',
      'can i',
      'show me',
      'find',
      'list',
      'get',
      'tell me',
    ];

    for (final starter in questionStarters) {
      if (query.startsWith(starter)) return true;
    }

    return query.contains('?');
  }

  bool _isNavigationIntent(String query) {
    final navKeywords = ['go to', 'open', 'navigate to', 'show', 'view'];
    for (final keyword in navKeywords) {
      if (query.startsWith(keyword)) return true;
    }
    return false;
  }

  SearchIntent _parseCommand(String query) {
    final parts = query.substring(1).split(' ');
    final command = parts.first;

    switch (command) {
      case 'create':
      case 'new':
        return SearchIntent(
          type: SearchIntentType.command,
          action: 'create',
          entityType: parts.length > 1 ? parts[1] : null,
          originalQuery: query,
        );
      case 'go':
      case 'open':
        return SearchIntent(
          type: SearchIntentType.navigation,
          originalQuery: query,
          parameters: {'target': parts.skip(1).join(' ')},
        );
      default:
        return SearchIntent(
          type: SearchIntentType.command,
          action: command,
          originalQuery: query,
        );
    }
  }

  Map<String, String> _extractQuestionParameters(String query) {
    final params = <String, String>{};

    // Detect entity type mentions
    if (query.contains('project')) params['entityType'] = 'project';
    if (query.contains('task')) params['entityType'] = 'task';
    if (query.contains('customer') || query.contains('client')) {
      params['entityType'] = 'customer';
    }
    if (query.contains('invoice')) params['entityType'] = 'invoice';
    if (query.contains('budget')) params['entityType'] = 'budget';

    // Detect status mentions
    if (query.contains('overdue')) params['filter'] = 'overdue';
    if (query.contains('complete') || query.contains('done')) {
      params['filter'] = 'completed';
    }
    if (query.contains('pending') || query.contains('active')) {
      params['filter'] = 'active';
    }

    return params;
  }

  Map<String, String> _extractNavigationParameters(String query) {
    final params = <String, String>{};

    // Remove navigation keywords
    var target = query
        .replaceAll('go to', '')
        .replaceAll('open', '')
        .replaceAll('navigate to', '')
        .replaceAll('show', '')
        .replaceAll('view', '')
        .trim();

    params['target'] = target;
    return params;
  }

  /// Get AI-powered suggestions based on query
  List<SearchResult> getAiSuggestions(String query, SearchIntent intent, {String projectTerminology = 'Projects'}) {
    final suggestions = <SearchResult>[];
    final queryLower = query.toLowerCase();
    final singular = singularProjectTerminology(projectTerminology);

    // Add contextual AI suggestions based on intent
    if (intent.type == SearchIntentType.question) {
      suggestions.add(
        SearchResult(
          id: 'ai_answer',
          title: 'Ask AI: "$query"',
          subtitle: 'Get an AI-powered answer',
          type: SearchResultType.aiSuggestion,
          metadata: {'action': 'ask_ai', 'query': query},
        ),
      );
    }

    // Suggest creating entities
    if (queryLower.contains('create') ||
        queryLower.contains('new') ||
        queryLower.contains('add')) {
      if (queryLower.contains('task')) {
        suggestions.add(
          SearchResult(
            id: 'ai_create_task',
            title: 'Create new task',
            subtitle: 'AI will help you create a task',
            type: SearchResultType.aiSuggestion,
            metadata: {'action': 'create_task'},
          ),
        );
      }
      if (queryLower.contains('project')) {
        suggestions.add(
          SearchResult(
            id: 'ai_create_project',
            title: 'Create new ${singular.toLowerCase()}',
            subtitle: 'Start a new ${singular.toLowerCase()}',
            type: SearchResultType.aiSuggestion,
            metadata: {'action': 'create_project'},
          ),
        );
      }
    }

    // Suggest analytics/reports for question patterns
    if (queryLower.contains('how many') ||
        queryLower.contains('total') ||
        queryLower.contains('count')) {
      suggestions.add(
        SearchResult(
          id: 'ai_analytics',
          title: 'View Analytics',
          subtitle: 'See detailed reports and metrics',
          type: SearchResultType.aiSuggestion,
          metadata: {'action': 'analytics'},
        ),
      );
    }

    // Suggest overdue tasks
    if (queryLower.contains('overdue') ||
        queryLower.contains('late') ||
        queryLower.contains('behind')) {
      suggestions.add(
        SearchResult(
          id: 'ai_overdue',
          title: 'Show overdue items',
          subtitle: 'View all overdue tasks and ${projectTerminology.toLowerCase()}',
          type: SearchResultType.aiSuggestion,
          metadata: {'action': 'show_overdue'},
        ),
      );
    }

    return suggestions;
  }

  // Helper methods to convert Supabase format to Firestore format

  String _stringValue(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  Map<String, dynamic> _toTaskFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'projectId': row['project_id'],
      'title': row['title'],
      'description': row['description'],
      'status': row['status'],
      'priority': row['priority'],
      'dueDate': row['due_date'] != null
          ? _FakeTimestamp(DateTime.parse(row['due_date']))
          : null,
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : _FakeTimestamp(DateTime.now()),
    };
  }

  Map<String, dynamic> _toCustomerFirestoreFormat(Map<String, dynamic> row) {
    final contacts =
        (row['customer_contacts'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
    final activeContacts = contacts
        .where((c) => c['is_active'] as bool? ?? true)
        .toList();
    final primaryContact = activeContacts.firstWhere(
      (c) => c['is_primary'] as bool? ?? false,
      orElse: () => activeContacts.isNotEmpty
          ? activeContacts.first
          : <String, dynamic>{},
    );

    return {
      'workspaceId': row['workspace_id'],
      'name': primaryContact['name'] ?? row['company_name'] ?? '',
      'email': primaryContact['email'],
      'phone': primaryContact['phone'],
      'contacts': activeContacts
          .map(
            (c) => {
              'name': c['name'] ?? '',
              'email': c['email'],
              'phone': c['phone'],
              'isPrimary': c['is_primary'] ?? false,
              'isActive': c['is_active'] ?? true,
            },
          )
          .toList(),
      'address': row['address'],
      'companyName': row['company_name'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : _FakeTimestamp(DateTime.now()),
    };
  }
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
