import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/file_attachment.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../models/checklist_item.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../screens/time_tracking/clock_in_out_screen.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../screens/files/file_markup_editor_screen.dart';
import '../photo_capture_assign_dialog.dart';
import '../task_assignee_avatars.dart';
import '../task_comments_widget.dart';
import '../task_form_popup.dart';
import '../field_forms/task_required_forms_widget.dart';
import 'package:provider/provider.dart';

Future<void> showMobileTaskDetailSheet(
  BuildContext context, {
  required Task task,
  Project? project,
  required Map<String, AppUser> usersMap,
  required List<AppUser> allWorkspaceUsers,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx2, scrollController) => _MobileTaskDetailSheet(
        task: task,
        project: project,
        usersMap: usersMap,
        allWorkspaceUsers: allWorkspaceUsers,
        scrollController: scrollController,
      ),
    ),
  );
}

class _MobileTaskDetailSheet extends StatefulWidget {
  final Task task;
  final Project? project;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final ScrollController scrollController;

  const _MobileTaskDetailSheet({
    required this.task,
    this.project,
    required this.usersMap,
    required this.allWorkspaceUsers,
    required this.scrollController,
  });

  @override
  State<_MobileTaskDetailSheet> createState() => _MobileTaskDetailSheetState();
}

class _MobileTaskDetailSheetState extends State<_MobileTaskDetailSheet> {
  late Task _task;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  Future<void> _setStatus(String newStatus) async {
    await ServiceLocator.taskService.updateTaskStatus(_task.id, newStatus);
    if (mounted) {
      setState(() {
        _task = _task.copyWith(
          status: newStatus,
          isComplete: newStatus == 'done',
        );
      });
    }
  }

  Future<void> _setProgress(int value) async {
    await ServiceLocator.taskService.updateTaskProgress(_task.id, value);
    if (mounted) setState(() => _task = _task.copyWith(progress: value));
  }

  Future<void> _toggleChecklist(ChecklistItem item) async {
    await ServiceLocator.taskService.updateChecklistItem(
      _task.id,
      item.id,
      isComplete: !item.isComplete,
    );
    if (mounted) {
      final updatedItems = _task.checklistItems.map((i) {
        return i.id == item.id ? i.copyWith(isComplete: !i.isComplete) : i;
      }).toList();
      setState(() => _task = _task.copyWith(checklistItems: updatedItems));
    }
  }

