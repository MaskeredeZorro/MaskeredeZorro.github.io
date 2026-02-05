import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/sms_service.dart';
import '/screens/home_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String email;
  final String? password; // <--- DETTE ER DET NYE FELT DU MANGLER

  const VerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.email,
    this.password, // <--- DETTE SKAL MED I KONSTRUKTØREN
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with WidgetsBindingObserver {
  final _otpController = TextEditingController();
  final _smsService = SmsService();

  bool _isLoading = false;
  int _smsResendTimer = 60;
  Timer? _smsTimer;
  String _displayPhone = "";

  // Email state
  bool _isSendingEmail = false;
  int _emailResendTimer = 60;
  Timer? _emailTimer;

  // Status
  bool _isEmailVerified = false;
  bool _codeSent = false;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _displayPhone = widget.phoneNumber;
    _startEmailTimer();

    // 1. Lyt til deep links
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.tokenRefreshed) {
        _checkStatusAndInit();
      }
    });

    // 2. Tjek ved start
    _checkStatusAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();
    _smsTimer?.cancel();
    _emailTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStatusAndInit();
    }
  }

  // --- HOVEDLOGIK ---
  Future<void> _checkStatusAndInit() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      // Brug eksisterende session data i stedet for at kalde refreshSession hver gang
      final user = session.user;
      bool emailConfirmed = user.emailConfirmedAt != null;

      if (emailConfirmed) {
        if (mounted) {
          setState(() => _isEmailVerified = true);
        }
        // Send kun SMS hvis den ikke er sendt i denne session
        if (!_codeSent) {
          _sendSmsCode();
        }
      }
    } catch (e) {
      debugPrint("Fejl i status tjek: $e");
    }
  }

  // --- SILENT LOGIN (Håndterer localhost problemet) ---
  Future<void> _manualCheck() async {
    // 1. Tjek først om vi allerede er logget ind via deep link
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await _checkStatusAndInit();
      return;
    }

    // 2. Hvis ingen session, men vi har password -> Prøv at logge ind
    if (widget.password != null) {
      setState(() => _isLoading = true);
      try {
        final res = await Supabase.instance.client.auth.signInWithPassword(
          email: widget.email,
          password: widget.password!,
        );

        if (res.user != null) {
          // Login lykkedes! Det betyder mailen ER bekræftet.
          if (mounted) {
            setState(() {
              _isEmailVerified = true;
              _isLoading = false;
            });
            _sendSmsCode();
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Din email er ikke bekræftet endnu. Prøv igen om lidt.",
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Kunne ikke verificere. Prøv at logge ind igen."),
          ),
        );
      }
    }
  }

  // --- EMAIL RESEND ---
  void _startEmailTimer() {
    _emailTimer?.cancel();
    _emailTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_emailResendTimer > 0) {
        setState(() => _emailResendTimer--);
      } else {
        _emailTimer?.cancel();
      }
    });
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isSendingEmail = true;
      _emailResendTimer = 60;
    });
    _startEmailTimer();

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
        emailRedirectTo: 'io.supabase.flutterquickstart://login-callback',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Email sendt igen!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fejl: $e")));
    } finally {
      if (mounted) setState(() => _isSendingEmail = false);
    }
  }

  // --- SMS LOGIK ---
  void _startSmsTimer() {
    _smsTimer?.cancel();
    _smsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_smsResendTimer > 0)
        setState(() => _smsResendTimer--);
      else
        _smsTimer?.cancel();
    });
  }

  Future<void> _sendSmsCode() async {
    // 1. SIKKERHEDS-TJEK: Stop hvis nummeret er tomt, før vi overhovedet prøver
    if (widget.phoneNumber.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Fejl: Telefonnummer mangler. Gå venligst tilbage og indtast det igen.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _codeSent = true;
      _isLoading = true;
      _smsResendTimer = 60;
    });
    _startSmsTimer();

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 2. Generer 6-cifret kode
      final code = (Random().nextInt(900000) + 100000).toString();

      // 3. Gem koden i databasen først
      await Supabase.instance.client.from('sms_verifications').insert({
        'user_id': user.id,
        'code': code,
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
      });

      // 4. SEND SMS: Her bruger vi widget.phoneNumber direkte for at undgå "" fejl
      final success = await _smsService.sendVerificationCode(
        widget.phoneNumber,
        code,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("SMS-kode sendt!"),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Hvis SureSMS melder fejl
          throw Exception(
            "SureSMS kunne ikke sende beskeden. Tjek din saldo eller login.",
          );
        }
      }
    } catch (e) {
      setState(() => _codeSent = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Fejl ved SMS: ${e.toString().replaceAll("Exception: ", "")}",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifySmsCode() async {
    if (_otpController.text.length < 6) return;

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw "Bruger ikke fundet. Log venligst ind igen.";

      // Hent koden fra DB
      final response = await Supabase.instance.client
          .from('sms_verifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) throw "Ingen kode fundet. Bestil en ny.";

      final dbCode = response['code'].toString();
      final expiresAt = DateTime.parse(response['expires_at']);

      if (DateTime.now().isAfter(expiresAt)) throw "Koden er udløbet.";
      if (_otpController.text.trim() != dbCode) throw "Forkert kode.";

      // SUCCES: Opdater profil
      await Supabase.instance.client
          .from('profiles')
          .update({'phone_verified': true, 'phone_number': _displayPhone})
          .eq('id', user.id);

      // STOP alt loading og lyttere før navigation
      _authSubscription.cancel();

      if (mounted) {
        // Brug pushAndRemoveUntil for at bryde ud af auth-flowet helt
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Bekræftelse", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            // --- SCENARIE A: Email mangler ---
            if (!_isEmailVerified) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 50,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "Venligst bekræft din email",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Vi har sendt et link til ${widget.email}.\nKlik på det, og vend tilbage hertil.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 20),

                    // KNAP 1: JEG HAR KLIKKET (Nu med SILENT LOGIN)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _manualCheck,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh, color: Colors.white),
                        label: const Text(
                          "JEG HAR KLIKKET",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // KNAP 2: SEND IGEN
                    TextButton(
                      onPressed: (_emailResendTimer == 0 && !_isSendingEmail)
                          ? _resendEmail
                          : null,
                      child: _isSendingEmail
                          ? const SizedBox(
                              height: 15,
                              width: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _emailResendTimer == 0
                                  ? "Fik du den ikke? Send email igen"
                                  : "Send email igen om $_emailResendTimer s",
                              style: TextStyle(
                                color: _emailResendTimer == 0
                                    ? Colors.blueGrey
                                    : Colors.grey,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ]
            // --- SCENARIE B: Email OK -> Vis SMS ---
            else ...[
              const Icon(
                Icons.sms_outlined,
                size: 60,
                color: Color(0xFF0F172A),
              ),
              const SizedBox(height: 20),
              const Text(
                "Indtast SMS-kode",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                "Kode sendt til $_displayPhone",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: "000000",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  counterText: "",
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifySmsCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "BEKRÆFT SMS",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: (_smsResendTimer == 0 && !_isLoading)
                    ? _sendSmsCode
                    : null,
                child: Text(
                  _smsResendTimer == 0
                      ? "Send ny SMS-kode"
                      : "Send ny SMS-kode om $_smsResendTimer s",
                  style: TextStyle(
                    color: _smsResendTimer == 0 ? primaryColor : Colors.grey,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
