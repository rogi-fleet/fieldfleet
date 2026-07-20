import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'adaptive_popup.dart';

/// One entry in [AddEntityFab]'s multi-action sheet.
class AddEntityAction {
  const AddEntityAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final IconData icon;

  /// Optional secondary line shown under [label] in the actions sheet.
  final String? subtitle;
  final VoidCallback onTap;
}

/// Shared "+ Add `<entity>`" floating action button (UI chrome unification
/// proposal, P1-1).
///
/// Two modes, exactly one of which must be provided:
/// - single action: pass [onPressed];
/// - multi action: pass [actions] — tapping the FAB opens an adaptive
///   bottom sheet (dialog on wide screens) listing them. A single-element
///   [actions] list invokes that action directly, no sheet.
///
/// Pulse-when-empty: when [isEmpty] is true and [filtersActive] is false the
/// FAB scales 1.0 → 1.08 on a repeating 1500 ms ease-in-out curve — the same
/// parameters previously copy-pasted across the Projects, Plans and Customers
/// screens. The controller lives inside this widget; adopters just pass the
/// two booleans.
///
/// [visible] is the permission-gating seam: when false the widget renders a
/// [SizedBox.shrink] so callers can write `visible: canCreateX` instead of
/// branching at the call site.
class AddEntityFab extends StatefulWidget {
  const AddEntityFab({
    super.key,
    required this.label,
    this.icon = Icons.add,
    this.onPressed,
    this.actions,
    this.isEmpty = false,
    this.filtersActive = false,
    this.visible = true,
    this.heroTag,
  }) : assert(
         (onPressed != null) ^ (actions != null),
         'Provide exactly one of onPressed or actions.',
       );

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final List<AddEntityAction>? actions;
  final bool isEmpty;
  final bool filtersActive;
  final bool visible;

  /// Passed through to [FloatingActionButton.extended]. Set this when more
  /// than one FAB can be on screen (e.g. tabbed modules) to avoid Hero tag
  /// collisions.
  final Object? heroTag;

  /// Shows the same actions sheet the FAB opens, for reuse by secondary
  /// affordances (e.g. an empty-state CTA that mirrors the FAB's menu).
  static Future<void> showActionsSheet(
    BuildContext context,
    List<AddEntityAction> actions,
  ) async {
    final choice = await showAdaptiveSheet<AddEntityAction>(
      context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              ListTile(
                leading: Icon(action.icon),
                title: Text(action.label),
                subtitle: action.subtitle == null
                    ? null
                    : Text(
                        action.subtitle!,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                onTap: () => Navigator.pop(sheetContext, action),
              ),
          ],
        ),
      ),
    );
    choice?.onTap();
  }

  @override
  State<AddEntityFab> createState() => _AddEntityFabState();
}

class _AddEntityFabState extends State<AddEntityFab>
    with SingleTickerProviderStateMixin {
  // Distinct from Flutter's own FAB default tag, so an AddEntityFab can
  // coexist with one stock FAB; two unlabeled AddEntityFabs still need
  // explicit heroTags, same as stock FABs do.
  static const Object _defaultHeroTag = Object();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool get _shouldPulse => widget.isEmpty && !widget.filtersActive;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(AddEntityFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (_shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handlePressed() {
    final actions = widget.actions;
    if (actions == null) {
      widget.onPressed?.call();
    } else if (actions.length == 1) {
      actions.first.onTap();
    } else {
      AddEntityFab.showActionsSheet(context, actions);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) => Transform.scale(
        scale: _shouldPulse ? _pulseAnimation.value : 1.0,
        child: child,
      ),
      child: FloatingActionButton.extended(
        heroTag: widget.heroTag ?? _defaultHeroTag,
        onPressed: _handlePressed,
        icon: Icon(widget.icon),
        label: Text(widget.label),
      ),
    );
  }
}
