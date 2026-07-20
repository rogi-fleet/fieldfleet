/// Backend configuration for the Supabase-only app runtime.
class BackendConfig {
  BackendConfig._();

  static const bool useSupabaseAuth = true;
  static const bool useSupabaseUsers = true;
  static const bool useSupabaseProjects = true;
  static const bool useSupabaseStorage = true;
  static const bool useSupabaseFinancial = true;
  static const bool useSupabaseMessaging = true;
  static const bool isSupabaseEnabled = true;
  static const bool isFirebaseEnabled = false;

  /// Print current configuration
  static void debugPrint() {
    print('Backend Configuration:');
    print('  Runtime: Supabase only');
    print('  Auth: Supabase');
    print('  Users: Supabase');
    print('  Projects: Supabase');
    print('  Storage: Supabase');
    print('  Financial: Supabase');
    print('  Messaging: Supabase');
  }
}
