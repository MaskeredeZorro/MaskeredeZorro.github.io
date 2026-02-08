import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'chat_detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _myUserId = Supabase.instance.client.auth.currentUser?.id;

  /// Henter beskeder live og grupperer dem til "Samtaler"
  Stream<List<Map<String, dynamic>>> _getChatsStream() {
    if (_myUserId == null) return const Stream.empty();

    // 1. Hent ALLE beskeder hvor jeg er afsender eller modtager
    return Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false) // Nyeste først
        .map((messages) {
          final Map<String, Map<String, dynamic>> uniqueChats = {};

          for (var msg in messages) {
            // Tjek om jeg er afsender eller modtager
            final isMeSender = msg['sender_id'] == _myUserId;
            final isMeReceiver = msg['receiver_id'] == _myUserId;

            // Hvis jeg hverken er afsender eller modtager (fejlsikring), spring over
            if (!isMeSender && !isMeReceiver) continue;

            // Find ID på "den anden part"
            String otherKey;
            if (msg['sender_id'] == null) {
              // Systembesked har sender_id = null
              otherKey = 'system_hoppon';
            } else {
              otherKey = isMeSender
                  ? (msg['receiver_id'] ?? 'unknown')
                  : msg['sender_id'];
            }

            // Vi gemmer kun den FØRSTE besked vi møder for hver person (nyeste)
            if (!uniqueChats.containsKey(otherKey)) {
              uniqueChats[otherKey] = msg;
            }
          }

          return uniqueChats.values.toList();
        });
  }

  String _formatTime(String timestamp) {
    final date = DateTime.parse(timestamp).toLocal();
    final now = DateTime.now();

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat('HH:mm').format(date); // I dag: Vis klokkeslæt
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('EEEE').format(date); // Indenfor ugen: Vis ugedag
    } else {
      return DateFormat('dd/MM').format(date); // Ældre: Vis dato
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Beskeder"),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _getChatsStream(),
        builder: (context, snapshot) {
          // 1. Fejl håndtering
          if (snapshot.hasError) {
            return Center(child: Text('Der opstod en fejl: ${snapshot.error}'));
          }

          // 2. Loading state
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0F172A)),
            );
          }

          final chats = snapshot.data!;

          // 3. Ingen beskeder (Empty State)
          if (chats.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "Ingen beskeder endnu",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // 4. Vis liste af samtaler
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (ctx, i) => const Divider(height: 1, indent: 82),
            itemBuilder: (context, index) {
              final chatMsg = chats[index];

              // Tjek om det er en systembesked
              final bool isSystemMessage = chatMsg['sender_id'] == null;

              // Find ID på den anden bruger
              final otherUserId = (chatMsg['sender_id'] == _myUserId)
                  ? chatMsg['receiver_id']
                  : chatMsg['sender_id'];

              // --- HVIS SYSTEM BESKED (HoppOn) ---
              if (isSystemMessage) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Colors.black, // HoppOn brand farve
                    radius: 28,
                    child: const Icon(Icons.security, color: Colors.white),
                  ),
                  title: const Text(
                    "HoppOn",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Text(
                    chatMsg['content'] ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  trailing: Text(
                    _formatTime(chatMsg['created_at']),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                  onTap: () {
                    // Naviger til chat med systemet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChatDetailScreen(
                          otherUserId: 'system_hoppon',
                          otherUserName: 'HoppOn',
                          rideId: null, // Ingen specifik tur tilknyttet
                        ),
                      ),
                    );
                  },
                );
              }

              // --- HVIS ALMINDELIG BRUGER (Hent profil) ---
              // --- HVIS ALMINDELIG BRUGER (Hent profil) ---
              // Vi tilføjer '?' til typen for at tillade null (hvis brugeren er slettet)
              return FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client
                    .from('profiles')
                    .select()
                    .eq('id', otherUserId)
                    .maybeSingle(), // Returnerer Map<String, dynamic>?
                builder: (context, userSnap) {
                  // Standard data mens vi loader eller hvis bruger mangler
                  String displayName = "Henter...";
                  String? avatarUrl;

                  if (userSnap.connectionState == ConnectionState.done) {
                    // Tjek om data er null (slettet bruger) eller eksisterer
                    if (userSnap.hasData && userSnap.data != null) {
                      displayName = userSnap.data!['full_name'] ?? "Bruger";
                      avatarUrl = userSnap.data!['avatar_url'];
                    } else {
                      displayName = "Slettet bruger";
                    }
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade200,
                      radius: 28,
                      backgroundImage: avatarUrl != null
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? const Icon(Icons.person, color: Colors.grey)
                          : null,
                    ),
                    title: Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        if (chatMsg['sender_id'] == _myUserId)
                          const Padding(
                            padding: EdgeInsets.only(right: 4.0),
                            child: Icon(
                              Icons.reply,
                              size: 14,
                              color: Colors.grey,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            chatMsg['content'] ?? "",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              // Gør teksten fed hvis den er ulæst og jeg er modtager
                              fontWeight:
                                  (chatMsg['is_read'] == false &&
                                      chatMsg['receiver_id'] == _myUserId)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      _formatTime(chatMsg['created_at']),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatDetailScreen(
                            otherUserId: otherUserId,
                            otherUserName: displayName,
                            rideId:
                                chatMsg['ride_id'], // Send ride_id med hvis det findes
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
