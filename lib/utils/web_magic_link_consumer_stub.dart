/// Non-web stub. The portal magic-link redirect flow is web-only — mobile
/// uses the existing custom-scheme deep link — so these methods are no-ops
/// off the web.
class WebMagicLinkConsumer {
  static String? currentHref() => null;
  static void replaceState(String hash) {}
}
