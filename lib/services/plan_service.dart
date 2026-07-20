import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/construction_plan.dart';
import '../models/plan_discipline.dart';
import '../utils/app_logger.dart';

class PlanService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Get all plans for a project
  Stream<List<ConstructionPlan>> getPlans(String projectId, String workspaceId) {
    return _firestore
        .collection('plans')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .orderBy('discipline')
        .orderBy('sheetNumber')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ConstructionPlan.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get a single plan by ID
  Future<ConstructionPlan?> getPlan(String planId, String workspaceId) async {
    try {
      final doc =
          await _firestore.collection('plans').doc(planId).get();
      if (doc.exists && doc.data()?['workspaceId'] == workspaceId) {
        return ConstructionPlan.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw Exception('Error fetching plan: $e');
    }
  }

  // Get a single plan stream by ID
  Stream<ConstructionPlan?> getPlanStream(String planId, String workspaceId) {
    return _firestore
        .collection('plans')
        .doc(planId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data()?['workspaceId'] == workspaceId) {
        return ConstructionPlan.fromJson(snapshot.data()!, snapshot.id);
      }
      return null;
    });
  }

  // Get only current version plans
  Stream<List<ConstructionPlan>> getCurrentPlans(String projectId, String workspaceId) {
    return _firestore
        .collection('plans')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('isCurrentVersion', isEqualTo: true)
        .orderBy('discipline')
        .orderBy('sheetNumber')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ConstructionPlan.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get all versions of a specific sheet
  Stream<List<ConstructionPlan>> getPlanVersions(
      String projectId, String workspaceId, String sheetNumber) {
    return _firestore
        .collection('plans')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('sheetNumber', isEqualTo: sheetNumber)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ConstructionPlan.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get version history for a plan
  Future<List<ConstructionPlan>> getVersionHistory(
    String projectId,
    String workspaceId,
    String name,
    String? sheetNumber,
  ) async {
    try {
      var query = _firestore
          .collection('plans')
          .where('projectId', isEqualTo: projectId)
          .where('workspaceId', isEqualTo: workspaceId)
          .where('name', isEqualTo: name);

      if (sheetNumber != null) {
        query = query.where('sheetNumber', isEqualTo: sheetNumber);
      }

      final snapshot = await query.orderBy('uploadedAt', descending: true).get();
      return snapshot.docs
          .map((doc) => ConstructionPlan.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error fetching version history: $e');
    }
  }

  // Get plans by discipline
  Stream<List<ConstructionPlan>> getPlansByDiscipline(
      String projectId, String workspaceId, PlanDiscipline discipline) {
    return _firestore
        .collection('plans')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('discipline', isEqualTo: discipline.toString())
        .orderBy('sheetNumber')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ConstructionPlan.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Upload a new plan
  Future<ConstructionPlan> uploadPlan({
    required File pdfFile,
    required String projectId,
    required String workspaceId,
    required String name,
    required PlanDiscipline discipline,
    String? sheetNumber,
    String? version,
    DateTime? drawingDate,
    bool isCurrentVersion = true,
    String? notes,
    required String uploadedBy,
  }) async {
    try {
      // Validate PDF file
      if (!pdfFile.path.toLowerCase().endsWith('.pdf')) {
        throw Exception('File must be a PDF');
      }

      final fileSize = await pdfFile.length();
      if (fileSize > 50 * 1024 * 1024) {
        // 50MB limit
        throw Exception('File size must be less than 50MB');
      }

      final now = DateTime.now();
      final planId = _firestore.collection('plans').doc().id;

      // Upload to Firebase Storage
      final storagePath =
          'workspaces/$workspaceId/projects/$projectId/plans/$planId.pdf';
      final uploadTask = _storage.ref(storagePath).putFile(pdfFile);
      final snapshot = await uploadTask;
      final fileUrl = await snapshot.ref.getDownloadURL();

      // If this is set as current version, update other plans with same sheet number
      if (isCurrentVersion && sheetNumber != null) {
        await _setOtherVersionsAsNonCurrent(projectId, workspaceId, sheetNumber, planId);
      }

      // Create plan document
      final planData = {
        'workspaceId': workspaceId,
        'projectId': projectId,
        'name': name,
        'discipline': discipline.toString(),
        'sheetNumber': sheetNumber,
        'version': version,
        'isCurrentVersion': isCurrentVersion,
        'drawingDate':
            drawingDate != null ? Timestamp.fromDate(drawingDate) : null,
        'fileUrl': fileUrl,
        'fileName': pdfFile.path.split('/').last,
        'fileSize': fileSize,
        'uploadedBy': uploadedBy,
        'uploadedAt': Timestamp.fromDate(now),
        'notes': notes,
        'linkedTaskIds': [],
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      await _firestore
          .collection('plans')
          .doc(planId)
          .set(planData);

      return ConstructionPlan.fromJson(planData, planId);
    } catch (e) {
      throw Exception('Error uploading plan: $e');
    }
  }

  // Set a plan as the current version
  Future<void> setCurrentVersion(
    String planId,
    String projectId,
    String workspaceId,
    String name,
    String? sheetNumber,
  ) async {
    try {
      final plan = await getPlan(planId, workspaceId);
      if (plan == null) {
        throw Exception('Plan not found');
      }

      final effectiveSheetNumber = sheetNumber ?? plan.sheetNumber;
      if (effectiveSheetNumber == null) {
        throw Exception('Sheet number is required to set current version');
      }

      // Set other versions to non-current
      await _setOtherVersionsAsNonCurrent(
          plan.projectId, plan.workspaceId, effectiveSheetNumber, planId);

      // Set this plan as current
      await _firestore.collection('plans').doc(planId).update({
        'isCurrentVersion': true,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Error setting current version: $e');
    }
  }

  // Helper to set other versions as non-current
  Future<void> _setOtherVersionsAsNonCurrent(
      String projectId, String workspaceId, String sheetNumber, String excludePlanId) async {
    final snapshot = await _firestore
        .collection('plans')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('sheetNumber', isEqualTo: sheetNumber)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      if (doc.id != excludePlanId) {
        batch.update(doc.reference, {
          'isCurrentVersion': false,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      }
    }
    await batch.commit();
  }

  // Delete a plan
  Future<void> deletePlan(String planId, String workspaceId, {bool force = false}) async {
    try {
      final plan = await getPlan(planId, workspaceId);
      if (plan == null) {
        throw Exception('Plan not found');
      }

      // Check if plan is current version
      if (plan.isCurrentVersion && !force) {
        throw Exception(
            'Cannot delete current version. Set another version as current first, or use force=true.');
      }

      // Delete from Storage (skip for editor-only plans without a PDF)
      try {
        final pdfUrl = plan.fileUrl;
        if (pdfUrl != null && pdfUrl.isNotEmpty) {
          final ref = _storage.refFromURL(pdfUrl);
          await ref.delete();
        }
      } catch (e) {
        AppLogger.warning('Could not delete plan file from storage', metadata: {
          'planId': planId,
          'error': e.toString(),
        });
        // Continue with document deletion even if storage deletion fails
      }

      // Delete from Firestore
      await _firestore.collection('plans').doc(planId).delete();
    } catch (e) {
      throw Exception('Error deleting plan: $e');
    }
  }

  // Link plan to task
  Future<void> linkPlanToTask(String planId, String taskId) async {
    try {
      await _firestore.collection('plans').doc(planId).update({
        'linkedTaskIds': FieldValue.arrayUnion([taskId]),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Error linking plan to task: $e');
    }
  }

  // Unlink plan from task
  Future<void> unlinkPlanFromTask(String planId, String taskId) async {
    try {
      await _firestore.collection('plans').doc(planId).update({
        'linkedTaskIds': FieldValue.arrayRemove([taskId]),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Error unlinking plan from task: $e');
    }
  }

  // Get all plans linked to a task
  Future<List<ConstructionPlan>> getTaskPlans(String taskId, String workspaceId) async {
    try {
      final snapshot = await _firestore
          .collection('plans')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('linkedTaskIds', arrayContains: taskId)
          .get();

      return snapshot.docs
          .map((doc) => ConstructionPlan.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error fetching task plans: $e');
    }
  }

  // Search plans
  Future<List<ConstructionPlan>> searchPlans(
      String projectId, String workspaceId, String query) async {
    try {
      // Get all plans for the project
      final snapshot = await _firestore
          .collection('plans')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('projectId', isEqualTo: projectId)
          .get();

      // Filter locally (Firestore doesn't support full-text search)
      final queryLower = query.toLowerCase();
      return snapshot.docs
          .map((doc) => ConstructionPlan.fromJson(doc.data(), doc.id))
          .where((plan) {
        return plan.name.toLowerCase().contains(queryLower) ||
            (plan.sheetNumber?.toLowerCase().contains(queryLower) ?? false) ||
            (plan.version?.toLowerCase().contains(queryLower) ?? false) ||
            (plan.notes?.toLowerCase().contains(queryLower) ?? false);
      }).toList();
    } catch (e) {
      throw Exception('Error searching plans: $e');
    }
  }
}
