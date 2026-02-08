import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
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

  // Obligatoriske felter
  File? _imageFile;
  String? _selectedGender;
  final List<String> _genderOptions = ['Mand', 'Kvinde', 'Andet'];

  // Chauffør Del
  bool _isDriver = false;
  final _plateCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _isFetchingCar = false;

  // --- FUNKTION: Vælg Billede ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
    );

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Bil fundet! ✅"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw "Bil ikke fundet";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Kunne ikke finde bil")));
      }
    } finally {
      setState(() => _isFetchingCar = false);
    }
  }

  // --- 2. OPRET BRUGER & NAVIGER ---
  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Du mangler et profilbillede 📸"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Du skal vælge et køn 🚻"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Tjek kun bil hvis man er chauffør
    if (_isDriver && _makeCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Du skal hente dine biloplysninger via nummerpladen 🚗",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;

      // TRIN A: Upload Billede
      final fileExt = _imageFile!.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = '/$fileName';

      await client.storage.from('avatars').upload(filePath, _imageFile!);

      final avatarUrl = client.storage.from('avatars').getPublicUrl(filePath);

      // TRIN B: Forbered Bil Data
      String? carDetailsString;
      if (_isDriver) {
        final carJson = {
          'make': _makeCtrl.text,
          'model': _modelCtrl.text,
          'year': _yearCtrl.text,
          'color': _colorCtrl.text,
          'plate': _plateCtrl.text,
          'details':
              "${_yearCtrl.text} • ${_colorCtrl.text} • ${_plateCtrl.text}",
          'display_name': "${_makeCtrl.text} ${_modelCtrl.text}",
        };
        carDetailsString = jsonEncode(carJson);
      }

      final String? finalPhone = _isDriver ? _phoneCtrl.text.trim() : null;

      // TRIN C: Opret Bruger
      // INDSÆT DETTE I STEDET:
      final AuthResponse res = await client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        emailRedirectTo: 'io.supabase.flutterquickstart://login-callback',
        data: {
          'full_name': _nameCtrl.text.trim(),
          'avatar_url': avatarUrl,
          'gender': _selectedGender,
        },
      );

      final userId = res.user?.id;

      // TRIN D: TVING OPDATERING AF PROFILES TABELLEN
      if (userId != null) {
        await Future.delayed(const Duration(milliseconds: 500));
        await client
            .from('profiles')
            .update({
              'full_name': _nameCtrl.text.trim(),
              'gender': _selectedGender,
              'avatar_url': avatarUrl,
              'is_driver': _isDriver,
              // Vi sætter kun phone_number hvis de er chauffør, men phone_verified er false indtil SMS er klaret
              'phone_number': finalPhone,
              'license_plate': _isDriver ? _plateCtrl.text : null,
              'car_details': carDetailsString,
            })
            .eq('id', userId);
      }

      // TRIN E: Naviger til Verificering
      if (mounted) {
        // Vi sender dem altid til verificering, men med info om de skal være driver
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => VerificationScreen(
              phoneNumber: finalPhone ?? "",
              email: _emailCtrl.text.trim(),
              password: _passCtrl.text.trim(),
              isBecomingDriver: _isDriver, // VIGTIGT: Sender status videre
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
          SnackBar(content: Text("Fejl: $e"), backgroundColor: Colors.red),
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

              // --- 1. PROFILBILLEDE ---
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: _imageFile != null
                            ? FileImage(_imageFile!)
                            : null,
                        child: _imageFile == null
                            ? const Icon(
                                Icons.camera_alt,
                                size: 40,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _imageFile == null
                            ? "Tilføj profilbillede *"
                            : "Ændre billede",
                        style: TextStyle(
                          color: _imageFile == null ? Colors.red : Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // --- NAVN ---
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Fulde navn *",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v?.isEmpty ?? true) ? "Påkrævet" : null,
              ),
              const SizedBox(height: 15),

              // --- KØN ---
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(
                  labelText: "Køn *",
                  prefixIcon: Icon(Icons.wc),
                ),
                items: _genderOptions.map((String gender) {
                  return DropdownMenuItem<String>(
                    value: gender,
                    child: Text(gender),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedGender = val),
                validator: (v) => v == null ? "Vælg venligst køn" : null,
              ),
              const SizedBox(height: 15),

              // --- EMAIL ---
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Email *",
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) => (v?.isEmpty ?? true) || !v!.contains('@')
                    ? "Ugyldig email"
                    : null,
              ),
              const SizedBox(height: 15),

              // --- PASSWORD ---
              TextFormField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Adgangskode *",
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => (v?.length ?? 0) < 6 ? "Mindst 6 tegn" : null,
              ),

              const SizedBox(height: 30),
              const Divider(),

              // --- DRIVER SWITCH ---
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  "Jeg vil gerne være chauffør",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text("Kræver telefonnummer og bil"),
                value: _isDriver,
                activeColor: const Color(0xFF6366F1),
                onChanged: (val) => setState(() => _isDriver = val),
              ),

              // --- VIS KUN HVIS CHAUFFØR ---
              if (_isDriver) ...[
                const SizedBox(height: 15),

                // --- TELEFONNUMMER ---
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Telefonnummer *",
                    prefixIcon: Icon(Icons.phone_android),
                    helperText: "Passagerer skal kunne kontakte dig",
                  ),
                  validator: (v) {
                    if (!_isDriver) return null;
                    return (v == null || v.length < 8)
                        ? "Ugyldigt nummer"
                        : null;
                  },
                ),
                const SizedBox(height: 15),

                // --- BIL BOKS ---
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
                                labelText: "Nummerplade *",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _isFetchingCar ? null : _fetchCar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              padding: const EdgeInsets.all(16),
                            ),
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

              // --- OPRET KNAP ---
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
