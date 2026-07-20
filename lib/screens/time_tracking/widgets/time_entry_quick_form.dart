import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/theme.dart';
import '../../../models/overtime_rules.dart';
import '../../../models/time_entry.dart';
import '../../../models/time_entry_template.dart';
import '../../../services/service_locator.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../utils/project_terminology.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/forms/stacked_field.dart';
import 'time_tracking_pickers.dart';

/// A reusable time-entry creation/editing form used on the timesheet page
/// (inline Quick Add) and inside the Add/Edit Entry dialog.
class TimeEntryQuickForm extends StatefulWidget {
  const TimeEntryQuickForm({
    super.key,
    required this.selectedDate,
    this.existingEntry,
    this.initialProjectId,
    this.initialTaskId,
    this.showTemplates = true,
    this.showHeader = true,
    this.onEntrySaved,
    this.onProjectChanged,
    this.onTaskChanged,
  });

  /// The date the entry is being created/edited for.
  final DateTime selectedDate;

  /// When non-null the form is in edit mode.
  final TimeEntry? existingEntry;

  /// Pre-fill the project picker.
  final String? initialProjectId;

  /// Pre-fill the task picker.
  final String? initialTaskId;

  /// Whether to show the template selector row.
  final bool showTemplates;

  /// Whether to show the header row (title + Save Template button).
  /// Set to false when used inside a dialog that already has a title.
  final bool showHeader;

  /// Called after a new entry is saved or an existing entry is updated.
  final VoidCallback? onEntrySaved;

  /// Notifies the parent whenever the selected project changes.
  final ValueChanged<String?>? onProjectChanged;

  /// Notifies the parent whenever the selected task changes.
  final ValueChanged<String?>? onTaskChanged;

  @override
  State<TimeEntryQuickForm> createState() => _TimeEntryQuickFormState();
}

