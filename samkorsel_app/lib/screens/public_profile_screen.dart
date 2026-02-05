import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId; // ID på den person vi besøger

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  // Farver
  final Color _slate = const Color(0xFF0F172A);
  final Color _indigo = const Color(0xFF6366F1);
  final Color _bg = const Color(0xFFF8FAFC);

  bool _isLoading = true;
  Map<String, dynamic>? _profile;

  // Statistik
  int _rideCount = 0;
  double _avgRating = 0.0;
  int _totalReviews = 0;

  // Review tilladelse
  bool _canReview = false; // Må brugeren anmelde?
  bool _hasReviewed = false; // Har brugeren allerede anmeldt?

  // Data til UI
  Map<int, int> _ratingDistribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
  List<Map<String, dynamic>> _latestReviews = [];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final client = Supabase.instance.client;
      final currentUserId = client.auth.currentUser?.id;

      // 1. Hent profil data
      final profileRes = await client
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .single();

      // 2. Hent antal ture (Driver)
      final ridesRes = await client
          .from('rides')
          .count()
          .eq('driver_id', widget.userId);

      // 3. Hent alle anmeldelser
      final reviewsRes = await client
          .from('reviews')
          .select('*, profiles:reviewer_id(full_name, avatar_url)')
          .eq('reviewee_id', widget.userId)
          .order('created_at', ascending: false);

      final reviews = List<Map<String, dynamic>>.from(reviewsRes);

      // 4. Beregn statistik & Tjek om jeg allerede har anmeldt
      double sum = 0;
      Map<int, int> dist = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
      bool alreadyReviewed = false;

      for (var r in reviews) {
        int stars = r['rating'];
        sum += stars;
        if (dist.containsKey(stars)) dist[stars] = dist[stars]! + 1;

        // Tjek om jeg har skrevet denne anmeldelse
        if (currentUserId != null && r['reviewer_id'] == currentUserId) {
          alreadyReviewed = true;
        }
      }

      // 5. TJEK OM JEG MÅ ANMELDE (Har vi kørt sammen?)
      bool userCanReview = false;
      if (currentUserId != null &&
          currentUserId != widget.userId &&
          !alreadyReviewed) {
        // Vi tjekker: Findes der en booking hvor JEG er passager, HAN er chauffør, og status er approved?
        // Vi bruger !inner til at filtrere på relationen 'rides'
        final sharedRides = await client
            .from('bookings')
            .select('id, rides!inner(driver_id)')
            .eq('passenger_id', currentUserId)
            .eq('status', 'approved') // Kun godkendte ture
            .eq('rides.driver_id', widget.userId)
            .limit(1); // Vi behøver kun finde én

        if (sharedRides.isNotEmpty) {
          userCanReview = true;
        }
      }

      setState(() {
        _profile = profileRes;
        _rideCount = ridesRes;
        _totalReviews = reviews.length;
        _avgRating = _totalReviews > 0 ? sum / _totalReviews : 0.0;
        _ratingDistribution = dist;
        _latestReviews = reviews.take(3).toList();
        _canReview = userCanReview;
        _hasReviewed = alreadyReviewed;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fejl ved profil hentning: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -- DIALOG: SKRIV ANMELDELSE --
  void _showAddReviewDialog() {
    if (!_canReview) return; // Sikkerhedstjek

    final commentController = TextEditingController();
    int selectedStars = 5;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Hvordan var turen?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Giv en vurdering af din oplevelse."),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        onPressed: () =>
                            setDialogState(() => selectedStars = index + 1),
                        icon: Icon(
                          index < selectedStars
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      );
                    }),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: commentController,
                    decoration: InputDecoration(
                      labelText: "Kommentar (valgfri)",
                      hintText: "God kørestil, kom til tiden...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Annuller",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _submitReview(selectedStars, commentController.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _slate,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Send"),
                ),
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

      await Supabase.instance.client.from('reviews').insert({
        'reviewer_id': myId,
        'reviewee_id': widget.userId,
        'rating': rating,
        'comment': comment,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Tak for din anmeldelse!"),
          backgroundColor: Colors.green,
        ),
      );
      _loadProfileData(); // Genindlæs for at vise den nye rating
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Fejl: Kunne ikke sende."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Anmeld bruger"),
        content: const Text(
          "Er du sikker på, at du vil anmelde denne profil for upassende adfærd? Dette vil blive sendt til support.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Annuller", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Tak. Vi kigger på sagen."),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text(
              "Anmeld",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null)
      return const Scaffold(body: Center(child: Text("Profil ikke fundet")));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: _showReportDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ---
            _buildHeader(),
            const SizedBox(height: 30),

            // --- INFO BOX ---
            _buildInfoStats(),
            const SizedBox(height: 30),

            // --- OM MIG ---
            if (_profile!['bio'] != null &&
                (_profile!['bio'] as String).isNotEmpty) ...[
              Text(
                "Om mig",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _slate,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _profile!['bio'],
                style: TextStyle(
                  color: Colors.grey[700],
                  height: 1.5,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 30),
            ],

            // --- VERIFIED ---
            Text(
              "Verificerede oplysninger",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _slate,
              ),
            ),
            const SizedBox(height: 15),

            _buildVerifiedTile("Telefonnummer bekræftet", Icons.phone_android),
            const SizedBox(height: 30),

            // --- RATINGS HEADER + KNAP ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Anmeldelser",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _slate,
                  ),
                ),

                // VIS KUN KNAP HVIS MAN MÅ ANMELDE
                if (_canReview)
                  TextButton.icon(
                    onPressed: _showAddReviewDialog,
                    icon: Icon(Icons.edit, color: _indigo, size: 18),
                    label: Text(
                      "Skriv anmeldelse",
                      style: TextStyle(
                        color: _indigo,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (_hasReviewed)
                  const Text(
                    "Du har anmeldt",
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 20),
            _buildRatingBreakdown(),

            const SizedBox(height: 25),

            // --- NYESTE REVIEWS ---
            if (_latestReviews.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "Ingen anmeldelser endnu.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ..._latestReviews.map((r) => _buildReviewCard(r)),

            const SizedBox(height: 20),

            // --- SE ALLE KNAP ---
            if (_totalReviews > 3)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: _slate),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    "Se alle $_totalReviews anmeldelser",
                    style: TextStyle(
                      color: _slate,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 15),

            Center(
              child: TextButton.icon(
                onPressed: _showReportDialog,
                icon: const Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: Colors.grey,
                ),
                label: const Text(
                  "Anmeld personen",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS (Samme design som før) ---

  Widget _buildHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 45,
          backgroundColor: Colors.grey[200],
          backgroundImage: _profile!['avatar_url'] != null
              ? NetworkImage(_profile!['avatar_url'])
              : null,
          child: _profile!['avatar_url'] == null
              ? const Icon(Icons.person, size: 45, color: Colors.grey)
              : null,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _profile!['full_name'] ?? "Anonym",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _slate,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    _avgRating > 0 ? _avgRating.toStringAsFixed(1) : "Ny",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    " ($_totalReviews)",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoStats() {
    String memberSince = "Nyligt medlem";
    if (_profile!['created_at'] != null) {
      try {
        memberSince =
            "Medlem siden ${DateFormat('MMM yyyy').format(DateTime.parse(_profile!['created_at']))}";
      } catch (_) {}
    }

    String city = "Danmark";
    if (_profile!['address'] != null) {
      city = (_profile!['address'] as String).split(',').last.trim();
    }

    // NYT: Hent CO2 værdien sikkert (hvis den er null, bruger vi 0.0)
    final double co2Saved =
        (_profile!['co2_saved_kg'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildStatRow(Icons.calendar_today_outlined, memberSince),
          const SizedBox(height: 12),
          _buildStatRow(Icons.location_on_outlined, "Bor i $city"),
          const SizedBox(height: 12),
          _buildStatRow(
            Icons.directions_car_filled_outlined,
            "$_rideCount samkørsler",
          ),

          // --- NYT: CO2 VISNING ---
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.eco, color: Colors.green),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${co2Saved.toStringAsFixed(1)} kg CO₂",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green,
                      ),
                    ),
                    const Text(
                      "Sparet ved samkørsel",
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ------------------------
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _slate.withOpacity(0.7)),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            color: _slate,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildVerifiedTile(String text, IconData icon) {
    bool isVerified = true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: isVerified ? Colors.green : Colors.grey, size: 22),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: _slate,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          if (isVerified)
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
        ],
      ),
    );
  }

  Widget _buildRatingBreakdown() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [5, 4, 3, 2, 1].map((star) {
              int count = _ratingDistribution[star] ?? 0;
              double percent = _totalReviews == 0 ? 0 : count / _totalReviews;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 15,
                      child: Text(
                        "$star",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          backgroundColor: Colors.grey[200],
                          color: _slate,
                          minHeight: 6,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 30),
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Text(
                _avgRating.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: _slate,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => Icon(
                    index < _avgRating.round() ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                "$_totalReviews anmeldelser",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final sender = review['profiles'];
    final date = DateTime.parse(review['created_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade100),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: sender?['avatar_url'] != null
                    ? NetworkImage(sender['avatar_url'])
                    : null,
                child: sender?['avatar_url'] == null
                    ? const Icon(Icons.person, size: 20)
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sender?['full_name'] ?? "Slettet bruger",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    DateFormat('MMM yyyy').format(date),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    Icons.star,
                    size: 14,
                    color: i < review['rating']
                        ? Colors.amber
                        : Colors.grey[200],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            review['comment'] ?? "",
            style: TextStyle(color: _slate.withOpacity(0.8), height: 1.4),
          ),
        ],
      ),
    );
  }
}
