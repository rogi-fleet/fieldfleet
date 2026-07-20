import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// One-time heads-up banner explaining the new Master Admin tier introduced
/// by the role expansion migration (2026-04-19). Hidden once the user
/// dismisses it.
///
/// Dismissal is stored in the view-prefs service (SharedPreferences cache +
/// per-user `user_preferences` row on the server), so it survives browser
/// profile resets and follows the user across devices. The pre-existing
/// SharedPreferences-only flag is migrated forward on first load.
///
/// Shown only to admins (who are the only ones affected by the change).
class MasterAdminTierBanner extends StatefulWidget {
  const MasterAdminTierBanner({
    super.key,
    required this.userId,
    required this.isAdmin,
    this.teamSize,
  });

  final String userId;
  final bool isAdmin;

  /// Onboarding "team size" bucket (1..5). The banner explains a role split
  /// that only matters when there is more than one admin/member, so we hide
  /// it for solo workspaces (teamSize == 1).
  final int? teamSize;

  @override
  State<MasterAdminTierBanner> createState() => _MasterAdminTierBannerState();
}

class _MasterAdminTierBannerState extends State<MasterAdminTierBanner> {
  static const _scopeKey = 'banner.master_admin_tier';

  bool _resolved = false;
  bool _dismissed = true;
  StreamSubscription<void>? _changesSub;

  String get _legacyPrefKey =>
      'banner.master_admin_tier.dismissed.${widget.userId}';

  @override
  void initState() {
    super.initState();
    _loadDismissed();
    // A fresh device hydrates the local cache before the server snapshot
    // arrives — hide the banner when a late reconcile reports it dismissed.
    _changesSub = ServiceLocator.viewPrefsService
        .changes(_scopeKey)
        .listen((_) => _refreshFromService());
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDismissed() async {
    final svc = ServiceLocator.viewPrefsService;
    await svc.whenHydrated;
    if (!mounted) return;

    var dismissed = svc.read(_scopeKey)?['dismissed'] == true;

    if (!dismissed) {
      // Migrate the pre-service flag so users who already dismissed the
      // banner don't see it resurrected (and get server persistence too).
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_legacyPrefKey) ?? false) {
        dismissed = true;
        svc.write(_scopeKey, {'dismissed': true});
      }
      if (!mounted) return;
    }

    setState(() {
      _dismissed = dismissed;
      _resolved = true;
    });
  }

  void _refreshFromService() {
    if (!mounted || _dismissed) return;
    if (ServiceLocator.viewPrefsService.read(_scopeKey)?['dismissed'] ==
        true) {
      setState(() => _dismissed = true);
    }
  }

  Future<void> _dismiss() async {
    final svc = ServiceLocator.viewPrefsService;
    svc.write(_scopeKey, {'dismissed': true});
    // Don't leave the server copy to the debounced flush — a dismissal is
    // tiny and the tab may close before the timer fires.
    unawaited(svc.flush());
    setState(() => _dismissed = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_legacyPrefKey, true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin || !_resolved || _dismissed) {
      return const SizedBox.shrink();
    }
    // Hide for solo workspaces — the role split is irrelevant when there's
    // only one admin/member.
    if (widget.teamSize == 1) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        border: Border(
          left: BorderSide(color: AppColors.info, width: 3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.infoDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New: Master Admin tier',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.infoDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Role templates now separate Master Admin (user + billing '
                  'management) from Admin (full operational access). Your '
                  'existing admins keep the same workspace access — only the '
                  'label changed.',
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close),
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}
