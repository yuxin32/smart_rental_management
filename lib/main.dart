import 'package:flutter/material.dart';

import 'core/auth/app_auth_gate.dart';
import 'core/config/integrated_backend.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The client uses only the Supabase project URL and publishable key. Login
  // credentials are never stored in the Flutter application.
  try {
    await IntegratedBackend.initialize();
  } catch (_) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [const Text('Unable to connect to Smart Rental Management.'),
        TextButton(onPressed: main, child: const Text('Retry connection'))],
    )))));
    return;
  }

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
      routes: {'/login': (_) => const AppAuthGate()},
    );
  }
}
