import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../../../widgets/messaging_popup.dart';
import '../../../widgets/project_form_popup.dart';
import '../../../widgets/project_selector_dialog.dart';
import '../../../widgets/task_form_popup.dart';
import '../quick_action_config.dart';
import '../quick_actions_controller.dart';

/// Default actions used when the controller has no saved config.
const _defaultActions = [
  QuickAction(
    label: 'New Project',
    icon: Icons.add_business,
    route: '/projects/new',
  ),
  QuickAction(
    label: 'New Task',
    icon: Icons.add_task,
    route: '/tasks',
  ),
  QuickAction(
    label: 'New Message',
    icon: Icons.chat,
    route: '/messages/new',
  ),
  QuickAction(
    label: 'New Document',
    icon: Icons.note_add,
    route: '/documents/create',
  ),
];

/// Horizontal row of action chips for quick creation actions.
class QuickActionsBar extends StatelessWidget {
  const QuickActionsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Consumer<QuickActionsController>(
      builder: (context, controller, _) {
        final actions = controller.actions.isNotEmpty
            ? controller.actions
            : _defaultActions;

        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: actions.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final action = actions[index];
              return ActionChip(
                avatar: Icon(action.icon, size: 18),
                label: Text(_displayLabel(action, singularTerminology)),
                onPressed: () => _onActionTap(context, action),
              );
            },
          ),
        );
      },
    );
  }

  void _onActionTap(BuildContext context, QuickAction action) {
    switch (action.route) {
      case '/projects/new':
        showProjectFormPopup(context);
        break;
      case '/tasks':
        _showWithProjectSelector(
          context,
          (projectId) => showTaskFormPopup(context, projectId: projectId),
        );
        break;
      case '/messages/new':
        showMessagingPopup(context);
        break;
      default:
        // For document and any other actions, use the route directly.
        context.go(action.route);
        break;
    }
  }

  String _displayLabel(QuickAction action, String singularTerminology) {
    if (action.route == '/projects/new') {
      return 'New $singularTerminology';
    }
    return action.label;
  }

  Future<void> _showWithProjectSelector(
    BuildContext context,
    Function(String) onProjectSelected,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';

    if (workspaceId.isEmpty) return;

    final project = await showDialog<Project>(
      context: context,
      builder: (context) => ProjectSelectorDialog(workspaceId: workspaceId),
    );

    if (project != null) {
      onProjectSelected(project.id);
    }
  }
}
