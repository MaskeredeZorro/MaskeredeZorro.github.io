import 'package:supabase_flutter/supabase_flutter.dart';

class SmsService {
  Future<bool> sendVerificationCode(String phoneNumber, String code) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'send-verification-sms',
        body: {'phoneNumber': phoneNumber, 'code': code},
      );

      if (response.status == 200) {
        print("✅ SMS bestilt via Edge Function");
        return true;
      } else {
        print("❌ Edge Function fejl: ${response.data}");
        return false;
      }
    } catch (e) {
      print("❌ Kunne ikke kalde SMS funktionen: $e");
      return false;
    }
  }
}
