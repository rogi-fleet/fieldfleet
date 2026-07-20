import 'package:flutter/foundation.dart';

/// Application configuration constants
class AppConfig {
  AppConfig._();

  /// The base URL for the application
  /// This is used for generating invitation links, etc.
  static String get appUrl {
    // On web, links must point at whichever domain is serving this app
    // (app.example.com, portal.example.com, localhost…). The old
    // hardcoded example.com pointed invite links at the marketing
    // holding page, which doesn't serve the app at all.
    if (kIsWeb) {
      return Uri.base.origin;
    }
    if (kDebugMode) {
      return 'http://localhost:8080';
    }
    return 'https://portal.example.com';
  }

  /// Generate an invitation URL for the given token
  static String getInvitationUrl(String token) {
    return '$appUrl/invite/$token';
  }
}
