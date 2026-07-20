import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/customer.dart';
import '../utils/address_formatter.dart';
import '../utils/project_terminology.dart';

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
        return '/projects/$parentId/documents/$id';
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

/// Service for searching across all entity types
class SearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

    // Run searches in parallel
    final futures = <Future<List<SearchResult>>>[];

    if (typesToSearch.contains(SearchResultType.project)) {
      futures.add(_searchProjects(queryLower, workspaceId, limit: limit ~/ 4));
    }
    if (typesToSearch.contains(SearchResultType.task)) {
      futures.add(_searchTasks(queryLower, workspaceId, limit: limit ~/ 4));
    }
    if (typesToSearch.contains(SearchResultType.customer)) {
      futures.add(_searchCustomers(queryLower, workspaceId, limit: limit ~/ 4));
    }
    if (typesToSearch.contains(SearchResultType.vendor)) {
      futures.add(_searchVendors(queryLower, workspaceId, limit: limit ~/ 4));
    }

    final searchResults = await Future.wait(futures);
    for (final resultList in searchResults) {
      results.addAll(resultList);
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
      // Firestore doesn't support full-text search, so we fetch and filter
      final snapshot = await _firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId)
          .orderBy('updatedAt', descending: true)
          .limit(100) // Fetch more to filter locally
          .get();

      final results = <SearchResult>[];
      for (final doc in snapshot.docs) {
        final project = Project.fromJson(doc.data(), doc.id);
        final nameMatch = project.name.toLowerCase().contains(query);
        final addressMatch = project.address.toLowerCase().contains(query);
        final customerMatch =
            project.customerName?.toLowerCase().contains(query) ?? false;

        if (nameMatch || addressMatch || customerMatch) {
          results.add(
            SearchResult(
              id: project.id,
              title: project.name,
              subtitle: AddressFormatter.condense(project.address),
              type: SearchResultType.project,
              metadata: {
                'status': project.status.displayName,
                'customerName': project.customerName,
              },
            ),
          );
        }

        if (results.length >= limit) break;
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
      final snapshot = await _firestore
          .collection('tasks')
          .where('workspaceId', isEqualTo: workspaceId)
          .orderBy('updatedAt', descending: true)
          .limit(100)
          .get();

      final results = <SearchResult>[];

      // Get project names for context
      final projectIds = snapshot.docs
          .map((doc) => doc.data()['projectId'] as String?)
          .whereType<String>()
          .toSet();

      final projectNames = <String, String>{};
      for (final projectId in projectIds) {
        try {
          final projectDoc = await _firestore
              .collection('projects')
              .doc(projectId)
              .get();
          if (projectDoc.exists) {
            projectNames[projectId] =
                projectDoc.data()?['name'] as String? ?? 'Unknown Project';
          }
        } catch (_) {}
      }

      for (final doc in snapshot.docs) {
        final task = Task.fromJson(doc.data(), doc.id);
        final titleMatch = task.title.toLowerCase().contains(query);
        final descMatch =
            task.description?.toLowerCase().contains(query) ?? false;

        if (titleMatch || descMatch) {
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
        }

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
      final snapshot = await _firestore
          .collection('customers')
          .where('workspaceId', isEqualTo: workspaceId)
          .limit(100)
          .get();

      final results = <SearchResult>[];
      for (final doc in snapshot.docs) {
        final customer = Customer.fromJson(doc.data(), doc.id);
        final nameMatch = customer.name.toLowerCase().contains(query);
        final emailMatch =
            customer.email?.toLowerCase().contains(query) ?? false;
        final phoneMatch =
            customer.phone?.toLowerCase().contains(query) ?? false;
        final addressMatch =
            customer.address?.toLowerCase().contains(query) ?? false;

        if (nameMatch || emailMatch || phoneMatch || addressMatch) {
          results.add(
            SearchResult(
              id: customer.id,
              title: customer.name,
              subtitle: customer.email ?? customer.phone ?? customer.address,
              type: SearchResultType.customer,
              metadata: {'email': customer.email, 'phone': customer.phone},
            ),
          );
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
      final snapshot = await _firestore
          .collection('vendors')
          .where('workspaceId', isEqualTo: workspaceId)
          .limit(100)
          .get();

      final results = <SearchResult>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? '';
        final email = data['email'] as String?;
        final phone = data['phone'] as String?;

        final nameMatch = name.toLowerCase().contains(query);
        final emailMatch = email?.toLowerCase().contains(query) ?? false;
        final phoneMatch = phone?.toLowerCase().contains(query) ?? false;

        if (nameMatch || emailMatch || phoneMatch) {
          results.add(
            SearchResult(
              id: doc.id,
              title: name,
              subtitle: email ?? phone,
              type: SearchResultType.vendor,
              metadata: {'email': email, 'phone': phone},
            ),
          );
        }

        if (results.length >= limit) break;
      }

      return results;
    } catch (e) {
      debugPrint('Error searching vendors: $e');
      return [];
    }
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
    if (query.contains('project')) {
      params['entityType'] = 'project';
    }
    if (query.contains('task')) {
      params['entityType'] = 'task';
    }
    if (query.contains('customer') || query.contains('client')) {
      params['entityType'] = 'customer';
    }
    if (query.contains('invoice')) {
      params['entityType'] = 'invoice';
    }
    if (query.contains('budget')) {
      params['entityType'] = 'budget';
    }

    // Detect status mentions
    if (query.contains('overdue')) {
      params['filter'] = 'overdue';
    }
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
}
