import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

// Sørg for at stierne passer til dine filer
import '../screens/auth/welcome_screen.dart';
import '../screens/chat_detail_screen.dart';
import 'edit_profile_screen.dart';
import 'payments_screen.dart';

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

  // ------------------------------------------------------------------------
  // LOGIK: AFLYS BOOKING (Med advarsler)
  // ------------------------------------------------------------------------
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

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: ColorScheme.light(primary: _primaryColor)),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _filterDate = picked);
    }
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
  // LOGIK: CO2 BEREGNING (MED TVUNGEN FÆRGE-SPLIT)
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
        // TRIN A: Prøv først at finde en direkte færgerute via API'et
        // Vi beder om 'alternatives' og 'steps'
        final directRoute = await _fetchMapboxRoute(
          startLng,
          startLat,
          endLng,
          endLat,
          params: '&alternatives=true&steps=true',
        );

        // Tjek om den fundne rute er en "ægte" færgerute (under 200 km)
        // Aarhus-Hillerød via færge er ca 125 km. Via broen er den 330 km.
        if (directRoute != null &&
            (directRoute['distance'] as num) / 1000.0 < 200) {
          totalDistanceKm = (directRoute['distance'] as num) / 1000.0;
          debugPrint(
            "Succes: Direkte færgerute fundet (${totalDistanceKm.toStringAsFixed(1)} km).",
          );
        } else {
          // TRIN B (FALLBACK): Tving ruten via GPS koordinaterne
          debugPrint(
            "Info: Ingen færge fundet automatisk. Beregner splittet rute (Start->Aarhus + Odden->Slut).",
          );

          // Aarhus Færge GPS (Lng, Lat til Mapbox)
          final double aarhusFerryLng = 10.252944144688946;
          final double aarhusFerryLat = 56.15091404030663;

          // Odden Færge GPS (Lng, Lat til Mapbox)
          final double oddenFerryLng = 11.30108715834335;
          final double oddenFerryLat = 55.97709587751027;

          // 1. Kørsel: Start -> Aarhus Havn
          final leg1 = await _fetchMapboxRoute(
            startLng,
            startLat,
            aarhusFerryLng,
            aarhusFerryLat,
          );

          // 2. Kørsel: Odden Havn -> Slut
          final leg2 = await _fetchMapboxRoute(
            oddenFerryLng,
            oddenFerryLat,
            endLng,
            endLat,
          );

          if (leg1 != null && leg2 != null) {
            final dist1 = (leg1['distance'] as num) / 1000.0;
            final dist2 = (leg2['distance'] as num) / 1000.0;
            totalDistanceKm = dist1 + dist2;
            debugPrint(
              "Splittet rute beregnet: Leg 1 ($dist1 km) + Leg 2 ($dist2 km) = $totalDistanceKm km",
            );
          } else {
            debugPrint("Fejl: Kunne ikke beregne en af del-ruterne.");
            return;
          }
        }
      } else {
        // IKKE FÆRGE: Beregn normal rute (ekskluder færger)
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
      final int passengerCount = passengers.length;
      final double co2PerCar = totalDistanceKm * 0.16;
      final double totalSaved = co2PerCar * passengerCount;
      final double sharePerPerson = totalSaved / (passengerCount + 1);

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
        "CO2 fordelt: ${sharePerPerson.toStringAsFixed(3)} kg til hver (Distance: ${totalDistanceKm.toStringAsFixed(1)} km).",
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
  // LOGIK: AFSLUT TUR (Håndterer både med og uden passagerer)
  // ------------------------------------------------------------------------
  Future<void> _completeTrip(String rideId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final client = Supabase.instance.client;

      // 1. Find alle godkendte passagerer, hvor vi endnu ikke har "hævet" pengene (captured)
      final bookingsResponse = await client
          .from('bookings')
          .select('stripe_payment_id, profiles(full_name)')
          .eq('ride_id', rideId)
          .eq('status', 'approved');

      final bookings = List<Map<String, dynamic>>.from(bookingsResponse);

      // 2. SIKKERHEDS-CHECK: Hæv pengene NU, hvis de stadig kun er reserverede
      // (Dette kører kun hvis de ikke allerede er hævet)
      for (var booking in bookings) {
        final String? stripeId = booking['stripe_payment_id'];
        if (stripeId != null && stripeId.isNotEmpty) {
          await client.functions.invoke(
            'settle-payment',
            body: {'paymentIntentId': stripeId, 'action': 'capture'},
          );
        }
      }

      // 3. Fordel CO2
      await _calculateAndDistributeCO2(rideId);

      // 4. Afregn turen (Flyt penge til chaufførens udbetalings-saldo)
      final String? jwt = client.auth.currentSession?.accessToken;
      final response = await client.functions.invoke(
        'complete-trip',
        body: {'trip_id': rideId},
        headers: {'Authorization': 'Bearer $jwt'},
      );

      if (mounted) {
        Navigator.pop(context);
        if (response.status == 200) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Turen er afsluttet og afregnet! 💸"),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw response.data['error'] ?? "Kunne ikke afregne.";
        }
      }
    } catch (e) {
      if (mounted) {
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
          // 1. TOP MENU
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
                  subtitle: "Udbetaling, saldo og skatteinfo",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaymentsScreen()),
                  ),
                ),
              ],
            ),
          ),

          // 2. TAB BAR
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: _primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: _accentColor,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: "Jeg kører"),
                Tab(text: "Jeg rejser"),
              ],
            ),
          ),
          // --- NYT: DATO FILTER BAR ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_filterDate != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: TextButton(
                      onPressed: () => setState(() => _filterDate = null),
                      child: const Text(
                        "Nulstil",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                InkWell(
                  onTap: _pickFilterDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _filterDate != null
                          ? _primaryColor
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _filterDate != null
                            ? _primaryColor
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: _filterDate != null
                              ? Colors.white
                              : Colors.grey[700],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _filterDate != null
                              ? DateFormat(
                                  'd. MMM',
                                  'da_DK',
                                ).format(_filterDate!)
                              : "Filtrer dato",
                          style: TextStyle(
                            color: _filterDate != null
                                ? Colors.white
                                : Colors.grey[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1), // En lille streg for pænhedens skyld
          // 3. LISTER
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // FANE 1: JEG KØRER
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('rides')
                      .stream(primaryKey: ['id'])
                      .eq('driver_id', _userId)
                      .order('departure_time', ascending: true),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    // --- FILTRERINGS LOGIK ---
                    final rides = snapshot.data!.where((ride) {
                      // 1. Skjul færdige ture
                      if (ride['status'] == 'completed') return false;

                      // 2. Tjek Dato Filter
                      if (_filterDate != null) {
                        final rideDate = DateTime.parse(
                          ride['departure_time'],
                        ).toLocal();
                        return _isSameDay(rideDate, _filterDate!);
                      }
                      return true;
                    }).toList();
                    // -------------------------

                    if (rides.isEmpty)
                      return _buildEmptyState("Ingen ture fundet.");

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rides.length,
                      itemBuilder: (context, index) =>
                          _buildDriverRideCard(rides[index]),
                    );
                  },
                ),
                // FANE 2: JEG REJSER
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('bookings')
                      .stream(primaryKey: ['id'])
                      .eq('passenger_id', _userId)
                      .order('created_at', ascending: false),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final bookings = snapshot.data!;

                    if (bookings.isEmpty)
                      return _buildEmptyState("Du har ikke booket nogen ture.");

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: bookings.length,
                      itemBuilder: (context, index) {
                        final booking = bookings[index];
                        // Vi henter turen for at se datoen
                        return FutureBuilder<Map<String, dynamic>>(
                          future: Supabase.instance.client
                              .from('rides')
                              .select('*, profiles(*)')
                              .eq('id', booking['ride_id'])
                              .single(),
                          builder: (context, rSnapshot) {
                            // Vent på data eller skjul hvis fejl
                            if (!rSnapshot.hasData) return const SizedBox();
                            final ride = rSnapshot.data!;

                            // --- NYT: SKJUL HVIS TUREN ER SLUT ---
                            // Hvis turen er completed, skal den ikke vises i "Aktive rejser"
                            if (ride['status'] == 'completed') {
                              return const SizedBox.shrink();
                            }

                            // --- FILTRERINGS LOGIK ---
                            if (_filterDate != null) {
                              final rideDate = DateTime.parse(
                                ride['departure_time'],
                              ).toLocal();
                              // Hvis datoen ikke matcher, returnerer vi en "tom" boks, så den forsvinder fra listen
                              if (!_isSameDay(rideDate, _filterDate!)) {
                                return const SizedBox.shrink();
                              }
                            }
                            // -------------------------

                            return _buildPassengerRideCard(booking, ride);
                          },
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
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('bookings')
                  .stream(primaryKey: ['id'])
                  .eq('ride_id', ride['id']),
              builder: (context, bSnapshot) {
                // Vi håndterer ventetid pænt, men viser tomme sæder med det samme hvis data mangler
                final bookings = bSnapshot.data ?? [];

                // 1. Hent total kapacitet (standard til 3 hvis null)
                final int totalCapacity = ride['seats_available'] ?? 3;

                // 2. Opret en liste til at holde alle widgets (både bookede og tomme)
                List<Widget> seatWidgets = [];

                // 3. Fyld listen med de faktiske bookinger
                for (var booking in bookings) {
                  // Hvor mange sæder fylder denne booking?
                  int seatsBooked = booking['seats_booked'] ?? 1;

                  for (int i = 0; i < seatsBooked; i++) {
                    // Tilføj en widget for HVERT sæde denne person har booket
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

                          // Vis (1/2) hvis det er flersædes-booking
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
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(
                                        booking['status'],
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
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
                          );
                        },
                      ),
                    );
                  }
                }

                // 4. Fyld resten op med "Ingen passager" indtil vi rammer kapaciteten
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
  Widget _buildPassengerRideCard(
    Map<String, dynamic> booking,
    Map<String, dynamic> ride,
  ) {
    final driver = ride['profiles'];
    final bool isCancelled = booking['status'].toString().contains('cancelled');

    // TJEK OM TUREN ER STARTET
    final DateTime depTime = DateTime.parse(ride['departure_time']).toLocal();
    final bool hasStarted = DateTime.now().isAfter(depTime);

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
                          color: _primaryColor,
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
                          color: _accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isCancelled
                        ? Colors.red.withOpacity(0.1)
                        : _getStatusColor(booking['status']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCancelled ? "Aflyst" : _getStatusText(booking['status']),
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
          ),

          // KNAPPER (Vis kun hvis ikke aflyst)
          if (booking['status'] == 'approved' && !isCancelled) ...[
            const Divider(height: 1),

            // KONTAKT KNAP
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text("Kontakt Chauffør"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          otherUserId: ride['driver_id'],
                          otherUserName: driver['full_name'] ?? 'Chauffør',
                          rideId: ride['id'],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // AFLYS KNAP (Deaktiveret hvis startet)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(
                    hasStarted ? Icons.timer_off : Icons.cancel_outlined,
                    size: 18,
                  ),
                  label: Text(hasStarted ? "Turen er startet" : "Aflys Tur"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: hasStarted ? Colors.grey : Colors.red,
                    side: BorderSide(
                      color: hasStarted
                          ? Colors.grey.shade300
                          : Colors.red.shade200,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  // Hvis startet = null (deaktiveret), ellers kald funktion
                  onPressed: hasStarted
                      ? null
                      : () => _cancelBooking(
                          booking['id'],
                          ride['departure_time'],
                        ),
                ),
              ),
            ),
          ],

          // VIS STATUS HVIS ALLEREDE AFLYST
          if (isCancelled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.info_outline, size: 16, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    "Du har aflyst denne tur",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
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
