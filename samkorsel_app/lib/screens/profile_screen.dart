import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';

// Sørg for at stierne passer til dine filer
import '../screens/auth/welcome_screen.dart';
import '../screens/chat_detail_screen.dart';
import 'edit_profile_screen.dart';
import 'payments_screen.dart';
import 'review_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _userId = Supabase.instance.client.auth.currentUser!.id;

  // Design farver
  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _accentColor = const Color(0xFF6366F1);
  final Color _bgLight = const Color(0xFFF8FAFC);

  // Mapbox Token
  final String _mapboxToken =
      "pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w";

  // --- NYT: DATO FILTER ---
  DateTime? _filterDate;

  // --- FUNKTION: CHAUFFØR AFLYSER PASSAGER ---
  Future<void> _driverCancelPassenger(String bookingId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Fjern passager?"),
        content: Text(
          "Er du sikker på, at du vil fjerne $name fra turen?\n\nPassageren får alle sine penge tilbage.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Fortryd", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Fjern", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final client = Supabase.instance.client;
      await client.functions.invoke(
        'driver-cancel-booking', // Navnet på din nye funktion
        body: {'booking_id': bookingId},
      );

      if (mounted) {
        setState(() {}); // Opdater listen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$name er blevet fjernet."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fejl: $e")));
      }
    }
  }

  // ------------------------------------------------------------------------
  // LOGIK: AFLYS BOOKING (Med advarsler)
  // ------------------------------------------------------------------------
  // --- NY HJÆLPER: HENT TURE TIL BOOKING-SORTERING ---
  // Sæt denne ind i _ProfileScreenState klassen (fx før build metoden)
  Future<List<Map<String, dynamic>>> _enrichBookingsWithRides(
    List<Map<String, dynamic>> bookings,
  ) async {
    if (bookings.isEmpty) return [];

    // 1. Saml alle ride_ids
    final rideIds = bookings.map((b) => b['ride_id']).toList();

    // 2. Hent alle disse rides fra databasen
    final response = await Supabase.instance.client
        .from('rides')
        .select('*, profiles(*)') // Hent også chauffør info
        .filter('id', 'in', rideIds);

    final List<Map<String, dynamic>> rides = List<Map<String, dynamic>>.from(
      response,
    );

    // 3. Kombiner Booking + Ride data i ét objekt
    return bookings.map((booking) {
      // Find den tur der passer til bookingen
      final ride = rides.firstWhere(
        (r) => r['id'] == booking['ride_id'],
        orElse: () => {}, // Returner tomt map hvis turen er slettet
      );

      // Vi returnerer en ny map der har både booking-info og ride-info samlet
      return {
        ...booking, // status, id, passenger_id, seats_booked
        'ride': ride, // departure_time, price, driver info, origin/dest
      };
    }).toList();
  }

  Future<void> _cancelBooking(String bookingId, String departureTimeStr) async {
    // 1. Beregn advarsel (Ingen ændringer her)
    final departure = DateTime.parse(departureTimeStr).toLocal();
    final now = DateTime.now();
    final hoursUntil = departure.difference(now).inHours;

    if (now.isAfter(departure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Turen er startet og kan ikke længere aflyses."),
        ),
      );
      return;
    }

    String warningTitle = "Afmeld tur";
    String warningText = "Er du sikker på, at du vil afmelde turen?";
    String subWarning = "Dette kan ikke fortrydes.";
    Color warningColor = Colors.grey;

    if (hoursUntil < 3) {
      warningTitle = "100% Gebyr ⚠️";
      warningText = "Du mister hele beløbet!";
      subWarning = "Der er under 3 timer til afgang. Ingen refundering.";
      warningColor = Colors.red;
    } else if (hoursUntil < 24) {
      warningTitle = "50% Gebyr ⚠️";
      warningText = "Du mister 50% af beløbet.";
      subWarning =
          "Der er under 24 timer til afgang. Vi trækker halvdelen af prisen.";
      warningColor = Colors.orange;
    } else {
      warningTitle = "Gratis afmelding ✅";
      warningText = "Du afmelder i god tid.";
      subWarning = "Hele beløbet frigives på dit kort.";
      warningColor = Colors.green;
    }

    // 2. Vis dialog (Ingen ændringer her)
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(warningTitle, style: TextStyle(color: warningColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              warningText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(subWarning),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Behold tur",
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Bekræft Aflysning",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 3. Kald Edge Function
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final client = Supabase.instance.client;

      // --- RETTELSE: FORNY SESSION FØRST ---
      // Dette sikrer, at tokenet ikke er udløbet
      try {
        await client.auth.refreshSession();
      } catch (e) {
        debugPrint("Kunne ikke opfriske session: $e");
        // Vi fortsætter alligevel, i tilfælde af at det gamle token stadig virker
      }

      final session = client.auth.currentSession;
      if (session == null) throw "Ingen aktiv session. Log ind igen.";

      final String jwt = session.accessToken;
      debugPrint(
        "Sender request med token: ${jwt.substring(0, 10)}...",
      ); // Debug print

      final response = await client.functions.invoke(
        'cancel-booking',
        body: {'booking_id': bookingId},
        headers: {'Authorization': 'Bearer $jwt'},
      );

      if (mounted) Navigator.pop(context); // Fjern loading

      if (response.status == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Turen er aflyst."),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {});
        }
      } else {
        final errorData = response.data;
        final errorMsg = (errorData is Map)
            ? errorData['error']
            : "Fejl (${response.status})";
        // Hvis vi stadig får 401 her, er der noget galt med selve brugeren/serveren
        if (response.status == 401) {
          throw "Din session er udløbet. Prøv at logge ud og ind igen.";
        }
        throw errorMsg ?? "Ukendt fejl";
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- IOS STYLE DATE PICKER ---
  void _pickFilterDate() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                // 1. Header med "Færdig" knap
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Vælg dato",
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text(
                          "Færdig",
                          style: TextStyle(
                            color: _accentColor, // Bruger din lilla farve
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Selve iOS Rulle-hjulet
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode
                        .date, // Viser kun dato (ingen tid)
                    initialDateTime: _filterDate ?? DateTime.now(),
                    minimumDate: DateTime(2024),
                    maximumDate: DateTime(2030),
                    use24hFormat: true,
                    // Opdaterer filteret med det samme man ruller
                    onDateTimeChanged: (DateTime newDate) {
                      setState(() {
                        _filterDate = newDate;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isSameDay(DateTime? date1, DateTime date2) {
    if (date1 == null) return false;
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // ------------------------------------------------------------------------
  // HJÆLPEFUNKTION: Parse POINT(lng lat) string
  // ------------------------------------------------------------------------
  // ------------------------------------------------------------------------
  // HJÆLPEFUNKTION: Parse POINT(lng lat) ELLER Hex WKB
  // ------------------------------------------------------------------------
  Map<String, double> _getCoordsFromPoint(String pointStr) {
    // Tjek om det er Hex-format (PostGIS WKB)
    // Det starter typisk med "01" (Little Endian) og indeholder kun hex-tegn
    final isHex =
        RegExp(r'^[0-9A-Fa-f]+$').hasMatch(pointStr) && pointStr.length > 20;

    if (isHex) {
      try {
        return _parseWkbPoint(pointStr);
      } catch (e) {
        debugPrint("Hex parse fejl: $e");
        return {'lng': 0.0, 'lat': 0.0};
      }
    }

    // Fallback til tekst-parsing: "POINT(10.123 56.123)"
    try {
      final clean = pointStr.replaceAll('POINT(', '').replaceAll(')', '');
      final parts = clean.split(' ');
      return {'lng': double.parse(parts[0]), 'lat': double.parse(parts[1])};
    } catch (e) {
      debugPrint("Text parse fejl: $pointStr - Fejl: $e");
      return {'lng': 0.0, 'lat': 0.0};
    }
  }

  // Ny hjælper til at afkode Hex-strengen
  Map<String, double> _parseWkbPoint(String hexString) {
    // 1. Konverter hex string til bytes
    List<int> bytes = [];
    for (int i = 0; i < hexString.length; i += 2) {
      String byteStr = hexString.substring(i, i + 2);
      bytes.add(int.parse(byteStr, radix: 16));
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));

    // 2. Læs byte order (første byte)
    // 01 = Little Endian, 00 = Big Endian
    final endian = byteData.getUint8(0) == 1 ? Endian.little : Endian.big;

    // PostGIS EWKB struktur for POINT:
    // Byte 0: Endianness (1 byte)
    // Byte 1-4: Type (4 bytes) - Vi skipper disse
    // Byte 5-8: SRID (4 bytes) - Vi skipper disse (hvis de findes, typisk 20 i hex flag)

    // Vi antager PostGIS EWKB format som din fejlbesked viser (SRID er inkluderet)
    // Offset til X er typisk 9 bytes inde (1 byte endian + 4 bytes type + 4 bytes SRID)
    // X (Lng) er en 64-bit double
    // Y (Lat) er en 64-bit double

    double lng = byteData.getFloat64(9, endian);
    double lat = byteData.getFloat64(17, endian);

    return {'lng': lng, 'lat': lat};
  }

  // ------------------------------------------------------------------------
  // LOGIK: CO2 BEREGNING (SMART FÆRGE-LOGIK)
  // ------------------------------------------------------------------------
  Future<void> _calculateAndDistributeCO2(String rideId) async {
    try {
      final client = Supabase.instance.client;

      // 1. Hent tur-info
      final rideData = await client
          .from('rides')
          .select('driver_id, is_ferry, origin_location, destination_location')
          .eq('id', rideId)
          .single();

      // 2. Hent passagerer
      final passengers = await client
          .from('bookings')
          .select('passenger_id')
          .eq('ride_id', rideId)
          .eq('status', 'approved');

      if (passengers.isEmpty) {
        debugPrint("Ingen passagerer - ingen CO2 besparelse at fordele.");
        return;
      }

      // 3. Parse start/slut koordinater
      final startCoords = _getCoordsFromPoint(rideData['origin_location']);
      final endCoords = _getCoordsFromPoint(rideData['destination_location']);

      final double startLat = startCoords['lat']!;
      final double startLng = startCoords['lng']!;
      final double endLat = endCoords['lat']!;
      final double endLng = endCoords['lng']!;

      final bool isFerry = rideData['is_ferry'] ?? false;

      double totalDistanceKm = 0.0;

      if (isFerry) {
        // --- SMART FÆRGE LOGIK ---

        // Havne-koordinater
        final double aarhusLng = 10.21396; // Aarhus Havn (Færge)
        final double aarhusLat = 56.15720;
        final double oddenLng = 11.29615; // Odden Færgehavn
        final double oddenLat = 55.97330;

        // Bestem retning: Kører vi mod Øst eller Vest?
        // Danmark ligger ca. mellem 8.0 (Vest) og 12.6 (Øst) længdegrad.
        // Hvis start er mindre end slut, kører vi mod Øst (Jylland -> Sjælland)
        bool isEastbound = startLng < endLng;

        double ferryStartLng, ferryStartLat, ferryEndLng, ferryEndLat;

        if (isEastbound) {
          debugPrint(
            "Retning: ØST (Jylland -> Sjælland). Via Aarhus -> Odden.",
          );
          ferryStartLng = aarhusLng;
          ferryStartLat = aarhusLat;
          ferryEndLng = oddenLng;
          ferryEndLat = oddenLat;
        } else {
          debugPrint(
            "Retning: VEST (Sjælland -> Jylland). Via Odden -> Aarhus.",
          );
          ferryStartLng = oddenLng;
          ferryStartLat = oddenLat;
          ferryEndLng = aarhusLng;
          ferryEndLat = aarhusLat;
        }

        // TRIN A: Prøv først at finde en direkte rute (Mapbox er nogle gange klog nok)
        final directRoute = await _fetchMapboxRoute(
          startLng,
          startLat,
          endLng,
          endLat,
          params: '&alternatives=true',
        );

        // Hvis Mapbox finder en rute under 200km (typisk færge) for en tur tværs over landet, bruger vi den.
        // En tur over Storebælt er typisk markant længere.
        if (directRoute != null &&
            (directRoute['distance'] as num) / 1000.0 < 250) {
          totalDistanceKm = (directRoute['distance'] as num) / 1000.0;
          debugPrint(
            "Mapbox fandt selv færgeruten: ${totalDistanceKm.toStringAsFixed(1)} km",
          );
        } else {
          // TRIN B (FALLBACK): Tving ruten via de rigtige havne
          debugPrint("Beregner splittet rute via havne...");

          // Leg 1: Start -> Færge Start
          final leg1 = await _fetchMapboxRoute(
            startLng,
            startLat,
            ferryStartLng,
            ferryStartLat,
          );

          // Leg 2: Færge Slut -> Slut Destination
          final leg2 = await _fetchMapboxRoute(
            ferryEndLng,
            ferryEndLat,
            endLng,
            endLat,
          );

          if (leg1 != null && leg2 != null) {
            final dist1 = (leg1['distance'] as num) / 1000.0;
            final dist2 = (leg2['distance'] as num) / 1000.0;
            // Vi lægger 75 km til for selve færgeturen (ca. distancen i fugleflugt/sejlads)
            // Dette giver en mere retvisende total "rejse-længde", selvom bilen står stille.
            // Hvis du KUN vil have kørte kilometer, fjern + 75.
            // Men CO2 beregningen er baseret på "sparet kørsel", så vi tæller kun det kørte.
            totalDistanceKm = dist1 + dist2;

            debugPrint(
              "Splittet rute: $dist1 km (til færge) + $dist2 km (fra færge) = $totalDistanceKm km kørsel.",
            );
          } else {
            debugPrint("Fejl: Kunne ikke beregne del-ruter.");
            return;
          }
        }
      } else {
        // IKKE FÆRGE: Beregn normal rute (ekskluder færger for at tvinge broen hvis relevant)
        final route = await _fetchMapboxRoute(
          startLng,
          startLat,
          endLng,
          endLat,
          params: '&exclude=ferry',
        );
        if (route != null) {
          totalDistanceKm = (route['distance'] as num) / 1000.0;
        }
      }

      if (totalDistanceKm == 0.0) return;

      // 4. Beregn besparelse
      // Formel: (Distance * 0.16 kg/km) * Antal Passagerer
      // Det antages at hver passager sparer 1 bil på vejen.
      final int passengerCount = passengers.length;
      final double co2SavedTotal = (totalDistanceKm * 0.16) * passengerCount;

      // Vi fordeler "æren" for besparelsen ligeligt mellem alle i bilen (inklusiv chauffør)
      final double sharePerPerson = co2SavedTotal / (passengerCount + 1);

      // 5. Opdater Chauffør
      await client.rpc(
        'increment_co2',
        params: {'user_id': rideData['driver_id'], 'amount': sharePerPerson},
      );

      // 6. Opdater Passagerer
      for (var p in passengers) {
        await client.rpc(
          'increment_co2',
          params: {'user_id': p['passenger_id'], 'amount': sharePerPerson},
        );
      }

      debugPrint(
        "CO2 fordelt: ${sharePerPerson.toStringAsFixed(3)} kg til hver. (Total sparet: ${co2SavedTotal.toStringAsFixed(1)} kg)",
      );
    } catch (e) {
      debugPrint("Fejl i CO2 beregning: $e");
    }
  }

  // ------------------------------------------------------------------------
  // HJÆLPEFUNKTION TIL MAPBOX KALD
  // ------------------------------------------------------------------------
  Future<Map<String, dynamic>?> _fetchMapboxRoute(
    double startLng,
    double startLat,
    double endLng,
    double endLat, {
    String params = '',
  }) async {
    try {
      // Vi bruger driving-traffic for bedst mulige ruter
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$startLng,$startLat;$endLng,$endLat?access_token=$_mapboxToken$params',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          // Vi sorterer altid kortest først for at være sikre
          routes.sort(
            (a, b) => (a['distance'] as num).compareTo(b['distance'] as num),
          );
          return routes[0];
        }
      }
    } catch (e) {
      debugPrint("Mapbox Helper Fejl: $e");
    }
    return null;
  }

  // ------------------------------------------------------------------------
  // LOGIK: UPDATE BOOKING STATUS (Med Stripe + Navn i besked)
  // ------------------------------------------------------------------------
  Future<void> _updateBookingStatus(
    String bookingId,
    String newStatus,
    String passengerName,
  ) async {
    try {
      // 1. Opdater status i databasen
      await Supabase.instance.client
          .from('bookings')
          .update({'status': newStatus})
          .eq('id', bookingId);

      // 2. Hent Stripe ID
      final bookingData = await Supabase.instance.client
          .from('bookings')
          .select('stripe_payment_id')
          .eq('id', bookingId)
          .maybeSingle();

      final String? stripeId = bookingData?['stripe_payment_id'];

      // 3. Håndter Stripe (KUN ved afvisning)
      if (stripeId != null && stripeId.isNotEmpty && newStatus == 'rejected') {
        debugPrint("Afviser booking - frigiver reserveret beløb hos Stripe...");
        await Supabase.instance.client.functions.invoke(
          'settle-payment',
          body: {'paymentIntentId': stripeId, 'action': 'cancel'},
        );
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'approved'
                  ? "Godkendt: $passengerName"
                  : "Afvist: $passengerName",
            ),
            backgroundColor: newStatus == 'approved'
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fejl: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ------------------------------------------------------------------------
  // LOGIK: AFSLUT TUR (Komplet med Stripe, CO2 og Anmeldelser)
  // ------------------------------------------------------------------------
  Future<void> _completeTrip(String rideId) async {
    // 1. Vis loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final client = Supabase.instance.client;

      // 2. Hent bookinger for at finde Stripe ID'er og Navne til anmeldelse
      final bookingsResponse = await client
          .from('bookings')
          .select('passenger_id, stripe_payment_id, profiles(full_name)')
          .eq('ride_id', rideId)
          .eq('status', 'approved');

      final List<Map<String, dynamic>> bookings =
          List<Map<String, dynamic>>.from(bookingsResponse);

      // 3. Forbered liste til ReviewScreen (Sikker håndtering af navne)
      final List<Map<String, String>> reviewTargets = [];

      for (var b in bookings) {
        // Vi caster sikkert, da 'profiles' kommer som et Map fra Supabase
        final profileData = b['profiles'] as Map<String, dynamic>?;
        final String passengerName =
            profileData?['full_name'] ?? 'Ukendt Passager';

        reviewTargets.add({
          'id': b['passenger_id'].toString(),
          'name': passengerName,
          'role': 'Passager',
        });
      }

      // 4. Capture betalinger (Stripe)
      for (var booking in bookings) {
        final String? stripeId = booking['stripe_payment_id'];
        if (stripeId != null && stripeId.isNotEmpty) {
          try {
            await client.functions.invoke(
              'settle-payment',
              body: {'paymentIntentId': stripeId, 'action': 'capture'},
            );
          } catch (e) {
            debugPrint("Kunne ikke hæve betaling for $stripeId: $e");
            // Vi fortsætter alligevel, så turen kan afsluttes
          }
        }
      }

      // 5. Fordel CO2 besparelse
      await _calculateAndDistributeCO2(rideId);

      // 6. Afregn turen via Edge Function (Flytter penge + Sender beskeder)
      final String? jwt = client.auth.currentSession?.accessToken;
      final response = await client.functions.invoke(
        'complete-trip',
        body: {'trip_id': rideId},
        headers: {'Authorization': 'Bearer $jwt'},
      );

      // 7. Håndter resultat
      if (mounted) {
        Navigator.pop(context); // Fjern loading spinner

        if (response.status == 200) {
          setState(() {}); // Opdater listen i baggrunden

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Turen er afsluttet og afregnet! 💸"),
              backgroundColor: Colors.green,
            ),
          );

          // 8. Naviger til Anmeldelser (hvis der var passagerer)
          if (reviewTargets.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ReviewScreen(rideId: rideId, peopleToReview: reviewTargets),
              ),
            );
          }
        } else {
          final errorMsg = response.data['error'] ?? "Kunne ikke afregne.";
          throw errorMsg;
        }
      }
    } catch (e) {
      if (mounted) {
        // Sikrer at dialogen lukkes ved fejl
        if (Navigator.canPop(context)) Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fejl: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ------------------------------------------------------------------------
  // LOGIK: VÆLG PASSAGER (Bundmenu)
  // ------------------------------------------------------------------------
  void _showPassengerSelector(String rideId, String rideTitle) async {
    final response = await Supabase.instance.client
        .from('bookings')
        .select('passenger_id, profiles(*)')
        .eq('ride_id', rideId)
        .eq('status', 'approved');

    if (!mounted) return;

    final passengers = List<Map<String, dynamic>>.from(response);

    if (passengers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingen godkendte passagerer endnu.")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Vælg passager",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...passengers.map((booking) {
                final profile = booking['profiles'];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: profile['avatar_url'] != null
                        ? NetworkImage(profile['avatar_url'])
                        : null,
                    child: profile['avatar_url'] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(profile['full_name'] ?? 'Ukendt'),
                  trailing: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.blue,
                  ),
                  onTap: () {
                    Navigator.pop(context); // Luk listen
                    // Naviger til chat
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          otherUserId: booking['passenger_id'],
                          otherUserName: profile['full_name'] ?? 'Passager',
                          rideId: rideId,
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------------
  // HJÆLPEFUNKTIONER
  // ------------------------------------------------------------------------
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM • HH:mm').format(date);
    } catch (_) {
      return "";
    }
  }

  String _extractTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('HH:mm').format(date);
    } catch (_) {
      return "--:--";
    }
  }

  Color _getStatusColor(String status) {
    if (status == 'approved') return Colors.green;
    if (status == 'rejected') return Colors.red;
    return Colors.orange;
  }

  String _getStatusText(String status) {
    if (status == 'approved') return "Godkendt";
    if (status == 'rejected') return "Afvist";
    return "Afventer";
  }

  // ------------------------------------------------------------------------
  // BUILD UI
  // ------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: Text(
          "Min Profil",
          style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. TOP MENU (Uændret)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
            child: Column(
              children: [
                _buildMenuOption(
                  icon: Icons.person_outline,
                  title: "Personlige oplysninger",
                  subtitle: "Navn, bil, telefonnummer",
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EditProfileScreen(),
                      ),
                    );
                    setState(() {});
                  },
                ),
                const SizedBox(height: 10),
                _buildMenuOption(
                  icon: Icons.account_balance_wallet_outlined,
                  title: "Betalinger & Skat",
                  subtitle: "Historik, udbetaling og saldo", // Opdateret tekst
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaymentsScreen()),
                  ),
                ),
              ],
            ),
          ),

          // 2. TAB BAR (Uændret)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 15),
            child: Column(
              children: [
                Container(
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      color: _primaryColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey.shade600,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: "Jeg kører"),
                      Tab(text: "Jeg rejser"),
                    ],
                  ),
                ),
                // (Dato filter fjernet herfra, da det kun er relevant for historik som nu er flyttet)
              ],
            ),
          ),
          const Divider(height: 1),

          // 3. LISTER (KUN AKTIVE TURE)
          // 3. LISTER (KUN AKTIVE/KOMMENDE TURE)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // FANE 1: JEG KØRER (Kun aktive)
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('rides')
                      .stream(primaryKey: ['id'])
                      .eq('driver_id', _userId)
                      .order('departure_time', ascending: true),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    final allRides = snapshot.data!;
                    final now = DateTime.now();

                    // FILTER: Vis kun ture der IKKE er completed, og ikke er over 24 timer gamle
                    final activeRides = allRides.where((ride) {
                      final depTime = DateTime.parse(
                        ride['departure_time'],
                      ).toLocal();
                      final isCompleted = ride['status'] == 'completed';

                      return !isCompleted &&
                          now.isBefore(depTime.add(const Duration(hours: 24)));
                    }).toList();

                    if (activeRides.isEmpty) {
                      return _buildEmptyState("Du har ingen planlagte ture.");
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: activeRides.length,
                      itemBuilder: (ctx, i) =>
                          _buildDriverRideCard(activeRides[i]),
                    );
                  },
                ),

                // FANE 2: JEG REJSER (Kun aktive)
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('bookings')
                      .stream(primaryKey: ['id'])
                      .eq('passenger_id', _userId)
                      .order('created_at', ascending: false),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _enrichBookingsWithRides(snapshot.data!),
                      builder: (context, enrichedSnapshot) {
                        if (!enrichedSnapshot.hasData)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );

                        final allData = enrichedSnapshot.data!;
                        final now = DateTime.now();

                        // FILTER: Vis kun hvis ikke aflyst, afvist eller completed
                        final activeTrips = allData.where((item) {
                          final ride = item['ride'];
                          if (ride == null) return false;

                          final status = item['status'];
                          final rideStatus = ride['status'];
                          final depTime = DateTime.parse(
                            ride['departure_time'],
                          ).toLocal();

                          final isCancelled =
                              status == 'rejected' ||
                              status.toString().contains('cancelled');
                          final isCompleted = rideStatus == 'completed';
                          final isOld = now.isAfter(
                            depTime.add(const Duration(hours: 24)),
                          );

                          return !isCancelled && !isCompleted && !isOld;
                        }).toList();

                        if (activeTrips.isEmpty) {
                          return _buildEmptyState(
                            "Du har ingen kommende rejser.",
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: activeTrips.length,
                          itemBuilder: (ctx, i) => _buildPassengerRideCard(
                            activeTrips[i],
                            activeTrips[i]['ride'],
                          ),
                        );
                      },
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

  // ------------------------------------------------------------------------
  // WIDGETS
  // ------------------------------------------------------------------------

  // WIDGET: DRIVER RIDE CARD (Expansion + Timeline)
  Widget _buildDriverRideCard(Map<String, dynamic> ride) {
    // Tjek waypoints fra JSON
    final List<dynamic> waypoints = ride['waypoints'] ?? [];
    final bool hasWaypoints = waypoints.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        // Fjerner standard borders på expansion tile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: EdgeInsets.zero,

          // HEADER: Altid synlig (Start -> Slut)
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.drive_eta, color: _accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${ride['origin_city']} ➝ ${ride['destination_city']}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _primaryColor,
                      ),
                    ),
                    Text(
                      _formatDate(ride['departure_time']),
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                "${ride['price_dkk']} kr.",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _primaryColor,
                ),
              ),
            ],
          ),

          // EXPANDED CONTENT
          children: [
            const Divider(height: 1),

            // 1. RUTEPLAN (Tidslinje med mellemstops)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Ruteplan",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 10),

                  // Start
                  _buildTimelineRow(
                    ride['origin_city'],
                    _extractTime(ride['departure_time']),
                    isFirst: true,
                  ),

                  // Mellemstops
                  ...waypoints.map((wp) {
                    return _buildTimelineRow(
                      wp['city'],
                      wp['departure_time'] ?? "--:--",
                    );
                  }).toList(),

                  // Slut
                  _buildTimelineRow(
                    ride['destination_city'],
                    _extractTime(ride['arrival_time']),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 2. PASSAGERER LISTE
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Passagerer",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            // ... (Inde i _buildDriverRideCard under "Passagerer" overskriften) ...
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('bookings')
                  .stream(primaryKey: ['id'])
                  .eq('ride_id', ride['id']),
              builder: (context, bSnapshot) {
                final allBookings = bSnapshot.data ?? [];

                // --- VIGTIG RETTELSE HER ---
                // Vi filtrerer bookinger, så vi KUN ser dem, der er aktive (pending/approved)
                // Dette fjerner passageren fra listen, hvis de har aflyst.
                final activeBookings = allBookings
                    .where(
                      (b) =>
                          b['status'] == 'approved' || b['status'] == 'pending',
                    )
                    .toList();

                // 1. Hent total kapacitet
                final int totalCapacity = ride['seats_available'] ?? 3;

                // 2. Beregn hvor mange sæder der ER taget (kun af aktive bookinger)
                int seatsTaken = 0;
                for (var b in activeBookings) {
                  seatsTaken += (b['seats_booked'] as int? ?? 1);
                }

                // 3. Beregn hvor mange "Ledigt sæde" linjer vi skal vise
                // Hvis seats_available i databasen er 4 (fordi den tæller forkert),
                // men vi kun viser 3 rækker totalt, ser det pænere ud.
                // Vi bruger dog databasens tal, men sikrer os at vi ikke viser negative ledige sæder.

                List<Widget> seatWidgets = [];

                // A. Vis de AKTIVE bookinger
                for (var booking in activeBookings) {
                  int seatsBooked = booking['seats_booked'] ?? 1;
                  for (int i = 0; i < seatsBooked; i++) {
                    seatWidgets.add(
                      FutureBuilder<Map<String, dynamic>>(
                        future: Supabase.instance.client
                            .from('profiles')
                            .select()
                            .eq('id', booking['passenger_id'])
                            .single(),
                        builder: (context, pSnapshot) {
                          final name =
                              pSnapshot.data?['full_name'] ?? "Henter...";
                          final displayName = seatsBooked > 1
                              ? "$name (${i + 1}/$seatsBooked)"
                              : name;

                          return ListTile(
                            dense: true,
                            leading: const CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.blueAccent,
                              child: Icon(
                                Icons.person,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(displayName),
                            trailing: booking['status'] == 'pending'
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.check,
                                          color: Colors.green,
                                        ),
                                        onPressed: () => _updateBookingStatus(
                                          booking['id'],
                                          'approved',
                                          name,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.red,
                                        ),
                                        onPressed: () => _updateBookingStatus(
                                          booking['id'],
                                          'rejected',
                                          name,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(
                                            booking['status'],
                                          ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          _getStatusText(booking['status']),
                                          style: TextStyle(
                                            color: _getStatusColor(
                                              booking['status'],
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      // --- NYT: SLET KNAP HVIS GODKENDT ---
                                      if (booking['status'] == 'approved')
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                          onPressed: () =>
                                              _driverCancelPassenger(
                                                booking['id'],
                                                name,
                                              ),
                                        ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    );
                  }
                }

                // B. Fyld resten op med "Ledigt sæde" indtil vi rammer kapaciteten
                // Vi bruger en simpel loop: Total Kapacitet (fx 3) minus Antal Taget (fx 0) = 3 ledige
                // OBS: Hvis din 'seats_available' i DB er steget til 4 (fejl), viser vi 4 ledige linjer her.
                // Det er "korrekt" ift. databasen, men forkert ift. bilen.
                // Løsning: Vi stoler på 'seats_available' fra turen, men trækker aktive bookinger fra.

                // For at vise det "rigtige" antal ledige sæder baseret på visningen:
                // Antag at 'seats_available' i ride-objektet er det TOTALE antal pladser i bilen (hvis du har kodet det sådan),
                // ELLER det er "resterende pladser".
                // I din app virker det til at 'seats_available' er TOTAL kapacitet.

                while (seatWidgets.length < totalCapacity) {
                  seatWidgets.add(
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.grey[200],
                        child: Icon(
                          Icons.event_seat,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                      ),
                      title: Text(
                        "Ledigt sæde",
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      trailing: Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: Colors.grey[300],
                      ),
                    ),
                  );
                }

                return Column(children: seatWidgets);
              },
            ),
            const SizedBox(height: 10),

            // 3. ACTIONS (Kontakt + Afslut)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: _primaryColor,
                      ),
                      label: Text(
                        "Kontakt Passagerer",
                        style: TextStyle(color: _primaryColor),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _showPassengerSelector(
                        ride['id'],
                        "${ride['origin_city']} - ${ride['destination_city']}",
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Builder(
                    builder: (context) {
                      final DateTime arrivalTime = DateTime.parse(
                        ride['arrival_time'],
                      ).toLocal();
                      final bool isTimePassed = DateTime.now().isAfter(
                        arrivalTime,
                      );

                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.flag, size: 18),
                          label: Text(
                            isTimePassed
                                ? "Afslut tur & modtag betaling"
                                : "Turen er ikke slut endnu",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isTimePassed
                                ? Colors.green
                                : Colors.grey[300],
                            foregroundColor: isTimePassed
                                ? Colors.white
                                : Colors.grey[600],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isTimePassed
                              ? () => _completeTrip(ride['id'])
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // WIDGET: TIMELINE ROW
  Widget _buildTimelineRow(
    String city,
    String time, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              time,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isFirst || isLast ? _accentColor : Colors.white,
                  border: Border.all(color: _accentColor, width: 2),
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: Colors.grey[300])),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                city,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET: PASSENGER RIDE CARD
  // WIDGET: PASSENGER RIDE CARD (Opdateret med Gebyr visning)
  Widget _buildPassengerRideCard(
    Map<String, dynamic> booking,
    Map<String, dynamic> ride,
  ) {
    final driver = ride['profiles'];
    final bool isCancelled = booking['status'].toString().contains('cancelled');
    final DateTime depTime = DateTime.parse(ride['departure_time']).toLocal();
    final bool hasStarted = DateTime.now().isAfter(depTime);

    // Beregn om der var gebyr (Simpel logik baseret på status tekst eller tid)
    // Hvis du gemte gebyret i databasen, ville vi hente det her.
    // Her laver vi et estimat for visningen:
    String priceText = "${ride['price_dkk']} kr.";
    Color priceColor = _primaryColor;

    if (isCancelled) {
      // Hvis status er 'cancelled_by_passenger', tjekker vi om der var gebyr
      // (Dette er kun visuelt. Backend har trukket pengene)
      // Du kan evt. udvide din booking tabel med 'fee_charged' kolonne for præcision.
      // Her antager vi, at hvis turen er aflyst, viser vi bare "Aflyst" eller evt. minus beløb hvis du vil hardcode logikken.

      priceText = "Aflyst";
      priceColor = Colors.red;

      // Hvis du vil vise "-50 kr" skal du vide hvad der blev trukket.
      // Hvis du ikke har gemt det beløb på bookingen, er det svært at vide præcist nu.
      // Men vi kan gøre prisen rød og gennemstreget:
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey[200],
                  backgroundImage: driver['avatar_url'] != null
                      ? NetworkImage(driver['avatar_url'])
                      : null,
                  child: driver['avatar_url'] == null
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${ride['origin_city']} ➝ ${ride['destination_city']}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isCancelled ? Colors.grey : _primaryColor,
                          decoration: isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        "Chauffør: ${driver['full_name']}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(ride['departure_time']),
                        style: TextStyle(
                          color: isCancelled ? Colors.grey : _accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      priceText,
                      style: TextStyle(
                        color: priceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        decoration: isCancelled && priceText.contains('kr')
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (isCancelled)
                      const Text(
                        "Gebyr kan forekomme", // Eller "- XX kr" hvis du har dataen
                        style: TextStyle(color: Colors.red, fontSize: 10),
                      ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isCancelled
                            ? Colors.red.withOpacity(0.1)
                            : _getStatusColor(
                                booking['status'],
                              ).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isCancelled
                            ? "Aflyst"
                            : _getStatusText(booking['status']),
                        style: TextStyle(
                          color: isCancelled
                              ? Colors.red
                              : _getStatusColor(booking['status']),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // KNAPPER (Skjul hvis aflyst)
          if (booking['status'] == 'approved' &&
              !isCancelled &&
              !hasStarted) ...[
            const Divider(height: 1),
            // ... (Behold dine knapper her: Kontakt + Aflys) ...
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text("Chat"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        // --- HER ER RETTELSEN ---
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatDetailScreen(
                              otherUserId: ride['driver_id'], // Chaufførens ID
                              otherUserName: driver['full_name'] ?? 'Chauffør',
                              rideId: ride['id'],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text("Aflys"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red.shade200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () =>
                          _cancelBooking(booking['id'], ride['departure_time']),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // WIDGET: EMPTY STATE
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }

  // WIDGET: MENU OPTION
  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _primaryColor, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
