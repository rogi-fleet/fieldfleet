import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/mobile_app_links.dart';
import '../../theme/theme.dart';

/// Renders one of Apple's or Google's official badge PNGs. Locked to
/// a 56 px height — both stores publish their badges at a 4:1 aspect
/// ratio so width comes out around 224 px. If the asset is missing
/// (user hasn't added the PNGs yet) the errorBuilder shows a tiny
/// placeholder so the layout doesn't collapse.
class _OfficialBadge extends StatelessWidget {
  final String assetPath;
  final String url;
  final bool available;
  final String label;
  const _OfficialBadge({
    required this.assetPath,
    required this.url,
    required this.available,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      assetPath,
      height: 56,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          child: Text(
            'Missing $assetPath',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        );
      },
    );
    final wrapped = available ? image : Opacity(opacity: 0.55, child: image);
    return Tooltip(
      message: available ? label : '$label — coming soon',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: available
            ? () async {
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            : null,
        child: wrapped,
      ),
    );
  }
}

/// Reusable "Get the FieldFleet mobile app" block.
///
/// Renders two App Store / Play Store buttons; on wide layouts (desktop /
/// big browser) also shows a QR code so users on a laptop can scan with
/// their phone instead of typing.
///
/// Reads [MobileAppLinks.isAvailable] to decide whether the buttons are
/// active or rendered in a "Coming soon" disabled state. Keeps the UI
/// in place so users know mobile is on the way even before TestFlight
/// links exist.
///
/// The buttons fall back to a Material text-and-icon style — drop the
/// official Apple and Google badge artwork into
/// `assets/images/store_badges/{app_store,play_store}.png` (and declare
/// them in pubspec.yaml) and the buttons swap automatically. We do not
/// inline Apple's or Google's trademarked badge SVG because using
/// approximate artwork is a TOS violation.
class AppDownloadSection extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String body;

  /// When true, force-hide the QR even on wide layouts. Useful inside
  /// already-cramped surfaces (bottom sheets) where a 140 px square
  /// would push the buttons off the screen.
  final bool hideQr;

  const AppDownloadSection({
    super.key,
    this.eyebrow,
    this.title = 'Get the FieldFleet mobile app',
    this.body = 'Room scanning, on-site photo capture, and offline forms — '
        'available on iPhone and Android.',
    this.hideQr = false,
  });

  bool get _available => MobileAppLinks.isAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Show the QR on roomy layouts (typically desktop / wide web)
        // where it genuinely helps — users on phones already have one
        // of the store apps installed, so a QR there is noise.
        final showQr = !hideQr && constraints.maxWidth >= 520;
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _StoreButton(
                          platform: _StorePlatform.iOS,
                          url: MobileAppLinks.appStoreUrl,
                          available: _available,
                        ),
                        _StoreButton(
                          platform: _StorePlatform.android,
                          url: MobileAppLinks.playStoreUrl,
                          available: _available,
                        ),
                      ],
                    ),
                    if (MobileAppLinks.directAndroidApkUrl != null) ...[
                      const SizedBox(height: 10),
                      _DirectApkLink(
                        url: MobileAppLinks.directAndroidApkUrl!,
                      ),
                    ],
                  ],
                ),
              ),
              if (showQr) ...[
                const SizedBox(width: 16),
                _QrBlock(available: _available),
              ],
            ],
          ),
        );
      },
    );
  }
}

enum _StorePlatform { iOS, android }

class _StoreButton extends StatelessWidget {
  final _StorePlatform platform;
  final String url;
  final bool available;
  const _StoreButton({
    required this.platform,
    required this.url,
    required this.available,
  });

  IconData get _icon => switch (platform) {
        _StorePlatform.iOS => Icons.apple,
        _StorePlatform.android => Icons.android_outlined,
      };

  String get _topLine => switch (platform) {
        _StorePlatform.iOS => 'Download on the',
        _StorePlatform.android => 'Get it on',
      };

  String get _bottomLine => switch (platform) {
        _StorePlatform.iOS => 'App Store',
        _StorePlatform.android => 'Google Play',
      };

  String get _assetPath => switch (platform) {
        _StorePlatform.iOS => 'assets/images/store_badges/app_store.png',
        _StorePlatform.android => 'assets/images/store_badges/play_store.png',
      };

  @override
  Widget build(BuildContext context) {
    // When the user has dropped in the official Apple/Google badge
    // artwork (and flipped MobileAppLinks.useOfficialBadges), render
    // those images instead of the Material-styled fallback.
    if (MobileAppLinks.useOfficialBadges) {
      return _OfficialBadge(
        assetPath: _assetPath,
        url: url,
        available: available,
        label: '$_topLine $_bottomLine',
      );
    }
    final theme = Theme.of(context);
    final fg = available ? Colors.white : theme.colorScheme.onSurfaceVariant;
    final bg =
        available ? Colors.black : theme.colorScheme.surfaceContainerHighest;
    return Tooltip(
      message:
          available ? '$_topLine $_bottomLine' : '$_bottomLine — coming soon',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: available ? () => _launch(context, url) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: available ? Colors.black : theme.colorScheme.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, color: fg, size: 26),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _topLine,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg.withValues(alpha: 0.85),
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _bottomLine,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  if (!available) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Coming soon',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t open $url')),
      );
    }
  }
}

class _QrBlock extends StatelessWidget {
  final bool available;
  const _QrBlock({required this.available});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Encode a small redirect URL that the portal can later route by
    // user-agent (iOS → App Store, Android → Play Store, other →
    // marketing page). For now point at the public marketing root —
    // safe regardless of platform.
    const target = 'https://example.com/app';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 132,
          height: 132,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: available
              ? QrImageView(
                  data: target,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                )
              : const Center(
                  child: Icon(
                    Icons.qr_code_2_outlined,
                    size: 48,
                    color: Colors.black26,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          available ? 'Scan to install' : 'QR coming soon',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Secondary "tester" download — surfaces the self-hosted APK as a small
/// link below the store buttons. Deliberately understated so it doesn't
/// compete with the real Play Store CTA once that ships. Hides itself
/// on iOS, where direct sideloading isn't possible without TestFlight.
class _DirectApkLink extends StatelessWidget {
  final String url;
  const _DirectApkLink({required this.url});

  @override
  Widget build(BuildContext context) {
    // Android-only. On iOS / web / desktop the link makes no sense.
    // Detect with `defaultTargetPlatform` so the same widget works in
    // the web portal (where Platform.isAndroid would throw).
    final platform = Theme.of(context).platform;
    final showAlways = kIsWeb; // marketing visitor — show on all platforms
    if (!showAlways && platform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Direct APK download — for internal testers. Sideload only; '
          'Android will warn about installing from an unknown source.',
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.android_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Direct .apk download (testers)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the [AppDownloadSection] as a Material 3 bottom sheet. Returns
/// the future that completes when the sheet is dismissed.
Future<void> showAppDownloadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: AppDownloadSection(
            eyebrow: 'MOBILE',
            title: 'Open this on your phone',
            body: 'Room scanning needs the camera and AR runtime, which '
                'only ship in the iPhone and Android apps. Install the '
                'FieldFleet mobile app and sign in with the same account.',
            hideQr: true,
          ),
        ),
      );
    },
  );
}
