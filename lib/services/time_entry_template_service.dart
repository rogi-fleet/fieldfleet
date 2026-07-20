import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/time_entry_template.dart';
import '../utils/app_logger.dart';

class TimeEntryTemplateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<TimeEntryTemplate>> getTemplates({
    required String workspaceId,
    required String userId,
  }) {
    return _firestore
        .collection('time_entry_templates')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots()
        .map((snapshot) {
      final templates = snapshot.docs
          .map((doc) => TimeEntryTemplate.fromJson(doc.data(), doc.id))
          .where((template) => template.userId == null || template.userId == userId)
          .toList();
      templates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return templates;
    });
  }

  Future<TimeEntryTemplate> createTemplate({
    required String workspaceId,
    required String name,
    required String projectId,
    required String taskId,
    required String userId,
    bool shared = false,
    double defaultHours = 0,
    int defaultBreakMinutes = 0,
    String? notesTemplate,
  }) async {
    try {
      final now = DateTime.now();
      final templateRef = _firestore.collection('time_entry_templates').doc();
      final template = TimeEntryTemplate(
        id: templateRef.id,
        workspaceId: workspaceId,
        userId: shared ? null : userId,
        name: name,
        projectId: projectId,
        taskId: taskId,
        defaultHours: defaultHours,
        defaultBreakMinutes: defaultBreakMinutes,
        notesTemplate: notesTemplate,
        createdAt: now,
        updatedAt: now,
      );
      await templateRef.set(template.toJson());
      return template;
    } catch (e) {
      AppLogger.error('Failed to create time entry template', error: e);
      rethrow;
    }
  }

  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? projectId,
    String? taskId,
    double? defaultHours,
    int? defaultBreakMinutes,
    String? notesTemplate,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': Timestamp.now(),
      };
      if (name != null) updates['name'] = name;
      if (projectId != null) updates['projectId'] = projectId;
      if (taskId != null) updates['taskId'] = taskId;
      if (defaultHours != null) updates['defaultHours'] = defaultHours;
      if (defaultBreakMinutes != null) updates['defaultBreakMinutes'] = defaultBreakMinutes;
      if (notesTemplate != null) updates['notesTemplate'] = notesTemplate;

      await _firestore.collection('time_entry_templates').doc(templateId).update(updates);
    } catch (e) {
      AppLogger.error('Failed to update time entry template', error: e);
      rethrow;
    }
  }

  Future<void> deleteTemplate(String templateId) async {
    try {
      await _firestore.collection('time_entry_templates').doc(templateId).delete();
    } catch (e) {
      AppLogger.error('Failed to delete time entry template', error: e);
      rethrow;
    }
  }
}