  Future<void> _setPriority(String value) async {
    await ServiceLocator.taskService.updateTaskPriority(_task.id, value);
    if (mounted) setState(() => _task = _task.copyWith(priority: value));
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _task.dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      await ServiceLocator.taskService.updateTask(
        taskId: _task.id,
        dueDate: picked,
      );
      if (mounted) setState(() => _task = _task.copyWith(dueDate: picked));
    }
  }

  Future<void> _clearDueDate() async {
    // Pass a sentinel far-future date then clear via raw update
    await ServiceLocator.taskService.updateTask(taskId: _task.id);
    if (mounted) setState(() => _task = _task.copyWith(dueDate: null));
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _task.startDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      await ServiceLocator.taskService.updateTask(
        taskId: _task.id,
        startDate: picked,
      );
      if (mounted) setState(() => _task = _task.copyWith(startDate: picked));
    }
  }

  Future<void> _getDirections() async {
    final address = widget.project?.address;
    final lat = widget.project?.latitude;
    final lng = widget.project?.longitude;

    Uri uri;
    if (lat != null && lng != null) {
      // prefer coordinates for accuracy
      uri = Uri.parse('https://maps.google.com/maps?daddr=$lat,$lng');
    } else if (address != null && address.isNotEmpty) {
      uri = Uri.parse(
        'https://maps.google.com/maps?daddr=${Uri.encodeComponent(address)}',
      );
    } else {
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _clockIn(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClockInOutScreen(projectId: _task.projectId),
      ),
    );
  }

  void _openEdit(BuildContext context) {
    Navigator.of(context).pop();
    showTaskFormPopup(context, projectId: _task.projectId, taskId: _task.id);
  }

  Future<void> _addPhoto(BuildContext context) async {
    final project =
        widget.project ??
        await ServiceLocator.projectService.getProject(_task.projectId);
    if (!context.mounted) return;

    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load project for photo upload'),
        ),
      );
      return;
    }

    await showPhotoCaptureAssignDialog(
      context,
      preSelectedProject: project,
      preSelectedTask: _task,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final isManager = authProvider.canCreateTasks;
    final canUpload = authProvider.canUploadFiles;
    final hasAddress =
        widget.project != null &&
        (widget.project!.address.isNotEmpty ||
            widget.project?.latitude != null);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          _DragHandle(),

          // Header row: title + edit button (edit only for managers)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _task.displayTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isManager)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openEdit(context),
                    tooltip: 'Edit task',
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Scrollable body
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                // Description
                if (_task.description != null &&
                    _task.description!.isNotEmpty) ...[
                  Text(
                    _task.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Priority picker (admin/PM only)
                if (isManager) ...[
                  _SectionLabel('Priority'),
                  const SizedBox(height: 8),
                  _PriorityPicker(
                    currentPriority: _task.priority,
                    onChanged: _setPriority,
                  ),
                  const SizedBox(height: 20),
                ],

                // Status picker
                _SectionLabel('Status'),
                const SizedBox(height: 8),
                _StatusPicker(
                  currentStatus: _task.status,
                  onChanged: _setStatus,
                ),
                const SizedBox(height: 20),

                // Dates section
                _SectionLabel('Schedule'),
                const SizedBox(height: 8),
                _DateRow(
                  label: 'Due',
                  icon: Icons.event_outlined,
                  date: _task.dueDate,
                  editable: isManager,
                  onTap: () => _pickDueDate(context),
                  onClear: _clearDueDate,
                ),
                if (isManager) ...[
                  const SizedBox(height: 6),
                  _DateRow(
                    label: 'Start',
                    icon: Icons.play_arrow_outlined,
                    date: _task.startDate,
                    editable: true,
                    onTap: () => _pickStartDate(context),
                  ),
                ],
                const SizedBox(height: 20),

                // Quick actions: Clock In + Directions
                if (!kIsWeb) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.timer_outlined,
                          label: 'Clock In',
                          color: AppColors.success,
                          onTap: () => _clockIn(context),
                        ),
                      ),
                      if (hasAddress) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.directions_outlined,
                            label: 'Directions',
                            color: AppColors.info,
                            onTap: _getDirections,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (kIsWeb && hasAddress) ...[
                  _ActionButton(
                    icon: Icons.directions_outlined,
                    label: 'Get Directions',
                    color: AppColors.info,
                    onTap: _getDirections,
                  ),
                  const SizedBox(height: 20),
                ],

                // Assignees
                _SectionLabel('Assigned To'),
                const SizedBox(height: 8),
                TaskAssigneeAvatars(
                  task: _task,
                  usersMap: widget.usersMap,
                  allWorkspaceUsers: widget.allWorkspaceUsers,
                  maxVisible: 5,
                  avatarSize: 32,
                  readOnly: !isManager,
                ),
                const SizedBox(height: 20),

                // Checklist
                if (_task.checklistItems.isNotEmpty) ...[
                  _SectionLabel('Checklist'),
                  const SizedBox(height: 8),
                  ..._task.checklistItems.map(
                    (item) => _ChecklistRow(
                      item: item,
                      onToggle: () => _toggleChecklist(item),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Required Forms
                TaskRequiredFormsWidget(
                  taskId: _task.id,
                  projectId: _task.projectId,
                  readOnly: true,
                ),
                const SizedBox(height: 20),

                // Progress
                _SectionLabel('Progress'),
                const SizedBox(height: 8),
                _ProgressSlider(
                  progress: _task.progress,
                  onChanged: _setProgress,
                ),
                const SizedBox(height: 20),

                // Photos
                if (workspaceId.isNotEmpty) ...[
                  _SectionLabel('Photos'),
                  const SizedBox(height: 8),
                  _PhotosSection(
                    workspaceId: workspaceId,
                    taskId: _task.id,
                    onAddPhoto: () => _addPhoto(context),
                    canUpload: canUpload,
                  ),
                  const SizedBox(height: 20),
                ],

                // Notes / Comments
                if (workspaceId.isNotEmpty && _task.id.isNotEmpty) ...[
                  _SectionLabel('Notes'),
                  const SizedBox(height: 8),
                  TaskCommentsWidget(
                    taskId: _task.id,
                    workspaceId: workspaceId,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
        letterSpacing: 0.5,
      ),
    );
  }
}

class _StatusPicker extends StatelessWidget {
  final String currentStatus;
  final Future<void> Function(String) onChanged;

  const _StatusPicker({required this.currentStatus, required this.onChanged});

  static const _statuses = [
    ('not_started', 'Not Started', AppColors.textTertiary),
    ('working_on_it', 'In Progress', AppColors.info),
    ('stuck', 'Stuck', AppColors.error),
    ('done', 'Done', AppColors.success),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _statuses.map((entry) {
        final (value, label, color) = entry;
        final isSelected = currentStatus == value;
        return Expanded(
          child: GestureDetector(
            onTap: isSelected ? null : () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.22)
                    : color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isSelected ? color : color.withValues(alpha: 0.4),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : color.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PriorityPicker extends StatelessWidget {
  final String currentPriority;
  final Future<void> Function(String) onChanged;

  const _PriorityPicker({
    required this.currentPriority,
    required this.onChanged,
  });

  static const _priorities = [
    ('low', 'Low', AppColors.textTertiary),
    ('medium', 'Medium', AppColors.warning),
    ('high', 'High', AppColors.error),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _priorities.map((entry) {
        final (value, label, color) = entry;
        final isSelected = currentPriority == value;
        return Expanded(
          child: GestureDetector(
            onTap: isSelected ? null : () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.22)
                    : color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isSelected ? color : color.withValues(alpha: 0.4),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : color.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final DateTime? date;
  final bool editable;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const _DateRow({
    required this.label,
    required this.icon,
    required this.date,
    this.editable = false,
    this.onTap,
    this.onClear,
  });

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff < -1) return '${-diff}d overdue';
    return '${d.month}/${d.day}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue =
        date != null && date!.isBefore(DateTime.now()) && label == 'Due';

    return InkWell(
      onTap: editable ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isOverdue ? AppColors.error : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 8),
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            Expanded(
              child: Text(
                date != null ? _formatDate(date!) : 'Not set',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: date != null ? FontWeight.w600 : FontWeight.w400,
                  color: isOverdue
                      ? AppColors.error
                      : date != null
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
            if (editable && date != null && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            if (editable)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final ChecklistItem item;
  final VoidCallback onToggle;

  const _ChecklistRow({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: item.isComplete
                      ? AppColors.success
                      : Colors.grey.shade400,
                  width: 2,
                ),
                color: item.isComplete ? AppColors.success : Colors.transparent,
              ),
              child: item.isComplete
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: 14,
                  color: item.isComplete
                      ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)
                      : Theme.of(context).colorScheme.onSurface,
                  decoration: item.isComplete
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressSlider extends StatefulWidget {
  final int progress;
  final Future<void> Function(int) onChanged;

  const _ProgressSlider({required this.progress, required this.onChanged});

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  late double _local;

  @override
  void initState() {
    super.initState();
    _local = widget.progress.toDouble();
  }

  @override
  void didUpdateWidget(_ProgressSlider old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) {
      _local = widget.progress.toDouble();
    }
  }

  Color get _color {
    if (_local >= 100) return AppColors.success;
    if (_local >= 50) return AppColors.info;
    if (_local > 0) return AppColors.warning;
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                  activeTrackColor: _color,
                  thumbColor: _color,
                  inactiveTrackColor: _color.withValues(alpha: 0.2),
                  overlayColor: _color.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: _local,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() => _local = v),
                  onChangeEnd: (v) => widget.onChanged(v.round()),
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${_local.round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _color,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotosSection extends StatelessWidget {
  final String workspaceId;
  final String taskId;
  final VoidCallback onAddPhoto;
  final bool canUpload;

  const _PhotosSection({
    required this.workspaceId,
    required this.taskId,
    required this.onAddPhoto,
    this.canUpload = true,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FileAttachment>>(
      stream: ServiceLocator.storageService.getTaskFiles(workspaceId, taskId),
      builder: (context, snapshot) {
        final files = snapshot.data ?? [];
        final photos = files.where((f) => f.isImage).toList();

        if (!canUpload && photos.isEmpty) {
          return Text(
            'No photos',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          );
        }

        return SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length + (canUpload ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (canUpload && i == 0) {
                return _AddPhotoTile(
                  onTap: onAddPhoto,
                  isLoading:
                      snapshot.connectionState == ConnectionState.waiting,
                  hasPhotos: photos.isNotEmpty,
                );
              }
              final photoIndex = canUpload ? i - 1 : i;
              return _PhotoThumbnail(file: photos[photoIndex]);
            },
          ),
        );
      },
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLoading;
  final bool hasPhotos;

  const _AddPhotoTile({
    required this.onTap,
    required this.isLoading,
    required this.hasPhotos,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Ink(
        width: 100,
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading && !hasPhotos)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: AppColors.secondary,
                  size: 18,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              hasPhotos ? 'Add photo' : 'Add first photo',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  final FileAttachment file;

  const _PhotoThumbnail({required this.file});

  @override
  Widget build(BuildContext context) {
    final displayUrl = file.thumbnailUrl ?? file.fileUrl;
    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: CachedNetworkImage(
          imageUrl: displayUrl,
          key: ValueKey(displayUrl),
          memCacheWidth: 200,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          progressIndicatorBuilder: (_, __, ___) => Container(
            width: 100,
            height: 100,
            color: Colors.grey.shade100,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: 100,
            height: 100,
            color: Colors.grey.shade200,
            child: Icon(
              Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              file.fileName,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white),
                tooltip: 'Edit image',
                onPressed: () => Navigator.of(routeContext).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => FileMarkupEditorScreen(file: file),
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: file.fileUrl),
            ),
          ),
        ),
      ),
    );
  }
}
