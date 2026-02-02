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
  // Standard felter
  String? _origin;
  String? _destination;
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _seatsController = TextEditingController(text: "3");
  final _priceController = TextEditingController();
  final _carController = TextEditingController();
  
  // -- NYE FELTER --
  bool _isFerry = false;
  bool _detourFlex = true; // Max 5 min afvigelse
  bool _comfortGuarantee = false; // Max 2 på bagsæde
  String _luggageSize = 'Mellem'; // Lille, Mellem, Stor
  
  // Præferencer
  bool _prefMusic = true;
  bool _prefPets = false;
  bool _prefSmoking = false;

  final _commentController = TextEditingController();
  bool _isLoading = false;

  // -- MAGI: GPS Opslag --
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

  Future<void> _createRide() async {
    if (_origin == null || _destination == null || _dateController.text.isEmpty || 
        _timeController.text.isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Udfyld venligst by, dato, tid og pris.")));
      return;
    }

    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    final fullDate = DateTime.parse("${_dateController.text} ${_timeController.text}");

    try {
      final originCoords = await _getCoordinates(_origin!);
      final destCoords = await _getCoordinates(_destination!);

      await Supabase.instance.client.from('rides').insert({
        'driver_id': user!.id,
        'origin_city': _origin,
        'destination_city': _destination,
        'origin_location': originCoords != null ? 'POINT(${originCoords['lng']} ${originCoords['lat']})' : null,
        'destination_location': destCoords != null ? 'POINT(${destCoords['lng']} ${destCoords['lat']})' : null,
        'departure_time': fullDate.toIso8601String(),
        'seats_available': int.parse(_seatsController.text),
        'price_dkk': int.parse(_priceController.text),
        'car_model': _carController.text,
        'status': 'active',
        // -- NYE DATA --
        'is_ferry': _isFerry,
        'detour_flex': _detourFlex,
        'luggage_size': _luggageSize,
        'comfort_guarantee': _comfortGuarantee,
        'pref_music': _prefMusic,
        'pref_pets': _prefPets,
        'pref_smoking': _prefSmoking,
        'comment': _commentController.text,
      });

      if (mounted) {
        Navigator.pop(context, true); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tur oprettet!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fejl: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Dato/Tid hjælpere
  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2030), initialDate: DateTime.now());
    if (picked != null) setState(() => _dateController.text = picked.toIso8601String().split('T')[0]);
  }
  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _timeController.text = "${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Opret Tur")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AddressSearchField(label: "Fra", onSelected: (val) => setState(() => _origin = val)),
              const SizedBox(height: 15),
              AddressSearchField(label: "Til", onSelected: (val) => setState(() => _destination = val)),
              const SizedBox(height: 15),
              
              Row(children: [
                Expanded(child: TextField(controller: _dateController, readOnly: true, onTap: _pickDate, decoration: const InputDecoration(labelText: "Dato", prefixIcon: Icon(Icons.calendar_today), border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _timeController, readOnly: true, onTap: _pickTime, decoration: const InputDecoration(labelText: "Tid", prefixIcon: Icon(Icons.access_time), border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 15),

              Row(children: [
                Expanded(child: TextField(controller: _seatsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Pladser", suffixText: "stk", border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Pris", suffixText: "kr.", border: OutlineInputBorder()))),
              ]),
              
              const SizedBox(height: 20),
              const Divider(),
              const Text("Detaljer & Komfort", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              
              // 1. BAGAGE
              DropdownButtonFormField<String>(
                value: _luggageSize,
                decoration: const InputDecoration(labelText: "Bagagestørrelse"),
                items: ["Lille", "Mellem", "Stor"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) => setState(() => _luggageSize = val!),
              ),

              // 2. SWITCHES
              SwitchListTile(
                title: const Text("Max. 5 min. afvigelse"),
                subtitle: const Text("Jeg er fleksibel med opsamling"),
                value: _detourFlex,
                onChanged: (val) => setState(() => _detourFlex = val),
              ),
              SwitchListTile(
                title: const Text("Komfort Garanti"),
                subtitle: const Text("Max. 2 passagerer på bagsædet"),
                value: _comfortGuarantee,
                onChanged: (val) => setState(() => _comfortGuarantee = val),
              ),
              SwitchListTile(
                title: const Text("Inkluderer Færge"),
                value: _isFerry,
                onChanged: (val) => setState(() => _isFerry = val),
              ),

              const Divider(),
              const Text("Præferencer (Tilladt?)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildPrefToggle("Musik", Icons.music_note, _prefMusic, (v) => setState(() => _prefMusic = v)),
                  _buildPrefToggle("Dyr", Icons.pets, _prefPets, (v) => setState(() => _prefPets = v)),
                  _buildPrefToggle("Rygning", Icons.smoking_rooms, _prefSmoking, (v) => setState(() => _prefSmoking = v)),
                ],
              ),

              const SizedBox(height: 20),
              TextField(
                controller: _carController,
                decoration: const InputDecoration(labelText: "Bilmodel (Valgfri)", prefixIcon: Icon(Icons.directions_car), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: "Kommentar til turen...", alignLabelWithHint: true, border: OutlineInputBorder()),
              ),

              const SizedBox(height: 30),
              SizedBox(height: 50, child: ElevatedButton(onPressed: _createRide, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text("OPRET TUR"))),
            ],
          ),
    );
  }

  Widget _buildPrefToggle(String label, IconData icon, bool value, Function(bool) onChanged) {
    return Column(
      children: [
        IconButton(
          onPressed: () => onChanged(!value),
          icon: Icon(icon, color: value ? Colors.green : Colors.grey, size: 30),
          style: IconButton.styleFrom(backgroundColor: value ? Colors.green.shade50 : Colors.grey.shade100),
        ),
        Text(label, style: TextStyle(color: value ? Colors.green : Colors.grey, fontSize: 12)),
      ],
    );
  }
}