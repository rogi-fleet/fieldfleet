import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../services/service_locator.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../models/property.dart';
import '../../models/task.dart';
import '../../widgets/timeline/unified_gantt_widget.dart';
import '../../widgets/task_form_popup.dart';
import '../../widgets/projects/save_task_group_as_template_dialog.dart';
import '../../widgets/projects/import_task_template_dialog.dart';
import '../../theme/theme.dart';
import '../../utils/task_filter_engine.dart';
import '../../utils/user_facing_error.dart';

class ScheduleDashboardScreen extends StatefulWidget {
  final bool showAppBar;
  final bool hideProjectSelector;
  final bool? externalMyTasksOnly;
  final bool? externalHideDone;
  final String? externalSearchQuery;
  final String? externalPropertyFilterId;
  final bool? externalOverdueOnly;
  final String? externalCustomerFilterId;
  final String? externalPriorityFilter;
  final String? externalAssigneeFilterId;
  final DateTime? externalDueDateStart;
  final DateTime? externalDueDateEnd;
  final Map<String, Project>? externalProjectMap;

  const ScheduleDashboardScreen({
    super.key,
    this.showAppBar = true,
    this.hideProjectSelector = false,
    this.externalMyTasksOnly,
    this.externalHideDone,
    this.externalSearchQuery,
    this.externalPropertyFilterId,
    this.externalOverdueOnly,
    this.externalCustomerFilterId,
    this.externalPriorityFilter,
    this.externalAssigneeFilterId,
    this.externalDueDateStart,
    this.externalDueDateEnd,
    this.externalProjectMap,
  });

  @override
  State<ScheduleDashboardScreen> createState() =>
      _ScheduleDashboardScreenState();
}

class _ScheduleDashboardScreenState extends State<ScheduleDashboardScreen> {
  String? _selectedProjectId;
  bool _hasInitialized = false;
  Map<String, int> _taskCounts = {};
  bool _showMyTasksOnly = false;
  final _ganttKey = GlobalKey<UnifiedGanttWidgetState>();

  bool get _effectiveMyTasksOnly =>
      widget.externalMyTasksOnly ?? _showMyTasksOnly;

  bool get _effectiveHideDone => widget.externalHideDone ?? false;

  String get _normalizedSearchQuery =>
      widget.externalSearchQuery?.trim().toLowerCase() ?? '';

  void _loadTaskCounts(List<Project> projects, String workspaceId) async {
    final taskService = ServiceLocator.taskService;
    final counts = <String, int>{};

    for (final project in projects) {
      try {
        final count = await taskService.getTaskCount(
          project.id,
          workspaceId: workspaceId,
        );
        counts[project.id] = count;
      } catch (e) {
        counts[project.id] = 0;
      }
    }

    if (mounted) {
      setState(() {
        _taskCounts = counts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      if (widget.showAppBar) {
        return const Scaffold(body: Center(child: Text('No workspace found')));
      }
      return const Center(child: Text('No workspace found'));
    }

    final mainContent = _buildMainContent(workspaceId);

    // If not showing AppBar, just return the content
    if (!widget.showAppBar) {
      return mainContent;
    }

    // Wrap in Scaffold with AppBar
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          // My Tasks filter toggle
          if (widget.externalMyTasksOnly == null)
            Tooltip(
              message: _effectiveMyTasksOnly
                  ? 'Showing My Tasks'
                  : 'Show My Tasks Only',
              child: IconButton(
                icon: Icon(
                  _effectiveMyTasksOnly ? Icons.assignment_ind : Icons.assignment,
                  color: _effectiveMyTasksOnly
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: () {
                  setState(() {
                    _showMyTasksOnly = !_showMyTasksOnly;
                  });
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () => _ganttKey.currentState?.scrollToToday(),
            tooltip: 'Jump to Today',
          ),
        ],
      ),
      body: mainContent,
    );
  }

  Widget _buildMainContent(String workspaceId) {
    if (widget.hideProjectSelector) {
      return _buildWorkspaceSchedule(workspaceId);
    }

    return Column(
      children: [
        _buildProjectSelectorSection(workspaceId),
        Expanded(
          child: !_hasInitialized
              ? const Center(child: CircularProgressIndicator())
              : _selectedProjectId == null
              ? _buildAllProjectsSchedule(workspaceId)
              : _buildProjectSchedule(_selectedProjectId!),
        ),
      ],
    );
  }

  Widget _buildProjectSelectorSection(String workspaceId) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: StreamBuilder<List<Project>>(
        stream: ServiceLocator.projectService.getProjects(workspaceId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              UserFacingError.uiMessage(
                snapshot.error,
                action: 'load projects',
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final projects = snapshot.data!;

          if (projects.isEmpty) {
            final ptLower = context.read<WorkspaceProvider>().projectTerminology.toLowerCase();
            return Text('No $ptLower available');
          }

          if (!_hasInitialized &&
              _selectedProjectId == null &&
              projects.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _selectedProjectId = projects.first.id;
                  _hasInitialized = true;
                });
                _loadTaskCounts(projects, workspaceId);
              }
            });
          }

