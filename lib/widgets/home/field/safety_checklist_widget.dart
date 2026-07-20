import 'package:flutter/material.dart';

import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';

/// Daily safety sign-off checklist for field technicians.
///
/// Persists state to user preferences keyed by date so it resets each day.
class SafetyChecklistWidget extends StatefulWidget {
  final String workspaceId;
  final String userId;

  const SafetyChecklistWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
  });

  @override
  State<SafetyChecklistWidget> createState() => _SafetyChecklistWidgetState();
}

class _SafetyChecklistWidgetState extends State<SafetyChecklistWidget> {
  static const _items = [
    _CheckItem('ppe_hard_hat', 'Hard hat'),
    _CheckItem('ppe_safety_glasses', 'Safety glasses'),
    _CheckItem('ppe_gloves', 'Gloves'),
    _CheckItem('ppe_steel_toe', 'Steel-toe boots'),
    _CheckItem('ppe_high_vis', 'High-vis vest'),
    _CheckItem('hazards_reviewed', 'Site hazards reviewed'),
    _CheckItem('emergency_exits', 'Emergency exits noted'),
    _CheckItem('first_aid_located', 'First aid kit located'),
  ];

  static const _prefKey = 'safety_checklist';

  final Map<String, bool> _checked = {};
  bool _loading = true;
  late final String _sessionDate;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _sessionDate =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    final raw = await ServiceLocator.userPreferencesService.getWidgetConfig(
      _prefKey,
    );
    // Reset if the stored date doesn't match today.
    final storedDate = raw['date'] as String?;
    final isToday = storedDate == _sessionDate;
    for (final item in _items) {
      _checked[item.id] = isToday && raw[item.id] == true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String itemId) async {
    setState(() {
      _checked[itemId] = !(_checked[itemId] ?? false);
    });
    final data = <String, dynamic>{
      'date': _sessionDate,
      for (final item in _items) item.id: _checked[item.id] ?? false,
    };
    await ServiceLocator.userPreferencesService.updatePreferenceKey(
      _prefKey,
      data,
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkedCount = _checked.values.where((v) => v).length;
    final total = _items.length;
    final allDone = checkedCount == total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(checkedCount, total, allDone),
            const SizedBox(height: AppSpacing.base),
            if (_loading)
              const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: LinearProgressIndicator(
                  value: total > 0 ? checkedCount / total : 0,
                  backgroundColor: AppColors.surfaceAlt,
                  color: allDone
                      ? AppColors.success
                      : AppColors.error,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: AppSpacing.iconGap),

              // Checklist items
              ..._items.map((item) {
                final isChecked = _checked[item.id] ?? false;
                return InkWell(
                  onTap: () => _toggle(item.id),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        // IgnorePointer so a single tap on the row toggles
                        // exactly once. Without it, both the InkWell and
                        // the Checkbox fire _toggle and cancel each other.
                        IgnorePointer(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isChecked,
                              onChanged: (_) => _toggle(item.id),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              activeColor: AppColors.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: isChecked
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                              decoration: isChecked
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              if (allDone) ...[
                const SizedBox(height: AppSpacing.iconGap),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 18,
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Text(
                        'Safety check complete',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int checked, int total, bool allDone) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (allDone
                    ? AppColors.success
                    : AppColors.error)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Icon(
            allDone ? Icons.verified_user : Icons.health_and_safety,
            color: allDone
                ? AppColors.success
                : AppColors.error,
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            'Safety Checklist',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: allDone
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            '$checked/$total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: allDone
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckItem {
  final String id;
  final String label;

  const _CheckItem(this.id, this.label);
}
