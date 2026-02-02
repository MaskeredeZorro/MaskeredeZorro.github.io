import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/address_search_field.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  // --- Controllers & Vars ---
  String? _origin;
  String? _destination;
  final _dateController = TextEditingController();
  final _depTimeController = TextEditingController(); // Afgang
  final _arrTimeController = TextEditingController(); // Ankomst
  final _seatsController = TextEditingController(text: "3");
  final _priceController = TextEditingController();
  final _commentController = TextEditingController();
  
  bool _isFerry = false;
  bool _detourFlex = true;
  bool _comfortGuarantee = false;
  String _luggageSize = 'Mellem';
  bool _prefMusic = true;
  bool _prefPets = false;
  bool _prefSmoking = false;

  bool _isLoading = false;

  // -- GPS Opslag --
  Future<Map<String, double>?> _getCoordinates(String address) async {
    final cleanAddress = address.split(',')[0]; 
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$cleanAddress&format=json&limit=1');
    try {
      final response = await http.get(url, headers: {'User-Agent': 'SamkorselApp/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          return {'lat': double.parse(data[0]['lat']), 'lng': double.parse(data[0]['lon'])};
        }
      }
    } catch (e) { debugPrint("GPS Fejl: $e"); }
    return null;
  }

  // -- OPRET TUR LOGIK --
  Future<void> _createRide() async {
    if (_origin == null || _destination == null || _dateController.text.isEmpty || 
        _depTimeController.text.isEmpty || _arrTimeController.text.isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Husk at udfylde rute, tider og pris!")));
      return;
    }

    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    
    // Byg dato-objekter
    final depDateTime = DateTime.parse("${_dateController.text} ${_depTimeController.text}");
    // For ankomst antager vi samme dag, medmindre tiden er mindre end afgang (så er det næste dag)
    // Dette er en simpel logik. For avanceret logik skal man vælge dato for ankomst også.
    var arrDateTime = DateTime.parse("${_dateController.text} ${_arrTimeController.text}");
    if (arrDateTime.isBefore(depDateTime)) {
      arrDateTime = arrDateTime.add(const Duration(days: 1)); // Ankomst næste dag
    }

    try {
      final profile = await Supabase.instance.client.from('profiles').select('car_details').eq('id', user!.id).single();
      final carModel = profile['car_details'] ?? "Ukendt bil";
      final originCoords = await _getCoordinates(_origin!);
      final destCoords = await _getCoordinates(_destination!);

      await Supabase.instance.client.from('rides').insert({
        'driver_id': user.id,
        'origin_city': _origin,
        'destination_city': _destination,
        'origin_location': originCoords != null ? 'POINT(${originCoords['lng']} ${originCoords['lat']})' : null,
        'destination_location': destCoords != null ? 'POINT(${destCoords['lng']} ${destCoords['lat']})' : null,
        'departure_time': depDateTime.toIso8601String(),
        'arrival_time': arrDateTime.toIso8601String(),
        'seats_available': int.parse(_seatsController.text),
        'price_dkk': int.parse(_priceController.text),
        'car_model': carModel,
        'pref_smoking': _prefSmoking,
        'comment': _commentController.text,
      });

      if (mounted) {
        Navigator.pop(context, true); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Succes! Din tur er online 🚀"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fejl: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Pickers
  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2030), initialDate: DateTime.now());
    if (picked != null) setState(() => _dateController.text = picked.toIso8601String().split('T')[0]);
  }
  Future<void> _pickTime(TextEditingController controller) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => controller.text = "${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Opret Tur"), elevation: 0, backgroundColor: Colors.white, foregroundColor: Colors.black),
      backgroundColor: Colors.white,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF005C4B)))
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // RUTE CARD
              _buildSectionHeader("Rute"),
              AddressSearchField(label: "Hvor kører du fra?", onSelected: (val) => setState(() => _origin = val)),
              const SizedBox(height: 10),
              AddressSearchField(label: "Hvor kører du til?", onSelected: (val) => setState(() => _destination = val)),
              
              const SizedBox(height: 30),
              
              // TIDSPLAN CARD
              _buildSectionHeader("Tidsplan"),
              TextField(
                controller: _dateController, readOnly: true, onTap: _pickDate, 
                decoration: _inputDeco("Dato for afgang", Icons.calendar_month)
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _depTimeController, readOnly: true, onTap: () => _pickTime(_depTimeController), decoration: _inputDeco("Afgang", Icons.schedule))),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward, color: Colors.grey),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _arrTimeController, readOnly: true, onTap: () => _pickTime(_arrTimeController), decoration: _inputDeco("Ankomst", Icons.flag))),
              ]),

              const SizedBox(height: 30),

              // ØKONOMI & PLADSER
              _buildSectionHeader("Pladser & Pris"),
              Row(children: [
                Expanded(child: TextField(controller: _seatsController, keyboardType: TextInputType.number, decoration: _inputDeco("Sæder", Icons.event_seat))),
                const SizedBox(width: 15),
                Expanded(child: TextField(controller: _priceController, keyboardType: TextInputType.number, decoration: _inputDeco("Pris (kr)", Icons.attach_money))),
              ]),

              const SizedBox(height: 30),
              const Divider(),
              
              // EKSTRA DETALJER (Switches m.m.)
              _buildSectionHeader("Detaljer"),
              _buildSwitchTile("Inkluderer færge", "Er prisen inkl. billet?", _isFerry, (v) => setState(() => _isFerry = v)),
              _buildSwitchTile("Fleksibel rute", "Max. 5 min afvigelse", _detourFlex, (v) => setState(() => _detourFlex = v)),
              _buildSwitchTile("Komfort Garanti", "Max 2 på bagsædet", _comfortGuarantee, (v) => setState(() => _comfortGuarantee = v)),
              
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: _luggageSize,
                decoration: _inputDeco("Bagageplads", Icons.luggage),
                items: ["Lille", "Mellem", "Stor"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) => setState(() => _luggageSize = val!),
              ),

              const SizedBox(height: 30),
              _buildSectionHeader("Præferencer"),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPrefToggle("Musik", Icons.music_note, _prefMusic, (v) => setState(() => _prefMusic = v)),
                  _buildPrefToggle("Dyr", Icons.pets, _prefPets, (v) => setState(() => _prefPets = v)),
                  _buildPrefToggle("Rygning", Icons.smoking_rooms, _prefSmoking, (v) => setState(() => _prefSmoking = v)),
                ],
              ),

              const SizedBox(height: 20),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: _inputDeco("Kommentar til passagerer...", Icons.chat_bubble_outline),
              ),

              const SizedBox(height: 40),
              SizedBox(
                height: 55, 
                child: ElevatedButton(
                  onPressed: _createRide, 
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005C4B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), 
                  child: const Text("OFFENTLIGGØR TUR", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                )
              ),
              const SizedBox(height: 20),
            ],
          ),
    );
  }

  // --- HJÆLPE METODER TIL UI ---
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87)),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey[600]),
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Widget _buildSwitchTile(String title, String sub, bool val, Function(bool) change) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(sub, style: const TextStyle(color: Colors.grey)),
      activeColor: const Color(0xFF005C4B),
      value: val,
      onChanged: change,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildPrefToggle(String label, IconData icon, bool value, Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: value ? const Color(0xFF005C4B).withOpacity(0.1) : Colors.grey[100],
              shape: BoxShape.circle,
              border: Border.all(color: value ? const Color(0xFF005C4B) : Colors.transparent),
            ),
            child: Icon(icon, color: value ? const Color(0xFF005C4B) : Colors.grey),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: value ? const Color(0xFF005C4B) : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}