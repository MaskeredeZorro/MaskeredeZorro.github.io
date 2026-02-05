import 'dart:math'; // Til at generere OTP koden
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import '../screens/verification_screen.dart'; // Importér din nye skærm
import '../services/sms_service.dart'; // Importér din SMS service

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController(); // NY: Til mobilnummer
  bool _isLoading = false;
  final _smsService = SmsService();

  // Tjekker profilstatus og verifikation før viderestilling
  Future<void> _checkStatusAndRedirect() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone_verified')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      // 1. Tjek om SMS er bekræftet (Produktions-krav)
      bool isPhoneVerified = data?['phone_verified'] ?? false;
      if (!isPhoneVerified) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VerificationScreen(
              phoneNumber: _phoneController.text.trim(),
              email: _emailController.text.trim(), // Tilføj denne linje
            ),
          ),
        );
        return;
      }

      // 2. Tjek om profilnavn er udfyldt
      if (data == null ||
          data['full_name'] == null ||
          data['full_name'].toString().trim().isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      debugPrint("Fejl ved status-tjek: $e");
    }
  }

  Future<void> _authenticate({required bool isSignUp}) async {
    print("DEBUG: _authenticate kaldet. isSignUp: $isSignUp");
    setState(() => _isLoading = true);

    try {
      if (isSignUp) {
        print("DEBUG: Starter signUp hos Supabase...");
        final authResponse = await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (authResponse.user != null) {
          print("DEBUG: Bruger oprettet: ${authResponse.user!.id}");
          final String phoneNumber = _phoneController.text.trim();
          final String code = (Random().nextInt(900000) + 100000).toString();

          // 1. GEM TELEFONNUMMER
          print("DEBUG: Forsøger at opdatere profil med tlf: $phoneNumber");
          await Supabase.instance.client
              .from('profiles')
              .update({'phone_number': phoneNumber})
              .eq('id', authResponse.user!.id);

          // 2. GEM OTP-KODEN
          print("DEBUG: Forsøger at indsætte OTP kode i sms_verifications...");
          await Supabase.instance.client.from('sms_verifications').insert({
            'user_id': authResponse.user!.id,
            'code': code,
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 10))
                .toIso8601String(),
          });

          // 3. SEND SMS
          print("DEBUG: Kalder SmsService.sendVerificationCode...");
          final success = await _smsService.sendVerificationCode(
            phoneNumber,
            code,
          );

          if (mounted) {
            if (success) {
              print("DEBUG: SMS succes! Navigerer til VerificationScreen");
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  // Ret linjen til dette:
                  builder: (_) => VerificationScreen(
                    phoneNumber: phoneNumber,
                    email: _emailController.text
                        .trim(), // Tilføj email controlleren her
                  ),
                ),
              );
            } else {
              print("DEBUG: SmsService returnerede false");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Fejl ved afsendelse af SMS. Tjek nummeret."),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
      } else {
        // --- LOG IND FLOW ---
        print("DEBUG: Logger ind...");
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (mounted) {
          await _checkStatusAndRedirect();
        }
      }
    } on AuthException catch (error) {
      print("DEBUG AUTH FEJL: ${error.message}");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: Colors.red),
        );
    } catch (e) {
      print("DEBUG GENEREL FEJL: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Der skete en fejl: $e"),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          // Tilføjet så tastaturet ikke dækker alt
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 80),
              const Icon(
                Icons.directions_car,
                size: 80,
                color: Color(0xFF0F172A),
              ),
              const SizedBox(height: 20),
              const Text(
                "HoppOn 2026",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kode',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Vi viser kun telefon-feltet ved oprettelse
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobilnummer (+45)',
                  border: OutlineInputBorder(),
                  hintText: '88888888',
                ),
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        ElevatedButton(
                          onPressed: () => _authenticate(isSignUp: false),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Log Ind'),
                        ),
                        TextButton(
                          onPressed: () => _authenticate(isSignUp: true),
                          child: const Text('Opret Konto'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
