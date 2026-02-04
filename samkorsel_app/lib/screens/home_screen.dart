import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../features/rides/create_ride_screen.dart';
import '../features/rides/ride_detail_screen.dart';
import 'profile_screen.dart'; // Denne importerer nu din NYE profil fil

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // --- SØGE STATE ---
  String? _searchOrigin;
  String? _searchDest;

  double? _originLat;
  double? _originLng;
  double? _destLat;
  double? _destLng;

  DateTime? _searchDate;
  double _searchRadius = 20.0;

  void _performSearch(
    String origin,
    String dest,
    double? oLat,
    double? oLng,
    double? dLat,
    double? dLng,
    DateTime date,
    double radius,
  ) {
    setState(() {
      _searchOrigin = origin;
      _searchDest = dest;
      _originLat = oLat;
      _originLng = oLng;
      _destLat = dLat;
      _destLng = dLng;
      _searchDate = date;
      _searchRadius = radius;
      _currentIndex = 1;
    });
  }

  void _clearSearch() {
    setState(() {
      _searchOrigin = null;
      _searchDest = null;
      _originLat = null;
      _originLng = null;
      _destLat = null;
      _destLng = null;
      _searchRadius = 20.0;
      _searchDate = null;
    });
  }

  void _onTabTapped(int index) async {
    if (index == 2) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreateRideScreen()),
      );
      setState(() {});
    } else {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = const Color(0xFF0F172A);

    final List<Widget> pages = [
      SearchTab(onSearch: _performSearch),
      RidesTab(
        filterOrigin: _searchOrigin,
        filterDest: _searchDest,
        originLat: _originLat,
        originLng: _originLng,
        destLat: _destLat,
        destLng: _destLng,
        filterDate: _searchDate,
        radius: _searchRadius,
        onClearFilters: _clearSearch,
      ),
      const SizedBox(), // Placeholder for 'Opret' knappen
      const Center(child: Text("Beskeder (Kommer snart)")),
      const ProfileScreen(), // <--- RETTET: Bruger nu den nye klasse fra profile_screen.dart
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: activeColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        elevation: 10,
        backgroundColor: Colors.white,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.search), label: "Søg"),
          const BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: "Alle lift",
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activeColor,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
            label: "",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: "Beskeder",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: "Profil",
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 1. SEARCH TAB
// ==========================================
class SearchTab extends StatefulWidget {
  final Function(
    String,
    String,
    double?,
    double?,
    double?,
    double?,
    DateTime,
    double,
  )
  onSearch;
  const SearchTab({super.key, required this.onSearch});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _originController = TextEditingController();
  final _destController = TextEditingController();

  double? _selOriginLat;
  double? _selOriginLng;
  double? _selDestLat;
  double? _selDestLng;

  double _currentRadius = 20.0;
  bool _isDestFieldActive = false;
  DateTime _selectedDate = DateTime.now();
  final _dateDisplayController = TextEditingController(
    text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
  );

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _accentColor = const Color(0xFF6366F1);
  final Color _bgLight = const Color(0xFFF8FAFC);

  final List<String> _smartZones = [
    "Storkøbenhavn",
    "Nordsjælland",
    "Vestsjælland",
    "Sydsjælland",
    "Midtsjælland",
    "Aarhus & Omegn",
    "Odense & Omegn",
    "Aalborg & Omegn",
    "Trekantsområdet",
  ];

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      initialDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateDisplayController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  // --- NY LOGIK: HENT KUN BY-KOORDINATER ---
  Future<void> _handleSearch() async {
    final results = await Future.wait([
      _fetchCityCoords(_originController.text),
      _fetchCityCoords(_destController.text),
    ]);

    final startCoords = results[0];
    final endCoords = results[1];

    print("--- SØGNING PÅ BY-NIVEAU ---");
    print(
      "FRA: ${_originController.text} -> ${startCoords?[0]}, ${startCoords?[1]}",
    );
    print("TIL: ${_destController.text} -> ${endCoords?[0]}, ${endCoords?[1]}");

    widget.onSearch(
      _originController.text.trim(),
      _destController.text.trim(),
      startCoords?[0],
      startCoords?[1],
      endCoords?[0],
      endCoords?[1],
      _selectedDate,
      _currentRadius,
    );
  }

