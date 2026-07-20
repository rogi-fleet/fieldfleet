// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Web-only helper for reading the raw browser URL and replacing history
/// state. Used by the magic-link consumer to strip auth tokens out of the
/// URL bar after they've been handed to supabase_flutter.
class WebMagicLinkConsumer {
  static String? currentHref() => html.window.location.href;

  static void replaceState(String hash) {
    html.window.history.replaceState(null, '', hash);
  }
}
