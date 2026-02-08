import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'public_profile_screen.dart';
import 'review_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? rideId;

  const ChatDetailScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.rideId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();
  final _myUserId = Supabase.instance.client.auth.currentUser!.id;
  bool _isSending = false;

  // Appens tema farve
  final Color _primaryColor = const Color(0xFF0F172A);

  String? _realName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    if (widget.otherUserId == 'system_hoppon') return;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', widget.otherUserId)
          .single();

      if (mounted) {
        setState(() {
          _realName = data['full_name'];
          _avatarUrl = data['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint("Kunne ikke hente profil: $e");
    }
  }

  Future<void> _handlePassengerReview(String rideId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final client = Supabase.instance.client;

      final rideData = await client
          .from('rides')
          .select('driver_id, profiles(full_name)')
          .eq('id', rideId)
          .single();

      final driverId = rideData['driver_id'];
      final profileData = rideData['profiles'] as Map<String, dynamic>?;
      final driverName = profileData?['full_name'] ?? 'Chauffør';

      final existingReview = await client
          .from('reviews')
          .select()
          .eq('ride_id', rideId)
          .eq('reviewer_id', _myUserId)
          .eq('reviewee_id', driverId)
          .maybeSingle();

      if (mounted) Navigator.pop(context);

      if (existingReview != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Du har allerede anmeldt denne tur ✅"),
            ),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReviewScreen(
              rideId: rideId,
              peopleToReview: [
                {'id': driverId, 'name': driverName, 'role': 'Chauffør'},
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      debugPrint("Fejl ved review start: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kunne ikke åbne anmeldelse. Prøv igen.")),
      );
    }
  }

  Stream<List<Map<String, dynamic>>> _getMessages() {
    return Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((messages) {
          return messages.where((msg) {
            final sender = msg['sender_id'];
            final receiver = msg['receiver_id'];

            final isMeToOther =
                (sender == _myUserId && receiver == widget.otherUserId);
            final isOtherToMe =
                (sender == widget.otherUserId && receiver == _myUserId);

            final isSystemToMe =
                (sender == null &&
                receiver == _myUserId &&
                widget.otherUserId == 'system_hoppon');

            return isMeToOther || isOtherToMe || isSystemToMe;
          }).toList();
        });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await Supabase.instance.client.from('messages').insert({
        'content': text,
        'sender_id': _myUserId,
        'receiver_id': widget.otherUserId,
        'ride_id': widget.rideId,
        'created_at': DateTime.now().toIso8601String(),
      });
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fejl: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatTime(String timestamp) {
    final date = DateTime.parse(timestamp).toLocal();
    return DateFormat('HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isSystemChat = widget.otherUserId == 'system_hoppon';
    final displayName = _realName ?? widget.otherUserName;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Lys baggrundsfarve
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            if (!isSystemChat)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PublicProfileScreen(userId: widget.otherUserId),
                    ),
                  );
                },
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: _avatarUrl != null
                      ? NetworkImage(_avatarUrl!)
                      : null,
                  child: _avatarUrl == null
                      ? const Icon(Icons.person, size: 20, color: Colors.grey)
                      : null,
                ),
              ),

            if (isSystemChat)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security,
                  size: 16,
                  color: Colors.white,
                ),
              ),

            const SizedBox(width: 10),

            if (!isSystemChat)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PublicProfileScreen(userId: widget.otherUserId),
                    ),
                  );
                },
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              const Text(
                "HoppOn",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _getMessages(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      "Start samtalen her 👋",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == _myUserId;
                    final isSystem = msg['sender_id'] == null;
                    final String? currentRideId = msg['ride_id'];

                    // --- NYT DESIGN: SYSTEM BESKED (Centreret kort) ---
                    if (isSystem) {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          padding: const EdgeInsets.all(20),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Ikon Header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: _primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "OPDATERING FRA HOPPON",
                                    style: TextStyle(
                                      color: _primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),

                              // Besked Tekst
                              Text(
                                msg['content'] ?? "",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _formatTime(msg['created_at']),
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11,
                                ),
                              ),

                              // Knap
                              if (currentRideId != null) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        _handlePassengerReview(currentRideId),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryColor,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      "Giv Anmeldelse ⭐",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    // --- ALMINDELIG CHAT BESKED (Bobler) ---
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? _primaryColor : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: isMe
                                ? const Radius.circular(18)
                                : Radius.zero,
                            bottomRight: isMe
                                ? Radius.zero
                                : const Radius.circular(18),
                          ),
                          boxShadow: [
                            if (!isMe)
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['content'] ?? "",
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatTime(msg['created_at']),
                              style: TextStyle(
                                color: isMe ? Colors.white60 : Colors.grey[400],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          if (!isSystemChat)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: "Skriv en besked...",
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _isSending ? null : _sendMessage,
                      child: CircleAvatar(
                        backgroundColor: _primaryColor,
                        radius: 24,
                        child: _isSending
                            ? const Padding(
                                padding: EdgeInsets.all(14.0),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              color: const Color(0xFFF1F5F9),
              alignment: Alignment.center,
              child: Text(
                "Dette er en automatisk besked. Du kan ikke svare, men du er velkommen til at kontakte mig via hej@hoppon.dk",
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
