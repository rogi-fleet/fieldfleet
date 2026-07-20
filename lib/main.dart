import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'widgets/nav_breadcrumb_bar.dart';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';
import 'config/supabase_config.dart';
import 'providers/auth_provider.dart';
import 'theme/theme.dart';
import 'providers/reporting_provider.dart';
import 'providers/workspace_provider.dart';
import 'providers/chrome_provider.dart';
import 'router.dart';
import 'utils/app_logger.dart';
import 'utils/web_magic_link_consumer.dart';
import 'widgets/common/connectivity_banner.dart';
import 'widgets/error_screen.dart';
import 'services/deep_link_handler.dart';
import 'services/push_service.dart';
import 'services/service_locator.dart';

const bool _uiTestMode = bool.fromEnvironment('UI_TEST_MODE');
const String _uiTestEmail = String.fromEnvironment('UI_TEST_EMAIL');
const String _uiTestPassword = String.fromEnvironment('UI_TEST_PASSWORD');

String _buildFlutterErrorDiagnosticLog(FlutterErrorDetails details) {
  final buffer = StringBuffer();
  buffer.writeln(details.exceptionAsString());
  if (details.library != null) {
    buffer.writeln('library: ${details.library}');
  }
  if (details.context != null) {
    buffer.writeln('context: ${details.context}');
  }

  final info = details.informationCollector?.call();
  if (info != null && info.isNotEmpty) {
    buffer.writeln('diagnostics:');
    for (final node in info.take(20)) {
      buffer.writeln('  - ${node.toDescription()}');
    }
  }

  if (details.stack != null) {
    buffer.writeln('stack (top 12):');
    for (final line in details.stack.toString().split('\n').take(12)) {
      buffer.writeln('  $line');
    }
  }

  return buffer.toString();
}

void _logFlutterErrorDebug(FlutterErrorDetails details) {
  if (!kDebugMode) return;

  final message = details.exceptionAsString();
  final isLayoutAssertion = message.contains('requires bounded constraints') ||
      message.contains('Cannot hit test a render box with no size') ||
      message.contains('RenderBox was not laid out');

  debugPrint('');
  debugPrint(
    '=== FLUTTER ERROR (${isLayoutAssertion ? 'LAYOUT' : 'GENERAL'}) START ===',
  );
  debugPrint(_buildFlutterErrorDiagnosticLog(details));
  debugPrint('=== FLUTTER ERROR END ===');
  debugPrint('');
}

bool _isMouseTrackerReentrantAssertion(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return message.contains('mouse_tracker.dart') &&
      message.contains('!_debugDuringDeviceUpdate');
}

Future<void> _maybeSignInUiTestUser() async {
  if (!_uiTestMode) return;
  if (_uiTestEmail.isEmpty || _uiTestPassword.isEmpty) {
    throw StateError(
      'UI_TEST_MODE requires UI_TEST_EMAIL and UI_TEST_PASSWORD dart-defines.',
    );
  }

  final authService = ServiceLocator.authService as dynamic;
  final currentUser = authService.currentUser;
  if (currentUser?.email == _uiTestEmail) {
    AppLogger.info(
      'UI test user already signed in',
      metadata: {'email': _uiTestEmail},
    );
    return;
  }

  if (currentUser != null) {
    AppLogger.info(
      'Signing out existing session before UI test login',
      metadata: {'email': currentUser.email},
    );
    await authService.signOut();
  }

  AppLogger.info(
    'Signing in dedicated UI test user',
    metadata: {'email': _uiTestEmail},
  );
  await authService.signIn(email: _uiTestEmail, password: _uiTestPassword);
}

