import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'public_profile_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName; // Vi bruger denne som "midlertidig" tekst
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

  // Variabler til at gemme profil-data, som vi henter
  String? _realName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _fetchProfile(); // <--- Vi starter hentning af profil med det samme
  }

  /// Henter navn og billede på den anden person
  Future<void> _fetchProfile() async {
    if (widget.otherUserId == 'system_hoppon') return;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select(
            'full_name, avatar_url',
          ) // <--- RETTET HER (fra first_name til full_name)
          .eq('id', widget.otherUserId)
          .single();

      if (mounted) {
        setState(() {
          _realName = data['full_name']; // <--- OG RETTET HER
          _avatarUrl = data['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint("Kunne ikke hente profil: $e");
    }
  }

  /// Henter beskeder (Samme funktion som før)
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

    // Vi bruger det hentede navn hvis vi har det, ellers det vi fik sendt med (placeholder)
    final displayName = _realName ?? widget.otherUserName;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            // PROFIL BILLEDE (Nu klikbart!)
            if (!isSystemChat)
              GestureDetector(
                onTap: () {
                  // Naviger til PublicProfileScreen
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

            // System ikon (ikke klikbart)
            if (isSystemChat)
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.black,
                child: Icon(Icons.security, size: 20, color: Colors.white),
              ),

            const SizedBox(width: 10),

            // NAVN (Også klikbart for god UX)
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Text(
                "HoppOn",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == _myUserId;
                    final isSystem = msg['sender_id'] == null;

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
                          color: isSystem
                              ? Colors.amber.shade50
                              : (isMe ? Colors.black : Colors.grey.shade200),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isMe
                                ? const Radius.circular(16)
                                : const Radius.circular(0),
                            bottomRight: isMe
                                ? const Radius.circular(0)
                                : const Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['content'] ?? "",
                              style: TextStyle(
                                color: isSystem
                                    ? Colors.black87
                                    : (isMe ? Colors.white : Colors.black87),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatTime(msg['created_at']),
                              style: TextStyle(
                                color: isSystem
                                    ? Colors.black54
                                    : (isMe ? Colors.white70 : Colors.black54),
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
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _isSending ? null : _sendMessage,
                      child: CircleAvatar(
                        backgroundColor: Colors.black,
                        radius: 22,
                        child: _isSending
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
