/// Canonical URLs and metadata for the FieldFleet mobile apps. Surfaces
/// like the scan-unsupported screen, the preset picker download sheet,
/// and the /apps route all read from here so we update one constant
/// when an app moves from TestFlight to production.
///
/// ── Update path ──
/// 1. While in pre-launch: leave [isAvailable] as `false`. The download
///    surfaces render the buttons in a disabled "Coming soon" state so
///    users know mobile is on the way but can't click through to a
///    broken store URL.
/// 2. When TestFlight / Play Internal Testing public links exist:
///    update [appStoreUrl] / [playStoreUrl] below and flip
///    [isAvailable] to `true`. No other code changes needed.
/// 3. Once production review approves: replace the URLs again with
///    the canonical store URLs. Still no code changes elsewhere.
class MobileAppLinks {
  /// Apple App Store / TestFlight URL.
  static const String appStoreUrl =
      'https://apps.apple.com/app/taskfleet/id000000000';

  /// Google Play Store / internal testing URL.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.taskfleet.taskfleet';

  /// Apple's `apple-itunes-app` Smart App Banner id. Numeric portion
  /// of the App Store URL above. Returns null until an App Store id
  /// is issued — the portal's index.html meta tag falls back gracefully.
  static const String? smartAppBannerId = null;

  /// Bundle / package id, mirrored from native build configuration.
  static const String iosBundleId = 'com.taskfleet.taskfleet';
  static const String androidPackageId = 'com.taskfleet.taskfleet';

  /// Flip to `true` once you have working TestFlight / Play Internal
  /// links (or production store URLs) in the constants above. The
  /// download surfaces gate their CTAs on this — disabled state
  /// shows "Coming soon" badges so users don't click through to
  /// dead URLs while we're still in pre-launch.
  static const bool isAvailable = false;

  /// Stable direct-download URL for the self-hosted Android APK,
  /// served by nginx (see `setup-portal-downloads.sh`). Always
  /// resolves to the latest release uploaded by
  /// `build_and_upload.sh`. Pre-launch sideload path until Play
  /// Store + TestFlight take over. Set to `null` to hide the link
  /// once Play Internal Testing makes it redundant — the widget
  /// gates on null, so this stays nullable on purpose.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? directAndroidApkUrl =
      'https://app.example.com/downloads/taskfleet-latest.apk';

  /// Set to `true` once the official Apple and Google badge artwork
  /// has been added to `assets/images/store_badges/`:
  ///   * `app_store.png`   — Apple's official "Download on the App Store"
  ///                          badge (downloaded from
  ///                          https://developer.apple.com/app-store/marketing/guidelines/).
  ///   * `play_store.png`  — Google's official "Get it on Google Play"
  ///                          badge (downloaded from
  ///                          https://play.google.com/intl/en_us/badges/).
  ///
  /// While `false`, the widget falls back to a Material-styled
  /// text+icon button — looks decent, but not the polished badge.
  static const bool useOfficialBadges = false;

  /// Hosts the app expects to handle as Universal Links / App Links.
  /// Mirror these in:
  ///   * web/.well-known/apple-app-site-association
  ///   * web/.well-known/assetlinks.json
  ///   * ios/Runner/Runner.entitlements
  ///   * android/app/src/main/AndroidManifest.xml
  static const List<String> deepLinkHosts = [
    'example.com',
    'app.example.com',
  ];

  /// Apple Team ID — required for the `appID` field of the AASA file.
  /// Look it up at https://developer.apple.com/account/#/membership/.
  /// Replace `TEAMID` once you know it; the AASA template at
  /// `web/.well-known/apple-app-site-association` references this value.
  static const String iosTeamId = 'TEAMID';

  /// Android signing-cert SHA-256 fingerprint, colon-separated and
  /// upper-case. Get it via:
  ///   `keytool -list -v -keystore /path/to/release.keystore`
  ///   `  -alias [ALIAS] | grep SHA256`
  /// The assetlinks.json template references this value.
  static const String androidSigningSha256 = 'AA:BB:CC:DD:EE:FF';
}
