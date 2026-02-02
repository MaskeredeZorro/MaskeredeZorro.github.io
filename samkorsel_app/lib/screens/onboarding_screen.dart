import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  
  bool _isDriver = false;
  bool _isLoading = false;
  String? _avatarUrl;
  String? _carDetails; // Her gemmer vi nu JSON-pakken med al bil-info

  // -- 1. UPLOAD BILLEDE --
  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final imageFile = await picker.pickImage(source: ImageSource.gallery);
    if (imageFile == null) return;

    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final fileExt = imageFile.path.split('.').last;
      final fileName = '$userId-onboard.${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      
      final bytes = await imageFile.readAsBytes();
      await Supabase.instance.client.storage.from('avatars').uploadBinary(
        fileName, bytes, fileOptions: FileOptions(contentType: imageFile.mimeType)
      );

      final imageUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
      setState(() => _avatarUrl = imageUrl);
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fejl ved upload: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // -- 2. SLÅ NUMMERPLADE OP (GEM ALT INFO) --
  Future<void> _lookupPlate() async {
    final plate = _plateController.text.replaceAll(' ', '');
    if (plate.length < 2) return;

    setState(() => _isLoading = true);
    
    // Din API nøgle
    const apiKey = '7dzgmx0qvnjtwwza0bkpu307k47yrjyq'; 
    final url = Uri.parse('https://v1.motorapi.dk/vehicles/$plate');

    try {
      final response = await http.get(url, headers: {'X-Auth-Token': apiKey});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Vi henter dataene fra API'et
        final make = data['make'] ?? 'Bil';
        final model = data['model'] ?? '';
        final variant = data['variant'] ?? ''; // Fx "3.0 TDI"
        final year = data['model_year'] ?? '';
        final color = data['color'] ?? '';
        final regNr = data['registration_number'] ?? plate;

        setState(() {
          // Vi pakker det hele sammen i en Map (JSON struktur)
          Map<String, String> carInfo = {
            'make': '$make $model',       // Det der vises med stort (fx "Audi A6")
            'details': '$year • $color • $regNr' // Det der vises under (fx "2015 • Sort • AT21931")
          };
          
          // Vi gemmer det som tekst i databasen
          _carDetails = json.encode(carInfo);
        });
        
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fandt din $make $model! 🚗"), backgroundColor: Colors.green));
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kunne ikke finde bil. Tjek nummerpladen.")));
      }
    } catch (e) {
      debugPrint("API Fejl: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // -- 3. GEM OG FORTSÆT --
  Future<void> _saveAndContinue() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Skriv venligst dit navn")));
      return;
    }

    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      await Supabase.instance.client.from('profiles').update({
        'full_name': _nameController.text,
        'avatar_url': _avatarUrl,
        'license_plate': _isDriver ? _plateController.text : null,
        'car_details': _isDriver ? _carDetails : null, // Her gemmes JSON pakken nu
      }).eq('id', userId);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()), 
          (route) => false
        );
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fejl: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Velkommen! 👋"), centerTitle: true),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(25),
            children: [
              const Text("Lad os få din profil på plads, før du kører.", 
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
              
              const SizedBox(height: 30),

              // BILLEDE
              Center(
                child: GestureDetector(
                  onTap: _uploadImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                    child: _avatarUrl == null ? const Icon(Icons.add_a_photo, size: 40, color: Colors.grey) : null,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(child: Text("Tilføj profilbillede", style: TextStyle(color: Colors.blue))),

              const SizedBox(height: 30),

              // NAVN
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Fulde navn",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 30),

              // CHAUFFØR SWITCH
              SwitchListTile(
                title: const Text("Jeg vil tilbyde lift (Chauffør)"),
                value: _isDriver,
                onChanged: (val) => setState(() => _isDriver = val),
                activeColor: Colors.green,
              ),

              // NUMMERPLADE FELT (Kun hvis chauffør)
              if (_isDriver) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _plateController,
                        decoration: InputDecoration(
                          labelText: "Nummerplade (fx AB 12 345)",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.directions_car),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _lookupPlate,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.grey[800],
                        foregroundColor: Colors.white
                      ),
                      child: const Icon(Icons.search),
                    )
                  ],
                ),
                
                // VIS BIL INFO (Hvis fundet)
                if (_carDetails != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                // Vi pakker JSON ud for at vise det pænt her i onboarding også
                                try {
                                  final map = json.decode(_carDetails!);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(map['make'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text(map['details'], style: const TextStyle(color: Colors.black54)),
                                    ],
                                  );
                                } catch (e) {
                                  return const Text("Bil data gemt");
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
              ],

              const SizedBox(height: 50),

              // GEM KNAP
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  onPressed: _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: const Text("GEM OG FORTSÆT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
    );
  }
}