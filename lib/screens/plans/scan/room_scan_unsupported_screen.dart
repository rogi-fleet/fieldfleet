import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/floorplan/scan/floor_plan_scan_result.dart';
import '../../../widgets/adaptive_navigation.dart';
import '../../../widgets/mobile_app/app_download_section.dart';
import '../../../theme/theme.dart';

/// Shown when the native plugin says it cannot scan on this device — either
/// because we're on web/desktop, because the OS version is too old, or
/// because the camera permission was permanently denied.
class RoomScanUnsupportedScreen extends StatelessWidget {
  final String reason;
  final ScanFailureKind? failureKind;
  final String? backRoute;

  const RoomScanUnsupportedScreen({
    super.key,
    required this.reason,
    this.failureKind,
    this.backRoute,
  });

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(title: const Text('Scan a room')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const Icon(Icons.view_in_ar_outlined, size: 72),
                const SizedBox(height: 16),
                Text(
                  'Scanning isn\'t available here',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const AppDownloadSection(
                  eyebrow: 'GET THE APP',
                  title: 'Scan rooms with FieldFleet mobile',
                  body: 'Room scanning uses your phone\'s camera and AR '
                      'runtime. Install the mobile app, sign in with the '
                      'same account, and scans appear in the same project.',
                ),
                const SizedBox(height: 16),
                Center(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).maybePop().then((popped) {
                      if (!popped && backRoute != null && context.mounted) {
                        context.go(backRoute!);
                      }
                    }),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );

    // On web/desktop the scan route lives outside the ShellRoute (so the
    // native AR view can be fullscreen). When we fall through to the
    // unsupported screen on those platforms the user is stranded without
    // chrome — wrap the unsupported screen in AdaptiveNavigation so they
    // can navigate elsewhere.
    if (kIsWeb) {
      return AdaptiveNavigation(selectedIndex: -1, child: scaffold);
    }
    return scaffold;
  }
}
