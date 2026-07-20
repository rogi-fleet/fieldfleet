import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../widgets/timeline/monday_gantt_widget.dart';
import '../services/service_locator.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';

/// Example showing how to integrate the new MondayGanttWidget
/// This replaces the old MondayTimelineWidget in your project detail screen
class ProjectTimelineTab extends StatelessWidget {
  final Project project;

  const ProjectTimelineTab({
    super.key,
    required this.project,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final taskService = ServiceLocator.taskService;

    return StreamBuilder<List<Task>>(
      stream: taskService.getTasks(project.id, workspaceId: workspaceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: SelectableText('Error: ${snapshot.error}'));
        }

        final tasks = snapshot.data ?? [];

        // OLD IMPLEMENTATION:
        // return MondayTimelineWidget(
        //   project: project,
        //   tasks: tasks,
        //   onTaskTap: _handleTaskTap,
        //   onTaskChanged: _handleTaskChanged,
        //   onTaskCreated: _handleTaskCreated,
        // );

        // NEW IMPLEMENTATION:
        return MondayGanttWidget(
          project: project,
          tasks: tasks,
          onTaskTap: (task) => _showTaskDetail(context, task),
          workspaceId: workspaceId,
        );
      },
    );
  }

  void _showTaskDetail(BuildContext context, Task task) {
    // Open task detail dialog/screen
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${task.status}'),
            Text('Priority: ${task.priority}'),
            Text('Progress: ${task.progress}%'),
            if (task.description != null) ...[
              const SizedBox(height: 8),
              Text(task.description!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// How to create sample hierarchical data for testing
Future<void> createSampleGanttData({
  required String workspaceId,
  required String projectId,
}) async {
  final taskService = ServiceLocator.taskService;
  final now = DateTime.now();

  // Create a summary task (parent)
  final summaryTask = await taskService.createTask(
    workspaceId: workspaceId,
    projectId: projectId,
    title: 'Frontend Development',
    taskType: TaskType.summary,
    status: 'working_on_it',
    priority: 'high',
    startDate: now,
    dueDate: now.add(const Duration(days: 30)),
  );

  // Create child tasks
  await taskService.createChildTask(
    workspaceId: workspaceId,
    projectId: projectId,
    title: 'Design UI mockups',
    parentId: summaryTask.id,
  );

  await taskService.createChildTask(
    workspaceId: workspaceId,
    projectId: projectId,
    title: 'Implement components',
    parentId: summaryTask.id,
  );

  // Create a milestone
  await taskService.createTask(
    workspaceId: workspaceId,
    projectId: projectId,
    title: 'Beta Launch',
    taskType: TaskType.milestone,
    status: 'not_started',
    priority: 'high',
    startDate: now.add(const Duration(days: 30)),
  );
}
