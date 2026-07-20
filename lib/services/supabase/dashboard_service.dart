import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/activity_item.dart';
import '../../models/user.dart';
import 'user_service.dart';

class DashboardStats {
  final int totalProjects;
  final int activeProjects;
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;
  final int totalCustomers;
  final int overdueTasksCount;
  final int todayTasksCount;
  final double totalRevenue;

  DashboardStats({
    required this.totalProjects,
    required this.activeProjects,
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
    required this.totalCustomers,
    required this.overdueTasksCount,
    required this.todayTasksCount,
    required this.totalRevenue,
  });
}

/// Supabase implementation of DashboardService
class SupabaseDashboardService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseUserService _userService = SupabaseUserService();

  /// Get recent activity across all collections
  Future<List<ActivityItem>> getRecentActivity(
    String workspaceId, {
    int limit = 20,
  }) async {
    try {
      final activities = <ActivityItem>[];

      // Get recent projects
      try {
        final projectsResponse = await _supabase
            .from('projects')
            .select()
            .eq('workspace_id', workspaceId)
            .order('updated_at', ascending: false)
            .limit(10);

        for (var row in projectsResponse) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'projects',
              data: _toProjectFirestoreFormat(row),
              id: row['id'],
            ),
          );
        }
      } catch (e) {
        // Continue with other collections
      }

      // Get recent tasks
      try {
        final tasksResponse = await _supabase
            .from('tasks')
            .select('*, projects(name)')
            .eq('workspace_id', workspaceId)
            .order('updated_at', ascending: false)
            .limit(10);

        for (var row in tasksResponse) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'tasks',
              data: _toTaskFirestoreFormat(row),
              id: row['id'],
            ),
          );
        }
      } catch (e) {
        // Continue with other collections
      }

      // Get recent customers
      try {
        final customersResponse = await _supabase
            .from('customers')
            .select()
            .eq('workspace_id', workspaceId)
            .order('created_at', ascending: false)
            .limit(5);

        for (var row in customersResponse) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'customers',
              data: _toCustomerFirestoreFormat(row),
              id: row['id'],
            ),
          );
        }
      } catch (e) {
        // Continue with other collections
      }

      // Get recent invoices
      try {
        final invoicesResponse = await _supabase
            .from('generated_documents')
            .select()
            .eq('workspace_id', workspaceId)
            .eq('document_type', 'invoice')
            .order('created_at', ascending: false)
            .limit(5);

        for (var row in invoicesResponse) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'invoices',
              data: _toInvoiceFirestoreFormat(row),
              id: row['id'],
            ),
          );
        }
      } catch (e) {
        // Continue with other collections
      }

      // Get recent plans
      try {
        final plansResponse = await _supabase
            .from('plans')
            .select()
            .eq('workspace_id', workspaceId)
            .order('uploaded_at', ascending: false)
            .limit(5);

        for (var row in plansResponse) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'plans',
              data: _toPlanFirestoreFormat(row),
              id: row['id'],
            ),
          );
        }
      } catch (e) {
        // Continue with other collections
      }

      // Sort all activities by timestamp
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Take only the most recent items up to limit
      final recentActivities = activities.take(limit).toList();

      // Populate user names
      await _populateUserNames(recentActivities);

      return recentActivities;
    } catch (e) {
      return [];
    }
  }

  /// Populate user names for activities
  Future<void> _populateUserNames(List<ActivityItem> activities) async {
    final userIds = activities
        .where((a) => a.userId != null)
        .map((a) => a.userId!)
        .toSet();

    final userCache = <String, AppUser>{};

    for (var userId in userIds) {
      try {
        final user = await _userService.getUserById(userId);
        if (user != null) {
          userCache[userId] = user;
        }
      } catch (e) {
        // Continue with other users
      }
    }

    // Update activities with user names
    for (var i = 0; i < activities.length; i++) {
      if (activities[i].userId != null) {
        final user = userCache[activities[i].userId];
        if (user != null) {
          // Create new activity with updated userName
          activities[i] = ActivityItem(
            id: activities[i].id,
            type: activities[i].type,
            title: activities[i].title,
            description: activities[i].description,
            userId: activities[i].userId,
            userName: user.displayName ?? user.email,
            entityId: activities[i].entityId,
            entityName: activities[i].entityName,
            timestamp: activities[i].timestamp,
            metadata: activities[i].metadata,
          );
        }
      }
    }
  }

  /// Get dashboard statistics
  Future<DashboardStats> getDashboardStats(String workspaceId) async {
    try {
      // Get projects
      final projectsResponse = await _supabase
          .from('projects')
          .select()
          .eq('workspace_id', workspaceId);

      final totalProjects = projectsResponse.length;
      const openStatuses = {'active', 'awarded', 'on_hold'};
      final activeProjects = projectsResponse
          .where((row) => openStatuses.contains(row['status']?.toString().toLowerCase()))
          .length;

      // Calculate total revenue from all projects
      double totalRevenue = 0.0;
      for (var row in projectsResponse) {
        final contractAmount = row['contract_amount'] as num?;
        if (contractAmount != null) {
          totalRevenue += contractAmount.toDouble();
        }
      }

      // Get tasks
      final tasksResponse = await _supabase
          .from('tasks')
          .select()
          .eq('workspace_id', workspaceId);

      final totalTasks = tasksResponse.length;
      final completedTasks = tasksResponse
          .where((row) => row['is_complete'] == true)
          .length;
      final pendingTasks = tasksResponse
          .where((row) =>
              row['is_complete'] != true)
          .length;

      // Count overdue and today's tasks
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      int overdueTasksCount = 0;
      int todayTasksCount = 0;

      for (var row in tasksResponse) {
        final isComplete = row['is_complete'] as bool? ?? false;
        if (isComplete) continue;

        final dueDateStr = row['due_date'] as String?;
        if (dueDateStr == null) continue;

        final dueDate = DateTime.parse(dueDateStr);

        // Date-only due dates (midnight) mean "due that day": overdue only
        // once the day has passed, and inclusive in today's bucket. Mirrors
        // Task.isOverdue()/isDueToday().
        final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
        final hasTime = dueDate.hour != 0 ||
            dueDate.minute != 0 ||
            dueDate.second != 0;
        final overdue = hasTime
            ? dueDate.isBefore(now)
            : dueDay.add(const Duration(days: 1)).isBefore(now) ||
                dueDay.add(const Duration(days: 1)).isAtSameMomentAs(now);
        if (overdue) {
          overdueTasksCount++;
        }

        if (!dueDate.isBefore(today) && dueDate.isBefore(tomorrow)) {
          todayTasksCount++;
        }
      }

      // Get customers
      final customersResponse = await _supabase
          .from('customers')
          .select('id')
          .eq('workspace_id', workspaceId);

      final totalCustomers = customersResponse.length;

      return DashboardStats(
        totalProjects: totalProjects,
        activeProjects: activeProjects,
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        pendingTasks: pendingTasks,
        totalCustomers: totalCustomers,
        overdueTasksCount: overdueTasksCount,
        todayTasksCount: todayTasksCount,
        totalRevenue: totalRevenue,
      );
    } catch (e) {
      return DashboardStats(
        totalProjects: 0,
        activeProjects: 0,
        totalTasks: 0,
        completedTasks: 0,
        pendingTasks: 0,
        totalCustomers: 0,
        overdueTasksCount: 0,
        todayTasksCount: 0,
        totalRevenue: 0.0,
      );
    }
  }

  // Helper methods to convert Supabase format to Firestore format

  Map<String, dynamic> _toProjectFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'name': row['name'],
      'description': row['description'],
      'status': row['status'],
      'customerId': row['customer_id'],
      'customerName': row['customer_name'],
      'contractAmount': row['contract_amount'],
      'address': row['address'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : _FakeTimestamp(DateTime.now()),
      'createdBy': row['created_by'],
    };
  }

  Map<String, dynamic> _toTaskFirestoreFormat(Map<String, dynamic> row) {
    final projectJoin = row['projects'] as Map<String, dynamic>?;
    return {
      'workspaceId': row['workspace_id'],
      'projectId': row['project_id'],
      'projectName': projectJoin?['name'],
      'title': row['title'],
      'description': row['description'],
      'status': row['status'],
      'isComplete': row['is_complete'],
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
      'createdBy': row['assigned_to'],
    };
  }

  Map<String, dynamic> _toCustomerFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'name': row['name'],
      'email': row['email'],
      'phone': row['phone'],
      'company': row['company'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : _FakeTimestamp(DateTime.now()),
      'createdBy': row['created_by'],
    };
  }

  Map<String, dynamic> _toInvoiceFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'projectId': row['project_id'],
      'customerId': row['customer_id'],
      'customerName': row['customer_name'],
      'invoiceNumber': row['document_number'],
      'status': row['status'],
      'total': row['total_price'] ?? row['total_amount'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'createdBy': row['created_by'],
    };
  }

  Map<String, dynamic> _toPlanFirestoreFormat(Map<String, dynamic> row) {
    return {
      'workspaceId': row['workspace_id'],
      'projectId': row['project_id'],
      'name': row['name'],
      'fileName': row['file_name'],
      'uploadedAt': row['uploaded_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['uploaded_at']))
          : _FakeTimestamp(DateTime.now()),
      'uploadedBy': row['uploaded_by'],
    };
  }
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
