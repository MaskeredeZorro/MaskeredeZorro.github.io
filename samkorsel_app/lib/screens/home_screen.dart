import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import 'auth_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Kortet
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
              initialZoom: 7.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.samkorsel.app',
              ),
            ],
          ),
          // 2. Søgeboks
          Positioned(
            top: 60, left: 20, right: 20,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(children: const [Icon(Icons.search), SizedBox(width: 10), Text("Hvor vil du hen?")]),
              ),
            ),
          ),
          // 3. Log ud knap (Midlertidig)
          Positioned(
            bottom: 40, right: 20,
            child: FloatingActionButton(
              child: const Icon(Icons.logout),
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
                }
              },
            ),
          )
        ],
      ),
    );
  }
}
