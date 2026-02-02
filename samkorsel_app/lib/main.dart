import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Supabase
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  runApp(const SamkorselApp());
}

class SamkorselApp extends StatelessWidget {
  const SamkorselApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Samkørsel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green, useMaterial3: true),
      // Tjek om bruger er logget ind
      home: Supabase.instance.client.auth.currentUser == null
          ? const AuthScreen()
          : const HomeScreen(),
    );
  }
}
