import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/app_auth_gate.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The client uses only the Supabase project URL and publishable key. Login
  // credentials are never stored in the Flutter application.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: true),
  );

  runApp(const SmartRentalApp());
}

class SmartRentalApp extends StatelessWidget {
  const SmartRentalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Rental Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppAuthGate(),
      routes: {'/login': (_) => const LoginPage()},
    );
  }
}
