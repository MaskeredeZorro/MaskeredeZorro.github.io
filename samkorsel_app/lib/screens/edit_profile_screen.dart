import 'dart:convert';
import 'dart:math'; // Til SMS kode generering
import 'dart:io'; // VIGTIGT: Til filhåndtering (File)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// HUSK AT TJEKKE AT STIERNE PASSER TIL DINE FILER
import '../../services/sms_service.dart';
import '../screens/verification_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isFetchingCar = false;

  // --- CONTROLLERS ---
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();

  // --- NYT: KØN STYRING ---
  String? _selectedGender;
  final List<String> _genderOptions = ['Mand', 'Kvinde', 'Andet'];

  // Variabel til at huske det oprindelige nummer for at tjekke for ændringer
  String _originalPhone = "";

  // Bil info
  bool _isDriver = false;
  final _plateController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colorController = TextEditingController();

  String _email = "";
  String _avatarUrl = "";

  final Color _primaryColor = const Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      setState(() => _email = user.email ?? "");

      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      setState(() {
        _nameController.text = (data['full_name'] ?? "").toString();

        // Hent telefonnummer
        String phoneFromDb = (data['phone_number'] ?? "").toString();
        _phoneController.text = phoneFromDb;
        _originalPhone = phoneFromDb;

        // Hent bio og avatar
        _bioController.text = (data['bio'] ?? "").toString();
        _avatarUrl = (data['avatar_url'] ?? "").toString();

        // --- NYT: HENT KØN ---
        _selectedGender = data['gender'];
        if (_selectedGender != null &&
            !_genderOptions.contains(_selectedGender)) {
          // Fallback hvis kønnet i databasen er noget mærkeligt
          _selectedGender = null;
        }

        // Tjek om chauffør
        bool isDriverFlag = data['is_driver'] as bool? ?? false;
        bool hasCarDetails = data['car_details'] != null;
        _isDriver = isDriverFlag || hasCarDetails;

        if (data['car_details'] != null) {
          dynamic carData = data['car_details'];

          if (carData is String) {
            try {
              carData = json.decode(carData);
            } catch (_) {
              carData = {};
            }
          }

          if (carData is Map) {
            if (carData['plate'] != null || carData['make'] != null) {
              _plateController.text = (carData['plate'] ?? "").toString();
              _makeController.text = (carData['make'] ?? "").toString();
              _modelController.text = (carData['model'] ?? "").toString();
              _yearController.text = (carData['year'] ?? "").toString();
              _colorController.text = (carData['color'] ?? "").toString();
            } else if (carData['details'] != null) {
              // Gammel data struktur fallback
              String fullMake = (carData['make'] ?? "").toString();
              String details = (carData['details'] ?? "").toString();

              List<String> makeParts = fullMake.split(' ');
              if (makeParts.isNotEmpty) {
                _makeController.text = makeParts[0];
                if (makeParts.length > 1) {
                  _modelController.text = fullMake
                      .substring(makeParts[0].length)
                      .trim();
                }
              }

              List<String> detailParts = details.split(' • ');
              if (detailParts.length >= 3) {
                _yearController.text = detailParts[0];
                _colorController.text = detailParts[1];
                _plateController.text = detailParts[2];
              }
            }
          }
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fejl i load: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UPLOAD BILLEDE ---
  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final imageFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
    );
    if (imageFile == null) return;

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final fileExt = imageFile.path.split('.').last;
      final fileName =
          '$userId-profile-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final file = File(imageFile.path); // Konverter til File objekt

      // Upload med File objekt (mere stabilt på mobil)
      await Supabase.instance.client.storage
          .from('avatars')
          .upload(
            fileName,
            file,
          ); // uploadBinary kan drille, .upload er bedre til File

      final imageUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      setState(() {
        _avatarUrl = imageUrl;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Billede uploadet! Husk at gemme."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("Upload fejl: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Kunne ikke uploade billede: $e")));
      setState(() => _isLoading = false);
    }
  }

  // --- MOTOR API OPSLAG ---
  Future<void> _fetchCarFromApi() async {
    String plate = _plateController.text.replaceAll(' ', '').trim();
    if (plate.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Indtast nummerplade først")),
      );
      return;
    }

    setState(() => _isFetchingCar = true);

    try {
      const String apiKey = "7dzgmx0qvnjtwwza0bkpu307k47yrjyq";
      final url = Uri.parse("https://v1.motorapi.dk/vehicles/$plate");

      final response = await http.get(url, headers: {'X-Auth-Token': apiKey});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          _makeController.text = (data['make'] ?? "").toString();
          _modelController.text = (data['model'] ?? "").toString();
          _yearController.text = (data['model_year'] ?? "").toString();
          _colorController.text = (data['color'] ?? "").toString();
          if (data['registration_number'] != null) {
            _plateController.text = data['registration_number'];
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Bil fundet!"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw "Kunne ikke finde bil (Status: ${response.statusCode})";
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Fejl ved opslag: $e")));
    } finally {
      setState(() => _isFetchingCar = false);
    }
  }

  // --- OPDATERING AF PROFIL ---
  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    // Tjek om køn er valgt
    if (_selectedGender == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Vælg venligst køn")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 1. Håndter Bil-data
      dynamic carJson;
      if (_isDriver) {
        carJson = {
          'make': _makeController.text,
          'model': _modelController.text,
          'year': _yearController.text,
          'color': _colorController.text,
          'plate': _plateController.text,
          'details':
              "${_yearController.text} • ${_colorController.text} • ${_plateController.text}",
          'display_name': "${_makeController.text} ${_modelController.text}",
        };
      } else {
        carJson = null;
      }

      // 2. Håndter Telefon-logik
      // Vi henter kun teksten, hvis man er chauffør. Ellers er det null.
      final String? newPhoneRaw = _isDriver
          ? _phoneController.text.trim()
          : null;

      // Vi skal kun verificere, hvis:
      // A) Man er chauffør
      // B) Der står noget i feltet
      // C) Det er forskelligt fra det, der står i databasen (_originalPhone)
      final bool hasPhoneChanged =
          _isDriver &&
          newPhoneRaw != null &&
          newPhoneRaw.isNotEmpty &&
          newPhoneRaw != _originalPhone;

      // 3. Forbered data til Supabase
      final Map<String, dynamic> updates = {
        'full_name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'avatar_url': _avatarUrl,
        'gender': _selectedGender,
        'is_driver': _isDriver,
        'car_details': carJson,
        'license_plate': _isDriver ? _plateController.text.trim() : null,
        'updated_at': DateTime.now().toIso8601String(),

        // LOGIK FOR TELEFON I DATABASEN:
        // Hvis _isDriver er true: Vi gemmer 'newPhoneRaw' (medmindre det ændret, se nedenfor).
        // Hvis _isDriver er false: Vi gemmer 'null' (sletter nummeret fra DB).
        'phone_number': _isDriver ? newPhoneRaw : null,
      };

      // VIGTIGT: Hvis nummeret er ændret, må vi IKKE gemme det endnu.
      // Vi skal vente til SMS-koden er indtastet.
      if (hasPhoneChanged) {
        updates.remove('phone_number');
      }

      // 4. Send opdatering til Supabase
      await Supabase.instance.client
          .from('profiles')
          .update(updates)
          .eq('id', user.id);

      // 5. Håndter SMS Verificering (hvis nummeret er nyt og man er chauffør)
      if (hasPhoneChanged) {
        final String code = (Random().nextInt(900000) + 100000).toString();

        await Supabase.instance.client.from('sms_verifications').insert({
          'user_id': user.id,
          'code': code,
          'expires_at': DateTime.now()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
        });

        // Send SMS (Husk at newPhoneRaw ikke er null her pga. hasPhoneChanged tjekket)
        final smsService = SmsService();
        await smsService.sendVerificationCode(newPhoneRaw!, code);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profil gemt! Bekræft venligst dit nye nummer."),
            ),
          );

          // Naviger til verificering
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  VerificationScreen(phoneNumber: newPhoneRaw, email: _email),
            ),
          );
        }
      } else {
        // Ingen ændring i telefon (eller brugeren er ikke længere chauffør)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profil opdateret!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Fejl ved opdatering: $e"),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Rediger Profil",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 1. PROFIL BILLEDE ---
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: _avatarUrl.isNotEmpty
                                ? NetworkImage(_avatarUrl)
                                : null,
                            child: _avatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: _primaryColor,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.camera_alt,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                onPressed: _uploadImage,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                    const Text(
                      "Personlige oplysninger",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),

                    _buildTextField(
                      "Fulde navn",
                      _nameController,
                      Icons.person,
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      initialValue: _email,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: "Email (Login)",
                        prefixIcon: const Icon(Icons.email, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[200],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    const SizedBox(height: 15),

                    // --- NYT: KØN DROPDOWN ---
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      decoration: InputDecoration(
                        labelText: "Køn",
                        prefixIcon: const Icon(Icons.wc, color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: _genderOptions.map((String gender) {
                        return DropdownMenuItem<String>(
                          value: gender,
                          child: Text(gender),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedGender = newValue;
                        });
                      },
                      validator: (v) => v == null ? "Vælg venligst køn" : null,
                    ),

                    const SizedBox(height: 30),
                    const Text(
                      "Om dig",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: _bioController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: "Fortæl lidt om dig selv...",
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 20),

                    // --- BIL SEKTION ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Er du chauffør?",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Switch(
                          value: _isDriver,
                          onChanged: (val) => setState(() => _isDriver = val),
                          activeColor: const Color(0xFF6366F1),
                        ),
                      ],
                    ),
                    const Text(
                      "Slå til for at tilføje din bil og tilbyde lift.",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),

                    if (_isDriver) ...[
                      // INDSÆT DETTE:
                      const SizedBox(height: 20),

                      // --- TELEFONNUMMER (Flyttet herned) ---
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType
                            .number, // Ændret til number for at fremtvinge tal-tastatur
                        maxLength: 8, // Dette stopper indtastning efter 8 tegn
                        decoration: InputDecoration(
                          counterText:
                              "", // Dette skjuler den lille "0/8" tæller nede i hjørnet
                          labelText: "Telefonnummer",
                          prefixIcon: const Icon(
                            Icons.phone_android,
                            color: Colors.grey,
                          ),
                          helperText: "Nødvendigt for at tilbyde ture",
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        // Validerer kun hvis _isDriver er true
                        validator: (v) {
                          if (_isDriver && (v == null || v.length < 8)) {
                            return "Ugyldigt nummer";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              "Nummerplade",
                              _plateController,
                              Icons.confirmation_number,
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 55,
                            child: ElevatedButton.icon(
                              onPressed: _isFetchingCar
                                  ? null
                                  : _fetchCarFromApi,
                              icon: _isFetchingCar
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.search, size: 18),
                              label: const Text("Hent"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              "Mærke (fx Audi)",
                              _makeController,
                              Icons.directions_car,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildTextField(
                              "Model (fx Q3)",
                              _modelController,
                              Icons.category,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              "Årgang",
                              _yearController,
                              Icons.calendar_today,
                              isNumber: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildTextField(
                              "Farve",
                              _colorController,
                              Icons.color_lens,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 40),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "GEM ÆNDRINGER",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool isNumber = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      textCapitalization: textCapitalization,
      validator: (val) {
        if (_isDriver &&
            val != null &&
            val.isEmpty &&
            !label.contains("Telefon"))
          return "Påkrævet";
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
