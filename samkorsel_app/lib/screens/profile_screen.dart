import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
  // LOGIK: CO2 BEREGNING
  // ------------------------------------------------------------------------
  Future<void> _calculateAndDistributeCO2(String rideId) async {
    try {
      final client = Supabase.instance.client;

      // 1. Hent tur-info inklusiv koordinater (PostGIS -> Lat/Lng)
      final rideData = await client
          .from('rides')
          .select(
            'driver_id, is_ferry, st_x(origin_location) as start_lng, st_y(origin_location) as start_lat, st_x(destination_location) as end_lng, st_y(destination_location) as end_lat',
          )
          .eq('id', rideId)
          .single();

      // 2. Hent passagerer (kun godkendte)
      final passengers = await client
          .from('bookings')
          .select('passenger_id')
          .eq('ride_id', rideId)
          .eq('status', 'approved');

      if (passengers.isEmpty) {
        debugPrint("Ingen passagerer - ingen CO2 besparelse at fordele.");
        return;
      }

      // 3. Beregn rute via Mapbox
      final double startLat = rideData['start_lat'];
      final double startLng = rideData['start_lng'];
      final double endLat = rideData['end_lat'];
      final double endLng = rideData['end_lng'];
      final bool isFerry = rideData['is_ferry'] ?? false;

      final String excludeParam = isFerry ? '' : '&exclude=ferry';

      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/$startLng,$startLat;$endLng,$endLat?access_token=$_mapboxToken$excludeParam',
      );

      final mapResponse = await http.get(url);

      if (mapResponse.statusCode != 200) {
        debugPrint("Mapbox API Fejl: ${mapResponse.body}");
        return;
      }

      final mapData = json.decode(mapResponse.body);
      final routes = mapData['routes'] as List;
      if (routes.isEmpty) return;

      // Distance i meter -> omregn til km
      final double distanceKm = (routes[0]['distance'] as num) / 1000.0;

      // 4. Beregn besparelse
      // 1 bil = 0.16 kg CO2 pr km.
      final int passengerCount = passengers.length;
      final double co2PerCar = distanceKm * 0.16;
      final double totalSaved = co2PerCar * passengerCount;

      // Fordeling: Ligeligt mellem chauffør og passagerer
      final double sharePerPerson = totalSaved / (passengerCount + 1);

      // 5. Opdater Chauffør (RPC)
      await client.rpc(
        'increment_co2',
        params: {'user_id': rideData['driver_id'], 'amount': sharePerPerson},
      );

      // 6. Opdater Passagerer (RPC)
      for (var p in passengers) {
        await client.rpc(
          'increment_co2',
          params: {'user_id': p['passenger_id'], 'amount': sharePerPerson},
        );
      }
    } catch (e) {
      debugPrint("Fejl i CO2 beregning: $e");
    }
  }

  // ------------------------------------------------------------------------
  // LOGIK: UPDATE BOOKING STATUS (Nu med Stripe integration)
  // ------------------------------------------------------------------------
  Future<void> _updateBookingStatus(String bookingId, String newStatus) async {
    try {
      // 1. Opdater status i databasen først
      await Supabase.instance.client
          .from('bookings')
          .update({'status': newStatus})
          .eq('id', bookingId);

      // 2. Hent Stripe ID'et for denne specifikke booking
      final bookingData = await Supabase.instance.client
          .from('bookings')
          .select('stripe_payment_id')
          .eq('id', bookingId)
          .maybeSingle();

      final String? stripeId = bookingData?['stripe_payment_id'];

      // 3. Hvis der er et Stripe ID, kalder vi din nye Edge Function
      if (stripeId != null && stripeId.isNotEmpty) {
        // Vi kalder 'settle-payment' som du lige har oprettet
        await Supabase.instance.client.functions.invoke(
          'settle-payment',
          body: {
            'paymentIntentId': stripeId,
            'action': newStatus == 'approved' ? 'capture' : 'cancel',
          },
        );
        debugPrint("Stripe handling udført: $newStatus for $stripeId");
      }

      if (mounted) {
        setState(() {}); // Opdater UI så listen genindlæses
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'approved'
                  ? "Godkendt! Betalingen er reserveret."
                  : "Afvist. Pengene er frigivet til passageren.",
            ),
            backgroundColor: newStatus == 'approved'
                ? Colors.green
                : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Fejl ved status/betaling opdatering: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Der skete en fejl med betalingen."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------------------
  // LOGIK: AFSLUT TUR & BETALING
  // ------------------------------------------------------------------------
  Future<void> _completeTrip(String rideId) async {
    try {
      // Vis loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 1. Beregn CO2
      await _calculateAndDistributeCO2(rideId);

      // 2. Betaling & Luk tur (Edge Function)
      final String? jwt =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (jwt == null) throw "Ingen session. Log ind igen.";

      final response = await Supabase.instance.client.functions.invoke(
        'complete-trip',
        body: {'trip_id': rideId},
        headers: {'Authorization': 'Bearer $jwt'},
      );

      if (mounted) Navigator.pop(context); // Fjern loading

      if (response.status == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Turen er afsluttet, CO2 fordelt og betaling gennemført! 🌿",
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final errorMsg = response.data['error'] ?? "Kunne ikke afregne turen.";
        throw errorMsg;
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
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
      // Bruger en simpel formatering hvis initializeDateFormatting driller, ellers 'da_DK'
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
                if (!bSnapshot.hasData || bSnapshot.data!.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "Ingen bookinger endnu",
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }

                final bookings = bSnapshot.data!;
                return Column(
                  children: bookings.map((booking) {
                    return FutureBuilder<Map<String, dynamic>>(
                      future: Supabase.instance.client
                          .from('profiles')
                          .select()
                          .eq('id', booking['passenger_id'])
                          .single(),
                      builder: (context, pSnapshot) {
                        final name = pSnapshot.data?['full_name'] ?? "Passager";
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.person,
                            size: 20,
                            color: Colors.grey,
                          ),
                          title: Text(name),
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
                                      color: _getStatusColor(booking['status']),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        );
                      },
                    );
                  }).toList(),
                );
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
                    color: _getStatusColor(booking['status']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getStatusText(booking['status']),
                    style: TextStyle(
                      color: _getStatusColor(booking['status']),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (booking['status'] == 'approved') ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
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
