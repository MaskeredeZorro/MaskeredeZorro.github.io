import 'dart:convert';
import 'dart:async'; // Til at vente mens man skriver
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SearchRideScreen extends StatefulWidget {
  const SearchRideScreen({super.key});

  @override
  State<SearchRideScreen> createState() => _SearchRideScreenState();
}

class _SearchRideScreenState extends State<SearchRideScreen> {
  // Controllere til tekstfelterne
  final _originController = TextEditingController();
  final _destController = TextEditingController();

  // Her gemmer vi de valgte koordinater
  Map<String, double>? _selectedOriginCoords;
  Map<String, double>? _selectedDestCoords;

  // Liste over forslag (når man skriver)
  List<dynamic> _suggestions = [];
  bool _isSearchingOrigin = true; // Holder styr på hvilket felt vi skriver i

  // Timer til at undgå at søge for hver eneste bogstav (Debounce)
  Timer? _debounce;

  // -- 1. Hent adresseforslag fra Mapbox --
  Future<void> _fetchSuggestions(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.length < 2) return; // Mapbox kan klare kortere queries

      // Din Mapbox Token
      const String mapboxAccessToken =
          'pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w';

      // Vi søger efter adresser, steder, byer og POIs
      final url = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=$mapboxAccessToken&country=dk&autocomplete=true&limit=5&types=place,locality,neighborhood,address,poi',
      );

      try {
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          setState(() {
            // Mapbox returnerer resultaterne i en liste kaldet 'features'
            _suggestions = data['features'];
          });
        }
      } catch (e) {
        debugPrint("Fejl: $e");
      }
    });
  }

  // -- 2. Udfør selve søgningen i Supabase --
  Future<void> _performSearch() async {
    if (_selectedOriginCoords == null || _selectedDestCoords == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vælg venligst en adresse fra listen i begge felter"),
        ),
      );
      return;
    }

    try {
      // Vi kalder vores SQL funktion 'search_rides'
      final data = await Supabase.instance.client.rpc(
        'search_rides',
        params: {
          'origin_lat': _selectedOriginCoords!['lat'],
          'origin_lng': _selectedOriginCoords!['lng'],
          'dest_lat': _selectedDestCoords!['lat'],
          'dest_lng': _selectedDestCoords!['lng'],
        },
      );

      // Send resultaterne tilbage til forrige skærm
      if (mounted) {
        Navigator.pop(context, data); // Vi returnerer listen af ture
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Søgefejl: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Find lift"),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Column(
        children: [
          // -- SØGE FELTER --
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                // Fra Felt
                TextField(
                  controller: _originController,
                  decoration: InputDecoration(
                    labelText: "Hvor rejser du fra?",
                    prefixIcon: const Icon(
                      Icons.circle_outlined,
                      size: 16,
                      color: Colors.green,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  onChanged: (val) {
                    setState(() => _isSearchingOrigin = true);
                    _fetchSuggestions(val);
                  },
                ),
                const SizedBox(height: 12),
                // Til Felt
                TextField(
                  controller: _destController,
                  decoration: InputDecoration(
                    labelText: "Hvor skal du hen?",
                    prefixIcon: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  onChanged: (val) {
                    setState(() => _isSearchingOrigin = false);
                    _fetchSuggestions(val);
                  },
                ),
                const SizedBox(height: 16),
                // Søge Knap
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _performSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "SØG EFTER LIFT",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // -- FORSLAGSLISTE --
          Expanded(
            child: ListView.builder(
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final place = _suggestions[index];

                // Mapbox bruger 'place_name' i stedet for 'display_name'
                final address = place['place_name'] as String;

                return ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: Colors.grey,
                  ),
                  // Vi splitter på komma for at vise hovednavnet først (f.eks. vejnavn eller by)
                  title: Text(
                    address.split(',')[0],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(address),
                  onTap: () {
                    // Mapbox gemmer koordinater i 'center' som [longitude, latitude]
                    final List<dynamic> center = place['center'];

                    final coords = {
                      'lat': center[1].toDouble(), // Index 1 er Latitude
                      'lng': center[0].toDouble(), // Index 0 er Longitude
                    };

                    setState(() {
                      if (_isSearchingOrigin) {
                        _originController.text = address.split(',')[0];
                        _selectedOriginCoords = coords;
                      } else {
                        _destController.text = address.split(',')[0];
                        _selectedDestCoords = coords;
                      }
                      _suggestions = []; // Skjul listen
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
