import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

// Importér din verification screen
import '/screens/verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controllers
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Chauffør Del
  bool _isDriver = false;
  final _plateCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _isFetchingCar = false;

  // --- 1. HENT BIL FRA NUMMERPLADE ---
  Future<void> _fetchCar() async {
    String plate = _plateCtrl.text.replaceAll(' ', '').trim();
    if (plate.length < 2) return;
    setState(() => _isFetchingCar = true);

    try {
      const String apiKey = "7dzgmx0qvnjtwwza0bkpu307k47yrjyq";
      final url = Uri.parse("https://v1.motorapi.dk/vehicles/$plate");
      final response = await http.get(url, headers: {'X-Auth-Token': apiKey});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _makeCtrl.text = (data['make'] ?? "").toString();
          _modelCtrl.text = (data['model'] ?? "").toString();
          _yearCtrl.text = (data['model_year'] ?? "").toString();
          _colorCtrl.text = (data['color'] ?? "").toString();
          if (data['registration_number'] != null) {
            _plateCtrl.text = data['registration_number'];
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Bil fundet! ✅"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw "Bil ikke fundet";
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Kunne ikke finde bil")));
    } finally {
      setState(() => _isFetchingCar = false);
    }
  }

  // --- 2. OPRET BRUGER & NAVIGER ---
  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isDriver && _makeCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Husk at hente din bil via nummerpladen")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // FORBERED DATA
      dynamic carJson;
      if (_isDriver) {
        carJson = {
          'make': _makeCtrl.text,
          'model': _modelCtrl.text,
          'year': _yearCtrl.text,
          'color': _colorCtrl.text,
          'plate': _plateCtrl.text,
          'details':
              "${_yearCtrl.text} • ${_colorCtrl.text} • ${_plateCtrl.text}",
          'display_name': "${_makeCtrl.text} ${_modelCtrl.text}",
        };
      }

      // OPRET I AUTH
      await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        emailRedirectTo: 'io.supabase.flutterquickstart://login-callback',
        data: {
          'full_name': _nameCtrl.text.trim(),
          'phone_number': _phoneCtrl.text.trim(),
          'is_driver': _isDriver,
          'license_plate': _isDriver ? _plateCtrl.text : null,
          'car_details': carJson,
        },
      );

      // NAVIGER STRAKS
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => VerificationScreen(
              phoneNumber: _phoneCtrl.text.trim(),
              email: _emailCtrl.text.trim(),
              password: _passCtrl.text
                  .trim(), // <--- VIGTIGT: Vi sender koden med!
            ),
          ),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint("Fejl: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Der skete en fejl"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Opret Konto")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Lad os få dig i gang 🚀",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Fulde navn",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v!.isEmpty ? "Påkrævet" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) =>
                    v!.isEmpty || !v.contains('@') ? "Ugyldig email" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Telefonnummer",
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: (v) => v!.length < 8 ? "Ugyldigt nummer" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Adgangskode",
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => v!.length < 6 ? "Mindst 6 tegn" : null,
              ),

              const SizedBox(height: 30),
              const Divider(),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  "Jeg vil gerne være chauffør",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text("Tilføj din bil med det samme"),
                value: _isDriver,
                activeColor: const Color(0xFF6366F1),
                onChanged: (val) => setState(() => _isDriver = val),
              ),

              if (_isDriver) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _plateCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: "AB 12 345",
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _isFetchingCar ? null : _fetchCar,
                            child: _isFetchingCar
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ],
                      ),
                      if (_makeCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          "✅ ${_makeCtrl.text} ${_modelCtrl.text}",
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Opret Konto"),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
