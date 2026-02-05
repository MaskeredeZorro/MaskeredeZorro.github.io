import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../features/rides/ride_detail_screen.dart';

class FlexibleMapScreen extends StatefulWidget {
  final String zipCode;

  const FlexibleMapScreen({super.key, required this.zipCode});

  @override
  State<FlexibleMapScreen> createState() => _FlexibleMapScreenState();
}

class _FlexibleMapScreenState extends State<FlexibleMapScreen> {
  final MapController _mapController = MapController();
  final String _mapboxAccessToken =
      'pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w';

  late TextEditingController _zipController;
  DateTime _selectedDate = DateTime.now();

  List<Marker> _markers = [];
  bool _isLoading = true;
  LatLng _currentCenter = const LatLng(56.26392, 9.501785);
  int _ridesFound = 0;

  @override
  void initState() {
    super.initState();
    _zipController = TextEditingController(text: widget.zipCode);
    _refreshData();
  }

  // Samlet funktion til at genopfriske kort og data
  Future<void> _refreshData() async {
    setState(() => _isLoading = true);

    // 1. Find koordinater for postnummeret for at centrere kortet
    await _centerMapOnZip(_zipController.text);

    // 2. Hent lifts fra Supabase
    await _fetchRidesFromZip();

    setState(() => _isLoading = false);
  }

  Future<void> _centerMapOnZip(String zip) async {
    try {
      final url = Uri.parse(
        "https://api.mapbox.com/geocoding/v5/mapbox.places/$zip%20Denmark.json?access_token=$_mapboxAccessToken&types=postcode&limit=1",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'].isNotEmpty) {
          final center = data['features'][0]['center'];
          final pos = LatLng(center[1].toDouble(), center[0].toDouble());
          _currentCenter = pos;
          _mapController.move(pos, 10.0);
        }
      }
    } catch (e) {
      debugPrint("Fejl ved centrering: $e");
    }
  }

  Future<void> _fetchRidesFromZip() async {
    try {
      // 1. Skab et tidsinterval for KUN den valgte dag
      final DateTime startOfSelectedDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        0,
        0,
        0,
      );

      final DateTime endOfSelectedDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      // 2. Opdater din query til at bruge både gte (start) og lte (slut)
      final response = await Supabase.instance.client
          .from('rides')
          .select(
            '*, profiles(*), origin_location::text, destination_location::text',
          )
          .ilike('origin_city', '%${_zipController.text}%')
          // Her er fixet:
          .gte('departure_time', startOfSelectedDay.toIso8601String())
          .lte('departure_time', endOfSelectedDay.toIso8601String())
          .eq('status', 'active');

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response,
      );

      setState(() {
        _generateMarkers(data);
        _ridesFound = data.length;
      });

      debugPrint("Søger mellem: ${startOfSelectedDay} og ${endOfSelectedDay}");
      debugPrint("Fandt: ${data.length} lift");
    } catch (e) {
      debugPrint("Supabase fejl: $e");
    }
  }

  void _generateMarkers(List<Map<String, dynamic>> rides) {
    Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var ride in rides) {
      final destCoords = _parsePostGISHex(ride['destination_location']);
      if (destCoords != null) {
        String key = "${destCoords.latitude},${destCoords.longitude}";
        grouped.putIfAbsent(key, () => []).add(ride);
      }
    }

    _markers = grouped.entries.map((entry) {
      final coords = entry.key.split(',');
      return Marker(
        point: LatLng(double.parse(coords[0]), double.parse(coords[1])),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () => _showRidesBottomSheet(entry.value),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A), // Slate mørk
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                entry.value.length.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // UI KOMPONENT: Den moderne filter-bar øverst
  Widget _buildFilterBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Color(0xFF6366F1), size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _zipController,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _refreshData(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              decoration: const InputDecoration(
                hintText: "Postnr.",
                border: InputBorder.none,
              ),
            ),
          ),
          const VerticalDivider(width: 30, indent: 15, endIndent: 15),
          GestureDetector(
            onTap: _pickDate,
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd. MMM').format(_selectedDate),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _refreshData();
    }
  }

  void _showRidesBottomSheet(List<Map<String, dynamic>> rides) {
    final destName = rides[0]['destination_city'].split(',')[0];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Lift til $destName",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: rides.length,
                itemBuilder: (context, index) {
                  final ride = rides[index];
                  final depTime = DateTime.parse(
                    ride['departure_time'],
                  ).toLocal();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundImage:
                            (ride['profiles']['avatar_url'] != null)
                            ? NetworkImage(ride['profiles']['avatar_url'])
                            : null,
                        child: ride['profiles']['avatar_url'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        "${DateFormat('HH:mm').format(depTime)} • ${ride['price_dkk']} kr.",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      subtitle: Text(ride['profiles']['full_name']),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Color(0xFF6366F1),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RideDetailScreen(ride: ride),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 9.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://api.mapbox.com/styles/v1/mapbox/light-v10/tiles/256/{z}/{x}/{y}@2x?access_token=$_mapboxAccessToken",
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          // Filter og navigations UI
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          height: 60,
                          width: 60,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 10),
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _buildFilterBar()),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
        ],
      ),
    );
  }

  // --- HJÆLPEFUNKTIONER ---
  LatLng? _parsePostGISHex(String? hex) {
    if (hex == null || hex.length < 42) return null;
    try {
      String hexLng = hex.substring(18, 34);
      String hexLat = hex.substring(34, 50);
      return LatLng(_hexToDouble(hexLat), _hexToDouble(hexLng));
    } catch (e) {
      return null;
    }
  }

  double _hexToDouble(String hex) {
    List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return ByteData.sublistView(
      Uint8List.fromList(bytes),
    ).getFloat64(0, Endian.little);
  }
}
