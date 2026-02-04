import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'core/constants.dart';
import 'screens/home_screen.dart';
import 'screens/auth/welcome_screen.dart'; // <--- NY IMPORT

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  Stripe.publishableKey =
      'pk_live_51SxARZEva3C2iRHuROjwB4fDAvUrCibEKXeoNA8VvWzZf7QwpCnUylfwXvBiB54nS2ptotVjp8t3idyKrXWi8JiX00Tp3wlQ4I';
  await Stripe.instance.applySettings();

  runApp(const SamkorselApp());
}

class SamkorselApp extends StatelessWidget {
  const SamkorselApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HoppOn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0F172A), // Slate
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo
          primary: const Color(0xFF0F172A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
      // Tjek login status
      home: Supabase.instance.client.auth.currentUser == null
          ? const WelcomeScreen()
          : const HomeScreen(),
    );
  }
}
