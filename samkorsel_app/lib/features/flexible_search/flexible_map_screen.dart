import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // VIGTIGT: Til iOS picker
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

  // --- TIDS FILTRE (Gemmes som Lokal tid i hukommelsen) ---
  DateTime _selectedDate = DateTime.now();
  DateTime? _latestArrivalTime;

  List<Marker> _markers = [];
  bool _isLoading = true;
  LatLng _currentCenter = const LatLng(
    56.26392,
    9.501785,
  ); // Default center (Jylland)
  int _ridesFound = 0;

  @override
  void initState() {
    super.initState();
    _zipController = TextEditingController(text: widget.zipCode);
    _refreshData();
  }

  // --- OPDATER DATA ---
  Future<void> _refreshData() async {
    setState(() => _isLoading = true);

    // 1. Find koordinater for søgningen
    final searchCoords = await _getCoordinatesForSearch(_zipController.text);

    if (searchCoords != null) {
      setState(() => _currentCenter = searchCoords);
      _mapController.move(searchCoords, 6.2);
      await _fetchRidesNearby(searchCoords);
    } else {
      await _fetchRidesFallbackText();
    }

    setState(() => _isLoading = false);
  }

  // --- iOS DATAVÆLGER LOGIK ---
  void _showIOSDateTimePicker({required bool isArrivalFilter}) {
    final DateTime now = DateTime.now();

    // Bestem start-tidspunkt for pickeren
    DateTime initialTime = isArrivalFilter
        ? (_latestArrivalTime ?? _selectedDate.add(const Duration(hours: 2)))
        : _selectedDate;

    // Sikr at vi ikke starter i fortiden
    if (initialTime.isBefore(now)) initialTime = now;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 350,
          child: Column(
            children: [
              // Header med "Færdig" knap
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isArrivalFilter
                          ? "Vælg senest ankomst"
                          : "Vælg tidligst afgang",
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _refreshData(); // Opdater kortet når man er færdig
                      },
                      child: const Text(
                        "Færdig",
                        style: TextStyle(
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Selve Hjulet
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  initialDateTime: initialTime,
                  minimumDate: DateTime(
                    now.year,
                    now.month,
                    now.day,
                    now.hour,
                    now.minute,
                  ),
                  onDateTimeChanged: (DateTime newDateTime) {
                    // Vi tillader ikke fortiden, men pickerens minimumDate klarer det meste.
                    // Her opdaterer vi state.
                    if (newDateTime.isBefore(now)) return;

                    setState(() {
                      if (isArrivalFilter) {
                        _latestArrivalTime = newDateTime;
                      } else {
                        _selectedDate = newDateTime;
                        // Hvis afgang flyttes til efter ankomst, nulstil ankomst
                        if (_latestArrivalTime != null &&
                            _latestArrivalTime!.isBefore(_selectedDate)) {
                          _latestArrivalTime = null;
                        }
                      }
                    });
                  },
                ),
              ),
              // Knap til at fjerne ankomst-filter
              if (isArrivalFilter)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TextButton(
                    onPressed: () {
                      setState(() => _latestArrivalTime = null);
                      Navigator.pop(context);
                      _refreshData();
                    },
                    child: const Text(
                      "Nulstil ankomsttid",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // --- HENT KOORDINATER (Mapbox) ---
  Future<LatLng?> _getCoordinatesForSearch(String query) async {
    String searchTerm = query.trim();
    if (searchTerm.isEmpty) return null;

    final bool isZipCode = RegExp(r'^\d{4}$').hasMatch(searchTerm);
    String searchUrl;

    if (isZipCode) {
      searchUrl =
          "https://api.mapbox.com/geocoding/v5/mapbox.places/$searchTerm%20Denmark.json?access_token=$_mapboxAccessToken&types=postcode&limit=1";
    } else {
      searchUrl =
          "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(searchTerm)}%20Denmark.json?access_token=$_mapboxAccessToken&limit=1&country=dk";
    }

    try {
      final response = await http.get(Uri.parse(searchUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'].isNotEmpty) {
          final center = data['features'][0]['center'];
          return LatLng(center[1].toDouble(), center[0].toDouble());
        }
      }
    } catch (e) {
      debugPrint("Mapbox fejl: $e");
    }
    return null;
  }

  // --- SØG EFTER TURE (SQL RPC) ---
  Future<void> _fetchRidesNearby(LatLng coords) async {
    try {
      // 1. Definer tidsrammen (VIGTIGT: Konverter til UTC for DB sammenligning)

      // Start: Det valgte tidspunkt (Tidligst afgang) -> UTC
      // Fx valgt 17:00 DK tid -> Bliver 16:00 UTC
      final String searchStartUTC = _selectedDate.toUtc().toIso8601String();

      // Slut: Resten af det valgte døgn (lokal tid 23:59:59) -> UTC
      // Vi finder slutningen af dagen i lokal tid først
      final DateTime localEndOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );
      // Og konverterer den til UTC, så vi får HELE dagen med i databasen
      final String searchEndDayUTC = localEndOfDay.toUtc().toIso8601String();

      // 2. Find ID'er tæt på
      final List<dynamic> nearbyIds = await Supabase.instance.client.rpc(
        'get_nearby_ride_ids',
        params: {
          'search_lat': coords.latitude,
          'search_lng': coords.longitude,
          'radius_meters': 20000.0, // 20 km radius
        },
      );

      if (nearbyIds.isEmpty) {
        setState(() {
          _markers = [];
          _ridesFound = 0;
        });
        return;
      }

      // 3. Byg Query
      var query = Supabase.instance.client
          .from('rides')
          .select(
            '*, profiles(*), origin_location::text, destination_location::text',
          )
          .inFilter('id', nearbyIds)
          .eq('status', 'active')
          .gte('departure_time', searchStartUTC) // UTC sammenligning
          .lte('departure_time', searchEndDayUTC); // UTC sammenligning

      // 4. Tilføj Ankomst Filter (hvis valgt)
      if (_latestArrivalTime != null) {
        query = query.lte(
          'arrival_time',
          _latestArrivalTime!.toUtc().toIso8601String(),
        );
      }

      final response = await query;
      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response,
      );

      setState(() {
        _generateMarkers(data);
        _ridesFound = data.length;
      });
    } catch (e) {
      debugPrint("Supabase Geo-fejl: $e");
    }
  }

  // --- FALLBACK SØGNING ---
  Future<void> _fetchRidesFallbackText() async {
    try {
      // VIGTIGT: Samme UTC logik her
      final String searchStartUTC = _selectedDate.toUtc().toIso8601String();

      final DateTime localEndOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );
      final String searchEndDayUTC = localEndOfDay.toUtc().toIso8601String();

      String queryText = _zipController.text.trim();
      if (!RegExp(r'^\d{4}$').hasMatch(queryText)) {
        queryText = queryText.split(' ')[0];
      }

      var query = Supabase.instance.client
          .from('rides')
          .select(
            '*, profiles(*), origin_location::text, destination_location::text',
          )
          .ilike('origin_city', '%$queryText%')
          .eq('status', 'active')
          .gte('departure_time', searchStartUTC)
          .lte('departure_time', searchEndDayUTC);

      if (_latestArrivalTime != null) {
        query = query.lte(
          'arrival_time',
          _latestArrivalTime!.toUtc().toIso8601String(),
        );
      }

      final response = await query;
      final data = List<Map<String, dynamic>>.from(response);

      setState(() {
        _generateMarkers(data);
        _ridesFound = data.length;
      });
    } catch (e) {
      debugPrint("Fallback fejl: $e");
    }
  }

  // --- MARKER GENERATOR ---
  void _generateMarkers(List<Map<String, dynamic>> rides) {
    Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var ride in rides) {
      final coords = _parsePostGISHex(ride['destination_location']);
      if (coords != null) {
        String key = "${coords.latitude},${coords.longitude}";
        grouped.putIfAbsent(key, () => []).add(ride);
      }
    }

    _markers = grouped.entries.map((entry) {
      final coords = entry.key.split(',');
      return Marker(
        point: LatLng(double.parse(coords[0]), double.parse(coords[1])),
        width: 35,
        height: 35,
        child: GestureDetector(
          onTap: () => _showRidesBottomSheet(entry.value),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
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
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // --- BUILD UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // KORTET
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 6.2,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://api.mapbox.com/styles/v1/mapbox/light-v10/tiles/256/{z}/{x}/{y}@2x?access_token=$_mapboxAccessToken",
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          // SØGEFELT & FILTRE
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      // TILBAGE KNAP
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          height: 50,
                          width: 50,
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

                      // SØGEFELT
                      Expanded(
                        child: Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search,
                                color: Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _zipController,
                                  onSubmitted: (_) => _refreshData(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: "Postnr. eller by",
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // TIDS FILTER KNAPPER
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // 1. TIDLIGST AFGANG
                        _buildTimeFilterChip(
                          icon: Icons.calendar_today,
                          label:
                              "Afgang: ${DateFormat('dd/MM HH:mm').format(_selectedDate)}",
                          isActive: true,
                          onTap: () =>
                              _showIOSDateTimePicker(isArrivalFilter: false),
                        ),

                        const SizedBox(width: 10),

                        // 2. SENEST ANKOMST
                        _buildTimeFilterChip(
                          icon: Icons.flag_outlined,
                          label: _latestArrivalTime == null
                              ? "Senest ankomst"
                              : "Ankomst: ${DateFormat('HH:mm').format(_latestArrivalTime!)}",
                          isActive: _latestArrivalTime != null,
                          onTap: () =>
                              _showIOSDateTimePicker(isArrivalFilter: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // LOADING INDIKATOR
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildTimeFilterChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- BOTTOM SHEET TIL TURE ---
  void _showRidesBottomSheet(List<Map<String, dynamic>> rides) {
    final destName = rides.isNotEmpty
        ? rides[0]['destination_city'].split(',')[0]
        : "Destination";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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

                  // VIGTIGT: Konverter fra UTC (DB) til Local (Visning)
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
                      subtitle: Text(
                        "Chauffør: ${ride['profiles']['full_name']}",
                      ),
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

  // --- HJÆLPEFUNKTIONER (PARSE HEX) ---
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
