import 'dart:convert';
import 'package:flutter/cupertino.dart'; // Til iOS pickers
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../widgets/address_search_field.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

// Model til at holde en specifik tur-instans (Dato + tider for start, slut og waypoints)
class RideInstance {
  DateTime date;
  TimeOfDay depTime;
  TimeOfDay arrTime;
  // Map der gemmer tidspunkt for hvert mellemstop (Index -> Tid)
  Map<int, TimeOfDay> waypointTimes;

  RideInstance({
    required this.date,
    required this.depTime,
    required this.arrTime,
    Map<int, TimeOfDay>? waypointTimes,
  }) : waypointTimes = waypointTimes ?? {};
}

// Model til selve mellemstoppet (Kun sted, ikke tid, da tid nu er per dato)
class WaypointDefinition {
  String? city;
  Map<String, double>? coords;
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  // --- Globale Rute Variabler ---
  String? _origin;
  String? _destination;

  // Listen af byer vi stopper i (uden tider)
  final List<WaypointDefinition> _waypoints = [];

  // Listen af faktiske ture (Datoer og specifikke tider)
  final List<RideInstance> _rideInstances = [];

  // Controllers
  final _seatsController = TextEditingController(text: "3");
  final _priceController = TextEditingController();
  final _commentController = TextEditingController();

  // Switches
  bool _isRecurring = false;
  bool _isFerry = false;
  bool _detourFlex = true;
  bool _comfortGuarantee = false;
  bool _instantBooking = false;
  bool _ladiesOnly = false;
  String _luggageSize = 'Mellem';

  // Præferencer
  bool _prefMusic = true;
  bool _prefPets = false;
  bool _prefSmoking = false;
  bool _prefKids = true;

