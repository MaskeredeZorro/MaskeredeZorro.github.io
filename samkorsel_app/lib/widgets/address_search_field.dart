import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle; // Til at læse JSON
import 'package:http/http.dart' as http;

class AddressSearchField extends StatefulWidget {
  final String label;
  final Function(String) onSelected;

  const AddressSearchField({
    super.key,
    required this.label,
    required this.onSelected,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final _controller = TextEditingController();

  // Vi gemmer både teksten og om det er en station (isPrio)
  List<Map<String, dynamic>> _suggestions = [];
  List<String> _localStationNames =
      []; // Her gemmer vi alle navne fra JSON-filen

  bool _isLoading = false;
  Timer? _debounce;

  // Din Mapbox Token
  final String _mapboxAccessToken =
      'pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w';

  @override
  void initState() {
    super.initState();
    _loadStations(); // Indlæs stationer med det samme
  }

  // 1. INDLÆS LOKALE STATIONER FRA JSON
  Future<void> _loadStations() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/station_taxa.json',
      );
      final Map<String, dynamic> data = json.decode(response);

      // Vi gemmer kun navnene (nøglerne) i en liste for hurtig søgning
      setState(() {
        _localStationNames = data.keys.toList();
      });
    } catch (e) {
      debugPrint("Fejl ved indlæsning af stationer i widget: $e");
    }
  }

  // 2. SØGE-FUNKTION (HYBRID)
  Future<void> _searchAddress(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.length < 2) {
        setState(() => _suggestions = []);
        return;
      }

      setState(() => _isLoading = true);

      List<Map<String, dynamic>> tempResults = [];

      // A. SØG LOKALT FØRST (Stationer)
      // Vi finder alle stationer i din JSON, der matcher det du skriver
      final localMatches = _localStationNames
          .where((name) => name.toLowerCase().contains(query.toLowerCase()))
          .take(3) // Tag max 3 stationer så de ikke fylder det hele
          .toList();

      for (var name in localMatches) {
        tempResults.add({
          'text': name,
          'isStation': true, // Markér som station (så vi kan vise tog-ikon)
        });
      }

      // B. SØG MAPBOX (Adresser & Byer)
      try {
        final url = Uri.parse(
          "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=$_mapboxAccessToken&country=dk&autocomplete=true&limit=5&types=place,locality,neighborhood,address,poi",
        );

        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final features = data['features'] as List;

          for (var feature in features) {
            // Tilføj kun hvis den ikke allerede er fundet lokalt (undgå dubletter)
            String mapboxText = feature['place_name'];

            // Simpelt tjek for at undgå at vise "Skive St." to gange
            bool alreadyExists = tempResults.any(
              (item) => item['text'] == mapboxText,
            );

            if (!alreadyExists) {
              tempResults.add({'text': mapboxText, 'isStation': false});
            }
          }
        }
      } catch (e) {
        debugPrint("Mapbox Fejl: $e");
      }

      if (mounted) {
        setState(() {
          _suggestions = tempResults;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.map),
            // Vis loader eller "ryd"-knap
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _suggestions = []);
                    },
                  )
                : null,
          ),
          onChanged: (val) {
            _searchAddress(val);
          },
        ),

        // RESULTAT LISTE
        if (_suggestions.isNotEmpty)
          Container(
            // Dynamisk højde, men max 250
            constraints: const BoxConstraints(maxHeight: 250),
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _suggestions[index];
                final text = item['text'];
                final isStation = item['isStation'] == true;

                return ListTile(
                  dense: true,
                  // Vis Tog-ikon hvis det er fra din JSON-fil, ellers Map-ikon
                  leading: Icon(
                    isStation ? Icons.train : Icons.location_on_outlined,
                    size: 20,
                    color: isStation ? const Color(0xFF6366F1) : Colors.grey,
                  ),
                  title: Text(
                    text,
                    style: TextStyle(
                      fontWeight: isStation
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isStation ? const Color(0xFF0F172A) : null,
                    ),
                  ),
                  onTap: () {
                    _controller.text = text;
                    widget.onSelected(text); // Sender teksten tilbage
                    setState(() {
                      _suggestions = [];
                      _isLoading = false;
                    });
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
