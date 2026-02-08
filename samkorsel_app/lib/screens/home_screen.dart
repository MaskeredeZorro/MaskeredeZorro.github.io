import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle; // VIGTIGT: Til at læse JSON filen
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../features/rides/create_ride_screen.dart';
import '../features/rides/ride_detail_screen.dart';
import '../features/flexible_search/flexible_map_screen.dart';
import '../../services/sms_service.dart'; // Tjek at stien passer
import '../screens/verification_screen.dart'; // Tjek at stien passer
import 'profile_screen.dart';
import '/screens/messages_screen.dart';
import 'package:flutter/cupertino.dart'; // REQUIRED for iOS pickers
import '../services/notification_service.dart'; // Justér stien så den passer til din filstruktur

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _isDriver = false;

  @override
  void initState() {
    super.initState();
    _checkDriverStatus(); // Tjek ved start
    NotificationService.initialize();
  }

  // --- NY FUNKTION: HENT CHAUFFØR STATUS ---
  Future<void> _checkDriverStatus() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_driver')
          .eq('id', userId)
          .single();

      if (mounted) {
        setState(() {
          _isDriver = data['is_driver'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Kunne ikke hente driver status: $e");
    }
  }

  // --- SØGE LOGIK ---
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RidesTab(
          filterOrigin: origin,
          filterDest: dest,
          originLat: oLat,
          originLng: oLng,
          destLat: dLat,
          destLng: dLng,
          radius: radius,
          filterDate: date,
          onClearFilters: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _onTabTapped(int index) async {
    if (index == 1) {
      // 1. Tjek status
      await _checkDriverStatus();

      // 2. HVIS IKKE CHAUFFØR -> VIS POPUP
      if (!_isDriver) {
        if (!mounted) return;

        showModalBottomSheet(
          context: context,
          isScrollControlled: true, // Vigtigt for at tastaturet ikke dækker
          backgroundColor: Colors.transparent,
          builder: (context) => BecomeDriverSheet(
            onSuccess: () async {
              // Når de har gemt data succesfuldt:
              Navigator.pop(context); // Luk sheet
              await _checkDriverStatus(); // Opdater status lokalt
              // Naviger til Opret Tur
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateRideScreen()),
                );
              }
            },
          ),
        );
        return;
      }

      // 3. HVIS ALLEREDE CHAUFFØR -> NAVIGER DIREKTE
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
    final Color inactiveColor = Colors.grey.shade400;

    final List<Widget> pages = [
      SearchTab(onSearch: _performSearch), // Index 0
      const SizedBox(), // Index 1 (Placeholder for Opret)
      const MessagesScreen(), // Index 2
      const ProfileScreen(), // Index 3
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        // Tilføjer en fin skygge i toppen af baren for et moderne look
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType
              .fixed, // Vigtigt for at teksten altid vises
          backgroundColor: Colors.white,
          elevation: 0, // Vi bruger vores egen skygge ovenover
          // --- MODERN TYPOGRAFI ---
          selectedItemColor: activeColor,
          unselectedItemColor: inactiveColor,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 12,
          ),

          items: [
            // 1. SØG
            const BottomNavigationBarItem(
              icon: Icon(Icons.search),
              activeIcon: Icon(Icons.search, size: 26), // Lidt større når aktiv
              label: "Søg",
            ),

            // 2. OPRET (Nu ren og pæn)
            BottomNavigationBarItem(
              // Vi bruger et "Add Circle" ikon for at vise handling
              icon: Icon(Icons.add_circle_outline, size: 28),
              activeIcon: Icon(Icons.add_circle, size: 28),
              label: "Opret",
            ),

            // 3. BESKEDER
            const BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: "Beskeder",
            ),

            // 4. PROFIL
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: "Profil",
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// NY WIDGET: BECOME DRIVER POPUP
// ==========================================
class BecomeDriverSheet extends StatefulWidget {
  final VoidCallback onSuccess;
  const BecomeDriverSheet({super.key, required this.onSuccess});

  @override
  State<BecomeDriverSheet> createState() => _BecomeDriverSheetState();
}

class _BecomeDriverSheetState extends State<BecomeDriverSheet> {
  bool _isDriverToggle = false;
  bool _isLoading = false;
  bool _isFetchingCar = false;

  final _plateCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();

  // 1. NY CONTROLLER TIL TELEFON
  final _phoneCtrl = TextEditingController();

  // API Opslag (Uændret)
  Future<void> _fetchCarFromApi() async {
    String plate = _plateCtrl.text.replaceAll(' ', '').trim();
    if (plate.length < 2) return;

    setState(() => _isFetchingCar = true);
    try {
      const String apiKey = "7dzgmx0qvnjtwwza0bkpu307k47yrjyq";
      final url = Uri.parse("https://v1.motorapi.dk/vehicles/$plate");
      final response = await http.get(url, headers: {'X-Auth-Token': apiKey});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _makeCtrl.text = (data['make'] ?? "").toString();
          _modelCtrl.text = (data['model'] ?? "").toString();
          _yearCtrl.text = (data['model_year'] ?? "").toString();
          _colorCtrl.text = (data['color'] ?? "").toString();
          if (data['registration_number'] != null) {
            _plateCtrl.text = data['registration_number'];
          }
        });
      }
    } catch (e) {
      debugPrint("Fejl: $e");
    } finally {
      setState(() => _isFetchingCar = false);
    }
  }

  Future<void> _saveAndContinue() async {
    if (_isLoading) return;
    if (!_isDriverToggle) return;

    // 2. TJEK AT TELEFON ER INDTASTET
    final String phone = _phoneCtrl.text.trim();
    if (phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Indtast venligst et gyldigt telefonnummer (min. 8 cifre).",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_makeCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Hent venligst dine biloplysninger først."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 3. BYG BIL-DATA (Men gem ikke i DB endnu!)
      final carJson = {
        'make': _makeCtrl.text,
        'model': _modelCtrl.text,
        'year': _yearCtrl.text,
        'color': _colorCtrl.text,
        'plate': _plateCtrl.text,
        'details':
            "${_yearCtrl.text} • ${_colorCtrl.text} • ${_plateCtrl.text}",
        'display_name': "${_makeCtrl.text} ${_modelCtrl.text}",
      };

      // 4. GENERER SMS KODE & GEM I DB
      final String code = (math.Random().nextInt(900000) + 100000).toString();

      await Supabase.instance.client.from('sms_verifications').insert({
        'user_id': user.id,
        'code': code,
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
      });

      // 5. SEND SMS
      final smsService = SmsService();
      final success = await smsService.sendVerificationCode(phone, code);

      if (success && mounted) {
        Navigator.pop(context); // Luk sheetet

        // 6. GÅ TIL VERIFICATION SCREEN MED DATA
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationScreen(
              phoneNumber: phone,
              email: user.email ?? "",
              // Vi sender data med, så VerificationScreen kan gemme det hele til sidst
              isBecomingDriver: true,
              licensePlate: _plateCtrl.text,
              carDetails: carJson,
            ),
          ),
        );
      } else {
        throw "Kunne ikke sende SMS. Prøv igen.";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fejl: $e")));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Bliv Chauffør 🚘",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "For at oprette ture skal vi verificere dit nummer og registrere din bil.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Vil du blive chauffør?",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Switch(
                  value: _isDriverToggle,
                  onChanged: (val) => setState(() => _isDriverToggle = val),
                  activeColor: const Color(0xFF6366F1),
                ),
              ],
            ),
            const Text(
              "Slå til for at starte processen.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),

            if (_isDriverToggle) ...[
              const SizedBox(height: 20),

              // 7. NYT: TELEFON FELT I UI
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Telefonnummer *",
                  prefixIcon: const Icon(
                    Icons.phone_android,
                    color: Colors.grey,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // BIL FELT
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: "Nummerplade *",
                        prefixIcon: const Icon(
                          Icons.confirmation_number,
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isFetchingCar ? null : _fetchCarFromApi,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isFetchingCar
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search, size: 18),
                      label: const Text("Hent"),
                    ),
                  ),
                ],
              ),

              if (_makeCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "${_makeCtrl.text} ${_modelCtrl.text} (${_yearCtrl.text})",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isDriverToggle && !_isLoading
                    ? _saveAndContinue
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Verificer & Opret Tur",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ==========================================
// 1. SEARCH TAB (OPDATERET MED FLEKSIBEL SØGNING)
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
  // Controllere
  final _originController = TextEditingController();
  final _destController = TextEditingController();
  final _flexZipController = TextEditingController(); // NY: Til postnummer

  double? _selOriginLat;
  double? _selOriginLng;
  double? _selDestLat;
  double? _selDestLng;

  double _currentRadius = 20.0;
  bool _isDestFieldActive = false;
  DateTime _selectedDate = DateTime.now();
  // TimeOfDay _selectedTime = TimeOfDay.now(); // Denne kan vi undvære nu, da DateTime indeholder tid

  final _dateDisplayController = TextEditingController(
    text: DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), // Nu med tid
  );

  // Variabel til at gemme stationsdata fra JSON
  Map<String, dynamic> _stationData = {};

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

  @override
  void initState() {
    super.initState();
    _loadStations(); // Indlæs JSON filen ved start
  }

  // Indlæser filen fra assets/station_taxa.json
  Future<void> _loadStations() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/station_taxa.json',
      );
      setState(() {
        _stationData = json.decode(response);
      });
    } catch (e) {
      print("⚠️ Fejl ved indlæsning af stationer: $e");
    }
  }

  // --- NY FUNKTION: GÅ TIL KORTET ---
  void _goToFlexibleMap() {
    String zip = _flexZipController.text.trim();
    if (zip.length != 4 || int.tryParse(zip) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Indtast venligst et 4-cifret postnummer"),
        ),
      );
      return;
    }

    // Naviger til den nye skærm
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FlexibleMapScreen(zipCode: zip)),
    );
  }

  void _pickDate() {
    final DateTime now = DateTime.now();

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
              _buildPickerHeader(context),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  // Sikrer at vi starter på nuværende tidspunkt eller valgte (hvis fremtid)
                  initialDateTime: _selectedDate.isBefore(now)
                      ? now
                      : _selectedDate,
                  // Forhindrer scrolling tilbage i tid (på dato niveau)
                  minimumDate: DateTime(
                    now.year,
                    now.month,
                    now.day,
                    now.hour,
                    now.minute,
                  ),
                  onDateTimeChanged: (DateTime newDateTime) {
                    // Ekstra sikkerhedstjek
                    if (newDateTime.isBefore(now)) {
                      setState(() {
                        _selectedDate = now;
                        _dateDisplayController.text = DateFormat(
                          'dd/MM/yyyy HH:mm',
                        ).format(now);
                      });
                    } else {
                      setState(() {
                        _selectedDate = newDateTime;
                        _dateDisplayController.text = DateFormat(
                          'dd/MM/yyyy HH:mm',
                        ).format(newDateTime);
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSearch() async {
    // --- RETTELSE START: Tjek om felterne er udfyldt ---
    if (_originController.text.trim().isEmpty ||
        _destController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Du skal udfylde både Fra og Til"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // --- RETTELSE SLUT ---

    final results = await Future.wait([
      _fetchCityCoords(_originController.text),
      _fetchCityCoords(_destController.text),
    ]);

    final startCoords = results[0];
    final endCoords = results[1];

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

  // --- HYBRID FETCH LOGIK (Din "gode" søgning) ---
  Future<List<double>?> _fetchCityCoords(String query) async {
    if (query.isEmpty) return null;

    // TRIN 1: JSON
    if (_stationData.containsKey(query)) {
      final station = _stationData[query];
      return [
        (station['lat'] as num).toDouble(),
        (station['lng'] as num).toDouble(),
      ];
    }

    // TRIN 2: MAPBOX
    const String mapboxAccessToken =
        'pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w';
    String optimizedQuery = "$query, Denmark";

    try {
      final url = Uri.parse(
        "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(optimizedQuery)}.json?access_token=$mapboxAccessToken&country=dk&limit=1&types=place,locality,neighborhood,address,poi",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final coords = feature['center'];
          return [coords[1].toDouble(), coords[0].toDouble()];
        }
      }
    } catch (e) {
      debugPrint("Mapbox Fejl: $e");
    }
    return null;
  }

  // ... (Dine andre små hjælpemetoder beholdes her) ...
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

              // --- NY KORT-BOKS: SØG FLEKSIBELT ---
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                height: 150,
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(24),
                  image: const DecorationImage(
                    // HUSK AT HAVE DETTE BILLEDE I ASSETS!
                    image: AssetImage('assets/map_pattern.png'),
                    fit: BoxFit.cover,
                    opacity: 0.2, // Gør det lidt svagt så teksten kan ses
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryColor.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Søg fleksibelt fra dit område",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "Alle ture har afgang fra dit postnr.",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 50,
                              alignment: Alignment
                                  .center, // Hjælper med at centrere selve TextField i Containeren
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              child: TextField(
                                controller: _flexZipController,
                                keyboardType: TextInputType.number,
                                textAlignVertical: TextAlignVertical
                                    .center, // <--- VIGTIGT: Centrerer teksten lodret
                                decoration: const InputDecoration(
                                  isCollapsed:
                                      true, // Fjerner unødvendig standard-højde
                                  contentPadding:
                                      EdgeInsets.zero, // Fjerner intern padding
                                  hintText: "Postnr. (fx 8000)",
                                  border: InputBorder.none,
                                  // Jeg har ændret 'icon' til 'prefixIcon' for bedre centrering
                                  prefixIcon: Icon(
                                    Icons.location_searching,
                                    color: Colors.grey,
                                  ),
                                  // Hvis du vil have ikonet tættere på kanten eller teksten,
                                  // kan du justere constraints:
                                  prefixIconConstraints: BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _goToFlexibleMap,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // --- SØG DIREKTE (Gammel formular) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  "Søg direkte", // <--- RETTET TITEL
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),

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
                    // ... Slider og Dato widgets her (kopieret fra din gamle kode) ...
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

                    // (Husk også SmartZones og Dato picker herunder fra din originale fil)
                    const SizedBox(height: 30),

                    _buildSearchOption(
                      label: "Hvornår skal du afsted?",
                      icon: Icons.calendar_month,
                      controller: _dateDisplayController,
                      onTap: _pickDate,
                    ),
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () =>
                Navigator.pop(context), // Nu bruger den context fra argumentet
            child: const Text(
              "Færdig",
              style: TextStyle(
                color: Color(0xFF6366F1), // Indsat farveværdi direkte (Accent)
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchOption({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: _accentColor, size: 22),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                Text(
                  controller.text,
                  style: TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildPickerHeader(BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text(
            "Færdig",
            style: TextStyle(
              color: Color(0xFF6366F1), // Farven er nu hardcoded
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildSearchOption({
  required String label,
  required IconData icon,
  required TextEditingController controller,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff6366f1), size: 22),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              Text(
                controller.text,
                style: TextStyle(
                  color: Color(0xff0f172a),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
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

  // Din liste (sørg for at navnene matcher dem i JSON filen præcist)
  final List<String> _prioList = [
    // --- KØBENHAVN & OMREGN ---
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

    // --- SJÆLLAND, LOLLAND & FALSTER ---
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
    "Helsinge St.",
    "Duemose St.",
    "Vejby St.",
    "Tisvildeleje St.",

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

    // --- JYLLAND ---
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
    "Gødstrup St.",
    "Troldhede St.",
    "Kibæk St.",
    "Studsgård St.",

    // --- NORDJYSKE JERNBANER ---
    "Hirtshals St.",
    "Emmersbæk St.",
    "Horne St.",
    "Tornby St.",
    "Vidstrup St.",
    "Vellingshøj St.",
    "Hjørring Øst St.",
    "Skagen St.",
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
    "Fasanvej St.",
    "Frederiksberg St.",
    "Forum St.",
    "Peblinge Sø St.",
    "Rådhuspladsen St.",
    "Gammel Strand St.",
    "Kongens Nytorv St.",
    "Marmorkirken St.",
    "Trianglen St.",
    "Poul Henningsens Plads St.",
    "Vibenshus Runddel St.",
    "Skjolds Plads St.",
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

    // 1. Filtrer din lokale prioriteringsliste
    List<String> prioMatches = _prioList
        .where((s) => s.toLowerCase().contains(query.toLowerCase()))
        .toList();

    const String mapboxAccessToken =
        'pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w';

    try {
      // 2. Hent adresseforslag fra Mapbox (for adresser der ikke er stationer)
      final url = Uri.parse(
        "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=$mapboxAccessToken&country=dk&autocomplete=true&limit=5&types=place,locality,neighborhood,address,poi",
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        List<Map<String, dynamic>> results = [];

        // A. Tilføj stationer fra din liste FØRST
        for (var p in prioMatches) {
          results.add({'tekst': p, 'isPrio': true});
        }

        // B. Tilføj Mapbox resultater bagefter
        for (var feature in features) {
          results.add({'tekst': feature['place_name'], 'isPrio': false});
        }

        setState(() {
          _suggestions = results;
        });
        _showOverlay();
      }
    } catch (e) {
      debugPrint("Mapbox Suggestion Fejl: $e");
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> selection) async {
    String text = selection['tekst'];
    // Bemærk: Vi sender ikke koordinater med herfra længere, da _fetchCityCoords
    // i SearchTab håndterer det via JSON-opslaget eller Mapbox.
    widget.onSelection(text, null, null);
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
                    if (!hasFocus) {
                      Future.delayed(
                        const Duration(milliseconds: 200),
                        _removeOverlay,
                      );
                    }
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
  String? _myGender;

  @override
  void initState() {
    super.initState();
    // Sætter startdatoen til det man søgte på, eller NU.
    _displayDate = widget.filterDate ?? DateTime.now();
    _initData();
  }

  // --- NY FUNKTION: HENT KØN FØRST ---
  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('gender')
            .eq('id', userId)
            .single();
        _myGender = data['gender']; // Fx "Kvinde" eller "Mand"
      }
    } catch (e) {
      debugPrint("Kunne ikke hente køn: $e");
    }
    await _fetchRides();
  }

  @override
  void didUpdateWidget(covariant RidesTab old) {
    super.didUpdateWidget(old);
    // Hvis søgekriterierne udefra ændrer sig (ny søgning), skal vi nulstille _displayDate
    if (old.filterOrigin != widget.filterOrigin ||
        old.filterDest != widget.filterDest ||
        old.radius != widget.radius ||
        old.filterDate != widget.filterDate) {
      // <--- Tjek også datoen

      setState(() {
        _displayDate = widget.filterDate ?? DateTime.now();
      });
      _fetchRides();
    }
  }

  void _changeDate(int days) {
    setState(() {
      _displayDate = _displayDate.add(Duration(days: days));
      // Vi kalder fetch igen, og nu bruger den den nye _displayDate
      _fetchRides();
    });
  }

  // ... (Behold _calculateDistance, _parsePostGISHex og _hexToDouble som de er) ...
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
  // ... (Slut på hjælpemetoder) ...

  Future<void> _fetchRides() async {
    setState(() => _isLoading = true);
    try {
      // --- RETTELSE HER: Brug _displayDate i stedet for widget.filterDate ---
      // Før brugte du widget.filterDate, som altid var den oprindelige søgedato.
      // Nu bruger vi _displayDate, som opdateres af pilene.
      final DateTime searchThresholdLocal = _displayDate;

      // 2. Find slutningen af det lokale døgn for den viste dato
      final DateTime startOfDayLocal = DateTime(
        searchThresholdLocal.year,
        searchThresholdLocal.month,
        searchThresholdLocal.day,
      );

      final DateTime endOfDayLocal = startOfDayLocal.add(
        const Duration(days: 1),
      );

      // 3. Konverter til UTC til databasen
      // Vi søger fra start af dagen (00:00) til slut af dagen (23:59) for den valgte dato
      final String startUTC = startOfDayLocal.toUtc().toIso8601String();
      final String endUTC = endOfDayLocal.toUtc().toIso8601String();

      final res = await Supabase.instance.client
          .from('rides')
          .select(
            '*, profiles(*), origin_location::text, destination_location::text',
          )
          .gte('departure_time', startUTC)
          .lt('departure_time', endUTC)
          .order('departure_time', ascending: true);

      List<Map<String, dynamic>> allRides = List<Map<String, dynamic>>.from(
        res,
      );
      List<Map<String, dynamic>> filteredRides = [];

      bool hasSearchCoords = widget.originLat != null && widget.destLat != null;

      for (var ride in allRides) {
        // 1. LADIES ONLY TJEK
        bool isLadiesOnly = ride['ladies_only'] ?? false;
        if (isLadiesOnly && _myGender != 'Kvinde') {
          continue; // Spring over hvis du er mand og turen er ladies only
        }

        // 2. GEOGRAFI TJEK (Hvis søgt)
        if (hasSearchCoords) {
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
        } else {
          // Hvis ingen geografi-søgning, tilføj bare (køn er tjekket)
          filteredRides.add(ride);
        }
      }

      if (mounted) {
        setState(() {
          _rides = filteredRides;
          _isLoading = false;
        });
      }
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

    // Tjek for "I dag" og "I morgen" logik
    final today = DateTime(now.year, now.month, now.day);
    final displayDay = DateTime(
      _displayDate.year,
      _displayDate.month,
      _displayDate.day,
    );

    if (displayDay == today) {
      headerDateText = "I dag";
    } else if (displayDay == today.add(const Duration(days: 1))) {
      headerDateText = "I morgen";
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(color: primaryColor),
        title: Text(
          isSearching
              ? "Resultater (${widget.radius.round()}km)"
              : "Søgeresultater",
          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isSearching)
            TextButton(
              onPressed: widget.onClearFilters,
              child: const Text("Luk", style: TextStyle(color: Colors.red)),
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
                ? const Center(child: Text("Ingen lift fundet på denne dato"))
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

  // ... (Behold _buildRideCard præcis som den var i din gamle kode) ...
  Widget _buildRideCard(Map<String, dynamic> ride, Color primaryColor) {
    final depTime = DateTime.parse(ride['departure_time']).toLocal();
    final driver = ride['profiles'];
    final accentColor = const Color(0xFF6366F1);

    // Tjek om det er ladies only
    final bool isLadiesOnly = ride['ladies_only'] ?? false;

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
          // --- NYT: Lyserød kant hvis Ladies Only ---
          border: isLadiesOnly
              ? Border.all(color: Colors.pink.shade200, width: 1.5)
              : Border.all(color: Colors.grey.shade100),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- NYT: LADIES ONLY SKILT ---
              if (isLadiesOnly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.pink.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.female, size: 16, color: Colors.pink),
                        const SizedBox(width: 4),
                        const Text(
                          "Ladies Only",
                          style: TextStyle(
                            color: Colors.pink,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // -----------------------------
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
              // ... (Resten er uændret - Rute visning) ...
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
