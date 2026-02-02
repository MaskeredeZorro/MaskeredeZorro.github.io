import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _isMitIdVerified = false;
  String? _avatarUrl;
  
  // Hent brugerens nuværende data
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client.from('profiles').select().eq('id', userId).single();
    
    setState(() {
      _nameController.text = data['full_name'] ?? '';
      _avatarUrl = data['avatar_url'];
      _isMitIdVerified = data['is_verified_mitid'] ?? false;
      _isLoading = false;
    });
  }

  // Simuler MitID Flow
  Future<void> _verifyMitID() async {
    // Her ville vi normalt åbne en WebView til Nets/MitID
    // Vi faker det med en lille "ventetid"
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2)); // Fake ventetid
    
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client.from('profiles').update({
      'is_verified_mitid': true
    }).eq('id', userId);

    setState(() {
      _isMitIdVerified = true;
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("MitID Verificeret Succesfuldt!"), backgroundColor: Colors.blue));
    }
  }

  // Upload billede
  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final imageFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (imageFile == null) return;

    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final fileExt = imageFile.path.split('.').last;
    final fileName = '$userId.${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    
    try {
      // 1. Upload til Supabase Storage
      final bytes = await imageFile.readAsBytes(); // Læs filen som bytes (virker på web og mobil)
      await Supabase.instance.client.storage.from('avatars').uploadBinary(
        fileName,
        bytes,
        fileOptions: FileOptions(contentType: imageFile.mimeType),
      );

      // 2. Få den offentlige URL
      final imageUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);

      // 3. Gem URL i profilen
      await Supabase.instance.client.from('profiles').update({
        'avatar_url': imageUrl
      }).eq('id', userId);

      setState(() => _avatarUrl = imageUrl);

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload fejl: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    
    await Supabase.instance.client.from('profiles').update({
      'full_name': _nameController.text,
    }).eq('id', userId);

    if (mounted) {
      Navigator.pop(context, true); // Gå tilbage og sig "Vi har opdateret!"
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rediger Profil")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 1. PROFIL BILLEDE
              Center(
                child: GestureDetector(
                  onTap: _uploadImage,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                    child: _avatarUrl == null ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey) : null,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(child: Text("Tryk for at ændre billede", style: TextStyle(color: Colors.grey))),
              
              const SizedBox(height: 30),

              // 2. NAVN FELT
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Fulde navn",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 30),

              // 3. MITID STATUS
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: _isMitIdVerified ? Colors.blue.shade50 : Colors.grey.shade50,
                  border: Border.all(color: _isMitIdVerified ? Colors.blue : Colors.grey),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Image.network("https://www.mitid.dk/static/mitid-logo.svg", width: 40, errorBuilder: (c,e,s) => const Icon(Icons.security)),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isMitIdVerified ? "Identitet bekræftet" : "Ikke bekræftet", 
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(_isMitIdVerified ? "Du er verificeret med MitID" : "Bekræft din identitet for at skabe tillid."),
                        ],
                      ),
                    ),
                    if (!_isMitIdVerified)
                      TextButton(onPressed: _verifyMitID, child: const Text("BEKRÆFT"))
                    else
                      const Icon(Icons.check_circle, color: Colors.blue),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 4. GEM KNAP
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                  child: const Text("GEM PROFIL"),
                ),
              )
            ],
          ),
    );
  }
}