  // --- DEN NYE FUNKTION (OpenStreetMap) ---
  Future<List<double>?> _fetchCityCoords(String query) async {
    if (query.isEmpty) return null;

    String searchQuery = query;
    RegExp zipRegExp = RegExp(r'\b\d{4}\b');
    Match? match = zipRegExp.firstMatch(query);

    if (match != null) {
      String zip = match.group(0)!;
      searchQuery = "$zip, Danmark";
    } else {
      searchQuery = "$query, Danmark";
    }

    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(searchQuery)}&format=json&limit=1&countrycodes=dk",
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'SamkorselApp/1.0'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          return [double.parse(data[0]['lat']), double.parse(data[0]['lon'])];
        }
      }
    } catch (e) {
      debugPrint("OSM Fejl: $e");
    }
    return null;
  }

  void _onOriginSelected(String name, double? lat, double? lng) {
    _originController.text = name;
    _selOriginLat = lat;
    _selOriginLng = lng;
  }

  void _onDestSelected(String name, double? lat, double? lng) {
    _destController.text = name;
    _selDestLat = lat;
    _selDestLng = lng;
  }

  void _useZone(String zoneName) {
    setState(() {
      if (_isDestFieldActive) {
        _destController.text = zoneName;
        _selDestLat = null;
        _selDestLng = null;
      } else {
        _originController.text = zoneName;
        _selOriginLat = null;
        _selOriginLng = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Hej!",
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          "Hvor skal du hen?",
                          style: TextStyle(
                            color: _primaryColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(Icons.person, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _bgLight,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _CityAutocompleteField(
                      controller: _originController,
                      label: "Fra",
                      icon: Icons.radio_button_checked,
                      hint: "Indtast by eller station",
                      onFocus: () => setState(() => _isDestFieldActive = false),
                      onSelection: _onOriginSelected,
                    ),
                    const Divider(height: 40),
                    _CityAutocompleteField(
                      controller: _destController,
                      label: "Til",
                      icon: Icons.location_on,
                      hint: "Indtast by eller station",
                      onFocus: () => setState(() => _isDestFieldActive = true),
                      onSelection: _onDestSelected,
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Radius: ${_currentRadius.round()} km",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
                          ),
                        ),
                        Icon(Icons.radar, size: 16, color: _accentColor),
                      ],
                    ),
                    Slider(
                      value: _currentRadius,
                      min: 0,
                      max: 50,
                      activeColor: _accentColor,
                      onChanged: (val) => setState(() => _currentRadius = val),
                    ),

                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _smartZones
                            .map(
                              (zone) => Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ActionChip(
                                  label: Text(
                                    zone,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  backgroundColor: Colors.white,
                                  onPressed: () => _useZone(zone),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                    const Divider(height: 40),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.calendar_today, color: _accentColor),
                      title: const Text(
                        "Hvornår?",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      subtitle: Text(
                        _dateDisplayController.text,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _primaryColor,
                        ),
                      ),
                      onTap: () => _pickDate(),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _handleSearch,
                        child: const Text(
                          "Søg efter lift",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback onFocus;
  final Function(String, double?, double?) onSelection;

  const _CityAutocompleteField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onFocus,
    required this.hint,
    required this.onSelection,
  });

  @override
  State<_CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<_CityAutocompleteField> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  final List<String> _prioList = [
    // --- KØBENHAVN & OMREGN (S-tog, Metro & Regional) ---
    "København H",
    "Nørreport St.",
    "Vesterport St.",
    "Østerport St.",
    "Nordhavn St.",
    "Svanemøllen St.",
    "Hellerup St.",
    "Bernstorffsvej St.",
    "Gentofte St.",
    "Vangede St.",
    "Dyssegård St.",
    "Emdrup St.",
    "Ryparken St.",
    "Bispebjerg St.",
    "Nørrebro St.",
    "Fuglebakken St.",
    "Grøndal St.",
    "Flintholm St.",
    "C.F. Richs Vej St.",
    "KB Hallen St.",
    "Ålholm St.",
    "Danshøj St.",
    "Vigerslev Allé St.",
    "København Syd St.",
    "Sydhavn St.",
    "Dybbølsbro St.",
    "Valby St.",
    "Hvidovre St.",
    "Rødovre St.",
    "Brøndbyøster St.",
    "Glostrup St.",
    "Albertslund St.",
    "Taastrup St.",
    "Høje Taastrup St.",
    "Vanløse St.",
    "Jyllingevej St.",
    "Islev St.",
    "Danshøj St.",
    "Herlev St.",
    "Skovlunde St.",
    "Malmparken St.",
    "Ballerup St.",
    "Måløv St.",
    "Kildedal St.",
    "Veksø St.",
    "Stenløse St.",
    "Egedal St.",
    "Ølstykke St.",
    "Frederikssund St.",
    "Åmarken St.",
    "Friheden St.",
    "Avedøre St.",
    "Brøndby Strand St.",
    "Vallensbæk St.",
    "Ishøj St.",
    "Hundige St.",
    "Greve St.",
    "Karlslunde St.",
    "Solrød Strand St.",
    "Jersie St.",
    "Køge Nord St.",
    "Ølby St.",
    "Køge St.",
    "Kildeskov St.",
    "Charlottenlund St.",
    "Ordrup St.",
    "Klampenborg St.",
    "Jægersborg St.",
    "Lyngby St.",
    "Sorgenfri St.",
    "Virum St.",
    "Holte St.",
    "Birkerød St.",
    "Allerød St.",
    "Hillerød St.",
    "Kildebakke St.",
    "Buddinge St.",
    "Stengården St.",
    "Bagsværd St.",
    "Skovbrynet St.",
    "Hareskov St.",
    "Værløse St.",
    "Farum St.",

    // --- SJÆLLAND, LOLLAND & FALSTER (Regional & Lokaltog) ---
    "Hedehusene St.",
    "Roskilde St.",
    "Viby Sjælland St.",
    "Borup St.",
    "Ringsted St.",
    "Sorø St.",
    "Slagelse St.",
    "Korsør St.",
    "Lejre St.",
    "Hvalsø St.",
    "Tølløse St.",
    "Vipperød St.",
    "Holbæk St.",
    "Regstrup St.",
    "Knabstrup St.",
    "Mørkøv St.",
    "Jyderup St.",
    "Svebølle St.",
    "Kalundborg Øst St.",
    "Kalundborg St.",
    "Gadstrup St.",
    "Havdrup St.",
    "Lille Skensved St.",
    "Ølby St.",
    "Herfølge St.",
    "Tureby St.",
    "Haslev St.",
    "Holme-Olstrup St.",
    "Næstved Nord St.",
    "Næstved St.",
    "Lundby St.",
    "Vordingborg St.",
    "Nørre Alslev St.",
    "Eskilstrup St.",
    "Nykøbing F. St.",
    "Øster Toreby St.",
    "Grænge St.",
    "Sakskøbing St.",
    "Maribo St.",
    "Ryde St.",
    "Søllested St.",
    "Avnede St.",
    "Nakskov St.",
    "Gørlev St.",
    "Høng St.",
    "Ruds Vedby St.",
    "Stenlille St.",
    "Dianalund St.",
    "Ny Hagested St.",
    "Gislinge St.",
    "Sandby St.",
    "Svinninge St.",
    "Hørve St.",
    "Fårevejle St.",
    "Asnæs St.",
    "Grevinge St.",
    "Nr. Asmindrup St.",
    "Nykøbing Sj. St.",
    "Snekkersten St.",
    "Espergærde St.",
    "Humlebæk St.",
    "Nivå St.",
    "Kokkedal St.",
    "Rungsted Kyst St.",
    "Vedbæk St.",
    "Skodsborg St.",
    "Grønnehave St.",
    "Marienlyst St.",
    "Hellebæk St.",
    "Ålsgårde St.",
    "Skibstrup St.",
    "Saunte St.",
    "Karinebæk St.",
    "Dronningmølle St.",
    "Firhøj St.",
    "Gilleleje St.",
    "Gribsø St.",
    "Kagerup St.",
    "Mårum St.",
    "Helsinge St.", "Duemose St.", "Vejby St.", "Tisvildeleje St.",

    // --- FYN ---
    "Odense St.",
    "Odense Sygehus St.",
    "Fruens Bøge St.",
    "Hjallese St.",
    "Højby St.",
    "Årslev St.",
    "Pederstrup St.",
    "Ringe St.",
    "Rudme St.",
    "Kværndrup St.",
    "Stenstrup St.",
    "Stenstrup Syd St.",
    "Svendborg Vest St.",
    "Svendborg St.",
    "Nyborg St.",
    "Langeskov St.",
    "Marslev St.",
    "Middelfart St.",
    "Kauslunde St.",
    "Nørre Åby St.",
    "Ejby St.",
    "Gelsted St.",
    "Aarup St.",
    "Bred St.",
    "Skalbjerg St.",
    "Tommerup St.",
    "Holmstrup St.",

    // --- JYLLAND (Hovedbaner & GoCollective) ---
    "Fredericia St.",
    "Taulov St.",
    "Kolding St.",
    "Lunderskov St.",
    "Vejen St.",
    "Brørup St.",
    "Holsted St.",
    "Gørding St.",
    "Bramming St.",
    "Esbjerg St.",
    "Vejle St.",
    "Hedensted St.",
    "Horsens St.",
    "Skanderborg St.",
    "Viby J St.",
    "Aarhus H",
    "Hinnerup St.",
    "Hadsten St.",
    "Langå St.",
    "Randers St.",
    "Hobro St.",
    "Arden St.",
    "Skørping St.",
    "Støvring St.",
    "Svenstrup St.",
    "Skalborg St.",
    "Aalborg St.",
    "Lindholm St.",
    "Brønderslev St.",
    "Vrå St.",
    "Hjørring St.",
    "Sindal St.",
    "Tolne St.",
    "Kvissel St.",
    "Frederikshavn St.",
    "Vojens St.",
    "Rødekro St.",
    "Tinglev St.",
    "Padborg St.",
    "Gråsten St.",
    "Sønderborg St.",
    "Varde St.",
    "Varde Kaserne St.",
    "Varde Nord St.",
    "Guldager St.",
    "Sig St.",
    "Tistrup St.",
    "Ølgod St.",
    "Lyne St.",
    "Tarm St.",
    "Skjern St.",
    "Lem St.",
    "Ringkøbing St.",
    "Heel St.",
    "Tim St.",
    "Ulfborg St.",
    "Vemb St.",
    "Bækmarksbro St.",
    "Lemvig St.",
    "Harboøre St.",
    "Thyborøn St.",
    "Struer St.",
    "Hvidbjerg St.",
    "Oddesund Nord St.",
    "Hurup Thy St.",
    "Bedsted Thy St.",
    "Snedsted St.",
    "Thisted St.",
    "Holstebro St.",
    "Aulum St.",
    "Vildbjerg St.",
    "Herning St.",
    "Herning Messecenter St.",
    "Ikast St.",
    "Bording St.",
    "Engesvang St.",
    "Silkeborg St.",
    "Svejbæk St.",
    "Laven St.",
    "Ry St.",
    "Alken St.",
    "Skive St.",
    "Vinderup St.",
    "Viborg St.",
    "Rødkærsbro St.",
    "Bjerringbro St.",
    "Ulstrup St.",
    "Give St.",
    "Thyregod St.",
    "Brande St.",
    "Gødstrup St.", "Troldhede St.", "Kibæk St.", "Studsgård St.",

    // --- NORDJYSKE JERNBANER ---
    "Hirtshals St.",
    "Emmersbæk St.",
    "Horne St.",
    "Tornby St.",
    "Vidstrup St.",
    "Vellingshøj St.",
    "Hjørring Øst St.",
    "Skagen St.",
    "Frederikshavn St.",
    "Jerup St.",
    "Bunken St.",
    "Hulsig St.",
    "Napstjært St.",
    "Rimmen St.",
    "Strandby St.",

    // --- LETBANE (Aarhus & Odense) ---
    "Dokk1 St.",
    "Skolebakken St.",
    "Østbanetorvet St.",
    "Risskov Strandpark St.",
    "Vestre Strandallé St.",
    "Torsøvej St.",
    "Lystrup St.",
    "Hovmarken St.",
    "Hornslet St.",
    "Mørke St.",
    "Ryomgård St.",
    "Kolind St.",
    "Trustrup St.",
    "Grenaa St.",
    "Aarhus Universitetshospital St.",
    "Skejby St.",
    "Gl. Skejby St.",
    "Humlehuse St.",
    "Lisbjerg St.",
    "Lisbjergskolen St.",
    "Nye St.",
    "Viby J (Letbane)",
    "Gunnar Clausens Vej St.",
    "Tranbjerg St.",
    "Mårslet St.",
    "Beder St.",
    "Mallling St.",
    "Odder St.",
    "Tarup Center St.",
    "Højstrup St.",
    "Bolbro St.",
    "Vestre Stationsvej St.",
    "Kongensgade St.",
    "Albani Torv St.",
    "Bennediks Plads St.",
    "Palnatokesvej St.",
    "Østerbæksvej St.",
    "Cortex Park St.",
    "SDU St.",
    "Hospital Syd St.",

    // --- METRO (Komplet M1-M4) ---
    "Vanløse St.",
    "Flintholm St.",
    "Lindevang St.",
    "Fasanvej St.",
    "Frederiksberg St.",
    "Forum St.",
    "Peblinge Sø St.",
    "Rådhuspladsen St.",
    "Gammel Strand St.",
    "Kongens Nytorv St.",
    "Marmorkirken St.",
    "Østerport St.",
    "Trianglen St.",
    "Poul Henningsens Plads St.",
    "Vibenshus Runddel St.",
    "Skjolds Plads St.",
    "Nørrebro St.",
    "Nuuks Plads St.",
    "Aksel Møllers Have St.",
    "Frederiksberg Allé St.",
    "Enghave Plads St.",
    "København H (Metro)",
    "Havneholmen St.",
    "Enghave Brygge St.",
    "Sluseholmen St.",
    "Mozarts Plads St.",
    "København Syd St. (Metro)",
    "Orientkaj St.",
    "Nordhavn St. (Metro)",
  ];

  Future<void> _fetchSuggestions(String query) async {
    if (query.length < 2) {
      _removeOverlay();
      return;
    }
    List<String> prioMatches = _prioList
        .where((s) => s.toLowerCase().contains(query.toLowerCase()))
        .toList();
    try {
      final url = Uri.parse(
        "https://api.dataforsyningen.dk/adresser/autocomplete?q=$query&per_side=5",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        List<Map<String, dynamic>> results = [];
        for (var p in prioMatches) {
          results.add({'tekst': p, 'forslagstekst': p, 'isPrio': true});
        }
        for (var item in data) {
          results.add(item);
        }
        setState(() {
          _suggestions = results;
        });
        _showOverlay();
      }
    } catch (e) {
      debugPrint("DAWA fejl: $e");
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> selection) async {
    String text = selection['tekst'];
    double? lat;
    double? lng;
    widget.onSelection(text, lat, lng);
    _removeOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    return OverlayEntry(
      builder: (context) => Positioned(
        width: renderBox.size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: Offset(0.0, renderBox.size.height + 5.0),
          child: Material(
            elevation: 8.0,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final item = _suggestions[index];
                bool isPrio = item['isPrio'] == true;
                return ListTile(
                  leading: Icon(
                    isPrio ? Icons.train : Icons.location_on,
                    size: 18,
                    color: isPrio ? const Color(0xFF6366F1) : Colors.grey,
                  ),
                  title: Text(
                    item['tekst'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isPrio ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () => _selectSuggestion(item),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Row(
        children: [
          Icon(widget.icon, color: const Color(0xFF6366F1)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (hasFocus) widget.onFocus();
                    if (!hasFocus)
                      Future.delayed(
                        const Duration(milliseconds: 200),
                        _removeOverlay,
                      );
                  },
                  child: TextField(
                    controller: widget.controller,
                    onChanged: (v) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        () => _fetchSuggestions(v),
                      );
                    },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: widget.hint,
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. RIDES TAB
// ==========================================
class RidesTab extends StatefulWidget {
  final String? filterOrigin;
  final String? filterDest;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final double radius;
  final DateTime? filterDate;
  final VoidCallback onClearFilters;

  const RidesTab({
    super.key,
    this.filterOrigin,
    this.filterDest,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    required this.radius,
    this.filterDate,
    required this.onClearFilters,
  });

  @override
  State<RidesTab> createState() => _RidesTabState();
}

class _RidesTabState extends State<RidesTab> {
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;
  late DateTime _displayDate;

  @override
  void initState() {
    super.initState();
    _displayDate = widget.filterDate ?? DateTime.now();
    _fetchRides();
  }

  @override
  void didUpdateWidget(covariant RidesTab old) {
    super.didUpdateWidget(old);
    if (old.filterOrigin != widget.filterOrigin ||
        old.filterDest != widget.filterDest ||
        old.radius != widget.radius) {
      _displayDate = widget.filterDate ?? DateTime.now();
      _fetchRides();
    }
  }

  void _changeDate(int days) {
    setState(() {
      _displayDate = _displayDate.add(Duration(days: days));
      _fetchRides();
    });
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a =
        0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }

  List<double>? _parsePostGISHex(String? hex) {
    if (hex == null || hex.length < 42) return null;
    try {
      String hexLng = hex.substring(18, 34);
      String hexLat = hex.substring(34, 50);
      return [_hexToDouble(hexLat), _hexToDouble(hexLng)];
    } catch (e) {
      debugPrint("Hex fejl: $e");
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

  Future<void> _fetchRides() async {
    setState(() => _isLoading = true);
    try {
      final startOfDay = DateTime(
        _displayDate.year,
        _displayDate.month,
        _displayDate.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final res = await Supabase.instance.client
          .from('rides')
          .select(
            '*, profiles(*), origin_location::text, destination_location::text',
          )
          .gte('departure_time', startOfDay.toIso8601String())
          .lt('departure_time', endOfDay.toIso8601String())
          .order('departure_time', ascending: true);

      List<Map<String, dynamic>> allRides = List<Map<String, dynamic>>.from(
        res,
      );
      List<Map<String, dynamic>> filteredRides = [];

      bool hasSearchCoords = widget.originLat != null && widget.destLat != null;

      if (hasSearchCoords) {
        for (var ride in allRides) {
          List<double>? rideOrigin = _parsePostGISHex(ride['origin_location']);
          List<double>? rideDest = _parsePostGISHex(
            ride['destination_location'],
          );

          if (rideOrigin != null && rideDest != null) {
            double dStart = _calculateDistance(
              widget.originLat!,
              widget.originLng!,
              rideOrigin[0],
              rideOrigin[1],
            );
            double dSlut = _calculateDistance(
              widget.destLat!,
              widget.destLng!,
              rideDest[0],
              rideDest[1],
            );

            if (dStart <= widget.radius && dSlut <= widget.radius) {
              filteredRides.add(ride);
            }
          }
        }
      } else {
        filteredRides = allRides;
      }

      if (mounted)
        setState(() {
          _rides = filteredRides;
          _isLoading = false;
        });
    } catch (e) {
      debugPrint("Fejl: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = const Color(0xFF0F172A);
    bool isSearching = widget.filterOrigin != null || widget.filterDest != null;

    String headerDateText = DateFormat('dd/MM/yyyy').format(_displayDate);
    final now = DateTime.now();
    if (DateTime(now.year, now.month, now.day) ==
        DateTime(_displayDate.year, _displayDate.month, _displayDate.day))
      headerDateText = "I dag";
    else if (DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1)) ==
        DateTime(_displayDate.year, _displayDate.month, _displayDate.day))
      headerDateText = "I morgen";

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          isSearching ? "Resultater (${widget.radius.round()}km)" : "Alle Lift",
          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isSearching)
            TextButton(
              onPressed: widget.onClearFilters,
              child: const Text("Nulstil", style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeDate(-1),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    headerDateText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeDate(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _rides.isEmpty
                ? const Center(child: Text("Ingen lift fundet"))
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _rides.length,
                    itemBuilder: (context, index) =>
                        _buildRideCard(_rides[index], primaryColor),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride, Color primaryColor) {
    final depTime = DateTime.parse(ride['departure_time']).toLocal();
    final driver = ride['profiles'];
    final accentColor = const Color(0xFF6366F1);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${DateFormat('dd/MM/yyyy').format(depTime)} • ${DateFormat('HH:mm').format(depTime)}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: primaryColor,
                    ),
                  ),
                  Text(
                    "${ride['price_dkk']} kr.",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          border: Border.all(color: accentColor, width: 2),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(width: 2, height: 25, color: Colors.grey[200]),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride['origin_city'].split(',')[0],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          ride['destination_city'].split(',')[0],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 15),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: driver['avatar_url'] != null
                        ? NetworkImage(driver['avatar_url'])
                        : null,
                    child: driver['avatar_url'] == null
                        ? Text(driver['full_name'][0])
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    driver['full_name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (ride['instant_booking'] == true)
                    const Icon(Icons.bolt, color: Colors.amber, size: 20),
                  Builder(
                    builder: (context) {
                      try {
                        final car = jsonDecode(ride['car_model']);
                        return Text(
                          car['make'] ?? 'Bil',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      } catch (_) {
                        return Text(
                          ride['car_model'] ?? 'Bil',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
