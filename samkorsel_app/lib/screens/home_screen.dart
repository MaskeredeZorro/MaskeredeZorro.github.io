import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import '../core/constants.dart'; // Hvis du har denne fil, behold den. Hvis ikke, bruger jeg hardcoded værdier herunder.
import '../features/rides/create_ride_screen.dart';
import '../features/rides/ride_detail_screen.dart';
// import '../features/rides/search_ride_screen.dart'; // Behold hvis du har den fil
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _rides = [];
  final MapController _mapController = MapController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRides();
  }

  // -- 1. HENT DATA --
  Future<void> _fetchRides() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('rides')
          // Hent også profiler, så vi kan se chaufførnavn i listen
          .select('*, profiles(*), origin_location::text, destination_location::text') 
          .order('departure_time', ascending: true); // Sorter efter dato, snarest først
      
      if (mounted) {
        setState(() {
          _rides = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fejl: $e");
      setState(() => _isLoading = false);
    }
  }

  // -- 2. GPS PARSER (Fra PostGIS string til LatLng) --
  LatLng? _parseCoordinates(String? geoString) {
    if (geoString == null) return null;
    try {
      final clean = geoString.replaceAll(RegExp(r'[a-zA-Z\(\)]'), '').trim();
      final parts = clean.split(RegExp(r'\s+'));
      if (parts.length < 2) return null;
      // PostGIS er ofte "lng lat", men LatLng biblioteket vil have (lat, lng)
      return LatLng(double.parse(parts[1]), double.parse(parts[0]));
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // --- LAG 1: KORTET (Baggrunden) ---
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(56.1629, 10.2039), // Aarhus ca.
              initialZoom: 6.8, 
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.samkorsel.app',
              ),
              MarkerLayer(
                markers: _rides.map((ride) {
                  final point = _parseCoordinates(ride['origin_location']);
                  if (point == null) return const Marker(point: LatLng(0,0), child: SizedBox());
                  
                  return Marker(
                    point: point,
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () {
                         Navigator.push(context, MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride)));
                      },
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // --- LAG 2: TOP BAR ---
          Positioned(
            top: 50, left: 16, right: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 10),
                    Text(_rides.isEmpty ? "Søg efter lift..." : "Viser ${_rides.length} ture", style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
          ),

          // --- LAG 3: LISTEN (Draggable Sheet) ---
          DraggableScrollableSheet(
            initialChildSize: 0.3, 
            minChildSize: 0.1,    
            maxChildSize: 0.8,    
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
                ),
                child: Column(
                  children: [
                    // Håndtag
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 10),
                        width: 40, height: 5,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    
                    // Overskrift
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Ledige lift", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text("${_rides.length} fundet", style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    const Divider(),

                    // Selve Listen
                    Expanded(
                      child: _isLoading 
                      ? const Center(child: CircularProgressIndicator()) 
                      : _rides.isEmpty 
                        ? const Center(child: Text("Ingen lift fundet.")) 
                        : ListView.builder(
                          controller: scrollController,
                          itemCount: _rides.length,
                          itemBuilder: (context, index) {
                            final ride = _rides[index];
                            final isFerry = ride['is_ferry'] == true;
                            
                            // Dato fix
                            DateTime time;
                            try { time = DateTime.parse(ride['departure_time']); } catch (e) { time = DateTime.now(); }
                            
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              onTap: () {
                                final point = _parseCoordinates(ride['origin_location']);
                                if (point != null) _mapController.move(point, 10);
                                Navigator.push(context, MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride)));
                              },
                              leading: CircleAvatar(
                                backgroundColor: isFerry ? Colors.blue.shade100 : Colors.green.shade100,
                                child: Icon(isFerry ? Icons.directions_boat : Icons.directions_car, color: isFerry ? Colors.blue : Colors.green),
                              ),
                              title: Row(
                                children: [
                                  // Vi klipper teksten hvis den er meget lang (DAWA adresser kan være lange)
                                  Flexible(child: Text(ride['origin_city'].split(',')[0], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey)),
                                  Flexible(child: Text(ride['destination_city'].split(',')[0], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
                                ],
                              ),
                              subtitle: Text("Kl. ${time.hour}:${time.minute.toString().padLeft(2, '0')} • ${ride['car_model'] ?? 'Bil'}"),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text("${ride['price_dkk']} kr.", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                                  Text("${ride['seats_available']} pl.", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            );
                          },
                        ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // --- LAG 4: KNAPPER (Profil + Opret Tur) ---
          Positioned(
            bottom: 30, 
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // PROFIL KNAP (Hvid)
                FloatingActionButton(
                  heroTag: "btn_profile",
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.person, color: Colors.black),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  },
                ),
                
                const SizedBox(height: 15),

                // OPRET TUR KNAP (Sort)
                FloatingActionButton(
                  heroTag: "btn_add",
                  backgroundColor: Colors.black,
                  child: const Icon(Icons.add, color: Colors.white),
                  onPressed: () async {
                      // BEMÆRK: Vi bruger await her, så når man kommer tilbage fra oprettelse, opdaterer vi listen
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRideScreen()));
                      if (result == true) {
                        _fetchRides();
                      }
                  },
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}