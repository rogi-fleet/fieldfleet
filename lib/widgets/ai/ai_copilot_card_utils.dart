import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/project.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/app_radius.dart';
import '../../utils/project_terminology.dart';

class AiCopilotProjectScope {
  final bool enabled;
  final List<Project> projects;
  final String? selectedProjectId;

  const AiCopilotProjectScope({
    required this.enabled,
    required this.projects,
    required this.selectedProjectId,
  });
}

Future<AiCopilotProjectScope> loadAiCopilotProjectScope({
  required String workspaceId,
  required String flagKey,
  String? initialProjectId,
}) async {
  final enabled = await ServiceLocator.aiCopilotService.isFeatureEnabled(
    workspaceId: workspaceId,
    flagKey: flagKey,
  );
  if (!enabled) {
    return const AiCopilotProjectScope(
      enabled: false,
      projects: <Project>[],
      selectedProjectId: null,
    );
  }

  final dynamic projectsRaw = await ServiceLocator.projectService
      .getProjectsOnce(workspaceId);
  final projects = projectsRaw is List<Project>
      ? projectsRaw
      : projectsRaw is List
      ? projectsRaw.whereType<Project>().toList()
      : <Project>[];

  final selected =
      initialProjectId ?? (projects.isNotEmpty ? projects.first.id : null);
  return AiCopilotProjectScope(
    enabled: true,
    projects: projects,
    selectedProjectId: selected,
  );
}

class AiCopilotProjectDropdown extends StatelessWidget {
  final List<Project> projects;
  final String? value;
  final ValueChanged<String?>? onChanged;

  const AiCopilotProjectDropdown({
    super.key,
    required this.projects,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return const SizedBox.shrink();
    }

    final hint = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    return DropdownButton<String>(
      borderRadius: AppRadius.cardRadius,
      value: value,
      hint: Text(hint),
      isExpanded: true,
      onChanged: onChanged,
      items: projects
          .map(
            (p) => DropdownMenuItem<String>(
              value: p.id,
              child: Text(p.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
    );
  }
}
