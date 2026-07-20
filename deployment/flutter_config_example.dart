// =============================================================================
// Flutter Supabase Configuration Example
// Copy this pattern to your lib/config/ directory
// =============================================================================

/// Supabase configuration for self-hosted instance
///
/// Usage in main.dart:
/// ```dart
/// await Supabase.initialize(
///   url: SupabaseConfig.url,
///   anonKey: SupabaseConfig.anonKey,
/// );
/// ```
class SupabaseConfig {
  // Private constructor to prevent instantiation
  SupabaseConfig._();

  /// Your self-hosted Supabase API URL
  /// Change this when migrating to a new server
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://api.example.com',
  );

  /// Anonymous key for client-side operations
  /// This is safe to include in client apps
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key-here',
  );

  /// Storage bucket names
  static const String projectFilesBucket = 'project-files';
  static const String avatarsBucket = 'avatars';
  static const String workspaceLogosBucket = 'workspace-logos';
  static const String companyLogosBucket = 'company-logos';
  static const String signedDocumentsBucket = 'signed-documents';
  static const String constructionPlansBucket = 'construction-plans';
}

// =============================================================================
// Environment-based configuration (alternative approach)
// =============================================================================

/// Use different configs for dev/staging/prod
enum Environment { dev, staging, prod }

class EnvironmentConfig {
  final String supabaseUrl;
  final String anonKey;

  const EnvironmentConfig({
    required this.supabaseUrl,
    required this.anonKey,
  });

  static const dev = EnvironmentConfig(
    supabaseUrl: 'http://localhost:54321',
    anonKey: 'your-local-anon-key',
  );

  static const staging = EnvironmentConfig(
    supabaseUrl: 'https://api.staging.example.com',
    anonKey: 'your-staging-anon-key',
  );

  static const prod = EnvironmentConfig(
    supabaseUrl: 'https://api.example.com',
    anonKey: 'your-prod-anon-key',
  );

  static EnvironmentConfig get current {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        return staging;
      case 'prod':
        return prod;
      default:
        return dev;
    }
  }
}

// =============================================================================
// Build commands for different environments
// =============================================================================
//
// Development (local Supabase):
//   flutter run
//
// Staging:
//   flutter run --dart-define=ENV=staging
//
// Production:
//   flutter run --dart-define=ENV=prod
//
// Or override URL directly:
//   flutter run --dart-define=SUPABASE_URL=https://api.newserver.com
// =============================================================================
