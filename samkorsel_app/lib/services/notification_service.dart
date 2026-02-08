import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _supabase = Supabase.instance.client;

  static Future<void> initialize() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 1. Bed om lov (især vigtigt på iOS)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. Hent telefonens unikke token
      String? token = await messaging.getToken();

      if (token != null) {
        // 3. Gem det i Supabase profiles tabellen
        final userId = _supabase.auth.currentUser?.id;
        if (userId != null) {
          await _supabase
              .from('profiles')
              .update({'fcm_token': token})
              .eq('id', userId);
        }
      }
    }

    // Lyt efter tokens der ændrer sig mens appen kører
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _supabase
            .from('profiles')
            .update({'fcm_token': newToken})
            .eq('id', userId);
      }
    });
  }
}
