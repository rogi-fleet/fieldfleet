// Cross-platform shim for reading the browser URL and rewriting history.
// Only the web implementation actually touches dart:html; mobile/desktop
// pretend the API is a no-op so callers don't need their own kIsWeb guard.
export 'web_magic_link_consumer_stub.dart'
    if (dart.library.html) 'web_magic_link_consumer_web.dart';
