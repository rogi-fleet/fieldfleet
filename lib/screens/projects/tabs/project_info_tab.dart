import 'package:flutter/material.dart';
import '../../../models/project.dart';
import 'project_properties_tab.dart';

/// Project info surface: the properties view is the operational primary view.
class ProjectInfoTab extends StatelessWidget {
  final Project project;
  final VoidCallback? onNavigateToTasks;
  final void Function(String propertyId)? onOpenTasksForProperty;

  const ProjectInfoTab({
    super.key,
    required this.project,
    this.onNavigateToTasks,
    this.onOpenTasksForProperty,
  });

  @override
  Widget build(BuildContext context) {
    return ProjectPropertiesTab(
      project: project,
      onOpenTasksForProperty: onOpenTasksForProperty,
    );
  }
}
