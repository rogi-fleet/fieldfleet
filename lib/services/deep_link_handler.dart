import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../config/mobile_app_links.dart';
import '../utils/app_logger.dart';

/// Bridges incoming Universal Links (iOS) and App Links (Android) into
/// the app's GoRouter. Set up once in `main.dart` after the router is
/// created, e.g.:
///
/// ```dart
/// final router = AppRouter.createRouter();
/// DeepLinkHandler(router: router).start();
/// ```
///
/// When the OS delivers a URL like `https://app.example.com/projects/abc`
/// (because iOS verified the AASA or Android verified assetlinks.json),
/// the handler strips the host and pushes the path through `router.go`,
/// landing the user inside the app at the same resource they would have
/// reached on the web.
///
/// URLs that target the marketing hosts (`example.com/get-the-app`,
/// blog posts, etc.) are ignored — those should stay in the browser.
class DeepLinkHandler {
  DeepLinkHandler({
    required this.router,
    AppLinks? appLinks,
  }) : _appLinks = appLinks ?? AppLinks();

  final GoRouter router;
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;
  bool _processedInitial = false;

  /// Begin listening. Safe to call multiple times — subsequent calls
  /// cancel the prior subscription first.
  Future<void> start() async {
    if (kIsWeb) {
      // The web build is *already* at the URL — go_router picks it up
      // from the browser address bar. Native deep-link routing only
      // applies to the iOS/Android builds.
      return;
    }
    await _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e, StackTrace st) {
        AppLogger.warning('deep link stream error',
            metadata: {'error': e.toString()});
      },
    );
    if (!_processedInitial) {
      _processedInitial = true;
      try {
        final initial = await _appLinks.getInitialLink();
        if (initial != null) _handle(initial);
      } catch (e) {
        AppLogger.warning('initial deep link fetch failed',
            metadata: {'error': e.toString()});
      }
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _handle(Uri uri) {
    // Only consume URLs from hosts we registered as Universal /
    // App Link domains. Other URIs (custom schemes, third-party
    // domains) are ignored.
    final host = uri.host.toLowerCase();
    if (!MobileAppLinks.deepLinkHosts.contains(host)) {
      AppLogger.debug('deep link ignored (unknown host)',
          metadata: {'host': host, 'uri': uri.toString()});
      return;
    }
    // For the marketing host (example.com), only /projects/* and
    // similar app-routes deep into the portal. /get-the-app, /blog,
    // /services etc. should stay in the browser — Apple's AASA file
    // already excludes them, but be defensive in case a stale AASA
    // is cached on the device.
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (host == 'example.com' && _isMarketingPath(path)) {
      AppLogger.debug('deep link skipped (marketing path)',
          metadata: {'path': path});
      return;
    }
    final fullPath = uri.hasQuery ? '$path?${uri.query}' : path;
    AppLogger.debug('deep link dispatched',
        metadata: {'host': host, 'path': fullPath});
    router.go(fullPath);
  }

  static bool _isMarketingPath(String path) {
    return path == '/' ||
        path == '/get-the-app' ||
        path == '/apps' ||
        path.startsWith('/blog') ||
        path.startsWith('/services') ||
        path == '/privacy' ||
        path == '/terms' ||
        path == '/cookies' ||
        path == '/api-policy';
  }
}
