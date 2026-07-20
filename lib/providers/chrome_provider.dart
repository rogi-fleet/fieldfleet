import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/service_locator.dart';
import '../theme/chrome_colors.dart';

/// Manages the dark/light chrome preference for toolbars and headers.
/// Preference is persisted both locally (SharedPreferences) and server-side
/// (user_preferences table) so it syncs across devices.
class ChromeProvider extends ChangeNotifier {
  static const _prefKey = 'dark_chrome_enabled';
  static const _serverKey = 'appearance_theme';

  bool _darkChrome = true;
  SharedPreferences? _prefs;
  StreamSubscription<AuthState>? _authSub;

  bool get isDarkChrome => _darkChrome;

  ChromeColors get chromeColors =>
      _darkChrome ? ChromeColors.dark : ChromeColors.light;

  ChromeProvider() {
    _load();
    // Re-pull from the server once auth is established. ChromeProvider is
    // built before login, so the initial _load() runs without a session and
    // can't read user_preferences. Without this listener, a returning user's
    // saved theme would silently revert to the local default on a fresh tab.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.initialSession ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        if (event.session != null) {
          _load();
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final localValue = prefs.getBool(_prefKey) ?? true;
    if (_darkChrome != localValue) {
      _darkChrome = localValue;
      notifyListeners();
    }

    // Check server preference — server wins if present.
    try {
      final serverPrefs =
          await ServiceLocator.userPreferencesService.getPreferences();
      final serverTheme = serverPrefs[_serverKey] as String?;
      if (serverTheme != null) {
        final serverDark = serverTheme == 'dark';
        if (serverDark != _darkChrome) {
          _darkChrome = serverDark;
          await prefs.setBool(_prefKey, _darkChrome);
          notifyListeners();
        }
      } else if (Supabase.instance.client.auth.currentUser != null) {
        // Only migrate the local value upward when we actually have a
        // session — otherwise we'd silently no-op and miss the real server
        // value once auth comes online.
        await ServiceLocator.userPreferencesService.updatePreferenceKey(
          _serverKey,
          localValue ? 'dark' : 'light',
        );
      }
    } catch (_) {
      // Server unavailable — local value stands.
    }
  }

  Future<void> setDarkChrome(bool value) async {
    if (_darkChrome == value) return;
    _darkChrome = value;
    notifyListeners();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    // Fire-and-forget server sync.
    ServiceLocator.userPreferencesService.updatePreferenceKey(
      _serverKey,
      value ? 'dark' : 'light',
    );
  }
}
