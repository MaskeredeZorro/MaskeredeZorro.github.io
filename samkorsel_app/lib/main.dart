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
  Stripe.publishableKey =
      'pk_live_51SwiSBFmUbPR9jrfajSYkLkqqtvJCjZi6eDpqbnoK4PKuW4sYOB3iWKKQiPEArVigFGv4iL1XKkGb3bjbgYj1zsO005TsJBugS';
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
