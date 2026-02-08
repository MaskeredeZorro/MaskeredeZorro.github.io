import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart'; // Til iOS Dato vælger
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class TaxInfoScreen extends StatefulWidget {
  const TaxInfoScreen({super.key});

  @override
  State<TaxInfoScreen> createState() => _TaxInfoScreenState();
}

class _TaxInfoScreenState extends State<TaxInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isCprLocked = false;

  // Mapbox Token
  final String _mapboxToken =
      "pk.eyJ1IjoiaG9wcG9uIiwiYSI6ImNtbDk0bDN3cTBiM3MzZnFzdThhOXRuZG4ifQ.9LP9GFe5zEvMjwhPtf6l0w";

  // Controllere
  final _fNameCtrl = TextEditingController();
  final _lNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cprCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  final _floorDoorCtrl = TextEditingController(); // Tilføj denne
  String _country = "Danmark";
  DateTime? _dob;

  final Color _primaryColor = const Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

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

        setState(() {
          _isCprLocked = true;
          _cprCtrl.text = "**********";
        });
      }
    } catch (e) {
      debugPrint("Fejl ved hentning af skatteinfo: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- MAPBOX SØGE FUNKTION ---
  Future<void> _showAddressPicker() async {
    final selectedAddress = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MapboxSearchWidget(mapboxToken: _mapboxToken),
    );

    if (selectedAddress != null) {
      setState(() {
        _addressCtrl.text = selectedAddress;
      });
    }
  }

  // --- iOS DATO VÆLGER ---
  void _showIOSDatePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              // Header med "Færdig" knap
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        "Færdig",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _dob ?? DateTime(2000),
                  minimumDate: DateTime(1900),
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (val) {
                    setState(() => _dob = val);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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
      // Fjerner mellemrum en ekstra gang for en sikkerheds skyld
      String ibanToSend = _ibanCtrl.text.replaceAll(' ', '');
      // Slet ikke noget, men indsæt dette før rpc-kaldet:
      String fullAddress = _addressCtrl.text;
      if (_floorDoorCtrl.text.isNotEmpty) {
        fullAddress += ", ${_floorDoorCtrl.text.trim()}";
      }
      await Supabase.instance.client.rpc(
        'submit_tax_info',
        params: {
          'p_full_name': "${_fNameCtrl.text} ${_lNameCtrl.text}",
          'p_address': fullAddress,
          'p_country': _country,
          'p_cpr': cprToSend,
          'p_bank_iban': ibanToSend,
        },
      );

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
        debugPrint("✅ Stripe Connect konto oprettet.");
      } catch (stripeError) {
        debugPrint("⚠️ Stripe fejl: $stripeError");
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
      if (e.toString().contains("Invalid account number")) {
        errorMsg = "Ugyldigt IBAN nummer. Tjek venligst igen.";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
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
                  // 1. SIKKERHEDS HEADER
                  _buildSecurityHeader(),
                  const SizedBox(height: 30),

                  // 2. FORMULAR
                  ExpansionTile(
                    title: const Text(
                      "Privatperson",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: const Text(
                      "Lovpligtige oplysninger for udbetaling",
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
                            // NAVN (Nu lige høje)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildInput(
                                    _fNameCtrl,
                                    "Fornavn",
                                    // Ingen helperText her, så det matcher efternavn
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildInput(_lNameCtrl, "Efternavn"),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),

                            // FØDSELSDAG (Med iOS picker)
                            _buildBirthdayPicker(),
                            const SizedBox(height: 15),

                            // ADRESSE
                            GestureDetector(
                              onTap: _showAddressPicker,
                              child: AbsorbPointer(
                                child: _buildInput(
                                  _addressCtrl,
                                  "Hjemstedsadresse",
                                  icon: Icons.location_on_outlined,
                                  hint: "Tryk for at søge adresse...",
                                  helperText:
                                      "Din folkeregisteradresse (Påkrævet jf. Hvidvaskloven)",
                                ),
                              ),
                            ),

                            const SizedBox(height: 15),
                            // Indsæt dette felt under adresse-søgeren:
                            _buildInput(
                              _floorDoorCtrl,
                              "Etage, dør (valgfri)",
                              hint: "f.eks. st. tv. eller 2. sal nr. 4",
                            ),
                            const SizedBox(height: 15),
                            _buildCountryDropdown(),

                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 20),

                            // CPR NUMMER (Maks 10 cifre, kun tal)
                            _buildCprField(),

                            const SizedBox(height: 20),

                            // IBAN (Ingen mellemrum)
                            _buildIbanField(),

                            const SizedBox(height: 30),
                            _buildSubmitButton(),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // 3. FAQ SEKTION
                  const Text(
                    "Ofte stillede spørgsmål",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),

                  _buildFAQ(
                    "Skal jeg betale skat af pengene?",
                    "Som hovedregel er samkørsel i Danmark skattefrit, så længe beløbet kun dækker dine omkostninger til bilen (benzin, vedligehold, osv.). Vi indberetter automatisk til SKAT for dig, så du slipper for bøvlet, men det betyder sjældent, at du skal betale penge.",
                  ),
                  _buildFAQ(
                    "Hvorfor skal I bruge mit CPR-nummer?",
                    "Det er et lovkrav fra EU (DAC7-direktivet). For at vi må udbetale penge til dig, skal vi kunne identificere dig over for myndighederne. Vi bruger det ALDRIG til andet, og det slettes, hvis du lukker din profil.",
                  ),
                  _buildFAQ(
                    "Kan I trække penge fra min konto?",
                    "Nej, aldrig. Dit IBAN-nummer fungerer kun én vej: Vi kan sætte dine optjente penge ind på din konto. Vi har ingen fuldmagt til at hæve penge fra dig.",
                  ),
                  _buildFAQ(
                    "Er mine oplysninger sikre?",
                    "Ja. Dine data sendes krypteret direkte til vores betalingspartner Stripe (samme sikkerhedsniveau som store banker). HoppOn gemmer ikke dine følsomme data ukrypteret.",
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // --- HJÆLPE WIDGETS ---

  Widget _buildSecurityHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF), // Meget lys blå
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                color: Color(0xFF2563EB),
                size: 28,
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Bank-niveau sikkerhed",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E40AF),
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Dine oplysninger behandles fortroligt og krypteret.",
                      style: TextStyle(color: Color(0xFF1E3A8A), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 14, color: Colors.green[600]),
                const SizedBox(width: 6),
                Text(
                  "Secured by Stripe Identity",
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCprField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "CPR-nummer",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(
                Icons.help_outline,
                size: 18,
                color: Colors.grey,
              ),
              onPressed: () => _showExplanationDialog(
                "Hvorfor CPR?",
                "Vi er lovmæssigt forpligtet til at indberette udbetalinger til SKAT. Ved at indtaste dit CPR-nummer her, sker indberetningen automatisk, så du ikke selv skal huske det.",
              ),
            ),
          ],
        ),
        TextFormField(
          controller: _cprCtrl,
          keyboardType: TextInputType.number,
          readOnly: _isCprLocked,
          obscureText: !_isCprLocked,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10), // Maks 10 cifre
          ],
          validator: (val) {
            if (_isCprLocked) return null;
            if (val == null || val.length != 10) return "Skal være 10 cifre";
            return null;
          },
          decoration: InputDecoration(
            hintText: "DDMMÅÅXXXX",
            helperText: "Sendes krypteret (Kun til SKAT-indberetning)",
            helperStyle: TextStyle(color: Colors.grey[600]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: _isCprLocked ? Colors.grey[200] : Colors.grey[50],
            prefixIcon: const Icon(Icons.fingerprint),
            suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildIbanField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "IBAN-nummer",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(
                Icons.help_outline,
                size: 18,
                color: Colors.grey,
              ),
              onPressed: () => _showExplanationDialog(
                "Hvad er IBAN?",
                "IBAN er din bankkontos internationale ID. Du finder det i din netbank under kontodetaljer. Det starter med 'DK' og efterfølges af 16 tal.",
              ),
            ),
          ],
        ),
        TextFormField(
          controller: _ibanCtrl,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')), // Forbyd mellemrum
          ],
          validator: (val) {
            if (val == null || val.isEmpty) return "Påkrævet";
            // Ingen grund til replaceAll her da vi blokerer det ved input,
            // men vi gør det alligevel for en sikkerheds skyld
            String clean = val.toUpperCase().replaceAll(' ', '');
            if (!clean.startsWith("DK") || clean.length != 18)
              return "Ugyldigt dansk IBAN";
            return null;
          },
          decoration: InputDecoration(
            hintText: "DK0000000000000000",
            helperText: "Her udbetaler vi din fortjeneste til",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.grey[50],
            prefixIcon: const Icon(Icons.account_balance),
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
    TextEditingController ctrl,
    String label, {
    IconData? icon,
    String? hint,
    String? helperText,
    bool isRequired = true, // Tilføj denne parameter
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          validator: (val) {
            if (!isRequired) return null;
            return (val == null || val.isEmpty) ? "Påkrævet" : null;
          },
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText, // Nu kun hvis det er sat
            helperMaxLines: 2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: icon != null ? Icon(icon) : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBirthdayPicker() {
    return InkWell(
      onTap: _showIOSDatePicker, // Kalder nu den nye iOS funktion
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: "Fødselsdato",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey[50],
        ),
        child: Text(
          _dob == null
              ? "Vælg dato"
              : "${_dob!.day}/${_dob!.month}-${_dob!.year}",
        ),
      ),
    );
  }

  Widget _buildCountryDropdown() {
    return DropdownButtonFormField(
      value: _country,
      items: const [DropdownMenuItem(value: "Danmark", child: Text("Danmark"))],
      onChanged: (v) {},
      decoration: InputDecoration(
        labelText: "Land",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitTaxInfo,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 15),
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
    );
  }

  Widget _buildFAQ(String question, String answer) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF8FAFC),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            answer,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showExplanationDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}

// --- MAPBOX ADRESSE SØGE WIDGET (Uden for state class) ---

class _MapboxSearchWidget extends StatefulWidget {
  final String mapboxToken;
  const _MapboxSearchWidget({required this.mapboxToken});

  @override
  State<_MapboxSearchWidget> createState() => _MapboxSearchWidgetState();
}

class _MapboxSearchWidgetState extends State<_MapboxSearchWidget> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _suggestions = [];
  Timer? _debounce;
  bool _isSearching = false;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.length > 2) {
        _fetchSuggestions(query);
      }
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isSearching = true);
    try {
      final url = Uri.parse(
        "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=${widget.mapboxToken}&country=dk&types=address&language=da&limit=5",
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _suggestions = data['features'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Mapbox fejl: $e");
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 20,
        left: 15,
        right: 15,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Søg efter din adresse...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: _suggestions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      "Begynd at skrive for at se forslag",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final place = _suggestions[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.location_on,
                          color: Colors.indigo,
                        ),
                        title: Text(place['place_name'] ?? ""),
                        onTap: () =>
                            Navigator.pop(context, place['place_name']),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