void main() async {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Path URL strategy: clean /jobs-style URLs that survive refresh and
      // deep-linking (nginx rewrites unknown paths to index.html). Hash
      // strategy made every path deep-link (e.g. /f/<slug> share links,
      // /jobs bookmarks) silently render the dashboard. Legacy /#/route
      // links are re-routed by the shim in _MyAppState.initState.
      setPathUrlStrategy();

      // go_router ≥8 stops reporting imperative push() navigations to the
      // browser URL by default — screens opened via context.push (customer/
      // vendor/equipment detail, …) rendered with a stale address bar, so
      // refresh/share/bookmark silently lost the screen. We want every
      // routed screen URL-addressable.
      GoRouter.optionURLReflectsImperativeAPIs = true;

      if (kDebugMode) {
        print('=== BACKEND CONFIGURATION ===');
        print('Runtime: Supabase only');
        print('=============================');
      }

      AppLogger.info(
        'Supabase URL configured',
        metadata: {'url': SupabaseConfig.url},
      );
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      if (kDebugMode) {
        SupabaseConfig.debugPrint();
      }

      await _maybeSignInUiTestUser();

      // Global error handling
      FlutterError.onError = (errorDetails) {
        FlutterError.presentError(errorDetails);
        if (_isMouseTrackerReentrantAssertion(errorDetails)) {
          return;
        }
        _logFlutterErrorDebug(errorDetails);
        AppLogger.fatal(
          'Uncaught Flutter error',
          error: errorDetails.exception,
          stackTrace: errorDetails.stack,
          metadata: {'library': errorDetails.library ?? 'unknown'},
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppLogger.fatal(
          'Uncaught async error',
          error: error,
          stackTrace: stack,
        );
        return true;
      };

      // Configure global error widget builder
      ErrorWidget.builder = (FlutterErrorDetails details) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ErrorScreen(
            errorDetails: details,
            friendlyMessage:
                'An unexpected error occurred. Please restart the app.',
          ),
        );
      };

      AppLogger.info('App starting');
      runApp(const MyApp());
    },
    (error, stack) {
      // Catch errors outside of Flutter framework
      AppLogger.fatal('Uncaught zone error', error: error, stackTrace: stack);
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.routerFactory});

  final GoRouter Function()? routerFactory;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  DateTime? _lastBackPressed;
  late final GoRouter _router;
  DeepLinkHandler? _deepLinkHandler;

  @override
  void initState() {
    super.initState();
    _router = (widget.routerFactory ?? AppRouter.createRouter)();
    PushService.instance.attachRouter(_router);
    NavHistoryController.instance.attach(_router);
    // Non-blocking bootstrap: push setup may fail if native push config is absent.
    unawaited(PushService.instance.initialize());
    // Universal Links (iOS) + App Links (Android) → GoRouter. No-op
    // on web because the browser address bar already drives the router.
    _deepLinkHandler = DeepLinkHandler(router: _router);
    unawaited(_deepLinkHandler!.start());
    // Web only: catch portal magic-link redirects. Supabase strips fragment
    // routes from redirect_to (#/portal becomes /#/), so the customer lands
    // at the root with `…/#/#access_token=…` — two fragments. Consume the
    // tokens here so they don't survive into the URL bar and route the user
    // to /portal/dashboard regardless of where on the app they landed.
    // Legacy /#/route links are resolved into the router's initialLocation
    // in AppRouter.createRouter (a post-frame go() here races the router's
    // initial route resolution and loses).
    if (kIsWeb) {
      unawaited(_maybeConsumePortalMagicLink());
    }
  }

  Future<void> _maybeConsumePortalMagicLink() async {
    final raw = WebMagicLinkConsumer.currentHref();
    if (raw == null) return;
    final hashes = raw.split('#');
    if (hashes.length < 2) return;
    final tokenFragment = hashes.last;
    if (!tokenFragment.contains('access_token=') ||
        !tokenFragment.contains('refresh_token=')) {
      return;
    }
    final params = Uri.splitQueryString(tokenFragment);
    final refreshToken = params['refresh_token'];
    if (refreshToken == null) return;
    try {
      // Strip the token fragment before signing in so it doesn't sit in the
      // URL bar / browser history.
      WebMagicLinkConsumer.replaceState('/portal');
      await Supabase.instance.client.auth.setSession(refreshToken);
      if (!mounted) return;
      _router.go('/portal/dashboard');
    } catch (e) {
      AppLogger.warning(
        'Portal magic-link consume failed',
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  void dispose() {
    NavHistoryController.instance.detach();
    unawaited(_deepLinkHandler?.stop());
    unawaited(PushService.instance.dispose());
    super.dispose();
  }

  Future<bool> _onWillPop(BuildContext context) async {
    // Only apply double-back-to-exit on Android
    if (!kIsWeb && Platform.isAndroid) {
      final now = DateTime.now();
      final backButtonHasNotBeenPressedOrSnackBarHasBeenClosed =
          _lastBackPressed == null ||
              now.difference(_lastBackPressed!) > const Duration(seconds: 2);

      if (backButtonHasNotBeenPressedOrSnackBarHasBeenClosed) {
        setState(() {
          _lastBackPressed = now;
        });

        // Show snackbar message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return false;
      }

      // Second press within 2 seconds - exit the app
      SystemNavigator.pop();
      return false;
    }

    // On other platforms, allow normal back navigation
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ReportingProvider()),
        ChangeNotifierProvider(create: (_) => WorkspaceProvider()),
        ChangeNotifierProvider(create: (_) => ChromeProvider()),
      ],
      child: Consumer<ChromeProvider>(
        builder: (context, chromeProvider, child) => MaterialApp.router(
          title: 'FieldFleet',
          theme: AppTheme.build(darkChrome: chromeProvider.isDarkChrome),
          routerConfig: _router,
          builder: (context, child) {
            // Only wrap with PopScope on Android
            if (!kIsWeb && Platform.isAndroid) {
              return ConnectivityBanner(
                child: PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) async {
                    if (didPop) return;

                    // Check if we can navigate back within the app
                    if (_router.canPop()) {
                      _router.pop();
                      return;
                    }

                    // Otherwise, handle double-back to exit
                    final shouldPop = await _onWillPop(context);
                    if (!shouldPop) {
                      return;
                    }
                  },
                  child: child!,
                ),
              );
            }
            return ConnectivityBanner(child: child!);
          },
        ),
      ),
    );
  }
}
