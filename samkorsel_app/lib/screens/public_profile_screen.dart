import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId; // ID på den person vi kigger på

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _reviews = [];
  int _rideCount = 0;
  double _averageRating = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    final client = Supabase.instance.client;
    
    try {
      // 1. Hent Profil Info
      final profileData = await client.from('profiles').select().eq('id', widget.userId).single();
      
      // 2. Hent Reviews
      final reviewsData = await client
          .from('reviews')
          .select('*, profiles:reviewer_id(*)') // Hent også navn på dem der skrev
          .eq('reviewee_id', widget.userId)
          .order('created_at', ascending: false);
      
      // 3. Hent Antal Ture (Som chauffør)
      final ridesCount = await client
          .from('rides')
          .count()
          .eq('driver_id', widget.userId);

      // Udregn snit
      final reviews = List<Map<String, dynamic>>.from(reviewsData);
      double totalStars = 0;
      if (reviews.isNotEmpty) {
        for (var r in reviews) totalStars += r['rating'];
        _averageRating = totalStars / reviews.length;
      }

      if (mounted) {
        setState(() {
          _profile = profileData;
          _reviews = reviews;
          _rideCount = ridesCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fejl: $e");
      setState(() => _isLoading = false);
    }
  }

  // -- VIS DIALOG TIL AT SKRIVE REVIEW --
  void _showAddReviewDialog() {
    final commentController = TextEditingController();
    int selectedStars = 5;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder( // Vigtig for at opdatere stjernerne i dialogen
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Skriv anmeldelse"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < selectedStars ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 30,
                        ),
                        onPressed: () {
                          setDialogState(() => selectedStars = index + 1);
                        },
                      );
                    }),
                  ),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(labelText: "Kommentar", hintText: "F.eks. God kørestil, kom til tiden..."),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULLER")),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context); // Luk dialog
                    await _submitReview(selectedStars, commentController.text);
                  },
                  child: const Text("SEND"),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitReview(int rating, String comment) async {
    try {
      final myId = Supabase.instance.client.auth.currentUser!.id;
      
      // Man kan ikke anmelde sig selv
      if (myId == widget.userId) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Du kan ikke anmelde dig selv!")));
        return;
      }

      await Supabase.instance.client.from('reviews').insert({
        'reviewer_id': myId,
        'reviewee_id': widget.userId,
        'rating': rating,
        'comment': comment,
      });

      _fetchAllData(); // Opdater listen
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tak for din anmeldelse!"), backgroundColor: Colors.green));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fejl: Kunne ikke sende.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null) return const Scaffold(body: Center(child: Text("Profil ikke fundet")));

    return Scaffold(
      appBar: AppBar(title: const Text("Profil")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. TOP HEADER (Billede + Navn)
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundImage: _profile!['avatar_url'] != null ? NetworkImage(_profile!['avatar_url']) : null,
              child: _profile!['avatar_url'] == null ? const Icon(Icons.person, size: 50) : null,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              _profile!['full_name'] ?? "Anonym",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          if (_profile!['is_verified_mitid'] == true)
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.verified, color: Colors.blue, size: 16),
              SizedBox(width: 5),
              Text("MitID Verificeret", style: TextStyle(color: Colors.blue)),
            ]),

          const SizedBox(height: 30),

          // 2. SCOREBOARD
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem("Ture kørt", "$_rideCount"),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              _buildStatItem("Rating", _averageRating.toStringAsFixed(1), icon: Icons.star, iconColor: Colors.amber),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              _buildStatItem("Reviews", "${_reviews.length}"),
            ],
          ),

          const SizedBox(height: 30),
          const Divider(),
          
          // 3. ANMELDELSER HEADER
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Anmeldelser", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _showAddReviewDialog,
                icon: const Icon(Icons.edit),
                label: const Text("Skriv"),
              )
            ],
          ),

          // 4. REVIEW LISTE
          if (_reviews.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("Ingen anmeldelser endnu.")))
          else
            ..._reviews.map((review) {
              final reviewer = review['profiles'];
              final date = DateTime.parse(review['created_at']);
              
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: reviewer?['avatar_url'] != null ? NetworkImage(reviewer['avatar_url']) : null,
                    child: reviewer?['avatar_url'] == null ? Text(reviewer?['full_name']?[0] ?? "?") : null,
                  ),
                  title: Text(reviewer?['full_name'] ?? "Slettet bruger"),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: List.generate(5, (i) => Icon(i < review['rating'] ? Icons.star : Icons.star_border, size: 14, color: Colors.amber))),
                      const SizedBox(height: 4),
                      Text(review['comment'] ?? ""),
                    ],
                  ),
                  trailing: Text("${date.day}/${date.month}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {IconData? icon, Color? iconColor}) {
    return Column(
      children: [
        Row(
          children: [
            if (icon != null) Icon(icon, color: iconColor, size: 20),
            if (icon != null) const SizedBox(width: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }
}