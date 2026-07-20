import 'package:flutter/foundation.dart';

/// Supabase configuration for FieldFleet
///
/// Supports multiple environments via compile-time flags:
/// - Local development: `flutter run --dart-define=SUPABASE_ANON_KEY=...`
/// - Production: `flutter run --dart-define=ENV=prod`
///
/// Or override URL directly:
/// - `flutter run --dart-define=SUPABASE_URL=https://api.example.com`
class SupabaseConfig {
  SupabaseConfig._();

  /// Current environment
  static const String _env =
      String.fromEnvironment('ENV', defaultValue: 'local');

  /// Supabase URL override (takes precedence over environment)
  static const String _urlOverride = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon key override
  static const String _anonKeyOverride =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Local development configuration
  /// Local Supabase CLI endpoint.
  static const _local = _SupabaseEnvConfig(
    url: 'http://127.0.0.1:55321',
    anonKey: 'your-local-supabase-anon-key',
  );

  /// Production configuration
  /// TODO: Update these values when deploying to production
  static const _prod = _SupabaseEnvConfig(
    url: 'https://api.example.com',
    anonKey: 'your-production-supabase-anon-key',
  );

  /// Get the active configuration
  static _SupabaseEnvConfig get _config {
    switch (_env) {
      case 'prod':
      case 'production':
        return _prod;
      case 'local':
      case 'dev':
      case 'development':
      default:
        return _local;
    }
  }

  /// Supabase project URL
  static String get url => _urlOverride.isNotEmpty ? _urlOverride : _config.url;

  /// Supabase anonymous key (safe for client-side use)
  static String get anonKey =>
      _anonKeyOverride.isNotEmpty ? _anonKeyOverride : _config.anonKey;

  /// Public-facing web app URL used for building external links (e.g. signing links).
  /// Override with --dart-define=SITE_URL=https://app.example.com
  static const String _siteUrlOverride = String.fromEnvironment('SITE_URL');
  static String get siteUrl {
    if (_siteUrlOverride.isNotEmpty) return _siteUrlOverride;
    if (isProduction) return 'https://app.example.com';
    return 'http://localhost:5000';
  }

  /// Whether we're in local development mode
  static bool get isLocal =>
      _env == 'local' || _env == 'dev' || _env == 'development';

  /// Whether we're in production mode
  static bool get isProduction => _env == 'prod' || _env == 'production';

  /// Storage bucket names
  static const String projectFilesBucket = 'project-files';
  static const String avatarsBucket = 'avatars';
  static const String workspaceLogosBucket = 'workspace-logos';
  static const String constructionPlansBucket = 'construction-plans';

  /// Print configuration (for debugging)
  static void debugPrint() {
    if (kDebugMode) {
      print('Supabase Configuration:');
      print('  Environment: $_env');
      print('  URL: $url');
      print('  Is Local: $isLocal');
    }
  }
}

/// Environment-specific configuration
class _SupabaseEnvConfig {
  final String url;
  final String anonKey;

  const _SupabaseEnvConfig({
    required this.url,
    required this.anonKey,
  });
}
