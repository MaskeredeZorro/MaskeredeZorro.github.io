import 'dart:convert'; // Til JSON parsing af Mapbox data
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // Til API kald mod Mapbox
import 'package:samkorsel_app/screens/auth/signup_screen.dart';
import 'package:samkorsel_app/screens/auth/welcome_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'auth_screen.dart';
import '../features/rides/chat_screen.dart';
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
  final Color _primaryColor = const Color(0xFF0F172A);

  // Din Mapbox Token
  final String _mapboxToken =
      "pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // -- LOGIK: BEREGN OG FORDEL CO2 --
  Future<void> _calculateAndDistributeCO2(String rideId) async {
    try {
      final client = Supabase.instance.client;

      // 1. Hent tur-info inklusiv koordinater konverteret fra PostGIS Hex til Lat/Lng
      // Vi bruger st_x (lng) og st_y (lat) direkte i SQL forespørgslen
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

      // Hvis is_ferry er FALSE, så ekskluder færger.
      // Hvis is_ferry er TRUE, så tillad standard rute (Mapbox vælger selv).
      final String excludeParam = isFerry ? '' : '&exclude=ferry';

      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/$startLng,$startLat;$endLng,$endLat?access_token=$_mapboxToken$excludeParam',
      );

      final mapResponse = await http.get(url);

      if (mapResponse.statusCode != 200) {
        debugPrint("Mapbox API Fejl: ${mapResponse.body}");
        return; // Afbryd CO2 beregning, men lad betaling fortsætte
      }

      final mapData = json.decode(mapResponse.body);
      final routes = mapData['routes'] as List;
      if (routes.isEmpty) return;

      // Distance i meter -> omregn til km
      final double distanceKm = (routes[0]['distance'] as num) / 1000.0;

      // 4. Beregn besparelse
      // Logik: Hver passager sparer 1 bil.
      // 1 bil = 0.16 kg CO2 pr km.
      // Total sparet = Antal passagerer * (km * 0.16)
      final int passengerCount = passengers.length;
      final double co2PerCar = distanceKm * 0.16;
      final double totalSaved = co2PerCar * passengerCount;

      // Fordeling: Ligeligt mellem chauffør og passagerer (passengerCount + 1 chauffør)
      final double sharePerPerson = totalSaved / (passengerCount + 1);

      debugPrint(
        "Rute: $distanceKm km. Total sparet: $totalSaved kg. Pr. person: $sharePerPerson kg.",
      );

      // 5. Opdater Chauffør (Brug RPC funktion 'increment_co2')
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
    } catch (e) {
      debugPrint("Kritisk fejl i CO2 beregning: $e");
      // Vi kaster ikke exception videre, da vi ikke vil blokere selve betalingen/afslutningen af turen
    }
  }

  // -- LOGIK: OPDATER STATUS --
  Future<void> _updateBookingStatus(String bookingId, String newStatus) async {
    try {
      await Supabase.instance.client
          .from('bookings')
          .update({'status': newStatus})
          .eq('id', bookingId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus == 'approved' ? "Godkendt!" : "Afvist"),
            backgroundColor: newStatus == 'approved'
                ? Colors.green
                : Colors.red,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint("Fejl: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Kunne ikke opdatere - Tjek RLS policies!"),
          ),
        );
      }
    }
  }

  Future<void> _completeTrip(String rideId) async {
    try {
      // Vis loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // --- TRIN 1: BEREGN OG FORDEL CO2 (Før betaling/lukning) ---
      // Vi venter på at denne bliver færdig, før vi lukker turen
      await _calculateAndDistributeCO2(rideId);

      // --- TRIN 2: BETALING & LUK TUR ---
      // Hent det aktuelle token manuelt for at være 100% sikker
      final String? jwt =
          Supabase.instance.client.auth.currentSession?.accessToken;

      if (jwt == null) {
        throw "Ingen gyldig session fundet. Log venligst ind igen.";
      }

      final session = Supabase.instance.client.auth.currentSession;
      print("Mit JWT: ${session?.accessToken}");

      // Kald Edge Function med eksplicit header for at undgå SDK-mismatch
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
                "Turen er afsluttet, CO2 er fordelt og pengene er overført! 💸🌿",
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Håndter fejlbeskeder fra din Edge Function
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

  // HJÆLPERE
  String _formatDate(String dateStr) {
    try {
      // Tilføj .toLocal() for at konvertere fra UTC til Dansk tid
      final date = DateTime.parse(dateStr).toLocal();

      // Vi bruger DateFormat for at få det pænere (f.eks. 04/02 i stedet for 4/2)
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} kl. ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return "";
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Min Profil",
          style: TextStyle(fontWeight: FontWeight.bold),
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
          // --- 1. NY MENU ØVERST ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5),
            child: Column(
              children: [
                _buildMenuOption(
                  icon: Icons.person_outline,
                  title: "Personlige oplysninger",
                  subtitle: "Navn, bil, telefonnummer",
                  // RETTELSE: Vi bruger 'await' og setState for at opdatere siden når man kommer tilbage
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EditProfileScreen(),
                      ),
                    );
                    setState(
                      () {},
                    ); // Tvinger profil-siden til at opdatere, hvis f.eks. billedet er ændret
                  },
                ),
                const SizedBox(height: 8),
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

          const Divider(thickness: 1, height: 20),

          // --- 2. TAB BAR ---
          TabBar(
            controller: _tabController,
            labelColor: _primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _primaryColor,
            tabs: const [
              Tab(text: "Jeg kører"),
              Tab(text: "Jeg rejser"),
            ],
          ),

          // --- 3. DINE EKSISTERENDE LISTER ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // --- FANE 1: JEG KØRER (CHAUFFØR) ---
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('rides')
                      .stream(primaryKey: ['id'])
                      .eq('driver_id', _userId)
                      .order('departure_time', ascending: true),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rides = snapshot.data!;
                    final activeRides = rides
                        .where((ride) => ride['status'] != 'completed')
                        .toList();
                    if (activeRides.isEmpty) {
                      return const Center(child: Text("Ingen ture oprettet."));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: activeRides.length,
                      itemBuilder: (context, index) {
                        final ride = activeRides[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 15),
                          child: Column(
                            children: [
                              ListTile(
                                title: Text(
                                  "${ride['origin_city']} ➝ ${ride['destination_city']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  _formatDate(ride['departure_time']),
                                ),
                                trailing: Text(
                                  "${ride['price_dkk']} kr.",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                              const Divider(height: 1),

                              // Stream 2 (Nested): Lyt LIVE på bookinger til denne tur
                              StreamBuilder<List<Map<String, dynamic>>>(
                                stream: Supabase.instance.client
                                    .from('bookings')
                                    .stream(primaryKey: ['id'])
                                    .eq('ride_id', ride['id']),
                                builder: (context, bSnapshot) {
                                  if (!bSnapshot.hasData) {
                                    return const SizedBox();
                                  }
                                  final bookings = bSnapshot.data!;

                                  if (bookings.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(15),
                                      child: Text(
                                        "Ingen passagerer endnu.",
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    );
                                  }

                                  return Column(
                                    children: bookings.map((booking) {
                                      return FutureBuilder<
                                        Map<String, dynamic>
                                      >(
                                        future: Supabase.instance.client
                                            .from('profiles')
                                            .select()
                                            .eq('id', booking['passenger_id'])
                                            .single(),
                                        builder: (context, pSnapshot) {
                                          final profileName =
                                              pSnapshot.data?['full_name'] ??
                                              "Passager";

                                          return ListTile(
                                            leading: const Icon(Icons.person),
                                            title: Text(profileName),
                                            subtitle: Text(
                                              "Status: ${_getStatusText(booking['status'])}",
                                              style: TextStyle(
                                                color: _getStatusColor(
                                                  booking['status'],
                                                ),
                                              ),
                                            ),
                                            trailing:
                                                booking['status'] == 'pending'
                                                ? Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.check,
                                                          color: Colors.green,
                                                        ),
                                                        onPressed: () =>
                                                            _updateBookingStatus(
                                                              booking['id'],
                                                              'approved',
                                                            ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.close,
                                                          color: Colors.red,
                                                        ),
                                                        onPressed: () =>
                                                            _updateBookingStatus(
                                                              booking['id'],
                                                              'rejected',
                                                            ),
                                                      ),
                                                    ],
                                                  )
                                                : Icon(
                                                    booking['status'] ==
                                                            'approved'
                                                        ? Icons.check_circle
                                                        : Icons.cancel,
                                                    color: _getStatusColor(
                                                      booking['status'],
                                                    ),
                                                  ),
                                          );
                                        },
                                      );
                                    }).toList(),
                                  );
                                },
                              ),

                              // DIN EKSISTERENDE CHAT KNAP
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.chat_bubble_outline),
                                    label: const Text("Åbn Tur-chat"),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            rideId: ride['id'],
                                            rideTitle:
                                                "${ride['origin_city']} ➝ ${ride['destination_city']}",
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                              // <--- INDSÆT DENNE NYE BLOK HERFRA --->
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Builder(
                                    builder: (context) {
                                      final DateTime arrivalTime =
                                          DateTime.parse(
                                            ride['arrival_time'],
                                          ).toLocal();
                                      final bool isTimePassed = DateTime.now()
                                          .isAfter(arrivalTime);
                                      final bool isCompleted =
                                          ride['status'] == 'completed';

                                      return ElevatedButton.icon(
                                        icon: Icon(
                                          isCompleted
                                              ? Icons.verified
                                              : Icons.flag_circle,
                                        ),
                                        label: Text(
                                          isCompleted
                                              ? "Turen er afregnet"
                                              : (isTimePassed
                                                    ? "Afslut tur & modtag betaling"
                                                    : "Turen er ikke slut endnu"),
                                        ),
                                        onPressed:
                                            (isTimePassed && !isCompleted)
                                            ? () => _completeTrip(ride['id'])
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isCompleted
                                              ? Colors.blueGrey
                                              : Colors.green,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              Colors.grey[200],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                              // <--- HERTIL --->
                            ], // Lukker Column inde i Card
                          ),
                        ); // Lukker Card
                      },
                    );
                  },
                ),

                // --- FANE 2: JEG REJSER (PASSAGER) ---
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('bookings')
                      .stream(primaryKey: ['id'])
                      .eq('passenger_id', _userId)
                      .order('created_at', ascending: false),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final bookings = snapshot.data!;
                    if (bookings.isEmpty) {
                      return const Center(child: Text("Ingen ture booket."));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: bookings.length,
                      itemBuilder: (context, index) {
                        final booking = bookings[index];

                        return FutureBuilder<Map<String, dynamic>>(
                          future: Supabase.instance.client
                              .from('rides')
                              .select('*, profiles(*)')
                              .eq('id', booking['ride_id'])
                              .single(),
                          builder: (context, rSnapshot) {
                            if (!rSnapshot.hasData) return const SizedBox();
                            final ride = rSnapshot.data!;
                            final driver = ride['profiles'];

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                onTap: booking['status'] == 'approved'
                                    ? () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              rideId: ride['id'],
                                              rideTitle:
                                                  "${ride['origin_city']} ➝ ${ride['destination_city']}",
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                leading: const Icon(
                                  Icons.directions_car,
                                  color: Colors.green,
                                ),
                                title: Text(
                                  "${ride['origin_city']} ➝ ${ride['destination_city']}",
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_formatDate(ride['departure_time'])),
                                    Text(
                                      "Chauffør: ${driver?['full_name'] ?? 'Ukendt'}",
                                    ),
                                    if (booking['status'] == 'approved')
                                      const Text(
                                        "Klik for at chatte",
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(
                                      booking['status'],
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _getStatusColor(booking['status']),
                                    ),
                                  ),
                                  child: Text(
                                    _getStatusText(booking['status']),
                                    style: TextStyle(
                                      color: _getStatusColor(booking['status']),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
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

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: _primaryColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }
}
