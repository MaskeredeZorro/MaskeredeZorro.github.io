import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// Sørg for at stierne passer til dine filer
import '../screens/auth/welcome_screen.dart';
import '../screens/chat_detail_screen.dart'; // <--- VIGTIGT: Brug den nye chat fil
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

  final String _mapboxToken =
      "pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // ... (Behold dine eksisterende funktioner: _calculateAndDistributeCO2, _updateBookingStatus, _completeTrip) ...
  // For overskuelighedens skyld har jeg skjult dem her i svaret, men du skal BEHOLDE dem i din fil.
  // Indsæt dem herunder:

  Future<void> _calculateAndDistributeCO2(String rideId) async {
    /* ... Din eksisterende kode ... */
  }

  Future<void> _updateBookingStatus(String bookingId, String newStatus) async {
    /* ... Din eksisterende kode ... */
  }

  Future<void> _completeTrip(String rideId) async {
    /* ... Din eksisterende kode ... */
  }

  // --- HJÆLPER: Vælg passager at chatte med (For chaufføren) ---
  void _showPassengerSelector(String rideId, String rideTitle) async {
    // 1. Hent godkendte passagerer
    final response = await Supabase.instance.client
        .from('bookings')
        .select('passenger_id, profiles(*)') // Hent profil data
        .eq('ride_id', rideId)
        .eq('status', 'approved');

    if (!mounted) return;

    final passengers = List<Map<String, dynamic>>.from(response);

    if (passengers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ingen godkendte passagerer at skrive til endnu."),
        ),
      );
      return;
    }

    // 2. Vis liste i bunden
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
                    // 3. Åbn 1-til-1 chatten
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          otherUserId: booking['passenger_id'],
                          otherUserName: profile['full_name'] ?? 'Passager',
                          rideId: rideId, // Vi linker beskeden til denne tur
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

  // --- HJÆLPER: Formater dato pænt ---
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('d. MMM • HH:mm').format(date);
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
      backgroundColor: _bgLight, // Lys baggrund for bedre kontrast til cards
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
          // --- 1. TOP MENU ---
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

          // --- 2. TAB BAR ---
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

          // --- 3. LISTER ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ==========================
                // FANE 1: JEG KØRER (DRIVER)
                // ==========================
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('rides')
                      .stream(primaryKey: ['id'])
                      .eq('driver_id', _userId)
                      .order('departure_time', ascending: true),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    final rides = snapshot.data!
                        .where((ride) => ride['status'] != 'completed')
                        .toList();

                    if (rides.isEmpty) {
                      return _buildEmptyState("Du har ingen aktive ture.");
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        final ride = rides[index];
                        return _buildDriverRideCard(ride);
                      },
                    );
                  },
                ),

                // ==============================
                // FANE 2: JEG REJSER (PASSENGER)
                // ==============================
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
                    if (bookings.isEmpty) {
                      return _buildEmptyState("Du har ikke booket nogen ture.");
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: bookings.length,
                      itemBuilder: (context, index) {
                        final booking = bookings[index];
                        return FutureBuilder<Map<String, dynamic>>(
                          future: Supabase.instance.client
                              .from('rides')
                              .select('*, profiles(*)') // Hent chauffør info
                              .eq('id', booking['ride_id'])
                              .single(),
                          builder: (context, rSnapshot) {
                            if (!rSnapshot.hasData) return const SizedBox();
                            return _buildPassengerRideCard(
                              booking,
                              rSnapshot.data!,
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

  // --- WIDGET: Driver Ride Card (Nyt Design) ---
  Widget _buildDriverRideCard(Map<String, dynamic> ride) {
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
          // Header: Rute og Tid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.drive_eta, color: _accentColor),
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
                      const SizedBox(height: 4),
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
                    fontSize: 18,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Liste af Bookings (Live)
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
                    "Ingen passagerer endnu",
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

          const Divider(height: 1),

          // Knapper: Kontakt Passagerer & Afslut Tur
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // 1. Kontakt Passagerer (NY LOGIK)
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

                // 2. Afslut Tur
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
        ],
      ),
    );
  }

  // --- WIDGET: Passenger Ride Card (Nyt Design) ---
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
                    // ÅBN CHAT DIREKTE MED CHAUFFØREN
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
            ),
          ],
        ],
      ),
    );
  }

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
