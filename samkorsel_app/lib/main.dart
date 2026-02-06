import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/constants.dart';
import 'screens/home_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/verification_screen.dart'; // Rettet sti
import 'screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('da_DK', null);

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
      locale: const Locale('da', 'DK'),
      theme: ThemeData(
        primaryColor: const Color(0xFF0F172A),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
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
      home: const InitialRedirect(),
    );
  }
}

class InitialRedirect extends StatelessWidget {
  const InitialRedirect({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    // 1. Hvis ikke logget ind -> Welcome Screen
    if (session == null) {
      return const WelcomeScreen();
    }

    // 2. Hvis logget ind, tjek verifikationsstatus
    return FutureBuilder<String>(
      future: _checkUserStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final String target = snapshot.data ?? 'welcome';

        switch (target) {
          case 'verify':
            // Fjernet 'const' her da phoneNumber er en variabel (selvom den er tom her)
            // Ret til dette (hent email fra current user):
            final user = Supabase.instance.client.auth.currentUser;
            return VerificationScreen(
              phoneNumber: "",
              email: user?.email ?? "", // <--- TILFØJ DETTE
            );
          case 'onboarding':
            return const OnboardingScreen();
          case 'home':
            return const HomeScreen();
          default:
            return const WelcomeScreen();
        }
      },
    );
  }

  Future<String> _checkUserStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'welcome';

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('phone_verified, full_name')
          .eq('id', user.id)
          .maybeSingle();

      // Hvis profilen slet ikke findes endnu (midt i oprettelse)
      if (profile == null) return 'onboarding';

      // Tjek SMS verifikation - kun hvis de er midt i oprettelsesflowet.
      // Eksisterende brugere sendes videre hvis de allerede har et navn.
      if (profile['phone_verified'] == false) {
        // Tjek om det er en helt ny bruger uden mail-bekræftelse endnu
        if (user.emailConfirmedAt == null) return 'verify';
        return 'verify';
      }

      // Tjek om navn mangler (Onboarding)
      if (profile['full_name'] == null ||
          profile['full_name'].toString().trim().isEmpty) {
        return 'onboarding';
      }

      return 'home';
    } catch (e) {
      // Ved fejl i database-opslag sender vi dem til home hvis de har en session
      return 'home';
    }
  }
}
