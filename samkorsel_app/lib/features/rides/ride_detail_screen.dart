import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // GoMore bruger en dyb grøn farve
  final Color _goMoreGreen = const Color(0xFF005C4B);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final client = Supabase.instance.client;
      
      // Hent chauffør info
      final driverData = await client
          .from('profiles')
          .select()
          .eq('id', widget.ride['driver_id'])
          .single();
      
      // Hent passagerer
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Log ind for at booke")));
      setState(() => _isLoading = false);
      return;
    }

    try {
      if (widget.ride['driver_id'] == user.id) throw Exception("Du kan ikke booke din egen tur!");

      // Tjek eksisterende booking
      final existing = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('ride_id', widget.ride['id'])
          .eq('passenger_id', user.id)
          .maybeSingle();
      
      if (existing != null) throw Exception("Du har allerede anmodet om denne tur.");

      await Supabase.instance.client.from('bookings').insert({
        'ride_id': widget.ride['id'],
        'passenger_id': user.id,
        'seats_booked': 1,
        'status': 'pending',
      });

      setState(() => _hasBooked = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Anmodning sendt!"), backgroundColor: Colors.green)
        );
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${e.toString().replaceAll('Exception: ', '')}"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dato formatering
    DateTime departureTime;
    try { departureTime = DateTime.parse(widget.ride['departure_time']); } catch (_) { departureTime = DateTime.now(); }
    
    // Beregn ankomsttid (Simuleret: Vi lægger 2 timer til for demoens skyld, da vi ikke har GPS tid endnu)
    final arrivalTime = departureTime.add(const Duration(hours: 2, minutes: 15));
    
    final dateStr = "${departureTime.day}/${departureTime.month}";
    final depTimeStr = "${departureTime.hour}:${departureTime.minute.toString().padLeft(2, '0')}";
    final arrTimeStr = "${arrivalTime.hour}:${arrivalTime.minute.toString().padLeft(2, '0')}";

    // Data
    final isFerry = widget.ride['is_ferry'] == true;
    final totalSeats = widget.ride['seats_available'] ?? 0;
    final luggage = widget.ride['luggage_size'] ?? "Mellem";
    final carModel = widget.ride['car_model'] ?? "Ukendt bil";
    final comment = widget.ride['comment'];

    return Scaffold(
      backgroundColor: Colors.white, // GoMore er meget hvid/ren
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(dateStr, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
           IconButton(icon: const Icon(Icons.share_outlined, color: Colors.black), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          // --- HOVED INDHOLD ---
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 100), // Plads til bundbaren
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                // 1. DEN VERTIKALE RUTE (GoMore Style)
                _buildTimelineStep(depTimeStr, widget.ride['origin_city'], isStart: true),
                _buildTimelineConnector(isFerry: isFerry),
                _buildTimelineStep(arrTimeStr, widget.ride['destination_city'], isEnd: true),

                const SizedBox(height: 30),
                const Divider(thickness: 1, color: Color(0xFFF0F0F0)),
                const SizedBox(height: 20),

                // 2. PRIS OVERBLIK (Total pris for 1 passager)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Samlet pris for 1 passager", style: TextStyle(color: Colors.grey, fontSize: 16)),
                    Text("${widget.ride['price_dkk']} kr.", style: TextStyle(color: _goMoreGreen, fontWeight: FontWeight.bold, fontSize: 22)),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(thickness: 8, color: Color(0xFFF5F7FA)), // Tyk separator
                const SizedBox(height: 20),

                // 3. CHAUFFØR PROFIL
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: widget.ride['driver_id']))),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: _driverProfile?['avatar_url'] != null ? NetworkImage(_driverProfile!['avatar_url']) : null,
                            child: _driverProfile?['avatar_url'] == null ? const Icon(Icons.person, size: 30, color: Colors.grey) : null,
                          ),
                          if (_driverProfile?['is_verified_mitid'] == true)
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: const Icon(Icons.check_circle, color: Colors.blue, size: 20),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_driverProfile?['full_name'] ?? "Henter...", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 4),
                            // Fake rating for nu (GoMore har stjerner)
                            const Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 16),
                                Text(" 4.9/5 ", style: TextStyle(fontWeight: FontWeight.bold)),
                                Text("• 12 bedømmelser", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            )
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                if (comment != null && comment.toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10)),
                    child: Text('"$comment"', style: TextStyle(color: Colors.grey[800], fontStyle: FontStyle.italic)),
                  ),

                const SizedBox(height: 20),
                const Divider(thickness: 1, color: Color(0xFFF0F0F0)),
                const SizedBox(height: 20),

                // 4. BIL & DETALJER
                Text("Køretøj & Komfort", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.directions_car_filled, color: Colors.black54, size: 30),
                    ),
                    const SizedBox(width: 15),
                    Text(carModel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Faciliteter (Chips)
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: [
                    _buildFeature(Icons.luggage, luggage),
                    if (widget.ride['detour_flex'] == true) _buildFeature(Icons.alt_route, "Fleksibel"),
                    if (widget.ride['comfort_guarantee'] == true) _buildFeature(Icons.airline_seat_recline_extra, "Max 2 bag"),
                    if (widget.ride['pref_pets'] == true) _buildFeature(Icons.pets, "Dyr OK"),
                    if (widget.ride['pref_music'] == true) _buildFeature(Icons.music_note, "Musik OK"),
                    if (widget.ride['pref_smoking'] == false) _buildFeature(Icons.smoke_free, "Ingen røg"),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(thickness: 8, color: Color(0xFFF5F7FA)),
                const SizedBox(height: 20),

                // 5. PASSAGERER
                Text("Passagerer", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 15),
                
                // Visning af sæder
                Column(
                  children: List.generate(totalSeats, (index) {
                    final isTaken = index < _passengers.length;
                    
                    if (isTaken) {
                      // BOOKET PASSAGER
                      final p = _passengers[index]['profiles'];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(backgroundImage: p['avatar_url'] != null ? NetworkImage(p['avatar_url']) : null, child: p['avatar_url'] == null ? Text(p['full_name'][0]) : null),
                        title: Text(p['full_name']),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: p['id']))),
                      );
                    } else {
                      // LEDIGT SÆDE ("Kunne være dig")
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)),
                          child: const Icon(Icons.add, color: Colors.grey),
                        ),
                        title: const Text("Ledig plads", style: TextStyle(color: Colors.grey)),
                        subtitle: const Text("Kunne være dig?", style: TextStyle(color: Color(0xFF005C4B), fontWeight: FontWeight.bold)),
                      );
                    }
                  }),
                ),
              ],
            ),
          ),

          // --- STICKY BOTTOM BAR (Som GoMore) ---
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))],
                border: Border(top: BorderSide(color: Colors.grey.shade200))
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Pris venstre side
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("${widget.ride['price_dkk']} kr.", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                        const Text("pr. plads", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(width: 20),
                    // Book knap højre side
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isLoading || _hasBooked) ? null : _bookRide,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasBooked ? Colors.grey : _goMoreGreen,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: Text(
                          _hasBooked ? "Anmodning sendt" : "Book plads", 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- HJÆLPE WIDGETS TIL LAYOUT ---
  
  // Tidslinje punkt (Klokkeslæt + By)
  Widget _buildTimelineStep(String time, String city, {bool isStart = false, bool isEnd = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        Column(
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: isStart || isEnd ? _goMoreGreen : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _goMoreGreen, width: 2),
              ),
            ),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(city.split(',')[0], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)), // Fjern postnummer visuelt
        ),
      ],
    );
  }

  // Tidslinje streg (Med evt færge ikon)
  Widget _buildTimelineConnector({bool isFerry = false}) {
    return IntrinsicHeight(
      child: Row(
        children: [
          const SizedBox(width: 60), // Samme bredde som tids-kolonnen
          SizedBox(
            width: 12,
            child: Center(
              child: Column(
                children: [
                  Expanded(child: Container(width: 2, color: Colors.grey[300])), // Stregen
                  if (isFerry) ...[
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: const Icon(Icons.directions_boat, size: 16, color: Colors.blue),
                    ),
                    Expanded(child: Container(width: 2, color: Colors.grey[300])),
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Her kunne man skrive "2t 15m kørsel" hvis man beregnede det
          if (isFerry) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("Inkl. Færgeoverfart", style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)))
        ],
      ),
    );
  }

  // Facilitet Chip (Ikon + Tekst)
  Widget _buildFeature(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.grey[800], fontSize: 13)),
        const SizedBox(width: 15),
      ],
    );
  }
}