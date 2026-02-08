import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewScreen extends StatefulWidget {
  final String rideId;
  // Listen af folk der skal anmeldes.
  // Hver map skal indeholde: {'id': 'user_uuid', 'name': 'Navn', 'role': 'Chauffør/Passager'}
  final List<Map<String, String>> peopleToReview;

  const ReviewScreen({
    super.key,
    required this.rideId,
    required this.peopleToReview,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // Vi gemmer ratings og kommentarer for hver person baseret på deres ID
  final Map<String, int> _ratings = {};
  final Map<String, TextEditingController> _controllers = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Initialiser controllere
    for (var person in widget.peopleToReview) {
      _controllers[person['id']!] = TextEditingController();
      _ratings[person['id']!] = 5; // Standard 5 stjerner
    }
  }

  @override
  void dispose() {
    for (var c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _submitReviews() async {
    setState(() => _isSubmitting = true);
    final myId = Supabase.instance.client.auth.currentUser!.id;

    try {
      final List<Map<String, dynamic>> reviewsData = [];

      for (var person in widget.peopleToReview) {
        final targetId = person['id']!;
        reviewsData.add({
          'ride_id': widget.rideId,
          'reviewer_id': myId,
          'reviewee_id': targetId,
          'rating': _ratings[targetId],
          'comment': _controllers[targetId]!.text.trim(),
        });
      }

      await Supabase.instance.client.from('reviews').insert(reviewsData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Tak for dine anmeldelser! ⭐"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Luk skærmen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fejl: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Giv en anmeldelse")),
      body: widget.peopleToReview.isEmpty
          ? const Center(child: Text("Ingen at anmelde."))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: widget.peopleToReview.length,
              itemBuilder: (context, index) {
                final person = widget.peopleToReview[index];
                final id = person['id']!;

                return Card(
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Anmeld ${person['name']} (${person['role']})",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // STJERNER
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (starIndex) {
                            final int value = starIndex + 1;
                            return IconButton(
                              icon: Icon(
                                value <= (_ratings[id] ?? 0)
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                                size: 32,
                              ),
                              onPressed: () {
                                setState(() {
                                  _ratings[id] = value;
                                });
                              },
                            );
                          }),
                        ),

                        const SizedBox(height: 10),

                        // KOMMENTAR
                        TextField(
                          controller: _controllers[id],
                          decoration: const InputDecoration(
                            labelText: "Skriv en kommentar (valgfrit)",
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitReviews,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isSubmitting
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text(
                  "Indsend",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
        ),
      ),
    );
  }
}
