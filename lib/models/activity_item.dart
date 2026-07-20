import 'package:cloud_firestore/cloud_firestore.dart';

enum ActivityType {
  projectCreated,
  projectUpdated,
  projectCompleted,
  taskCreated,
  taskUpdated,
  taskCompleted,
  customerCreated,
  invoiceCreated,
  planUploaded,
}

class ActivityItem {
  final String id;
  final ActivityType type;
  final String title;
  final String? description;
  final String? userId;
  final String? userName;
  final String? entityId; // Project ID, Task ID, etc.
  final String? entityName;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.userId,
    this.userName,
    this.entityId,
    this.entityName,
    required this.timestamp,
    this.metadata,
  });

  factory ActivityItem.fromDocument({
    required String collection,
    required Map<String, dynamic> data,
    required String id,
  }) {
    final updatedAt = _parseTimestamp(data['updatedAt']);
    final createdAt = _parseTimestamp(data['createdAt']);
    final timestamp = updatedAt ?? createdAt ?? DateTime.now();

    // Determine activity type based on collection and data
    ActivityType type;
    String title;
    String? description;
    String? entityName;

    switch (collection) {
      case 'projects':
        final isNew = createdAt != null && updatedAt != null && 
            createdAt.isAtSameMomentAs(updatedAt);
        type = isNew ? ActivityType.projectCreated : ActivityType.projectUpdated;
        entityName = data['name'] as String?;
        title = isNew ? 'New project created' : 'Project updated';
        
        // Build rich description with project details
        final descriptionParts = <String>[];

        // Prepend job number
        final purchaseOrderNumber = data['purchaseOrderNumber'] as String?;
        if (purchaseOrderNumber != null && purchaseOrderNumber.isNotEmpty) {
          descriptionParts.add('Job #$purchaseOrderNumber');
        }

        // Add project name
        if (entityName != null && entityName.isNotEmpty) {
          descriptionParts.add(entityName);
        }

        // Add customer name
        final customerName = data['customerName'] as String?;
        if (customerName != null && customerName.isNotEmpty) {
          descriptionParts.add('Customer: $customerName');
        }
        
        // Add contract amount
        final contractAmount = data['contractAmount'] as double?;
        if (contractAmount != null && contractAmount > 0) {
          descriptionParts.add('Amount: \$${contractAmount.toStringAsFixed(2)}');
        }
        
        // Add status
        final status = data['status'] as String?;
        if (status != null && status.isNotEmpty) {
          descriptionParts.add('Status: ${status[0].toUpperCase()}${status.substring(1)}');
        }
        
        // Add location
        final city = data['city'] as String?;
        final state = data['state'] as String?;
        if (city != null && city.isNotEmpty) {
          if (state != null && state.isNotEmpty) {
            descriptionParts.add('Location: $city, $state');
          } else {
            descriptionParts.add('Location: $city');
          }
        } else {
          final address = data['address'] as String?;
          if (address != null && address.isNotEmpty) {
            descriptionParts.add(address);
          }
        }

        description = descriptionParts.join(' • ');
        break;
      case 'tasks':
        final isComplete = data['isComplete'] as bool? ?? false;
        final taskName = data['title'] as String?;
        final projectName = data['projectName'] as String?;
        if (isComplete) {
          type = ActivityType.taskCompleted;
          title = 'Task completed';
        } else {
          final isNew = createdAt != null && updatedAt != null &&
              createdAt.isAtSameMomentAs(updatedAt);
          type = isNew ? ActivityType.taskCreated : ActivityType.taskUpdated;
          title = isNew ? 'New task created' : 'Task updated';
        }
        entityName = taskName;
        final taskDescParts = <String>[
          if (taskName != null && taskName.isNotEmpty) taskName,
          if (projectName != null && projectName.isNotEmpty) projectName,
        ];
        description = taskDescParts.isNotEmpty ? taskDescParts.join(' • ') : null;
        break;
      case 'customers':
        type = ActivityType.customerCreated;
        entityName = data['name'] as String?;
        title = 'New customer added';
        description = entityName;
        break;
      case 'invoices':
        type = ActivityType.invoiceCreated;
        entityName = data['invoiceNumber'] as String?;
        title = 'Invoice created';
        description = 'Invoice #$entityName';
        break;
      case 'plans':
        type = ActivityType.planUploaded;
        // Prefer fileName, fall back to plan name. Without either the
        // dashboard ends up showing N identical "Construction plan uploaded"
        // rows that users can't distinguish.
        final fileName = data['fileName'] as String?;
        final planName = data['name'] as String?;
        entityName = (fileName != null && fileName.isNotEmpty)
            ? fileName
            : planName;
        title = 'Construction plan uploaded';
        description = entityName;
        break;
      default:
        type = ActivityType.projectUpdated;
        title = 'Activity';
        description = null;
    }

    return ActivityItem(
      id: id,
      type: type,
      title: title,
      description: description,
      userId: data['createdBy'] as String? ?? data['userId'] as String?,
      userName: null, // Will be populated by service
      entityId: id,
      entityName: entityName,
      timestamp: timestamp,
      metadata: data,
    );
  }

  String getIcon() {
    switch (type) {
      case ActivityType.projectCreated:
      case ActivityType.projectUpdated:
        return '📁';
      case ActivityType.projectCompleted:
        return '✅';
      case ActivityType.taskCreated:
      case ActivityType.taskUpdated:
        return '📋';
      case ActivityType.taskCompleted:
        return '✓';
      case ActivityType.customerCreated:
        return '👤';
      case ActivityType.invoiceCreated:
        return '💰';
      case ActivityType.planUploaded:
        return '📐';
    }
  }

  String getRouteForEntity() {
    switch (type) {
      case ActivityType.projectCreated:
      case ActivityType.projectUpdated:
      case ActivityType.projectCompleted:
        return '/projects/$entityId';
      case ActivityType.taskCreated:
      case ActivityType.taskUpdated:
      case ActivityType.taskCompleted:
        // Tasks deep-link into the project Tasks tab and open the specific task.
        final projectId = metadata?['projectId'] as String?;
        if (projectId != null) {
          return '/projects/$projectId?tab=tasks&taskId=$entityId';
        }
        return '/tasks';
      case ActivityType.customerCreated:
        return '/customers/$entityId';
      case ActivityType.invoiceCreated:
        return '/documents/$entityId';
      case ActivityType.planUploaded:
        final projectId = metadata?['projectId'] as String?;
        if (projectId != null) {
          return '/projects/$projectId/plans';
        }
        return '/projects';
    }
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    } else if (value is Map && value.containsKey('toDate')) {
      // Handle potential map representation
      return (value as dynamic).toDate();
    } else {
      // Handle objects with toDate() method (like _FakeTimestamp)
      try {
        return (value as dynamic).toDate();
      } catch (e) {
        return null;
      }
    }
  }
}
