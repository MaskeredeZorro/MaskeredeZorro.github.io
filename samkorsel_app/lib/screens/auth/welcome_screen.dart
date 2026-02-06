import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // --- TOP LOGO / TEXT ---
              Column(
                children: [
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo.png',
                        width: 140,
                        height: 140,
                        fit: BoxFit
                            .cover, // Tvinger firkanten til at fylde cirklen ud
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Column(
                    children: [
                      const Text(
                        "HoppOn",
                        style: TextStyle(
                          fontSize: 42, // Gør den stor og dominerende
                          fontWeight:
                              FontWeight.w800, // Fed, men ikke "klumpet"
                          color: Color(0xFF0F172A),
                          letterSpacing:
                              -2.0, // Det vigtigste Apple-trick: Træk bogstaverne tæt sammen
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ), // Meget lille afstand mellem navn og slogan
                      const Text(
                        "Kør sammen. Rejs bedre.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight:
                              FontWeight.w500, // Medium vægt giver kvalitet
                          color: Color(
                            0xFF64748B,
                          ), // Slate 500 – en mere moderne grå end standard grey[600]
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(
                        height: 24,
                      ), // Mere luft ned til næste element/knap
                    ],
                  ),
                ],
              ),

              // --- BUND KNAPPER ---
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Log Ind",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpScreen(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFF0F172A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Opret Konto",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
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
