import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../quick_action_config.dart';
import '../quick_actions_controller.dart';

/// Popup widget for quick action options shown as a bottom sheet.
class QuickActionPopup extends StatelessWidget {
  final QuickAction action;
  final void Function(String route) onNavigate;

  const QuickActionPopup({
    required this.action,
    required this.onNavigate,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final actions = _buildActionOptions(context, singularTerminology);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildHeader(context),
          const Divider(height: 1),
          ...actions,
          const SizedBox(height: AppSpacing.sm),
          _buildPopupToggle(context),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  List<Widget> _buildActionOptions(
    BuildContext context,
    String singularTerminology,
  ) {
    final options = <Widget>[];

    // Main action
    options.add(
      ListTile(
        leading: Icon(
          action.icon,
          color: Theme.of(context).primaryColor,
        ),
        title: Text(
          _displayLabel(singularTerminology),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: () {
          onNavigate(action.route);
        },
      ),
    );

    // Additional options based on action type
    switch (action.route) {
      case '/projects/new':
        options.addAll([
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: Text('$singularTerminology from Template'),
            onTap: () {
              onNavigate('/projects/new?template=true');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text('$singularTerminology from Existing'),
            onTap: () {
              onNavigate('/projects/clone');
            },
          ),
        ]);
        break;

      case '/tasks':
        options.addAll([
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_task_outlined),
            title: const Text('Quick Task'),
            onTap: () {
              onNavigate('/tasks/quick');
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Task with Date'),
            onTap: () {
              onNavigate('/tasks?date=today');
            },
          ),
        ]);
        break;

      case '/documents/create':
        options.addAll([
          const Divider(),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('Blank Document'),
            onTap: () {
              onNavigate('/documents/create');
            },
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Document from Template'),
            onTap: () {
              onNavigate('/documents/create?template=true');
            },
          ),
        ]);
        break;
    }

    return options;
  }

  Widget _buildHeader(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(
            action.icon,
            size: 32,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayLabel(singularTerminology),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Quick actions and shortcuts',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayLabel(String singularTerminology) {
    if (action.route == '/projects/new') {
      return 'New $singularTerminology';
    }
    return action.label;
  }

  Widget _buildPopupToggle(BuildContext context) {
    return Consumer<QuickActionsController>(
      builder: (context, controller, child) {
        return ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Show Quick Options'),
          subtitle: Text(
            controller.showPopup ? 'Enabled' : 'Disabled',
            style: TextStyle(
              color: controller.showPopup
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
            ),
          ),
          trailing: Switch(
            value: controller.showPopup,
            onChanged: (value) {
              controller.togglePopupBehavior();
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          onTap: () {
            controller.togglePopupBehavior();
          },
        );
      },
    );
  }
}
