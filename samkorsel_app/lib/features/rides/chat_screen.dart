import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String rideId;
  final String rideTitle; // Fx "Aarhus -> København"

  const ChatScreen({super.key, required this.rideId, required this.rideTitle});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _myId = Supabase.instance.client.auth.currentUser!.id;

  // -- SEND BESKED --
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear(); // Tøm feltet med det samme for lækker UX

    try {
      await Supabase.instance.client.from('messages').insert({
        'ride_id': widget.rideId,
        'sender_id': _myId,
        'content': text,
      });
    } catch (e) {
      debugPrint("Fejl ved send: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kunne ikke sende besked.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.rideTitle)),
      body: Column(
        children: [
          // -- BESKED LISTE (REAL-TIME STREAM) --
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('messages')
                  .stream(primaryKey: ['id']) // Lytter efter nye ID'er
                  .eq('ride_id', widget.rideId)
                  .order('created_at', ascending: true) // Gamle beskeder øverst
                  .map((data) => List<Map<String, dynamic>>.from(data)), // Konverter data
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Fejl: ${snapshot.error}"));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!;

                if (messages.isEmpty) {
                  return const Center(child: Text("Ingen beskeder endnu. Sig hej! 👋"));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == _myId;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.green : Colors.grey[300],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          msg['content'],
                          style: TextStyle(color: isMe ? Colors.white : Colors.black),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // -- INPUT FELT --
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: "Skriv en besked...",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.green,
                    onPressed: _sendMessage,
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
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