import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle; // VIGTIGT: Til at læse JSON filen
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../widgets/address_search_field.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  // --- Controllers & Variabler ---
  String? _origin;
  String? _destination;
  final _dateController = TextEditingController();
  final _depTimeController = TextEditingController(); // Afgang
  final _arrTimeController = TextEditingController(); // Ankomst
  final _seatsController = TextEditingController(text: "3");
  final _priceController = TextEditingController();
  final _commentController = TextEditingController();

  // Detaljer & Switches
  bool _isFerry = false;
  bool _detourFlex = true;
  bool _comfortGuarantee = false; // Max 2 på bagsædet
  bool _instantBooking = false; // Lynbooking
  String _luggageSize = 'Mellem'; // Lille, Mellem, Stor

  // Præferencer (True = Tilladt)
  bool _prefMusic = true;
  bool _prefPets = false;
  bool _prefSmoking = false;
  bool _prefKids = true;

  bool _isLoading = false;

  // Variabel til at gemme stationsdata
  Map<String, dynamic> _stationData = {};

  // Farver til temaet (Slate & Indigo)
  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _accentColor = const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _loadStations(); // Indlæs stationsfilen når skærmen åbner
  }

  // Funktion til at indlæse JSON filen
  Future<void> _loadStations() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/station_taxa.json',
      );
      setState(() {
        _stationData = json.decode(response);
      });
      print(
        "✅ CreateRide: Indlæste ${_stationData.length} stationer fra filen.",
      );
    } catch (e) {
      print("⚠️ CreateRide: Kunne ikke indlæse stationer: $e");
    }
  }

  // --- NY HYBRID GPS LOGIK (JSON -> Mapbox) ---
  Future<Map<String, double>?> _getCityCoordinates(String query) async {
    if (query.isEmpty) return null;

    // TRIN 1: TJEK DIN LOKALE FIL (Prioritet #1)
    if (_stationData.containsKey(query)) {
      final station = _stationData[query];
      print("🎯 FAST STATION FUNDET (CreateRide): '$query'");

      return {
        'lat': (station['lat'] as num).toDouble(),
        'lng': (station['lng'] as num).toDouble(),
      };
    }

    // TRIN 2: SPØRG MAPBOX (Fallback)
    String optimizedQuery = "$query, Denmark";

    debugPrint("Søger hos Mapbox efter: '$optimizedQuery'");

    const String mapboxAccessToken =
        'pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w';

    try {
      final url = Uri.parse(
        "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(optimizedQuery)}.json?access_token=$mapboxAccessToken&country=dk&limit=1&types=place,locality,neighborhood,address,poi",
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'].isNotEmpty) {
          final center =
              data['features'][0]['center']; // Mapbox giver [Lng, Lat]

          debugPrint("Mapbox fandt: ${data['features'][0]['place_name']}");

          return {
            'lat': center[1].toDouble(), // Index 1 er Latitude
            'lng': center[0].toDouble(), // Index 0 er Longitude
          };
        }
      }
    } catch (e) {
      debugPrint("Mapbox Fejl: $e");
    }

    return null;
  }

  // -- OPRET TUR LOGIK --
  Future<void> _createRide() async {
    // 1. Validering
    if (_origin == null ||
        _destination == null ||
        _dateController.text.isEmpty ||
        _depTimeController.text.isEmpty ||
        _arrTimeController.text.isEmpty ||
        _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Udfyld venligst rute, tider og pris.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("Du er ikke logget ind");

      // 2. Dato & Tid håndtering
      final dateParts = _dateController.text.split('-'); // [2026, 02, 04]
      final depParts = _depTimeController.text.split(':'); // [22, 27]
      final arrParts = _arrTimeController.text.split(':'); // [23, 27]

      DateTime depDateTime = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(depParts[0]),
        int.parse(depParts[1]),
      );

      DateTime arrDateTime = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(arrParts[0]),
        int.parse(arrParts[1]),
      );

      if (arrDateTime.isBefore(depDateTime)) {
        arrDateTime = arrDateTime.add(const Duration(days: 1));
      }

      // 3. Hent bilmodel fra profil
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('car_details')
          .eq('id', user.id)
          .single();

      final carModel = profile['car_details'] ?? "Min Bil";

      // 4. Find KORREKTE koordinater (Hybrid: JSON eller Mapbox)
      final originCoords = await _getCityCoordinates(_origin!);
      final destCoords = await _getCityCoordinates(_destination!);

      if (originCoords == null || destCoords == null) {
        throw Exception(
          "Kunne ikke finde byens placering. Prøv at være mere specifik (fx 'Vejnavn, By')",
        );
      }

      print(
        "Opretter tur: ${_origin} (${originCoords['lat']},${originCoords['lng']}) -> ${_destination} (${destCoords['lat']},${destCoords['lng']})",
      );

      // 5. Indsæt i Supabase
      await Supabase.instance.client.from('rides').insert({
        'driver_id': user.id,
        'origin_city': _origin,
        'destination_city': _destination,
        // PostGIS format: POINT(lng lat) - Supabase kræver RÆKKEFØLGEN POINT(LNG LAT)
        'origin_location':
            'POINT(${originCoords['lng']} ${originCoords['lat']})',
        'destination_location':
            'POINT(${destCoords['lng']} ${destCoords['lat']})',
        'departure_time': depDateTime.toUtc().toIso8601String(),
        'arrival_time': arrDateTime.toUtc().toIso8601String(),
        'seats_available': int.parse(_seatsController.text),
        'price_dkk': int.parse(_priceController.text),
        'car_model': carModel,
        'status': 'active',
        // Nye felter
        'is_ferry': _isFerry,
        'detour_flex': _detourFlex,
        'instant_booking': _instantBooking,
        'luggage_size': _luggageSize,
        'comfort_guarantee': _comfortGuarantee,
        'pref_music': _prefMusic,
        'pref_pets': _prefPets,
        'pref_smoking': _prefSmoking,
        'pref_kids': _prefKids,
        'comment': _commentController.text,
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Succes! Din tur er online 🚀"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fejl: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI Helpers ---
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      initialDate: DateTime.now(),
    );
    if (picked != null)
      setState(
        () => _dateController.text = DateFormat('yyyy-MM-dd').format(picked),
      );
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final hour = picked.hour.toString().padLeft(2, '0');
      final minute = picked.minute.toString().padLeft(2, '0');
      setState(() => controller.text = "$hour:$minute");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Opret Tur",
          style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: _primaryColor),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _accentColor))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // --- SEKTION 1: RUTE ---
                Text(
                  "Ruten",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                AddressSearchField(
                  label: "Hvor kører du fra?",
                  onSelected: (val) => setState(() => _origin = val),
                ),
                const SizedBox(height: 10),
                AddressSearchField(
                  label: "Hvor kører du til?",
                  onSelected: (val) => setState(() => _destination = val),
                ),

                const SizedBox(height: 30),

                // --- SEKTION 2: TID ---
                Text(
                  "Tidspunkt",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                _buildTextField(
                  controller: _dateController,
                  label: "Dato",
                  icon: Icons.calendar_month,
                  onTap: _pickDate,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _depTimeController,
                        label: "Afgang",
                        icon: Icons.schedule,
                        onTap: () => _pickTime(_depTimeController),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _arrTimeController,
                        label: "Ankomst",
                        icon: Icons.flag,
                        onTap: () => _pickTime(_arrTimeController),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // --- SEKTION 3: ØKONOMI ---
                Text(
                  "Pladser & Pris",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _seatsController,
                        label: "Sæder",
                        icon: Icons.event_seat,
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildTextField(
                        controller: _priceController,
                        label: "Pris (kr)",
                        icon: Icons.attach_money,
                        isNumber: true,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),
                const Divider(),
                const SizedBox(height: 10),

                // --- SEKTION 4: INDSTILLINGER (Switches) ---
                Text(
                  "Indstillinger",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                _buildCustomSwitch(
                  "Lynbooking",
                  "Godkend automatisk",
                  _instantBooking,
                  (v) => setState(() => _instantBooking = v),
                ),
                _buildCustomSwitch(
                  "Færge",
                  "Prisen er inkl. færge",
                  _isFerry,
                  (v) => setState(() => _isFerry = v),
                ),
                _buildCustomSwitch(
                  "Fleksibel",
                  "Max 5 min. omvej",
                  _detourFlex,
                  (v) => setState(() => _detourFlex = v),
                ),
                _buildCustomSwitch(
                  "Komfort Garanti",
                  "Max 2 på bagsædet",
                  _comfortGuarantee,
                  (v) => setState(() => _comfortGuarantee = v),
                ),

                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: _luggageSize,
                  decoration: InputDecoration(
                    labelText: "Bagageplads",
                    prefixIcon: const Icon(Icons.luggage, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: ["Lille", "Mellem", "Stor"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _luggageSize = val!),
                ),

                const SizedBox(height: 30),

                // --- SEKTION 5: HUSREGLER ---
                Text(
                  "Husregler (Tilladt?)",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPrefIcon(
                      "Musik",
                      Icons.music_note,
                      _prefMusic,
                      (v) => setState(() => _prefMusic = v),
                    ),
                    _buildPrefIcon(
                      "Dyr",
                      Icons.pets,
                      _prefPets,
                      (v) => setState(() => _prefPets = v),
                    ),
                    _buildPrefIcon(
                      "Rygning",
                      Icons.smoking_rooms,
                      _prefSmoking,
                      (v) => setState(() => _prefSmoking = v),
                    ),
                    _buildPrefIcon(
                      "Børn",
                      Icons.child_care,
                      _prefKids,
                      (v) => setState(() => _prefKids = v),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Kommentar til passagerer...",
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // OPRET KNAP
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _createRide,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      "OFFENTLIGGØR TUR",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  // --- Design Widgets ---

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      readOnly: onTap != null,
      onTap: onTap,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
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

  Widget _buildCustomSwitch(
    String title,
    String sub,
    bool val,
    Function(bool) change,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: val ? _accentColor.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: val ? _accentColor : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              Text(
                sub,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          Switch(value: val, onChanged: change, activeColor: _accentColor),
        ],
      ),
    );
  }

  Widget _buildPrefIcon(
    String label,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: value ? _accentColor : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: value ? Colors.white : Colors.grey),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: value ? _accentColor : Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