          return Row(
            children: [
              const Icon(Icons.filter_list, size: 20),
              const SizedBox(width: 12),
              const Text(
                'Project:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  borderRadius: AppRadius.cardRadius,
                  value: _selectedProjectId,
                  isExpanded: true,
                  hint: Text('Select a ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology).toLowerCase()}'),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text('All ${context.read<WorkspaceProvider>().projectTerminology}'),
                    ),
                    ...projects.map((project) {
                      final taskCount = _taskCounts[project.id];
                      final countText = taskCount != null
                          ? ' ($taskCount ${taskCount == 1 ? 'task' : 'tasks'})'
                          : '';
                      return DropdownMenuItem<String>(
                        value: project.id,
                        child: Text('${project.name}$countText'),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedProjectId = value;
                      _hasInitialized = true;
                    });
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProjectSchedule(String projectId) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    return FutureBuilder<Project?>(
      future: ServiceLocator.projectService.getProject(
        projectId,
        workspaceId: workspaceId,
      ),
      builder: (context, projectSnapshot) {
        if (projectSnapshot.hasError) {
          return Center(
            child: Text(
              UserFacingError.uiMessage(
                projectSnapshot.error,
                action: 'load this project',
              ),
            ),
          );
        }

        if (!projectSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final project = projectSnapshot.data;
        if (project == null) {
          return Center(child: Text('${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)} not found'));
        }

        return StreamBuilder<List<Property>>(
          stream: ServiceLocator.propertyService.getPropertiesByWorkspace(
            project.workspaceId,
          ),
          builder: (context, propertySnapshot) {
            final propertyMap = {
              for (final property in (propertySnapshot.data ?? <Property>[]))
                property.id: property,
            };

            return StreamBuilder<List<Task>>(
              stream: ServiceLocator.taskService.getTasks(
                projectId,
                workspaceId: project.workspaceId,
              ),
              builder: (context, tasksSnapshot) {
                if (tasksSnapshot.hasError) {
                  return Center(
                    child: Text(
                      UserFacingError.uiMessage(
                        tasksSnapshot.error,
                        action: 'load tasks',
                      ),
                    ),
                  );
                }

                if (tasksSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allTasks = tasksSnapshot.data ?? [];
                final currentUserId = context.read<AuthProvider>().appUser?.id;
                final projectMap2 = widget.externalProjectMap != null
                    ? {...widget.externalProjectMap!, project.id: project}
                    : {project.id: project};
                final tasks = TaskFilterEngine.apply(
                  allTasks,
                  options: TaskFilterOptions(
                    myTasksOnly: _effectiveMyTasksOnly,
                    hideDone: _effectiveHideDone,
                    currentUserId: currentUserId,
                    propertyFilterId: widget.externalPropertyFilterId,
                    query: _normalizedSearchQuery,
                    overdueOnly: widget.externalOverdueOnly ?? false,
                    customerId: widget.externalCustomerFilterId,
                    priority: widget.externalPriorityFilter,
                    assigneeId: widget.externalAssigneeFilterId,
                    dueDateStart: widget.externalDueDateStart,
                    dueDateEnd: widget.externalDueDateEnd,
                  ),
                  context: TaskFilterContext(
                    projectMap: projectMap2,
                    propertyMap: propertyMap,
                  ),
                );

                if (tasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _effectiveMyTasksOnly
                              ? Icons.person_off
                              : Icons.calendar_today,
                          size: 80,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _effectiveMyTasksOnly
                              ? 'No tasks assigned to you'
                              : 'No tasks scheduled yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _effectiveMyTasksOnly
                              ? 'Tasks assigned to you will appear here'
                              : 'Add tasks with dates to see them here',
                          style: TextStyle(color: AppColors.textTertiary),
                        ),
                        const SizedBox(height: 24),
                        if (!_effectiveMyTasksOnly)
                          ElevatedButton.icon(
                            onPressed: () {
                              showTaskFormPopup(context, projectId: projectId);
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add Task'),
                          ),
                      ],
                    ),
                  );
                }

                return _buildProjectGantt(
                  project: project,
                  projectId: projectId,
                  tasks: tasks,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWorkspaceSchedule(String workspaceId) {
    final currentUserId = context.watch<AuthProvider>().appUser?.id;

    return StreamBuilder<List<Project>>(
      stream: ServiceLocator.projectService.getProjects(workspaceId),
      builder: (context, projectSnapshot) {
        if (projectSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (projectSnapshot.hasError) {
          return Center(
            child: Text(
              UserFacingError.uiMessage(
                projectSnapshot.error,
                action: 'load projects',
              ),
            ),
          );
        }

        final projects = projectSnapshot.data ?? <Project>[];
        final projectMap = {
          for (final project in projects) project.id: project,
        };

        return StreamBuilder<List<Property>>(
          stream: ServiceLocator.propertyService.getPropertiesByWorkspace(
            workspaceId,
          ),
          builder: (context, propertySnapshot) {
            final propertyMap = {
              for (final property in (propertySnapshot.data ?? <Property>[]))
                property.id: property,
            };

            return StreamBuilder<List<Task>>(
              stream: ServiceLocator.taskService.getAllWorkspaceTasks(
                workspaceId,
              ),
              builder: (context, tasksSnapshot) {
                if (tasksSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (tasksSnapshot.hasError) {
                  return Center(
                    child: Text(
                      UserFacingError.uiMessage(
                        tasksSnapshot.error,
                        action: 'load tasks',
                      ),
                    ),
                  );
                }

                final allTasks = tasksSnapshot.data ?? <Task>[];
                final mergedProjectMap = widget.externalProjectMap != null
                    ? {...widget.externalProjectMap!, ...projectMap}
                    : projectMap;
                final tasks = TaskFilterEngine.apply(
                  allTasks,
                  options: TaskFilterOptions(
                    myTasksOnly: _effectiveMyTasksOnly,
                    hideDone: _effectiveHideDone,
                    currentUserId: currentUserId,
                    propertyFilterId: widget.externalPropertyFilterId,
                    query: _normalizedSearchQuery,
                    overdueOnly: widget.externalOverdueOnly ?? false,
                    customerId: widget.externalCustomerFilterId,
                    priority: widget.externalPriorityFilter,
                    assigneeId: widget.externalAssigneeFilterId,
                    dueDateStart: widget.externalDueDateStart,
                    dueDateEnd: widget.externalDueDateEnd,
                  ),
                  context: TaskFilterContext(
                    projectMap: mergedProjectMap,
                    propertyMap: propertyMap,
                  ),
                );

                if (tasks.isEmpty) {
                  return Center(
                    child: Text(
                      _effectiveMyTasksOnly
                          ? 'No tasks assigned to you'
                          : 'No tasks match current filters',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                return _buildWorkspaceGantt(
                  workspaceId: workspaceId,
                  tasks: tasks,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAllProjectsSchedule(String workspaceId) {
    return StreamBuilder<List<Project>>(
      stream: ServiceLocator.projectService.getProjects(workspaceId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              UserFacingError.uiMessage(
                snapshot.error,
                action: 'load projects',
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final projects = snapshot.data!;

        if (projects.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 80,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No ${context.read<WorkspaceProvider>().projectTerminology} yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)} to get started',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    context.go('/projects/new');
                  },
                  icon: const Icon(Icons.add),
                  label: Text('Create ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)}'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedProjectId = project.id;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: ProjectStatusTheme.color(project.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              project.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                      if (project.startDate != null ||
                          project.targetCompletionDate != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${project.startDate != null ? "${project.startDate!.month}/${project.startDate!.day}/${project.startDate!.year}" : "TBD"} - ${project.targetCompletionDate != null ? "${project.targetCompletionDate!.month}/${project.targetCompletionDate!.day}/${project.targetCompletionDate!.year}" : "TBD"}',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProjectGantt({
    required Project project,
    required String projectId,
    required List<Task> tasks,
  }) {
    return UnifiedGanttWidget(
      key: _ganttKey,
      project: project,
      tasks: tasks,
      onTaskTap: (task) {
        context.go('/projects/$projectId/tasks/${task.id}/edit');
      },
      workspaceId: project.workspaceId,
      onTaskChanged: _onTaskChanged,
      onTaskCreated: (title, parentId) async {
        try {
          if (parentId != null) {
            await ServiceLocator.taskService.createChildTask(
              workspaceId: project.workspaceId,
              projectId: project.id,
              title: title,
              parentId: parentId,
            );
          } else {
            await ServiceLocator.taskService.createTask(
              workspaceId: project.workspaceId,
              projectId: project.id,
              title: title,
              startDate: DateTime.now(),
              dueDate: DateTime.now().add(const Duration(days: 1)),
              estimatedDuration: 8,
            );
          }
        } catch (_) {}
      },
      onTaskDelete: (task) => _onTaskDelete(task),
      onAddTask: () async {
        try {
          await ServiceLocator.taskService.createTask(
            workspaceId: project.workspaceId,
            projectId: project.id,
            title: 'New Task',
            taskType: TaskType.standard,
          );
        } catch (_) {}
      },
      onAddGroup: () async {
        try {
          await ServiceLocator.taskService.createGroup(
            workspaceId: project.workspaceId,
            projectId: project.id,
            title: 'New Group',
          );
        } catch (_) {}
      },
      onGroupCreated: (title, parentId) async {
        try {
          await ServiceLocator.taskService.createGroup(
            workspaceId: project.workspaceId,
            projectId: project.id,
            title: title,
            parentId: parentId,
          );
        } catch (_) {}
      },
      onConvertTaskType: (task, newType) async {
        try {
          await ServiceLocator.taskService.updateTaskType(task.id, newType);
        } catch (_) {}
      },
      onSaveAsTemplate: (task) async {
        await showSaveTaskGroupAsTemplateDialog(
          context,
          rootTask: task,
          projectId: project.id,
          workspaceId: project.workspaceId,
        );
      },
      onImportTemplate: (parentId) async {
        await showImportTaskTemplateDialog(
          context,
          projectId: project.id,
          workspaceId: project.workspaceId,
          parentId: parentId,
        );
      },
    );
  }

  Widget _buildWorkspaceGantt({
    required String workspaceId,
    required List<Task> tasks,
  }) {
    return UnifiedGanttWidget(
      key: _ganttKey,
      tasks: tasks,
      workspaceId: workspaceId,
      onTaskTap: (task) {
        showTaskFormPopup(context, projectId: task.projectId, taskId: task.id);
      },
      onTaskChanged: _onTaskChanged,
      onTaskDelete: (task) => _onTaskDelete(task),
    );
  }

  Future<void> _onTaskChanged(Task task) async {
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
    } catch (_) {}
  }

  Future<void> _onTaskDelete(Task task) async {
    try {
      await ServiceLocator.taskService.deleteTask(task.id);
    } catch (_) {}
  }
}
