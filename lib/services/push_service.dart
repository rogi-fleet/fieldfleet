import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/user.dart';
import '../utils/app_logger.dart';

/// Mobile push bootstrap + token registration + tap deep-link handling.
///
/// This service is resilient by design:
/// - No-op on non-mobile platforms.
/// - No-op if Firebase/APNs/FCM runtime config is missing.
/// - Never throws into UI lifecycle.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const _deviceIdKey = 'push_device_id';
  static const _pendingRouteKey = 'push_pending_deeplink';

  GoRouter? _router;
  String? _workspaceId;
  String? _deviceId;
  bool _initialized = false;
  bool _initializing = false;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;

  void attachRouter(GoRouter router) {
    _router = router;
  }

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    _initializing = true;
    try {
      await _ensureFirebaseInitialized();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _deviceId = await _getOrCreateDeviceId();

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((token) async {
        await _registerToken(token: token, transport: 'fcm');
      });

      _onMessageOpenedSub?.cancel();
      _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handlePushTap(message.data),
      );

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        await _handlePushTap(initialMessage.data);
      }

      await _registerCurrentTokens();
      await _consumePendingRouteIfAuthenticated();

      _initialized = true;
      AppLogger.info('Push service initialized');
    } catch (e) {
      AppLogger.warning(
        'Push service initialization skipped',
        metadata: {'error': e.toString()},
      );
    } finally {
      _initializing = false;
    }
  }

  Future<void> onUserContextUpdated(AppUser appUser) async {
    _workspaceId = appUser.currentWorkspaceId;
    if (!_initialized) return;
    await _registerCurrentTokens();
    await _consumePendingRouteIfAuthenticated();
  }

  Future<void> onSignedOut() async {
    if (!_initialized) return;
    await unregisterCurrentDevice();
  }

  Future<void> unregisterCurrentDevice() async {
    if (!_isSupabaseAuthenticatedMobile) return;

    try {
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (accessToken == null) return;

      await http.post(
        Uri.parse('${SupabaseConfig.url}/functions/v1/push-device-unregister'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({'device_id': _deviceId}),
      );
    } catch (e) {
      AppLogger.warning(
        'Push device unregister failed',
        metadata: {'error': e.toString()},
      );
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _onMessageOpenedSub?.cancel();
  }

  Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) return;
    // Uses native Firebase config files when present.
    await Firebase.initializeApp();
  }

  Future<void> _registerCurrentTokens() async {
    if (!_isSupabaseAuthenticatedMobile) return;

    final messaging = FirebaseMessaging.instance;

    final fcmToken = await messaging.getToken();
    if (fcmToken != null && fcmToken.isNotEmpty) {
      await _registerToken(token: fcmToken, transport: 'fcm');
    }

    if (Platform.isIOS) {
      final apnsToken = await messaging.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        await _registerToken(token: apnsToken, transport: 'apns');
      }
    }
  }

  Future<void> _registerToken({
    required String token,
    required String transport,
  }) async {
    if (!_isSupabaseAuthenticatedMobile) return;
    if (_workspaceId == null || _workspaceId!.isEmpty) return;

    try {
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (accessToken == null) return;

      final deviceId = _deviceId ?? await _getOrCreateDeviceId();

      final response = await http.post(
        Uri.parse('${SupabaseConfig.url}/functions/v1/push-device-register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'workspace_id': _workspaceId,
          'device_id': deviceId,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'transport': transport,
          'push_token': token,
          'app_version': null,
          'timezone': DateTime.now().timeZoneName,
          'locale': Platform.localeName,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.warning(
          'Push token registration failed',
          metadata: {
            'status': response.statusCode,
            'transport': transport,
            'response': response.body,
          },
        );
      }
    } catch (e) {
      AppLogger.warning(
        'Push token registration error',
        metadata: {'error': e.toString(), 'transport': transport},
      );
    }
  }

  Future<void> _handlePushTap(Map<String, dynamic> data) async {
    final route = _routeFromPushData(data);
    if (route == null) return;

    if (_isSupabaseAuthenticatedMobile) {
      _router?.go(route);
      return;
    }

    await _storePendingRoute(route);
    _router?.go('/login?from=${Uri.encodeQueryComponent(route)}');
  }

  String? _routeFromPushData(Map<String, dynamic> data) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      return null;
    }

    final explicit = pick([
      'deeplink_path',
      'deep_link',
      'route',
      'target_path',
    ]);
    if (explicit != null) {
      final normalized = explicit.startsWith('/') ? explicit : '/$explicit';
      if (normalized.startsWith('/messages/conversation/')) {
        return normalized.replaceFirst('/messages/conversation/', '/messages/');
      }
      return normalized;
    }

    final projectId = pick(['project_id', 'projectId']);
    final taskId = pick(['task_id', 'taskId']);
    final conversationId = pick(['conversation_id', 'conversationId']);
    final documentId = pick(['document_id', 'documentId']);

    if (projectId != null && taskId != null) {
      return '/projects/$projectId?tab=tasks&taskId=$taskId';
    }
    if (conversationId != null) {
      return '/messages/$conversationId';
    }
    if (documentId != null) {
      return '/documents/$documentId';
    }

    return '/notifications';
  }

  Future<void> _consumePendingRouteIfAuthenticated() async {
    if (!_isSupabaseAuthenticatedMobile) return;

    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_pendingRouteKey);
    if (pending == null || pending.isEmpty) return;

    await prefs.remove(_pendingRouteKey);
    _router?.go(pending);
  }

  Future<void> _storePendingRoute(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingRouteKey, route);
  }

  Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) {
      return _deviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _deviceId = existing;
      return existing;
    }

    final id = const Uuid().v4();
    await prefs.setString(_deviceIdKey, id);
    _deviceId = id;
    return id;
  }

  bool get _isSupabaseAuthenticatedMobile {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    return Supabase.instance.client.auth.currentUser != null;
  }
}
