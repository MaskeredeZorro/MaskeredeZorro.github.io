import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_stripe/flutter_stripe.dart'; // <--- VIGTIGT: Stripe import
import 'core/constants.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Start Supabase
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // 2. Start Stripe (Opsætning til betalinger)
  // Dette er din TEST-nøgle. Når du går live, skal denne skiftes til live-nøglen.
  Stripe.publishableKey = 'pk_test_51SwiSUCS6EieS5Fq5zouPoLfLf6TjaeFhXOrLOk6emC9cOVmtSdhl5KU5ovj09jTDwC1BnmxNVfwHwtdkejemQPj00cgzFXKvO';
  await Stripe.instance.applySettings();

  runApp(const SamkorselApp());
}

class SamkorselApp extends StatelessWidget {
  const SamkorselApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HoppOn', // Opdateret navn
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo, // Opdateret til at matche HoppOn temaet
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      // Tjek om bruger er logget ind
      home: Supabase.instance.client.auth.currentUser == null
          ? const AuthScreen()
          : const HomeScreen(),
    );
  }
}