  bool _isLoading = false;
  Map<String, dynamic> _stationData = {};

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _accentColor = const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _loadStations();
    // Opret en standard tur (i dag, nu, +1 time)
    _addRideInstance(initial: true);
  }

  void _addRideInstance({bool initial = false}) {
    final now = DateTime.now();
    final nextHour = TimeOfDay(hour: now.hour + 1, minute: 0);
    final arrival = TimeOfDay(hour: now.hour + 2, minute: 0);

    // Hvis vi tilføjer en ny, og der allerede findes en, kopier tiderne fra den forrige (UX feature)
    TimeOfDay defaultDep = nextHour;
    TimeOfDay defaultArr = arrival;
    Map<int, TimeOfDay> defaultWaypoints = {};

    if (!initial && _rideInstances.isNotEmpty) {
      final last = _rideInstances.last;
      defaultDep = last.depTime;
      defaultArr = last.arrTime;
      defaultWaypoints = Map.from(
        last.waypointTimes,
      ); // Kopier mellemstop tider
    }

    setState(() {
      _rideInstances.add(
        RideInstance(
          date: now.add(
            Duration(days: initial ? 0 : _rideInstances.length),
          ), // Læg en dag til for hver ny linje
          depTime: defaultDep,
          arrTime: defaultArr,
          waypointTimes: defaultWaypoints,
        ),
      );
    });
  }

  void _removeRideInstance(int index) {
    if (_rideInstances.length > 1) {
      setState(() {
        _rideInstances.removeAt(index);
      });
    }
  }

  // Tilføj et mellemstop (Globalt for ruten)
  void _addWaypoint() {
    setState(() {
      _waypoints.add(WaypointDefinition());
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
      // Ryd op i tiderne for alle instances
      for (var ride in _rideInstances) {
        ride.waypointTimes.remove(index);
      }
    });
  }

  Future<void> _loadStations() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/station_taxa.json',
      );
      setState(() {
        _stationData = json.decode(response);
      });
    } catch (e) {
      debugPrint("⚠️ CreateRide: Kunne ikke indlæse stationer.");
    }
  }

  // --- OPRET TUR LOGIK (MED KOMBINATORIK) ---
  Future<void> _createRide() async {
    if (_origin == null ||
        _destination == null ||
        _priceController.text.isEmpty) {
      _showError("Udfyld venligst rute og pris.");
      return;
    }

    // Tjek at mellemstops har bynavne
    for (var wp in _waypoints) {
      if (wp.city == null) {
        _showError("Vælg by for alle mellemstops.");
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("Log ind først.");

      // 1. Hent bilmodel & Geo-kordinater til ALLE punkter først
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('car_details')
          .eq('id', user.id)
          .single();
      final carModel = profile['car_details'] ?? "Min Bil";

      final originCoords = await _getCityCoordinates(_origin!);
      final destCoords = await _getCityCoordinates(_destination!);

      if (originCoords == null || destCoords == null)
        throw Exception("Kunne ikke finde start/slut koordinater.");

      // Hent koordinater for waypoints og gem dem i waypoints listen
      for (var wp in _waypoints) {
        wp.coords = await _getCityCoordinates(wp.city!);
        if (wp.coords == null)
          throw Exception("Kunne ikke finde koordinater for ${wp.city}");
      }

      // 2. Loop gennem hver dato (Instance)
      final instancesToCreate = _isRecurring
          ? _rideInstances
          : [_rideInstances.first];

      for (var instance in instancesToCreate) {
        // 3. BYG RUTEN TIL KOMBINATORIK
        // Vi laver en midlertidig liste over alle stop på denne tur med deres specifikke tider
        List<Map<String, dynamic>> routePoints = [];

        // Startpunkt
        routePoints.add({
          'city': _origin,
          'coords': originCoords,
          'time': instance.depTime,
          'type': 'origin',
        });

        // Mellemstops
        for (int i = 0; i < _waypoints.length; i++) {
          // Hent tid for dette stop (eller brug fallback)
          final time =
              instance.waypointTimes[i] ??
              TimeOfDay(
                hour: instance.depTime.hour + 1,
                minute: instance.depTime.minute,
              );

          routePoints.add({
            'city': _waypoints[i].city,
            'coords': _waypoints[i].coords,
            'time': time,
            'type': 'waypoint',
          });
        }

        // Slutpunkt
        routePoints.add({
          'city': _destination,
          'coords': destCoords,
          'time': instance.arrTime,
          'type': 'destination',
        });

        // 4. GENERER ALLE KOMBINATIONER (Double Loop)
        // A->B, A->C, B->C osv.
        for (int i = 0; i < routePoints.length - 1; i++) {
          for (int j = i + 1; j < routePoints.length; j++) {
            final fromPoint = routePoints[i];
            final toPoint = routePoints[j];

            // Tjek om det er HOVEDTUREN (Start til Slut)
            // Vi gemmer kun waypoints-JSON på hovedturen for at undgå rod i display
            bool isMainRide = (i == 0 && j == routePoints.length - 1);

            List<Map<String, dynamic>> waypointsJson = [];
            if (isMainRide) {
              // Byg JSON kun til hovedturen
              for (int k = 0; k < _waypoints.length; k++) {
                final wp = _waypoints[k];
                final t = instance.waypointTimes[k] ?? instance.depTime;
                waypointsJson.add({
                  'city': wp.city,
                  'lat': wp.coords!['lat'],
                  'lng': wp.coords!['lng'],
                  'departure_time':
                      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}",
                });
              }
            }

            // Beregn tider
            final startDateTime = _combineDateAndTime(
              instance.date,
              fromPoint['time'],
            );
            var endDateTime = _combineDateAndTime(
              instance.date,
              toPoint['time'],
            );

            if (endDateTime.isBefore(startDateTime)) {
              endDateTime = endDateTime.add(const Duration(days: 1));
            }

            // Indsæt som SELVSTÆNDIG tur i databasen
            await Supabase.instance.client.from('rides').insert({
              'driver_id': user.id,
              'origin_city': fromPoint['city'],
              'destination_city': toPoint['city'],
              'origin_location':
                  'POINT(${fromPoint['coords']['lng']} ${fromPoint['coords']['lat']})',
              'destination_location':
                  'POINT(${toPoint['coords']['lng']} ${toPoint['coords']['lat']})',
              'departure_time': startDateTime.toUtc().toIso8601String(),
              'arrival_time': endDateTime.toUtc().toIso8601String(),
              'seats_available': int.parse(_seatsController.text),
              'price_dkk': int.parse(
                _priceController.text,
              ), // NB: Samme pris for alle segmenter (indtil videre)
              'car_model': carModel,
              'status': 'active',
              'is_ferry': _isFerry,
              'detour_flex': _detourFlex,
              'instant_booking': _instantBooking,
              'ladies_only': _ladiesOnly,
              'luggage_size': _luggageSize,
              'comfort_guarantee': _comfortGuarantee,
              'pref_music': _prefMusic,
              'pref_pets': _prefPets,
              'pref_smoking': _prefSmoking,
              'pref_kids': _prefKids,
              'comment': _commentController.text,
              'waypoints': waypointsJson, // Kun hovedturen får JSON data
            });
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Turene er oprettet! 🚀"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError("Fejl: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- iOS STYLE PICKERS ---

  void _showIOSDatePicker(RideInstance instance) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              _buildPickerHeader(),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: instance.date,
                  minimumDate: DateTime.now().subtract(const Duration(days: 1)),
                  maximumDate: DateTime(2030),
                  onDateTimeChanged: (val) {
                    setState(() => instance.date = val);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showIOSTimePicker(TimeOfDay current, Function(TimeOfDay) onSelected) {
    final now = DateTime.now();
    final initial = DateTime(
      now.year,
      now.month,
      now.day,
      current.hour,
      current.minute,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              _buildPickerHeader(),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: initial,
                  onDateTimeChanged: (val) {
                    onSelected(TimeOfDay(hour: val.hour, minute: val.minute));
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPickerHeader() {
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
            child: Text(
              "Færdig",
              style: TextStyle(
                color: _accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI BYGGEKLODSER ---

  @override
  // --- NY WIDGET TIL HUSREGLER KNAPPER ---
  Widget _buildRuleButton(String label, bool isAllowed, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            // Grøn baggrund hvis true, Rød baggrund hvis false
            color: isAllowed
                ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              // Grøn kant hvis true, Rød kant hvis false
              color: isAllowed
                  ? Colors.green.withOpacity(0.3)
                  : Colors.red.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, // Centrer indholdet
            children: [
              Icon(
                isAllowed ? Icons.check_circle : Icons.cancel,
                color: isAllowed ? Colors.green : Colors.red.shade300,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  // Mørk tekst hvis tilladt, grå tekst hvis forbudt (som på billedet)
                  color: isAllowed
                      ? const Color(0xFF0F172A)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _isRecurring ? "Opret Turer" : "Opret Tur",
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
                // RUTE
                _buildSectionTitle("Ruten"),
                AddressSearchField(
                  label: "Hvor kører du fra?",
                  onSelected: (val) => setState(() => _origin = val),
                ),
                const SizedBox(height: 10),

                // Mellemstops (Kun bynavne her)
                ...List.generate(_waypoints.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AddressSearchField(
                            label: "Tilføj mellemstop by",
                            onSelected: (val) =>
                                setState(() => _waypoints[index].city = val),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => _removeWaypoint(index),
                        ),
                      ],
                    ),
                  );
                }),

                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addWaypoint,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Tilføj mellemstop"),
                    style: TextButton.styleFrom(foregroundColor: _accentColor),
                  ),
                ),

                AddressSearchField(
                  label: "Hvor kører du til?",
                  onSelected: (val) => setState(() => _destination = val),
                ),

                const SizedBox(height: 30),

                // GENTAGELSES LOGIK
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionTitle("Tidspunkt"),
                    Row(
                      children: [
                        Text(
                          "Gentag",
                          style: TextStyle(
                            color: _isRecurring ? _accentColor : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Switch(
                          value: _isRecurring,
                          activeColor: _accentColor,
                          onChanged: (val) =>
                              setState(() => _isRecurring = val),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // LISTEN AF TURE MED DERES SPECIFIKKE TIDER
                if (!_isRecurring)
                  _buildRideTimeCard(0)
                else
                  Column(
                    children: [
                      ...List.generate(
                        _rideInstances.length,
                        (index) => _buildRideTimeCard(index),
                      ),
                      TextButton.icon(
                        onPressed: _addRideInstance,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text("Tilføj en dato mere"),
                        style: TextButton.styleFrom(
                          foregroundColor: _accentColor,
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 30),
                _buildSectionTitle("Pladser & Pris"),
                const SizedBox(height: 10),
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
                _buildSectionTitle("Indstillinger"),
                const SizedBox(height: 10),
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
                _buildCustomSwitch(
                  "Ladies Only",
                  "Kun for kvinder",
                  _ladiesOnly,
                  (v) => setState(() => _ladiesOnly = v),
                  customColor: Colors.pinkAccent,
                ),

                // --- ERSTAT DE GAMLE SWITCHES MED DETTE ---
                const SizedBox(height: 30),
                const Divider(),
                _buildSectionTitle("Husregler"),
                const SizedBox(height: 15),

                // Række 1: Musik & Rygning
                Row(
                  children: [
                    _buildRuleButton(
                      "Musik",
                      _prefMusic,
                      () => setState(() => _prefMusic = !_prefMusic),
                    ),
                    const SizedBox(width: 15), // Mellemrum
                    _buildRuleButton(
                      "Rygning",
                      _prefSmoking,
                      () => setState(() => _prefSmoking = !_prefSmoking),
                    ),
                  ],
                ),

                const SizedBox(height: 15), // Mellemrum mellem rækkerne
                // Række 2: Kæledyr & Børn
                Row(
                  children: [
                    _buildRuleButton(
                      "Kæledyr",
                      _prefPets,
                      () => setState(() => _prefPets = !_prefPets),
                    ),
                    const SizedBox(width: 15), // Mellemrum
                    _buildRuleButton(
                      "Børn",
                      _prefKids,
                      () => setState(() => _prefKids = !_prefKids),
                    ),
                  ],
                ),

                // --- SLUT PÅ HUSREGLER SEKTION ---
                const SizedBox(height: 30),

                // --- KOMMENTARFELT ---
                _buildSectionTitle("Besked til passagerer"),
                const SizedBox(height: 10),
                TextField(
                  controller: _commentController,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText:
                        "Skriv lidt om opsamlingssted, regler eller andet...",
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
                    child: Text(
                      _isRecurring ? "OFFENTLIGGØR TURER" : "OFFENTLIGGØR TUR",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  // --- KORTET MED TIDSLINJE ---
  Widget _buildRideTimeCard(int index) {
    final instance = _rideInstances[index];

    // Sikker datovisning (hvis locale driller, fallback til EN)
    String dateStr;
    try {
      dateStr = DateFormat('EEE d. MMM', 'da_DK').format(instance.date);
    } catch (_) {
      dateStr = DateFormat('EEE d. MMM').format(instance.date);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: Border.all(color: Colors.transparent),
        title: Row(
          children: [
            const Icon(Icons.calendar_month, color: Colors.grey, size: 20),
            const SizedBox(width: 10),
            Text(
              dateStr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        subtitle: Text(
          "${_formatTime(instance.depTime)} - ${_formatTime(instance.arrTime)}",
          style: TextStyle(color: _accentColor, fontWeight: FontWeight.w600),
        ),
        trailing: _isRecurring && index > 0
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _removeRideInstance(index),
              )
            : const Icon(Icons.expand_more),

        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                const Divider(),
                _buildTimeRow(
                  "Dato",
                  DateFormat('dd/MM/yyyy').format(instance.date),
                  () => _showIOSDatePicker(instance),
                  icon: Icons.edit_calendar,
                ),
                const SizedBox(height: 15),

                // Start
                _buildTimeRow(
                  "Afgang (${_origin ?? 'Start'})",
                  _formatTime(instance.depTime),
                  () {
                    _showIOSTimePicker(
                      instance.depTime,
                      (t) => setState(() => instance.depTime = t),
                    );
                  },
                ),

                // Mellemstops
                ...List.generate(_waypoints.length, (wpIndex) {
                  final wpName =
                      _waypoints[wpIndex].city ?? "Stop ${wpIndex + 1}";
                  final currentTime =
                      instance.waypointTimes[wpIndex] ?? instance.depTime;

                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildTimeRow(
                      "Via $wpName",
                      _formatTime(currentTime),
                      () {
                        _showIOSTimePicker(currentTime, (t) {
                          setState(() {
                            instance.waypointTimes[wpIndex] = t;
                          });
                        });
                      },
                      isWaypoint: true,
                    ),
                  );
                }),

                // Slut
                const SizedBox(height: 10),
                _buildTimeRow(
                  "Ankomst (${_destination ?? 'Slut'})",
                  _formatTime(instance.arrTime),
                  () {
                    _showIOSTimePicker(
                      instance.arrTime,
                      (t) => setState(() => instance.arrTime = t),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Visual Helper Widgets
  Widget _buildTimeRow(
    String label,
    String value,
    VoidCallback onTap, {
    bool isWaypoint = false,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            if (isWaypoint)
              const Icon(
                Icons.subdirectory_arrow_right,
                size: 18,
                color: Colors.grey,
              )
            else
              Icon(icon ?? Icons.access_time, size: 20, color: _primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: isWaypoint ? FontWeight.normal : FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) {
    return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<Map<String, double>?> _getCityCoordinates(String query) async {
    if (query.isEmpty) return null;
    if (_stationData.containsKey(query)) {
      final station = _stationData[query];
      return {
        'lat': (station['lat'] as num).toDouble(),
        'lng': (station['lng'] as num).toDouble(),
      };
    }
    String optimizedQuery = "$query, Denmark";
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
          final center = data['features'][0]['center'];
          return {'lat': center[1].toDouble(), 'lng': center[0].toDouble()};
        }
      }
    } catch (e) {
      debugPrint("$e");
    }
    return null;
  }

  void _showError(String msg) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: _primaryColor,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
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
    Function(bool) change, {
    Color? customColor,
  }) {
    final activeColor = customColor ?? _accentColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: val ? activeColor.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: val ? activeColor : Colors.grey.shade200),
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
          Switch(value: val, onChanged: change, activeColor: activeColor),
        ],
      ),
    );
  }
}
