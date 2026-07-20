import 'package:flutter/material.dart';
import '../../../models/project.dart';
import '../../../widgets/notes/entity_notes_tab.dart';

class ProjectNotesTab extends StatelessWidget {
  final Project project;

  const ProjectNotesTab({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    return EntityNotesTab(
      workspaceId: project.workspaceId,
      entityType: 'project',
      entityId: project.id,
      projectId: project.id,
      entityTitle: project.name,
    );
  }
}
