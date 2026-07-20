import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';

/// A preset option for the quick add row (e.g., "+ Task", "+ Milestone").
class QuickAddPreset {
  final String label;
  final String value;
  final Color color;

  const QuickAddPreset({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// Inline row at the bottom of each group for fast task creation.
class QuickAddRow extends StatefulWidget {
  final Color groupColor;
  final Future<void> Function(String title) onSubmit;
  final bool showPhaseHierarchyGuide;

  /// When true the group has no task rows, so the phase guide draws a
  /// continuous vertical line (tee) instead of a terminating elbow.
  final bool groupIsEmpty;
  final List<QuickAddPreset> presets;
  final Future<void> Function(String title, String presetValue)? onSubmitWithPreset;

  /// Called when a task is dropped onto this row (e.g., into an empty group).
  final void Function(Task task)? onTaskDropped;

  const QuickAddRow({
    super.key,
    required this.groupColor,
    required this.onSubmit,
    this.showPhaseHierarchyGuide = false,
    this.groupIsEmpty = false,
    this.presets = const [],
    this.onSubmitWithPreset,
    this.onTaskDropped,
  });

  @override
  State<QuickAddRow> createState() => QuickAddRowState();
}

class QuickAddRowState extends State<QuickAddRow> {
  static const double _rowHorizontalPadding = 10;
  static const double _leadingControlWidth = 28;
  static const double _guideColumnWidth = 24;
  bool _isActive = false;
  bool _isSubmitting = false;
  bool _isDragTarget = false;
  String? _selectedPreset;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().canCreateTasks) {
      return const SizedBox.shrink();
    }
    final Widget content;
    if (!_isActive) {
      content = GestureDetector(
        onTap: _activate,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(
              horizontal: _rowHorizontalPadding,
            ),
            decoration: BoxDecoration(
              color: _isDragTarget
                  ? AppColors.info.withValues(alpha: 0.10)
                  : null,
              border: Border(
                left: BorderSide(
                  color: _isDragTarget
                      ? widget.groupColor
                      : widget.groupColor.withValues(alpha: 0.3),
                  width: 3,
                ),
                bottom: BorderSide(
                  color: _isDragTarget
                      ? AppColors.info
                      : Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: _isDragTarget ? 2 : 1,
                ),
                top: _isDragTarget
                    ? const BorderSide(color: AppColors.info, width: 2)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                if (widget.showPhaseHierarchyGuide) ...[
                  const SizedBox(width: _leadingControlWidth),
                  SizedBox(
                    width: _guideColumnWidth,
                    height: 36,
                    child: CustomPaint(
                      painter: _QuickAddGuidePainter(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.7),
                        continueVertical: widget.groupIsEmpty,
                      ),
                    ),
                  ),
                ],
                Icon(Icons.add, size: 16,
                    color: _isDragTarget ? AppColors.info : AppColors.textTertiary),
                const SizedBox(width: 8),
                Text(
                  _isDragTarget ? 'Drop here' : 'Add a task',
                  style: TextStyle(
                    fontSize: 13,
                    color: _isDragTarget ? AppColors.info : AppColors.textTertiary,
                    fontWeight: _isDragTarget ? FontWeight.w500 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      content = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: _rowHorizontalPadding),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.05),
        border: Border(
          left: BorderSide(color: widget.groupColor, width: 3),
          bottom: BorderSide(color: AppColors.info.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          if (widget.showPhaseHierarchyGuide) ...[
            const SizedBox(width: _leadingControlWidth),
            SizedBox(
              width: _guideColumnWidth,
              height: 36,
              child: CustomPaint(
                painter: _QuickAddGuidePainter(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.7),
                  continueVertical: widget.groupIsEmpty,
                ),
              ),
            ),
          ],
          Icon(Icons.add, size: 16, color: AppColors.info),
          const SizedBox(width: 8),
          // Preset type buttons
          if (widget.presets.isNotEmpty) ...[
            for (final preset in widget.presets) ...[
              _QuickAddPresetButton(
                preset: preset,
                isSelected: _selectedPreset == preset.value,
                onTap: () {
                  setState(() => _selectedPreset =
                      _selectedPreset == preset.value ? null : preset.value);
                  _focusNode.requestFocus();
                },
              ),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 4),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              enabled: !_isSubmitting,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.only(top: 8, bottom: 8, left: 4),
                hintText: 'Task name...',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
              ),
              onSubmitted: _submit,
              onTapOutside: (_) => _deactivate(),
            ),
          ),
          if (_isSubmitting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
    }

    if (widget.onTaskDropped == null) return content;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        setState(() => _isDragTarget = false);
        widget.onTaskDropped?.call(details.data);
      },
      onMove: (_) {
        if (!_isDragTarget) setState(() => _isDragTarget = true);
      },
      onLeave: (_) {
        if (_isDragTarget) setState(() => _isDragTarget = false);
      },
      builder: (context, candidateData, rejectedData) => content,
    );
  }

  void activateEditing() {
    setState(() => _isActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _activate() {
    activateEditing();
  }

  void _deactivate() {
    if (_controller.text.trim().isEmpty) {
      setState(() => _isActive = false);
    }
  }

  Future<void> _submit(String value) async {
    final title = value.trim();
    if (title.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      if (_selectedPreset != null && widget.onSubmitWithPreset != null) {
        await widget.onSubmitWithPreset!(title, _selectedPreset!);
      } else {
        await widget.onSubmit(title);
      }
      _controller.clear();
      _focusNode.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _QuickAddPresetButton extends StatelessWidget {
  final QuickAddPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickAddPresetButton({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? preset.color.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(
            color: isSelected
                ? preset.color.withValues(alpha: 0.5)
                : preset.color.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          '+ ${preset.label}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: preset.color,
          ),
        ),
      ),
    );
  }
}

class _QuickAddGuidePainter extends CustomPainter {
  final Color color;

  /// When true, the vertical line continues past the branch (tee pattern)
  /// instead of terminating at the branch (elbow pattern). Used when the
  /// group has no task rows so the phase-connecting line stays continuous.
  final bool continueVertical;

  const _QuickAddGuidePainter({
    required this.color,
    this.continueVertical = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cornerRadius = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Nudge left to match the task-row guide column center precisely.
    final midX = (size.width / 2) - 3.0;
    final midY = (size.height / 2);

    if (continueVertical) {
      // Group is empty – elbow from top of row (phase header bottom) to branch.
      final path = Path()
        ..moveTo(midX, 0)
        ..lineTo(midX, midY - cornerRadius)
        ..quadraticBezierTo(midX, midY, midX + cornerRadius, midY)
        ..lineTo(size.width, midY);
      canvas.drawPath(path, paint);
    } else {
      // Elbow pattern: vertical stops at branch.
      final path = Path()
        ..moveTo(midX, -23)
        ..lineTo(midX, midY - cornerRadius)
        ..quadraticBezierTo(midX, midY, midX + cornerRadius, midY)
        ..lineTo(size.width, midY);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _QuickAddGuidePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.continueVertical != continueVertical;
  }
}
