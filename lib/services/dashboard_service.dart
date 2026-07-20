import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/activity_item.dart';
import '../models/user.dart';
import 'user_service.dart';
import '../utils/app_logger.dart';

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

class DashboardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService = UserService();

  // Get recent activity across all collections
  Future<List<ActivityItem>> getRecentActivity(
    String workspaceId, {
    int limit = 20,
  }) async {
    try {
      final activities = <ActivityItem>[];

      // Get recent projects (no time filter, just get latest)
      try {
        final projectsQuery = await _firestore
            .collection('projects')
            .where('workspaceId', isEqualTo: workspaceId)
            .orderBy('updatedAt', descending: true)
            .limit(10)
            .get();

        for (var doc in projectsQuery.docs) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'projects',
              data: doc.data(),
              id: doc.id,
            ),
          );
        }
      } catch (e) {
        AppLogger.debug('Error fetching project activities', metadata: {'error': e.toString()});
      }

      // Get recent tasks (no time filter, just get latest)
      try {
        final tasksQuery = await _firestore
            .collection('tasks')
            .where('workspaceId', isEqualTo: workspaceId)
            .orderBy('updatedAt', descending: true)
            .limit(10)
            .get();

        for (var doc in tasksQuery.docs) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'tasks',
              data: doc.data(),
              id: doc.id,
            ),
          );
        }
      } catch (e) {
        AppLogger.debug('Error fetching task activities', metadata: {'error': e.toString()});
      }

      // Get recent customers
      try {
        final customersQuery = await _firestore
            .collection('customers')
            .where('workspaceId', isEqualTo: workspaceId)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get();

        for (var doc in customersQuery.docs) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'customers',
              data: doc.data(),
              id: doc.id,
            ),
          );
        }
      } catch (e) {
        AppLogger.debug('Error fetching customer activities', metadata: {'error': e.toString()});
      }

      // Get recent invoices
      try {
        final invoicesQuery = await _firestore
            .collection('invoices')
            .where('workspaceId', isEqualTo: workspaceId)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get();

        for (var doc in invoicesQuery.docs) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'invoices',
              data: doc.data(),
              id: doc.id,
            ),
          );
        }
      } catch (e) {
        AppLogger.debug('Error fetching invoice activities', metadata: {'error': e.toString()});
      }

      // Get recent plans
      try {
        final plansQuery = await _firestore
            .collection('plans')
            .where('workspaceId', isEqualTo: workspaceId)
            .orderBy('uploadedAt', descending: true)
            .limit(5)
            .get();

        for (var doc in plansQuery.docs) {
          activities.add(
            ActivityItem.fromDocument(
              collection: 'plans',
              data: doc.data(),
              id: doc.id,
            ),
          );
        }
      } catch (e) {
        AppLogger.debug('Error fetching plan activities', metadata: {'error': e.toString()});
      }

      // Sort all activities by timestamp
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Take only the most recent items up to limit
      final recentActivities = activities.take(limit).toList();

      // Populate user names
      await _populateUserNames(recentActivities);

      return recentActivities;
    } catch (e) {
      AppLogger.error('Failed to fetch recent activity', error: e, metadata: {'workspaceId': workspaceId});
      return [];
    }
  }

  // Populate user names for activities
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
        AppLogger.error('Failed to fetch user for activity', error: e, metadata: {'userId': userId});
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

  // Get dashboard statistics
  Future<DashboardStats> getDashboardStats(String workspaceId) async {
    try {
      // Get projects
      final projectsSnapshot = await _firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      final totalProjects = projectsSnapshot.docs.length;
      const openStatuses = {'active', 'awarded', 'on_hold'};
      final activeProjects = projectsSnapshot.docs
          .where((doc) => openStatuses.contains(doc.data()['status']))
          .length;
    
    // Calculate total revenue from all projects
    double totalRevenue = 0.0;
    for (var doc in projectsSnapshot.docs) {
      final data = doc.data();
      final contractAmount = data['contractAmount'] as double?;
      if (contractAmount != null) {
        totalRevenue += contractAmount;
      }
    }

      // Get tasks
      final tasksSnapshot = await _firestore
          .collection('tasks')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      final totalTasks = tasksSnapshot.docs.length;
      final completedTasks = tasksSnapshot.docs
          .where((doc) => doc.data()['status'] == 'completed')
          .length;
      final pendingTasks = tasksSnapshot.docs
          .where((doc) =>
              doc.data()['status'] == 'pending' ||
              doc.data()['status'] == 'in_progress')
          .length;

      // Count overdue and today's tasks
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      int overdueTasksCount = 0;
      int todayTasksCount = 0;

      for (var doc in tasksSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status == 'completed') continue;

        final dueDate = (data['dueDate'] as Timestamp?)?.toDate();
        if (dueDate == null) continue;

        if (dueDate.isBefore(now)) {
          overdueTasksCount++;
        }
        
        if (dueDate.isAfter(today) && dueDate.isBefore(tomorrow)) {
          todayTasksCount++;
        }
      }

      // Get customers
      final customersSnapshot = await _firestore
          .collection('customers')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      final totalCustomers = customersSnapshot.docs.length;

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
      AppLogger.error('Failed to fetch dashboard stats', error: e, metadata: {'workspaceId': workspaceId});
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
}
