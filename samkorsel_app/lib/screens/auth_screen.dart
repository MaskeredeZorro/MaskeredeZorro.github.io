import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart'; // <--- HUSK DENNE IMPORT

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // -- NY FUNKTION: TJEK OM PROFIL ER UDFYLDT --
  Future<void> _checkProfileAndRedirect() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    
    try {
      // Hent kun 'full_name' for at spare data
      final data = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle(); // Brug maybeSingle så den ikke crasher hvis profilen mangler

      if (!mounted) return;

      // Hvis data er null ELLER navnet er tomt/null -> Gå til Onboarding
      if (data == null || data['full_name'] == null || data['full_name'].toString().trim().isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen())
        );
      } else {
        // Hvis navn findes -> Gå til Home
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen())
        );
      }
    } catch (e) {
      debugPrint("Fejl ved profiltjek: $e");
      // Hvis noget går helt galt, send dem til Onboarding for en sikkerheds skyld
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen())
        );
      }
    }
  }

  Future<void> _authenticate({required bool isSignUp}) async {
    setState(() => _isLoading = true);
    try {
      if (isSignUp) {
        // Opret ny bruger
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          // BEMÆRK: Vi har fjernet 'data: full_name', så den starter som tom!
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konto oprettet! Log ind nu.')));
      } else {
        // Log ind
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        // BEMÆRK: I stedet for at gå direkte til Home, tjekker vi profilen først
        if (mounted) {
          await _checkProfileAndRedirect();
        }
      }
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message), backgroundColor: Colors.red));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fejl opstod'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car, size: 80, color: Colors.green),
            const SizedBox(height: 20),
            const Text("Samkørsel 2026", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Kode', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            _isLoading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => _authenticate(isSignUp: false),
                        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text('Log Ind'),
                      ),
                      TextButton(onPressed: () => _authenticate(isSignUp: true), child: const Text('Opret Konto')),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}