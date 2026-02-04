import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Nødvendig for input formatters
import 'package:supabase_flutter/supabase_flutter.dart';

class TaxInfoScreen extends StatefulWidget {
  const TaxInfoScreen({super.key});

  @override
  State<TaxInfoScreen> createState() => _TaxInfoScreenState();
}

class _TaxInfoScreenState extends State<TaxInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isCprLocked = false; // Styrer om CPR feltet er låst

  // Controllere
  final _fNameCtrl = TextEditingController();
  final _lNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cprCtrl = TextEditingController();
  // NYT: Kun én controller til IBAN
  final _ibanCtrl = TextEditingController();

  String _country = "Danmark";
  DateTime? _dob;

  final Color _primaryColor = const Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  // --- HENT DATA ---
  Future<void> _loadSavedData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Hent data (Bemærk: Vi kan ikke hente det krypterede IBAN tilbage til visning i klar tekst
      // medmindre vi laver en 'decrypt' funktion til brugeren.
      // For sikkerhedens skyld viser vi ofte bare tomt eller stjerner, men her henter vi stamdata)
      final data = await Supabase.instance.client
          .from('tax_identities')
          .select('full_name, address, country')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null) {
        _addressCtrl.text = data['address'] ?? "";
        _country = data['country'] ?? "Danmark";

        String fullName = data['full_name'] ?? "";
        List<String> names = fullName.split(' ');
        if (names.isNotEmpty) {
          _fNameCtrl.text = names.first;
          if (names.length > 1) {
            _lNameCtrl.text = names.sublist(1).join(' ');
          }
        }

        // Vi antager at CPR er gemt, hvis rækken findes. Vi låser feltet.
        setState(() {
          _isCprLocked = true;
          _cprCtrl.text = "**********";
          // Vi lader IBAN være tomt, så brugeren skal indtaste det igen ved ændringer,
          // eller vi kan lade det stå tomt indtil de gemmer nyt.
        });
      }
    } catch (e) {
      debugPrint("Fejl ved hentning af skatteinfo: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- SIKKER GEMME FUNKTION ---
  Future<void> _submitTaxInfo() async {
    if (!_formKey.currentState!.validate()) return;

    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vælg venligst fødselsdato")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw "Du er blevet logget ud.";

      String cprToSend = _isCprLocked ? "" : _cprCtrl.text;

      // Rens IBAN for mellemrum før vi sender
      String ibanToSend = _ibanCtrl.text.replaceAll(' ', '');

      // 1. Gem i databasen (Krypteret) - Kalder den opdaterede SQL funktion
      await Supabase.instance.client.rpc(
        'submit_tax_info',
        params: {
          'p_full_name': "${_fNameCtrl.text} ${_lNameCtrl.text}",
          'p_address': _addressCtrl.text,
          'p_country': _country,
          'p_cpr': cprToSend,
          'p_bank_iban': ibanToSend, // Her sender vi IBAN
        },
      );

      // --- 2. OPRET STRIPE KONTO AUTOMATISK ---
      try {
        await Supabase.instance.client.functions.invoke(
          'create-stripe-account',
          body: {
            'user_id': user.id,
            'email': user.email,
            'dob_day': _dob?.day,
            'dob_month': _dob?.month,
            'dob_year': _dob?.year,
            'client_ip': '0.0.0.0',
          },
        );
        debugPrint("✅ Stripe Connect konto oprettet succesfuldt i baggrunden.");
      } catch (stripeError) {
        debugPrint("⚠️ Advarsel: Stripe oprettelse fejlede: $stripeError");
        // Vi kaster fejlen videre så brugeren kan se, hvis noget gik galt med Stripe
        throw stripeError;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Oplysninger gemt og udbetaling aktiveret! 🔒"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Fejl: $e");
      String errorMsg = "Der skete en fejl. Tjek dine oplysninger.";

      // Hvis vi får den specifikke fejl fra Stripe, viser vi den
      if (e.toString().contains("Invalid account number")) {
        errorMsg = "Ugyldigt IBAN nummer. Tjek venligst igen.";
      }

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Skatteoplysninger"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. STATUS BOKS
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.5)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock, color: Colors.green),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Sikker Opbevaring",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Dine data krypteres øjeblikkeligt og bruges kun til lovpligtig indberetning.",
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // 2. FORMULAR
                  ExpansionTile(
                    title: const Text(
                      "Private individual",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: const Text(
                      "Udfyld lovpligtige oplysninger",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    initiallyExpanded: true,
                    collapsedBackgroundColor: const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    childrenPadding: const EdgeInsets.all(16),
                    children: [
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInput(_fNameCtrl, "Fornavn"),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildInput(_lNameCtrl, "Efternavn"),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                  initialDate: DateTime(2000),
                                );
                                if (d != null) setState(() => _dob = d);
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: "Fødselsdato",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                child: Text(
                                  _dob == null
                                      ? "Vælg dato"
                                      : "${_dob!.day}/${_dob!.month}-${_dob!.year}",
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildInput(_addressCtrl, "Hjemstedsadresse"),
                            const SizedBox(height: 10),
                            DropdownButtonFormField(
                              value: _country,
                              items: const [
                                DropdownMenuItem(
                                  value: "Danmark",
                                  child: Text("Danmark"),
                                ),
                              ],
                              onChanged: (v) {},
                              decoration: InputDecoration(
                                labelText: "Land",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // --- CPR FELT ---
                            TextFormField(
                              controller: _cprCtrl,
                              keyboardType: TextInputType.number,
                              readOnly: _isCprLocked,
                              obscureText: !_isCprLocked,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              validator: (val) {
                                if (_isCprLocked) return null;
                                if (val == null || val.length != 10)
                                  return "Skal være præcis 10 tal";
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: _isCprLocked
                                    ? "CPR (Gemt)"
                                    : "CPR Nummer (10 cifre)",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: _isCprLocked
                                    ? Colors.grey[200]
                                    : Colors.grey[50],
                                suffixIcon: const Icon(
                                  Icons.lock,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 10),

                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Bankkonto til udbetaling",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // --- NYT IBAN FELT ---
                            TextFormField(
                              controller: _ibanCtrl,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization
                                  .characters, // Store bogstaver automatisk
                              validator: (val) {
                                if (val == null || val.isEmpty)
                                  return "Påkrævet";
                                // Simpel validering for dansk IBAN
                                String clean = val.replaceAll(' ', '');
                                if (!clean.startsWith("DK"))
                                  return "Skal starte med DK";
                                if (clean.length != 18)
                                  return "Dansk IBAN skal være 18 tegn (du har ${clean.length})";
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: "IBAN Nummer",
                                hintText: "DK00 0000 0000 0000 00",
                                helperText:
                                    "Findes typisk i din netbank under kontooplysninger",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: Colors.grey[50],
                                prefixIcon: const Icon(Icons.account_balance),
                              ),
                            ),

                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitTaxInfo,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        "Gem & Krypter Oplysninger",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                  // FAQ Sektion (Beholdt som den var)
                  const Text(
                    "Ofte stillede spørgsmål",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildFAQ(
                    "Hvor finder jeg mit IBAN nummer?",
                    "Dit IBAN nummer står i din netbank. Det består af 'DK' efterfulgt af 16 tal. Det er IKKE det samme som dit kortnummer.",
                  ),
                  _buildFAQ(
                    "Hvorfor skal I bruge IBAN?",
                    "For at kunne udbetale dine penge sikkert via vores betalingspartner Stripe, kræves der et valideret internationalt kontonummer (IBAN). Dette sikrer, at pengene altid lander det rigtige sted.",
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInput(
    TextEditingController ctrl,
    String label, {
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      validator: (val) => (val == null || val.isEmpty) ? "Påkrævet" : null,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildFAQ(String title, String content) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              content,
              style: TextStyle(color: Colors.grey[700], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
