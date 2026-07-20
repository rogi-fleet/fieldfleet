import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/ai_copilot_models.dart';
import '../../models/project.dart';
import '../../providers/workspace_provider.dart';
import '../../services/ai_copilot_flags.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/project_terminology.dart';
import '../ai/ai_copilot_card_state.dart';
import '../ai/ai_copilot_card_utils.dart';

class WeeklyDigestCard extends StatefulWidget {
  final String workspaceId;
  final String userId;

  const WeeklyDigestCard({
    super.key,
    required this.workspaceId,
    required this.userId,
  });

  @override
  State<WeeklyDigestCard> createState() => _WeeklyDigestCardState();
}

class _WeeklyDigestCardState extends State<WeeklyDigestCard> {
  bool _loading = true;
  bool _refreshing = false;
  bool _enabled = false;
  String? _error;
  List<Project> _projects = [];
  String? _projectId;
  AiWeeklyProjectDigest? _digest;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final scope = await loadAiCopilotProjectScope(
        workspaceId: widget.workspaceId,
        flagKey: AiCopilotFlags.weeklyDigestV1,
        initialProjectId: null,
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
        await _loadDigest(scope.selectedProjectId!, force: false);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() {
        _error = 'Unable to load weekly digest';
        _loading = false;
      });
    }
  }

  Future<void> _loadDigest(String projectId, {required bool force}) async {
    setState(() {
      _error = null;
      _loading = !_refreshing;
    });
    try {
      final digest = await ServiceLocator.aiCopilotService.generateWeeklyDigest(
        workspaceId: widget.workspaceId,
        userId: widget.userId,
        projectId: projectId,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _digest = digest;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to generate weekly digest: $e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _openDigestLink(String href) async {
    if (href.isEmpty) return;
    if (href.startsWith('/')) {
      if (!mounted) return;
      context.go(href);
      return;
    }

    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  ({String level, int score})? _parseRiskFromMarkdown(String markdown) {
    final match = RegExp(
      r'Risk level:\s*\*\*([A-Z]+)\*\*\s*\((\d+)/100\)',
      caseSensitive: false,
    ).firstMatch(markdown);
    if (match == null) return null;
    final level = match.group(1)?.toUpperCase() ?? '';
    final score = int.tryParse(match.group(2) ?? '');
    if (level.isEmpty || score == null) return null;
    return (level: level, score: score);
  }

  Color _riskChipBackground(String level) {
    switch (level) {
      case 'CRITICAL':
      case 'HIGH':
        return AppColors.errorLight;
      case 'MEDIUM':
        return AppColors.warningLight;
      case 'LOW':
        return AppColors.successLight;
      default:
        return AppColors.surfaceAlt;
    }
  }

  Color _riskChipTextColor(String level) {
    switch (level) {
      case 'CRITICAL':
      case 'HIGH':
        return AppColors.errorDark;
      case 'MEDIUM':
        return AppColors.warningDark;
      case 'LOW':
        return AppColors.successDark;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _badgeBackground(String? badge) {
    final value = (badge ?? '').toLowerCase();
    if (value.contains('overdue') ||
        value.contains('stuck') ||
        value.contains('rising') ||
        value.contains('blocker') ||
        value.contains('now')) {
      return AppColors.errorLight;
    }
    if (value.contains('soon') ||
        value.contains('owner') ||
        value.contains('priority') ||
        value.contains('trend')) {
      return AppColors.warningLight;
    }
    if (value.contains('clean') ||
        value.contains('stable') ||
        value.contains('improving')) {
      return AppColors.successLight;
    }
    return AppColors.surfaceAlt;
  }

  Color _badgeTextColor(String? badge) {
    final value = (badge ?? '').toLowerCase();
    if (value.contains('overdue') ||
        value.contains('stuck') ||
        value.contains('rising') ||
        value.contains('blocker') ||
        value.contains('now')) {
      return AppColors.errorDark;
    }
    if (value.contains('soon') ||
        value.contains('owner') ||
        value.contains('priority') ||
        value.contains('trend')) {
      return AppColors.warningDark;
    }
    if (value.contains('clean') ||
        value.contains('stable') ||
        value.contains('improving')) {
      return AppColors.successDark;
    }
    return AppColors.textSecondary;
  }

  Widget _buildDigestSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<AiDigestItem> items,
  }) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final clickable = item.href != null && item.href!.isNotEmpty;
            final content = Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.r12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (item.badge != null && item.badge!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: _badgeBackground(item.badge),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.badge!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _badgeTextColor(item.badge),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.detail,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (clickable) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );

            if (!clickable) {
              return content;
            }

            return InkWell(
              borderRadius: BorderRadius.circular(AppRadius.r12),
              onTap: () => _openDigestLink(item.href!),
              child: content,
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.summarize_outlined, size: 18),
                const SizedBox(width: AppSpacing.iconGap),
                Expanded(
                  child: Text(
                    'Weekly $singularTerminology Digest',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _refreshing || _projectId == null
                      ? null
                      : () {
                          setState(() => _refreshing = true);
                          _loadDigest(_projectId!, force: true);
                        },
                  tooltip: 'Refresh digest',
                  icon: _refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            if (_projects.isNotEmpty)
              Row(
                children: [
                  Text(
                    '$singularTerminology:',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AiCopilotProjectDropdown(
                      projects: _projects,
                      value: _projectId,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _projectId = value);
                        _loadDigest(value, force: false);
                      },
                    ),
                  ),
                ],
              ),
            Builder(
              builder: (context) {
                Project? selectedProject;
                for (final p in _projects) {
                  if (p.id == _projectId) {
                    selectedProject = p;
                    break;
                  }
                }
                if (selectedProject == null) return const SizedBox.shrink();
                final hasJobNumber =
                    selectedProject.purchaseOrderNumber != null &&
                    selectedProject.purchaseOrderNumber!.isNotEmpty;
                final hasAddress = selectedProject.address.isNotEmpty;
                if (!hasJobNumber && !hasAddress) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      if (hasJobNumber) ...[
                        const Icon(
                          Icons.tag,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$singularTerminology #${selectedProject.purchaseOrderNumber}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (hasAddress) ...[
                        const Icon(
                          Icons.location_on,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            AddressFormatter.condense(selectedProject.address),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.base),
            AiCopilotCardStateView(
              enabled: _enabled,
              loading: _loading,
              error: _error,
              disabledMessage:
                  "Weekly digests aren't enabled for your workspace yet.",
              emptyMessage: 'No weekly digest available yet.',
              hasContent:
                  _digest != null && _digest!.digestMarkdown.trim().isNotEmpty,
              content: _digest == null
                  ? const SizedBox.shrink()
                  : Builder(
                      builder: (context) {
                        final risk = _parseRiskFromMarkdown(
                          _digest!.digestMarkdown,
                        );
                        return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  if (_digest!.weekStartDate.isNotEmpty &&
                                      _digest!.weekEndDate.isNotEmpty ||
                                      risk != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Row(
                                        children: [
                                          if (_digest!
                                                  .weekStartDate.isNotEmpty &&
                                              _digest!.weekEndDate.isNotEmpty)
                                            Expanded(
                                              child: Text(
                                                'Week ${_digest!.weekStartDate} to ${_digest!.weekEndDate}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          if (risk != null)
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _riskChipBackground(
                                                  risk.level,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'Risk: ${risk.level} ${risk.score}/100',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: _riskChipTextColor(
                                                    risk.level,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  _buildDigestSection(
                                    context,
                                    title: 'Highlights',
                                    icon: Icons.trending_up_rounded,
                                    items: _digest!.highlightItems,
                                  ),
                                  _buildDigestSection(
                                    context,
                                    title: 'Pressure Points',
                                    icon: Icons.warning_amber_rounded,
                                    items: _digest!.riskItems,
                                  ),
                                  _buildDigestSection(
                                    context,
                                    title: 'Watch This Week',
                                    icon: Icons.visibility_outlined,
                                    items: _digest!.watchItems
                                        .where(
                                          (w) => !_digest!.riskItems.any(
                                            (r) => r.title == w.title,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  _buildDigestSection(
                                    context,
                                    title: 'Next Moves',
                                    icon: Icons.checklist_rtl_rounded,
                                    items: _digest!.priorityItems,
                                  ),
                                ],
                              );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
