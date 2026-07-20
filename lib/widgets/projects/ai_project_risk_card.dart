import 'package:flutter/material.dart';

import '../../models/ai_copilot_models.dart';
import '../../models/project.dart';
import '../../services/ai_copilot_flags.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../ai/ai_copilot_card_state.dart';
import '../ai/ai_copilot_card_utils.dart';

class AiProjectRiskCard extends StatefulWidget {
  final String workspaceId;
  final String userId;
  final String? initialProjectId;

  const AiProjectRiskCard({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.initialProjectId,
  });

  @override
  State<AiProjectRiskCard> createState() => _AiProjectRiskCardState();
}

class _AiProjectRiskCardState extends State<AiProjectRiskCard> {
  bool _loading = true;
  bool _enabled = false;
  String? _error;
  List<Project> _projects = [];
  String? _projectId;
  AiProjectRiskAssessment? _risk;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final scope = await loadAiCopilotProjectScope(
        workspaceId: widget.workspaceId,
        flagKey: AiCopilotFlags.riskV1,
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
        await _loadRisk(scope.selectedProjectId!);
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() {
        _error = 'Unable to load AI risk insights';
        _loading = false;
      });
    }
  }

  Future<void> _loadRisk(String projectId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final risk = await ServiceLocator.aiCopilotService
          .getProjectRiskAssessment(
            workspaceId: widget.workspaceId,
            userId: widget.userId,
            projectId: projectId,
          );
      if (!mounted) return;
      setState(() {
        _risk = risk;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to generate risk score';
        _loading = false;
      });
    }
  }

  Color _riskColor(int score) {
    if (score >= 75) return AppColors.error;
    if (score >= 50) return AppColors.warning;
    if (score >= 30) return AppColors.secondary;
    return AppColors.success;
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
                const Icon(Icons.health_and_safety_outlined, size: 18),
                const SizedBox(width: AppSpacing.iconGap),
                const Expanded(
                  child: Text(
                    'AI Project Risk',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                AiCopilotProjectDropdown(
                  projects: _projects,
                  value: _projectId,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _projectId = value);
                    _loadRisk(value);
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
                  "AI risk analysis isn't enabled for your workspace yet.",
              emptyMessage: 'No project selected.',
              hasContent: _risk != null,
              content: _risk == null
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${_risk!.riskScore}/100',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: _riskColor(_risk!.riskScore),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              _risk!.riskLevel.toUpperCase(),
                              style: TextStyle(
                                color: _riskColor(_risk!.riskScore),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ..._risk!.drivers
                            .take(3)
                            .map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• ${d.detail}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                        const SizedBox(height: AppSpacing.sm),
                        ..._risk!.recommendedActions
                            .take(2)
                            .map(
                              (a) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('Next: $a'),
                              ),
                            ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
