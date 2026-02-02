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

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final client = Supabase.instance.client;
      
      final driverData = await client.from('profiles').select().eq('id', widget.ride['driver_id']).single();
      
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
    } catch (e) { debugPrint("Data fejl: $e"); }
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

      final existing = await Supabase.instance.client.from('bookings').select().eq('ride_id', widget.ride['id']).eq('passenger_id', user.id).maybeSingle();
      if (existing != null) throw Exception("Du har allerede anmodet.");

      await Supabase.instance.client.from('bookings').insert({
        'ride_id': widget.ride['id'],
        'passenger_id': user.id,
        'seats_booked': 1,
        'status': 'pending',
      });

      setState(() => _hasBooked = true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Anmodning sendt!"), backgroundColor: Colors.green));

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${e.toString().replaceAll('Exception: ', '')}"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime date;
    try { date = DateTime.parse(widget.ride['departure_time']); } catch (_) { date = DateTime.now(); }
    final formattedDate = "${date.day}/${date.month} - Kl. ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    
    // Hent de nye data
    final isFerry = widget.ride['is_ferry'] == true;
    final detourFlex = widget.ride['detour_flex'] == true;
    final comfort = widget.ride['comfort_guarantee'] == true;
    final luggage = widget.ride['luggage_size'] ?? "Mellem";
    final comment = widget.ride['comment'];
    
    final prefMusic = widget.ride['pref_music'] == true;
    final prefPets = widget.ride['pref_pets'] == true;
    final prefSmoke = widget.ride['pref_smoking'] == true;

    final totalSeats = widget.ride['seats_available'] ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text("Tur detaljer")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // RUTE OG FÆRGE
            Row(children: [
              const Icon(Icons.circle_outlined, color: Colors.green, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.ride['origin_city'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Row(children: [
                Container(height: 40, decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2)))),
                if (isFerry) ...[
                  const SizedBox(width: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.shade100)),
                    child: const Row(children: [
                      Icon(Icons.directions_boat, color: Colors.blue, size: 20),
                      SizedBox(width: 5),
                      Text("Inkl. Færge", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                  ),
                ]
              ]),
            ),
            Row(children: [
              const Icon(Icons.location_on, color: Colors.red, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.ride['destination_city'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ]),

            const SizedBox(height: 30),

            // INFO BOX
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("Dato & Tid", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text("Pris", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text("${widget.ride['price_dkk']} kr.", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 18)),
                  ]),
                ],
              ),
            ),

            const SizedBox(height: 25),
            
            // NY SEKTION: FACILITETER & DETALJER
            const Text("Faciliteter", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildFeatureChip(Icons.luggage, "Bagage: $luggage"),
                if (detourFlex) _buildFeatureChip(Icons.alt_route, "Max 5 min afvigelse", color: Colors.green),
                if (comfort) _buildFeatureChip(Icons.airline_seat_recline_extra, "Komfort garanti (Max 2 bag)", color: Colors.purple),
              ],
            ),

            const SizedBox(height: 20),
            
            // NY SEKTION: PRÆFERENCER
            const Text("Præferencer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildPrefIcon(Icons.music_note, prefMusic, "Musik"),
                const SizedBox(width: 20),
                _buildPrefIcon(Icons.pets, prefPets, "Dyr"),
                const SizedBox(width: 20),
                _buildPrefIcon(Icons.smoking_rooms, prefSmoke, "Rygning"),
              ],
            ),

            if (comment != null && comment.toString().isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text("Kommentar fra chaufføren:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200)
                ),
                child: Text(comment, style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            ],

            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),
            
            // PASSAGER LISTE
            Text("Passagerer ($totalSeats pladser)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Column(
              children: List.generate(totalSeats, (index) {
                final isTaken = index < _passengers.length;
                if (isTaken) {
                  final passenger = _passengers[index]['profiles'];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: passenger['id']))),
                      leading: CircleAvatar(backgroundImage: passenger['avatar_url'] != null ? NetworkImage(passenger['avatar_url']) : null, child: passenger['avatar_url'] == null ? Text(passenger['full_name'][0]) : null),
                      title: Text(passenger['full_name']),
                      subtitle: const Text("Passager", style: TextStyle(color: Colors.green, fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    ),
                  );
                } else {
                  return Card(
                    color: Colors.grey.shade50,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.transparent, child: Icon(Icons.person_outline, color: Colors.grey)),
                      title: const Text("Ledig plads", style: TextStyle(color: Colors.grey)),
                      subtitle: const Text("Kunne være dig?", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      trailing: _hasBooked ? const Icon(Icons.check, color: Colors.grey) : const Icon(Icons.add_circle_outline, color: Colors.blue),
                    ),
                  );
                }
              }),
            ),

            const SizedBox(height: 20),

            // CHAUFFØR
            const Text("Chauffør", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: widget.ride['driver_id']))),
              child: Row(
                children: [
                  CircleAvatar(backgroundImage: _driverProfile?['avatar_url'] != null ? NetworkImage(_driverProfile!['avatar_url']) : null, child: const Icon(Icons.person)),
                  const SizedBox(width: 15),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_driverProfile?['full_name'] ?? "Henter...", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Text("Se profil & anmeldelser", style: TextStyle(color: Colors.blue, fontSize: 12)),
                  ]),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                ],
              ),
            ),
            
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 10),
             // BIL INFO
            const Text("Køretøj", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.directions_car, color: Colors.black54),
              const SizedBox(width: 15),
              Text(widget.ride['car_model'] ?? "Ingen bil info", style: const TextStyle(fontSize: 16)),
            ]),

            const SizedBox(height: 40),

            // BOOK KNAP
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: (_isLoading || _hasBooked) ? null : _bookRide,
                style: ElevatedButton.styleFrom(backgroundColor: _hasBooked ? Colors.grey : Colors.black, foregroundColor: Colors.white),
                child: Text(_hasBooked ? "Anmodning sendt ✓" : "BOOK PLADS", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // Hjælpe Widgets
  Widget _buildFeatureChip(IconData icon, String label, {Color color = Colors.black}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPrefIcon(IconData icon, bool allowed, String label) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(shape: BoxShape.circle, color: allowed ? Colors.green.shade50 : Colors.grey.shade100),
              child: Icon(icon, color: allowed ? Colors.green : Colors.grey),
            ),
            if (!allowed)
              const Icon(Icons.block, color: Colors.red, size: 40), // Rødt kryds over hvis ikke tilladt
          ],
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}