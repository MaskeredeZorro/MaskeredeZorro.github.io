import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_stripe/flutter_stripe.dart'; // <--- VIGTIGT: Denne skal stå her!

// Juster stien herunder hvis din public profile ligger et andet sted
import '../../screens/public_profile_screen.dart';

class RideDetailScreen extends StatefulWidget {
  final Map<String, dynamic> ride;

  const RideDetailScreen({super.key, required this.ride});

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  bool _isLoading = false;
  bool _hasBooked = false;
  Map<String, dynamic>? _driverProfile;
  List<Map<String, dynamic>> _passengers = [];

  // --- DESIGN TEMA (Slate & Indigo) ---
  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _accentColor = const Color(0xFF6366F1);
  final Color _bgLight = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final client = Supabase.instance.client;
      // 1. Hent chauffør
      final driverData = await client
          .from('profiles')
          .select()
          .eq('id', widget.ride['driver_id'])
          .single();
      // 2. Hent passagerer
      final bookingsData = await client
          .from('bookings')
          .select('*, profiles(*)')
          .eq('ride_id', widget.ride['id'])
          .eq('status', 'approved');

      if (mounted) {
        setState(() {
          _driverProfile = driverData;
          _passengers = List<Map<String, dynamic>>.from(bookingsData);
        });
      }
    } catch (e) {
      debugPrint("Data fejl: $e");
    }
  }

  Future<void> _bookRide() async {
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Log ind for at booke")));
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Tjek: Booker man sin egen tur?
      if (widget.ride['driver_id'] == user.id)
        throw Exception("Du kan ikke booke din egen tur!");

      // 2. Tjek: Har man allerede booket?
      final existing = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('ride_id', widget.ride['id'])
          .eq('passenger_id', user.id)
          .maybeSingle();

      if (existing != null)
        throw Exception("Du har allerede anmodet om plads.");

      // 3. START BETALING: Kald Edge Function
      final double price = (widget.ride['price_dkk'] as num).toDouble();

      final res = await Supabase.instance.client.functions.invoke(
        'payment-sheet',
        body: {'amount': price, 'currency': 'dkk'},
      );

      if (res.status != 200)
        throw Exception("Kunne ikke kontakte betalings-serveren");

      final data = res.data;

      // 4. Initialiser Stripe Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: data['paymentIntent'],
          merchantDisplayName: 'HoppOn',
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'DK'),
          googlePay: const PaymentSheetGooglePay(merchantCountryCode: 'DK'),
        ),
      );

      // 5. Vis betalingsvinduet
      await Stripe.instance.presentPaymentSheet();

      // --- HVIS VI KOMMER HERTIL, ER BETALINGEN GODKENDT ---

      // 6. Opret bookingen i Supabase
      await Supabase.instance.client.from('bookings').insert({
        'ride_id': widget.ride['id'],
        'passenger_id': user.id,
        'seats_booked': 1,
        'status': 'approved',
      });

      // 7. Håndter Chaufførens penge
      final driverId = widget.ride['driver_id'];

      // Upsert wallet for driver
      await Supabase.instance.client.from('wallets').upsert({
        'user_id': driverId,
      }, onConflict: 'user_id');

      // Hent wallet ID
      final walletRes = await Supabase.instance.client
          .from('wallets')
          .select('id, balance')
          .eq('user_id', driverId)
          .single();

      final walletId = walletRes['id'];
      final double currentBalance = (walletRes['balance'] as num).toDouble();
      final double earnings = price - 9.0; // Gebyr på 9 kr

      // Opdater saldo
      await Supabase.instance.client
          .from('wallets')
          .update({'balance': currentBalance + earnings})
          .eq('id', walletId);

      // Log transaktionen
      await Supabase.instance.client.from('transactions').insert({
        'wallet_id': walletId,
        'amount': earnings,
        'type': 'booking_payment',
        'description':
            'Tur: ${widget.ride['origin_city']} -> ${widget.ride['destination_city']}',
      });

      setState(() => _hasBooked = true);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Betaling godkendt! God tur 🚗"),
            backgroundColor: Colors.green,
          ),
        );
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Betaling annulleret"),
              backgroundColor: Colors.orange,
            ),
          );
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Stripe Fejl: ${e.error.localizedMessage}"),
              backgroundColor: Colors.red,
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Fejl: ${e.toString().replaceAll('Exception: ', '')}",
            ),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openChat() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          rideId: widget.ride['id'],
          otherUserId: widget.ride['driver_id'],
          rideTitle:
              "${widget.ride['origin_city'].split(',')[0]} - ${widget.ride['destination_city'].split(',')[0]}",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime depTime = DateTime.parse(widget.ride['departure_time']);
    DateTime arrTime = widget.ride['arrival_time'] != null
        ? DateTime.parse(widget.ride['arrival_time'])
        : depTime.add(const Duration(hours: 2));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: _bgLight, shape: BoxShape.circle),
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.black, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          "Tur detaljer",
          style: TextStyle(
            color: _primaryColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PRIS I TOPPEN
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        DateFormat('d. MMM • HH:mm').format(depTime),
                        style: TextStyle(
                          color: _accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      "${widget.ride['price_dkk']} kr.",
                      style: TextStyle(
                        color: _primaryColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // --- 1. TIDSLINJE ---
                _buildTimelineRow(
                  DateFormat('HH:mm').format(depTime),
                  widget.ride['origin_city'],
                  isStart: true,
                ),
                _buildTimelineConnector(
                  isFerry: widget.ride['is_ferry'] ?? false,
                ),
                _buildTimelineRow(
                  DateFormat('HH:mm').format(arrTime),
                  widget.ride['destination_city'],
                  isEnd: true,
                ),

                const SizedBox(height: 30),

                // --- 2. KOMMENTAR ---
                if (widget.ride['comment'] != null &&
                    widget.ride['comment'].toString().isNotEmpty) ...[
                  Text(
                    "Besked fra chaufføren",
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _bgLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      '${widget.ride['comment']}',
                      style: TextStyle(
                        fontStyle: FontStyle.normal,
                        color: Colors.grey.shade800,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],

                // --- 3. DET PRAKTISKE ---
                Text(
                  "Det praktiske",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Column(
                  children: [
                    _buildPracticalRow(
                      Icons.luggage_outlined,
                      "Bagage: ${widget.ride['luggage_size']}",
                      "Plads til fx en ${widget.ride['luggage_size'].toString().toLowerCase()} kuffert eller taske.",
                    ),
                    if (widget.ride['detour_flex'] == true)
                      _buildPracticalRow(
                        Icons.alt_route,
                        "Fleksibel rute",
                        "Chaufføren er villig til at køre en omvej på maks. 15 minutter for at samle op.",
                      ),
                    if (widget.ride['comfort_guarantee'] == true)
                      _buildPracticalRow(
                        Icons.airline_seat_recline_extra,
                        "Komfort garanti",
                        "Chaufføren garanterer maks. 2 passagerer på bagsædet for bedre plads.",
                      ),
                    if (widget.ride['instant_booking'] == true)
                      _buildPracticalRow(
                        Icons.bolt,
                        "Lynbooking",
                        "Din anmodning bliver godkendt med det samme uden ventetid.",
                        iconColor: Colors.amber[700],
                      ),
                  ],
                ),

                const SizedBox(height: 30),

                // --- 4. HUSREGLER ---
                Text(
                  "Husregler",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildRuleItem("Musik", widget.ride['pref_music']),
                          _buildRuleItem("Kæledyr", widget.ride['pref_pets']),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _buildRuleItem(
                            "Rygning",
                            widget.ride['pref_smoking'],
                          ),
                          _buildRuleItem("Børn", widget.ride['pref_kids']),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // --- 5. DRIVER CARD ---
                Text(
                  "Chauffør",
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _buildDriverCard(),
                ),

                const SizedBox(height: 30),

                // --- 6. PASSAGERER ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Passagerer",
                      style: TextStyle(
                        color: _primaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "${widget.ride['seats_available']} pladser total",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Column(
                  children: List.generate(widget.ride['seats_available'], (
                    index,
                  ) {
                    if (index < _passengers.length) {
                      final p = _passengers[index]['profiles'];
                      return _buildPassengerRow(p, isMe: false);
                    }
                    return _buildPassengerRow(null, isMe: true);
                  }),
                ),

                const SizedBox(height: 30),
                Center(
                  child: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text(
                      "Rapporter tur",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  ),
                ),
              ],
            ),
          ),

          // --- STICKY BOTTOM BUTTON ---
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: (_isLoading || _hasBooked) ? null : _bookRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: _primaryColor.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.ride['instant_booking'] == true) ...[
                      const Icon(Icons.bolt, color: Colors.amber),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _hasBooked ? "Anmodning sendt ✓" : "Book plads nu",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildTimelineRow(
    String time,
    String address, {
    bool isStart = false,
    bool isEnd = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(
            time,
            style: TextStyle(
              color: _primaryColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isStart || isEnd ? _accentColor : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _accentColor, width: 2),
              ),
            ),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                address.split(',')[0],
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                address,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineConnector({bool isFerry = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Center(
                child: Column(
                  children: [
                    Expanded(
                      child: Container(width: 2, color: Colors.grey.shade200),
                    ),
                    if (isFerry) ...[
                      Icon(
                        Icons.directions_boat,
                        size: 16,
                        color: _accentColor,
                      ),
                      Expanded(
                        child: Container(width: 2, color: Colors.grey.shade200),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            if (isFerry)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Text(
                  "Færgeoverfart",
                  style: TextStyle(
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              const SizedBox(height: 35),
          ],
        ),
      ),
    );
  }

  Widget _buildPracticalRow(
    IconData icon,
    String title,
    String description, {
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (iconColor ?? _primaryColor).withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: iconColor ?? _primaryColor),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleItem(String label, bool? allowed) {
    bool isAllowed = allowed == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isAllowed
            ? Colors.green.withOpacity(0.05)
            : Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAllowed
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isAllowed ? Icons.check_circle : Icons.cancel,
            color: isAllowed ? Colors.green : Colors.red.shade300,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isAllowed ? _primaryColor : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerRow(
    Map<String, dynamic>? profile, {
    required bool isMe,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: InkWell(
        onTap: profile != null
            ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(userId: profile['id']),
                ),
              )
            : null,
        child: Row(
          children: [
            if (profile != null)
              CircleAvatar(
                backgroundImage: profile['avatar_url'] != null
                    ? NetworkImage(profile['avatar_url'])
                    : null,
                radius: 24,
                child: profile['avatar_url'] == null
                    ? Text(profile['full_name'][0])
                    : null,
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Icon(Icons.add, color: Colors.grey),
              ),

            const SizedBox(width: 15),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile != null ? profile['full_name'] : "Ledig plads",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _primaryColor,
                  ),
                ),
                if (profile == null)
                  Text(
                    "Kunne være dig?",
                    style: TextStyle(
                      color: _accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  const Text(
                    "Passager",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
            const Spacer(),
            if (profile != null)
              const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverCard() {
    String carMain = "Ukendt bil";
    String carSub = "Ingen info";

    final rawCarData = widget.ride['car_model'];

    if (rawCarData != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(rawCarData);
        carMain = data['make'] ?? "Bil";
        carSub = data['details'] ?? "";
      } catch (e) {
        carMain = rawCarData.toString();
        carSub = _driverProfile?['license_plate'] ?? "";
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PublicProfileScreen(userId: widget.ride['driver_id']),
                ),
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _driverProfile?['avatar_url'] != null
                    ? NetworkImage(_driverProfile!['avatar_url'])
                    : null,
                child: _driverProfile?['avatar_url'] == null
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _driverProfile?['full_name'] ?? "Chauffør",
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    carMain,
                    style: TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (carSub.isNotEmpty)
                    Text(
                      carSub,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (_driverProfile?['is_verified_mitid'] == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user, size: 14, color: Colors.green),
                    SizedBox(width: 4),
                    Text(
                      "Verificeret",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openChat,
            icon: Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: _primaryColor,
            ),
            label: Text(
              "Send besked",
              style: TextStyle(
                color: _primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- MINIMAL CHAT SCREEN (Placeholder) ---
class ChatScreen extends StatelessWidget {
  final String rideId;
  final String otherUserId;
  final String rideTitle;

  const ChatScreen({
    super.key,
    required this.rideId,
    required this.otherUserId,
    required this.rideTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(rideTitle),
        elevation: 1,
        foregroundColor: Colors.black,
        backgroundColor: Colors.white,
      ),
      body: const Center(child: Text("Chat funktion kommer her...")),
    );
  }
}
