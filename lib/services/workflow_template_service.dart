import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workflow_template.dart';

class WorkflowTemplateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<WorkflowTemplate>> getTemplates(String workspaceId) {
    return _firestore
        .collection('workflow_templates')
        .where('workspaceId', isEqualTo: workspaceId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return WorkflowTemplate(
              id: doc.id,
              workspaceId: data['workspaceId'] as String? ?? '',
              name: data['name'] as String? ?? '',
              slug: data['slug'] as String? ?? '',
              description: data['description'] as String?,
              workflowMarkdown: data['workflowMarkdown'] as String? ?? '',
              workflowSchema:
                  (data['workflowSchema'] as Map?)?.cast<String, dynamic>() ??
                  const {},
              isSystem: data['isSystem'] as bool? ?? false,
              createdBy: data['createdBy'] as String? ?? '',
              createdAt:
                  (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              updatedAt:
                  (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            );
          }).toList();
        });
  }

  Future<void> initializeCoreTemplates({
    required String workspaceId,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final defaults = [
      {
        'slug': 'roof-tarping-emergency',
        'name': 'Roof Tarping Emergency Workflow',
        'description':
            'Emergency roof weatherproofing with safety-first sequencing and follow-up checks.',
      },
      {
        'slug': 'water-damage-mitigation',
        'name': 'Water Damage Mitigation Workflow',
        'description':
            'Water extraction, drying, monitoring, and mitigation closeout workflow.',
      },
    ];

    for (final d in defaults) {
      final existing = await _firestore
          .collection('workflow_templates')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('slug', isEqualTo: d['slug'])
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) continue;

      await _firestore.collection('workflow_templates').add({
        'workspaceId': workspaceId,
        'name': d['name'],
        'slug': d['slug'],
        'description': d['description'],
        'workflowMarkdown':
            '# ${d['name']}\n\nUse this as a baseline and customize per workspace.',
        'workflowSchema': const {},
        'isSystem': true,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    }
  }

  Future<WorkflowTemplate> createTemplate({
    required String workspaceId,
    required String name,
    required String slug,
    String? description,
    required String workflowMarkdown,
    Map<String, dynamic> workflowSchema = const {},
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final ref = await _firestore.collection('workflow_templates').add({
      'workspaceId': workspaceId,
      'name': name,
      'slug': slug,
      'description': description,
      'workflowMarkdown': workflowMarkdown,
      'workflowSchema': workflowSchema,
      'isSystem': false,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });

    return WorkflowTemplate(
      id: ref.id,
      workspaceId: workspaceId,
      name: name,
      slug: slug,
      description: description,
      workflowMarkdown: workflowMarkdown,
      workflowSchema: workflowSchema,
      isSystem: false,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? description,
    String? slug,
    String? workflowMarkdown,
    Map<String, dynamic>? workflowSchema,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (slug != null) updates['slug'] = slug;
    if (workflowMarkdown != null) {
      updates['workflowMarkdown'] = workflowMarkdown;
    }
    if (workflowSchema != null) updates['workflowSchema'] = workflowSchema;

    await _firestore
        .collection('workflow_templates')
        .doc(templateId)
        .update(updates);
  }

  Future<WorkflowTemplate> duplicateTemplate({
    required WorkflowTemplate template,
    required String createdBy,
  }) async {
    return createTemplate(
      workspaceId: template.workspaceId,
      name: '${template.name} (Copy)',
      slug: '${template.slug}-copy-${DateTime.now().millisecondsSinceEpoch}',
      description: template.description,
      workflowMarkdown: template.workflowMarkdown,
      workflowSchema: template.workflowSchema,
      createdBy: createdBy,
    );
  }

  Future<void> deleteTemplate(String templateId) async {
    await _firestore.collection('workflow_templates').doc(templateId).delete();
  }
}
