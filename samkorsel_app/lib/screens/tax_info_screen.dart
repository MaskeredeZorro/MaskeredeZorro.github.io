import 'dart:async';
import 'dart:convert';
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

  // --- NY MAPBOX SØGE FUNKTION ---
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
      String ibanToSend = _ibanCtrl.text.replaceAll(' ', '');

      await Supabase.instance.client.rpc(
        'submit_tax_info',
        params: {
          'p_full_name': "${_fNameCtrl.text} ${_lNameCtrl.text}",
          'p_address': _addressCtrl.text,
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
                  // Status boks (Sikkerhed)
                  _buildSecurityHeader(),
                  const SizedBox(height: 30),

                  ExpansionTile(
                    title: const Text(
                      "Privatperson",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: const Text(
                      "Lovpligtige oplysninger",
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
                            _buildBirthdayPicker(),
                            const SizedBox(height: 10),

                            // --- ADRESSE FELT MED MAPBOX SØGNING ---
                            GestureDetector(
                              onTap: _showAddressPicker,
                              child: AbsorbPointer(
                                child: _buildInput(
                                  _addressCtrl,
                                  "Hjemstedsadresse",
                                  icon: Icons.location_on_outlined,
                                  hint: "Tryk for at søge adresse...",
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),
                            _buildCountryDropdown(),
                            const SizedBox(height: 10),
                            _buildCprField(),
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 10),
                            _buildIbanField(),
                            const SizedBox(height: 20),
                            _buildSubmitButton(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    "Ofte stillede spørgsmål",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildFAQ(
                    "Hvor finder jeg mit IBAN nummer?",
                    "Dit IBAN nummer står i din netbank. Det består af 'DK' efterfulgt af 16 tal.",
                  ),
                ],
              ),
            ),
    );
  }

  // --- UI Komponenter ---

  Widget _buildSecurityHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock, color: Colors.green),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Dine data krypteres øjeblikkeligt og bruges kun til lovpligtig indberetning.",
              style: TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthdayPicker() {
    return InkWell(
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

  Widget _buildCprField() {
    return TextFormField(
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
        if (val == null || val.length != 10) return "Skal være 10 cifre";
        return null;
      },
      decoration: InputDecoration(
        labelText: _isCprLocked ? "CPR (Gemt)" : "CPR Nummer",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: _isCprLocked ? Colors.grey[200] : Colors.grey[50],
        suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
      ),
    );
  }

  Widget _buildIbanField() {
    return TextFormField(
      controller: _ibanCtrl,
      textCapitalization: TextCapitalization.characters,
      validator: (val) {
        if (val == null || val.isEmpty) return "Påkrævet";
        String clean = val.replaceAll(' ', '');
        if (!clean.startsWith("DK") || clean.length != 18)
          return "Ugyldigt dansk IBAN";
        return null;
      },
      decoration: InputDecoration(
        labelText: "IBAN Nummer",
        hintText: "DK00 0000 0000 0000 00",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey[50],
        prefixIcon: const Icon(Icons.account_balance),
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

  Widget _buildInput(
    TextEditingController ctrl,
    String label, {
    IconData? icon,
    String? hint,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: (val) => (val == null || val.isEmpty) ? "Påkrævet" : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
            padding: const EdgeInsets.all(16),
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

// --- MAPBOX ADRESSE SØGE WIDGET ---

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