class _TimeEntryQuickFormState extends State<TimeEntryQuickForm>
    with SingleTickerProviderStateMixin {
  // ── services ──────────────────────────────────────────────────────────
  dynamic get _timeEntryService => ServiceLocator.timeEntryService;
  dynamic get _projectService => ServiceLocator.projectService;
  final _taskService = ServiceLocator.taskService;
  dynamic get _budgetService => ServiceLocator.budgetService;
  dynamic get _templateService => ServiceLocator.timeEntryTemplateService;

  // ── form state ────────────────────────────────────────────────────────
  String? _selectedProjectId;
  String? _selectedTaskId;
  String? _selectedBudgetItemId;
  final _hoursController = TextEditingController(text: '8');
  bool _showDetails = false;
  TimeOfDay? _clockIn;
  TimeOfDay? _clockOut;
  int _breakMinutes = 0;
  final _notesController = TextEditingController();
  String? _selectedTemplateId;
  bool _isSaving = false;
  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;


  String get _projectTerminology =>
      context.read<WorkspaceProvider>().projectTerminology;

  String get _singular => singularProjectTerminology(_projectTerminology);

  String get _singularLower => _singular.toLowerCase();

  bool get _isEditing => widget.existingEntry != null;

  // ── lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    if (_isEditing) {
      final e = widget.existingEntry!;
      _selectedProjectId = e.projectId;
      _selectedTaskId = e.taskId;
      _selectedBudgetItemId = e.budgetItemId;
      _clockIn = TimeOfDay.fromDateTime(e.clockIn);
      _clockOut =
          e.clockOut != null ? TimeOfDay.fromDateTime(e.clockOut!) : null;
      _breakMinutes = e.breakDuration;
      _notesController.text = e.notes ?? '';
      final hours = e.regularHours + e.overtimeHours + e.doubleTimeHours;
      _hoursController.text = hours.toStringAsFixed(1);
      _showDetails = true; // always show details when editing
    } else {
      _selectedProjectId = widget.initialProjectId;
      _selectedTaskId = widget.initialTaskId;
    }
  }

  @override
  void didUpdateWidget(covariant TimeEntryQuickForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pick up auto-populated project/task from parent (e.g. from last entry).
    if (!_isEditing) {
      if (oldWidget.initialProjectId != widget.initialProjectId &&
          _selectedProjectId == oldWidget.initialProjectId) {
        _selectedProjectId = widget.initialProjectId;
        _selectedTaskId = widget.initialTaskId;
        _selectedBudgetItemId = null;
      } else if (oldWidget.initialTaskId != widget.initialTaskId &&
          _selectedTaskId == oldWidget.initialTaskId) {
        _selectedTaskId = widget.initialTaskId;
      }
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _hoursController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;
    if (workspaceId == null || userId == null) {
      return const SizedBox.shrink();
    }

    final isAdminOrPm =
        authProvider.canManageUsers || authProvider.canCreateProjects;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          Row(
            children: [
              Icon(_isEditing ? Icons.edit : Icons.flash_on, size: 18),
              const SizedBox(width: 8),
              Text(
                _isEditing ? 'Edit Entry' : 'Quick Add',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (!_isEditing)
                TextButton.icon(
                  onPressed: () => _showSaveTemplateDialog(
                    context,
                    workspaceId,
                    userId,
                    isAdminOrPm,
                  ),
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save Template'),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _buildValidationBanner(),
        if (widget.showTemplates && !_isEditing)
          _buildTemplateSelector(workspaceId, userId),
        if (widget.showTemplates && !_isEditing) const SizedBox(height: 12),
        TimeTrackingPickers.projectField(
          stream: _projectService.getProjects(workspaceId),
          selectedProjectId: _selectedProjectId,
          singularTerm: _singular,
          singularTermLower: _singularLower,
          pluralTerm: projectTerminologyForCount(2, _projectTerminology),
          onSelected: (project) {
            setState(() {
              _selectedProjectId = project.id;
              _selectedTaskId = null;
              _selectedBudgetItemId = null;
            });
            _clearValidationErrors();
            widget.onProjectChanged?.call(project.id);
            widget.onTaskChanged?.call(null);
          },
        ),
        if (_selectedProjectId != null) ...[
          const SizedBox(height: 12),
          TimeTrackingPickers.taskField(
            stream: _taskService.getTasks(
              _selectedProjectId!,
              workspaceId: workspaceId,
            ),
            selectedTaskId: _selectedTaskId,
            singularTermLower: _singularLower,
            onSelected: (task) {
              setState(() => _selectedTaskId = task?.id);
              _clearValidationErrors();
              widget.onTaskChanged?.call(task?.id);
            },
          ),
          const SizedBox(height: 12),
          TimeTrackingPickers.budgetItemField(
            stream: _budgetService.getBudgetItems(
              _selectedProjectId!,
              workspaceId: workspaceId,
            ),
            selectedBudgetItemId: _selectedBudgetItemId,
            singularTermLower: _singularLower,
            onSelected: (item) {
              setState(() => _selectedBudgetItemId = item?.id);
            },
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StackedField(
                label: 'Hours *',
                child: TextField(
                  controller: _hoursController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () {
                setState(() => _showDetails = !_showDetails);
              },
              icon: Icon(
                _showDetails ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text(
                _showDetails ? 'Hide Details' : 'Add Details',
              ),
            ),
          ],
        ),
        if (_showDetails) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildTimeField('Clock In', _clockIn, true)),
              const SizedBox(width: 12),
              Expanded(child: _buildTimeField('Clock Out', _clockOut, false)),
            ],
          ),
          const SizedBox(height: 12),
          _buildBreakField(),
          const SizedBox(height: 12),
          StackedField(
            label: 'Notes (optional)',
            child: TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  final dx = _shakeController.isAnimating
                      ? math.sin(_shakeController.value * math.pi * 4) * 6
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: FilledButton.icon(
                  onPressed:
                      _isSaving ? null : () => _save(context, workspaceId, userId),
                  icon: Icon(_isEditing ? Icons.check : Icons.add),
                  label: Text(_isSaving
                      ? 'Saving...'
                      : _isEditing
                          ? 'Update Entry'
                          : 'Add Manual Time Entry'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }


  // ── time / break fields ───────────────────────────────────────────────

  Widget _buildTimeField(String label, TimeOfDay? time, bool isClockIn) {
    return StackedField(
      label: label,
      child: InkWell(
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: time ?? TimeOfDay.now(),
          );
          if (picked != null) {
            setState(() {
              if (isClockIn) {
                _clockIn = picked;
              } else {
                _clockOut = picked;
              }
            });
          }
        },
        child: InputDecorator(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          child: Text(time?.format(context) ?? 'Select'),
        ),
      ),
    );
  }

  Widget _buildBreakField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Break Duration: $_breakMinutes minutes',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        Slider(
          value: _breakMinutes.toDouble(),
          min: 0,
          max: 120,
          divisions: 24,
          label: '$_breakMinutes min',
          onChanged: (value) {
            setState(() {
              _breakMinutes = value.toInt();
            });
          },
        ),
      ],
    );
  }

  // ── templates ─────────────────────────────────────────────────────────

  Widget _buildTemplateSelector(String workspaceId, String userId) {
    return StreamBuilder<List<TimeEntryTemplate>>(
      stream: _templateService.getTemplates(
        workspaceId: workspaceId,
        userId: userId,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final templates = snapshot.data!;
        final personal = templates.where((t) => !t.isShared).toList();
        final shared = templates.where((t) => t.isShared).toList();

        return StackedField(
          label: 'Template',
          child: DropdownButtonFormField<String>(
            borderRadius: AppRadius.cardRadius,
            value: _selectedTemplateId,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              if (personal.isNotEmpty) ...[
                const DropdownMenuItem(
                  value: '__header_personal__',
                  enabled: false,
                  child: Text('My Templates'),
                ),
                ...personal.map(
                  (template) => DropdownMenuItem(
                    value: template.id,
                    child: Text(template.name),
                  ),
                ),
              ],
              if (shared.isNotEmpty) ...[
                const DropdownMenuItem(
                  value: '__header_shared__',
                  enabled: false,
                  child: Text('Shared Templates'),
                ),
                ...shared.map(
                  (template) => DropdownMenuItem(
                    value: template.id,
                    child: Text(template.name),
                  ),
                ),
              ],
            ],
            onChanged: (value) {
              if (value == null || value.startsWith('__header_')) return;
              final template = templates.firstWhere((t) => t.id == value);
              setState(() {
                _selectedTemplateId = template.id;
                _selectedProjectId = template.projectId;
                _selectedTaskId = template.taskId;
                _selectedBudgetItemId = null;
                _hoursController.text =
                    template.defaultHours.toStringAsFixed(1);
                _breakMinutes = template.defaultBreakMinutes;
                _notesController.text = template.notesTemplate ?? '';
                _showDetails = false;
                _clockIn = null;
                _clockOut = null;
              });
              widget.onProjectChanged?.call(template.projectId);
              widget.onTaskChanged?.call(template.taskId);
            },
          ),
        );
      },
    );
  }

  Future<void> _showSaveTemplateDialog(
    BuildContext context,
    String workspaceId,
    String userId,
    bool canCreateShared,
  ) async {
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Select $_singularLower before saving template'),
        ),
      );
      return;
    }
    final nameController = TextEditingController();
    bool shared = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Template'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StackedField(
                label: 'Template Name',
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (canCreateShared)
                SwitchListTile(
                  value: shared,
                  onChanged: (value) => setDialogState(() => shared = value),
                  title: const Text('Share with workspace'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final hours = double.tryParse(_hoursController.text.trim()) ?? 0;
    await _templateService.createTemplate(
      workspaceId: workspaceId,
      name: name,
      projectId: _selectedProjectId!,
      taskId: _selectedTaskId ?? '',
      userId: userId,
      shared: shared,
      defaultHours: hours,
      defaultBreakMinutes: _breakMinutes,
      notesTemplate: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
  }

  // ── save logic ────────────────────────────────────────────────────────

  Future<void> _save(
    BuildContext context,
    String workspaceId,
    String userId,
  ) async {
    if (_selectedProjectId == null) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = '$_singular is required';
      });
      _shakeController.forward(from: 0);
      return;
    }
    _clearValidationErrors();

    final workspaceProvider = context.read<WorkspaceProvider>();
    final hourlyRate =
        workspaceProvider.activeWorkspace?.hourlyRate ??
        workspaceProvider.activeWorkspace?.defaultHourlyRate ??
        context.read<AuthProvider>().appUser?.hourlyRate;

    if (hourlyRate == null || hourlyRate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hourly wage not set.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final hours = double.tryParse(_hoursController.text.trim()) ?? 0;
      if (hours <= 0) {
        throw Exception('Hours must be greater than zero');
      }

      DateTime clockIn;
      DateTime clockOut;

      if (_clockIn != null && _clockOut != null) {
        clockIn = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          _clockIn!.hour,
          _clockIn!.minute,
        );
        clockOut = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          _clockOut!.hour,
          _clockOut!.minute,
        );
        if (clockOut.isBefore(clockIn)) {
          throw Exception('Clock out must be after clock in');
        }
      } else {
        // Default to 8:00 AM start time
        clockIn = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          8,
          0,
        );
        final totalMinutes = (hours * 60).round() + _breakMinutes;
        clockOut = clockIn.add(Duration(minutes: totalMinutes));
      }

      if (_isEditing) {
        final totalDuration =
            TimeEntry.calculateDuration(clockIn, clockOut, _breakMinutes);
        const rules = OvertimeRules();
        final hoursBreakdown =
            TimeEntry.calculateHoursBreakdown(totalDuration, rules);
        final costs = TimeEntry.calculateCosts(
          regularHours: hoursBreakdown.regular,
          overtimeHours: hoursBreakdown.overtime,
          doubleTimeHours: hoursBreakdown.doubleTime,
          hourlyRate: hourlyRate,
          rules: rules,
        );
        await _timeEntryService.updateTimeEntry(widget.existingEntry!.id, {
          'projectId': _selectedProjectId,
          'taskId': _selectedTaskId,
          'budgetItemId': _selectedBudgetItemId,
          'clockIn': clockIn,
          'clockOut': clockOut,
          'breakDuration': _breakMinutes,
          'totalDuration': totalDuration,
          'regularHours': hoursBreakdown.regular,
          'overtimeHours': hoursBreakdown.overtime,
          'doubleTimeHours': hoursBreakdown.doubleTime,
          'regularCost': costs.regularCost,
          'overtimeCost': costs.overtimeCost,
          'doubleTimeCost': costs.doubleTimeCost,
          'totalCost': costs.totalCost,
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        });
      } else {
        await _timeEntryService.createTimeEntry(
          workspaceId: workspaceId,
          workerId: userId,
          projectId: _selectedProjectId!,
          taskId: _selectedTaskId,
          budgetItemId: _selectedBudgetItemId,
          date: widget.selectedDate,
          clockIn: clockIn,
          clockOut: clockOut,
          breakDuration: _breakMinutes,
          hourlyRate: hourlyRate,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }

      if (mounted) {
        if (!_isEditing) {
          setState(() {
            _showDetails = false;
            _clockIn = null;
            _clockOut = null;
            _breakMinutes = 0;
            _notesController.clear();
          });
        }
        widget.onEntrySaved?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'complete this action'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _clearValidationErrors() {
    if (_showFieldErrors) {
      setState(() {
        _showFieldErrors = false;
        _validationMessage = null;
      });
    }
  }

  Widget _buildValidationBanner() {
    if (!_showFieldErrors || _validationMessage == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _validationMessage!,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
