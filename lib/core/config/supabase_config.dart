abstract final class SupabaseConfig {
  // These are the project URL and publishable client key. Supabase publishable
  // keys are intended for client applications; never place the service-role
  // key here.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://myetpfavvwuevdcybdes.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_a4A_3sqJNSf69ggxM_rJEg_io66r19d',
    ),
  );
}
