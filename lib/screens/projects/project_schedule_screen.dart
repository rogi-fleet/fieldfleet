import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../utils/project_terminology.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/timeline/unified_gantt_widget.dart';
import '../../widgets/projects/save_task_group_as_template_dialog.dart';
import '../../widgets/projects/import_task_template_dialog.dart';

class ProjectScheduleScreen extends StatefulWidget {
  final String projectId;
  final String? externalSearchQuery;
  final bool? externalHideDone;
  final bool? externalMyTasksOnly;

  const ProjectScheduleScreen({
    super.key,
    required this.projectId,
    this.externalSearchQuery,
    this.externalHideDone,
    this.externalMyTasksOnly,
  });

  @override
  State<ProjectScheduleScreen> createState() => _ProjectScheduleScreenState();
}

class _ProjectScheduleScreenState extends State<ProjectScheduleScreen> {
  Project? _project;
  bool _isLoading = true;
  String? _error;
  bool _loadTriggered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // On a cold deep-link load (e.g. /projects/:id/schedule) the Supabase
    // session is restored asynchronously. Until it is, RLS hides the project
    // row and getProject() returns null — which previously rendered a
    // permanent "not found". Defer the first load until the authenticated user
    // is available (which implies the session is active), and re-run when
    // AuthProvider notifies. listen:true here registers the dependency so
    // didChangeDependencies fires again once auth resolves.
    final appUser = Provider.of<AuthProvider>(context).appUser;
    if (!_loadTriggered && appUser != null) {
      _loadTriggered = true;
      _loadProject();
    }
  }

  Future<void> _loadProject() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final project = await ServiceLocator.projectService.getProject(
        widget.projectId,
      );
      if (mounted) {
        setState(() {
          _project = project;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = UserFacingError.uiMessage(e, action: 'load this project');
          _isLoading = false;
        });
      }
    }
  }

  void _handleTaskTap(Task task) {
    // Navigate to task detail or edit
    context.push('/projects/${widget.projectId}/tasks/${task.id}/edit');
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final singular = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _project == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error ?? '$singular not found',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadProject, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (workspaceId == null) {
      return const Center(child: Text('No workspace found'));
    }

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Task>>(
            stream: ServiceLocator.taskService.getTasks(
              widget.projectId,
              workspaceId: workspaceId,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        UserFacingError.uiMessage(
                          snapshot.error,
                          action: 'load tasks',
                        ),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var tasks = snapshot.data!;

              // Apply my tasks filter
              if (widget.externalMyTasksOnly == true) {
                final currentUserId = authProvider.appUser?.id;
                if (currentUserId != null) {
                  tasks = tasks
                      .where((t) => t.assignedToIds.contains(currentUserId))
                      .toList();
                }
              }

              // Apply external filters
              if (widget.externalHideDone == true) {
                tasks = tasks
                    .where((t) => !t.isComplete && t.status != 'done')
                    .toList();
              }
              final searchQuery =
                  widget.externalSearchQuery?.trim().toLowerCase() ?? '';
              if (searchQuery.isNotEmpty) {
                tasks = tasks.where((t) {
                  return t.title.toLowerCase().contains(searchQuery) ||
                      (t.description?.toLowerCase().contains(searchQuery) ??
                          false);
                }).toList();
              }

              // Always show the Gantt chart with timeline and add task input,
              // even when there are no tasks
              return UnifiedGanttWidget(
                project: _project,
                tasks: tasks,
                onTaskTap: _handleTaskTap,
                workspaceId: workspaceId,
                onTaskChanged: (task) async {
                  try {
                    await ServiceLocator.taskService.updateTask(
                      taskId: task.id,
                      title: task.title,
                      startDate: task.startDate,
                      dueDate: task.dueDate,
                      estimatedDuration: task.estimatedDuration,
                      isComplete: task.isComplete,
                      progress: task.progress,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update task: $e')),
                      );
                    }
                  }
                },
                onTaskCreated: (title, parentId) async {
                  try {
                    if (parentId != null) {
                      await ServiceLocator.taskService.createChildTask(
                        workspaceId: _project!.workspaceId,
                        projectId: widget.projectId,
                        title: title,
                        parentId: parentId,
                      );
                    } else {
                      await ServiceLocator.taskService.createTask(
                        workspaceId: _project!.workspaceId,
                        projectId: widget.projectId,
                        title: title,
                        startDate: DateTime.now(),
                        dueDate: DateTime.now().add(const Duration(days: 1)),
                        estimatedDuration: 8,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to create task: $e')),
                      );
                    }
                  }
                },
                onTaskDelete: (task) async {
                  try {
                    // Confirm deletion
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Task'),
                        content: Text(
                          'Are you sure you want to delete "${task.title}"?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await ServiceLocator.taskService.deleteTask(task.id);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to delete task: $e')),
                      );
                    }
                  }
                },
                onAddTask: () async {
                  try {
                    await ServiceLocator.taskService.createTask(
                      workspaceId: _project!.workspaceId,
                      projectId: widget.projectId,
                      title: 'New Task',
                      taskType: TaskType.standard,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to create task: $e')),
                      );
                    }
                  }
                },
                onAddGroup: () async {
                  try {
                    await ServiceLocator.taskService.createGroup(
                      workspaceId: _project!.workspaceId,
                      projectId: widget.projectId,
                      title: 'New Group',
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to create group: $e')),
                      );
                    }
                  }
                },
                onGroupCreated: (title, parentId) async {
                  try {
                    await ServiceLocator.taskService.createGroup(
                      workspaceId: _project!.workspaceId,
                      projectId: widget.projectId,
                      title: title,
                      parentId: parentId,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to create group: $e')),
                      );
                    }
                  }
                },
                onConvertTaskType: (task, newType) async {
                  try {
                    await ServiceLocator.taskService.updateTaskType(
                      task.id,
                      newType,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to convert task: $e')),
                      );
                    }
                  }
                },
                onSaveAsTemplate: (task) async {
                  await showSaveTaskGroupAsTemplateDialog(
                    context,
                    rootTask: task,
                    projectId: widget.projectId,
                    workspaceId: _project!.workspaceId,
                  );
                },
                onImportTemplate: (parentId) async {
                  await showImportTaskTemplateDialog(
                    context,
                    projectId: widget.projectId,
                    workspaceId: _project!.workspaceId,
                    parentId: parentId,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
