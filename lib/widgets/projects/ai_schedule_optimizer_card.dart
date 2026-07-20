import 'package:flutter/material.dart';

import '../../models/ai_copilot_models.dart';
import '../../models/project.dart';
import '../../services/ai_copilot_flags.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../ai/ai_copilot_card_state.dart';
import '../ai/ai_copilot_card_utils.dart';

class AiScheduleOptimizerCard extends StatefulWidget {
  final String workspaceId;
  final String userId;
  final String? initialProjectId;

  const AiScheduleOptimizerCard({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.initialProjectId,
  });

  @override
  State<AiScheduleOptimizerCard> createState() =>
      _AiScheduleOptimizerCardState();
}

class _AiScheduleOptimizerCardState extends State<AiScheduleOptimizerCard> {
  bool _loading = true;
  bool _enabled = false;
  bool _applying = false;
  String? _error;
  List<Project> _projects = [];
  String? _projectId;
  AiScheduleOptimizationResult? _result;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final scope = await loadAiCopilotProjectScope(
        workspaceId: widget.workspaceId,
        flagKey: AiCopilotFlags.scheduleV1,
        initialProjectId: widget.initialProjectId,
      );
      if (!scope.enabled) {
        setState(() {
          _enabled = false;
          _loading = false;
        });
        return;
      }

      setState(() {
        _enabled = true;
        _projects = scope.projects;
        _projectId = scope.selectedProjectId;
      });

      if (scope.selectedProjectId != null) {
        await _loadSuggestions(scope.selectedProjectId!);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() {
        _error = 'Unable to load schedule optimizer';
        _loading = false;
      });
    }
  }

  Future<void> _loadSuggestions(String projectId) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ServiceLocator.aiCopilotService
          .getScheduleOptimization(
            workspaceId: widget.workspaceId,
            userId: widget.userId,
            projectId: projectId,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to generate schedule suggestions';
        _loading = false;
      });
    }
  }

  Future<void> _applySuggestion(AiScheduleSuggestion suggestion) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply AI suggestion?'),
        content: Text(
          'This will update task dependencies for "${suggestion.title}".\n\n'
          'Changes: ${suggestion.changes.length}\n'
          'Estimated days saved: ${suggestion.estimatedDaysSaved}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (approved != true) return;

    setState(() => _applying = true);
    try {
      await ServiceLocator.aiCopilotService.applyScheduleSuggestion(
        workspaceId: widget.workspaceId,
        userId: widget.userId,
        suggestion: suggestion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule suggestion applied')),
      );
      if (_projectId != null) {
        await _loadSuggestions(_projectId!);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to apply suggestion')),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule_send_outlined, size: 18, color: AppColors.secondary),
                const SizedBox(width: AppSpacing.iconGap),
                const Expanded(
                  child: Text(
                    'AI Schedule Optimizer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                AiCopilotProjectDropdown(
                  projects: _projects,
                  value: _projectId,
                  onChanged: _applying
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _projectId = value);
                          _loadSuggestions(value);
                        },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            AiCopilotCardStateView(
              enabled: _enabled,
              loading: _loading,
              error: _error,
              disabledMessage:
                  "AI schedule suggestions aren't enabled for your workspace yet.",
              emptyMessage: 'No suggestions yet.',
              hasContent: _result != null && _result!.suggestions.isNotEmpty,
              content: _result == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: _result!.suggestions.take(3).map((s) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.base,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.base),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(s.impactSummary),
                                const SizedBox(height: 4),
                                Text(
                                  'Estimated days saved: ${s.estimatedDaysSaved}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton(
                                    onPressed: _applying || s.changes.isEmpty
                                        ? null
                                        : () => _applySuggestion(s),
                                    child: _applying
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Review & Apply'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
