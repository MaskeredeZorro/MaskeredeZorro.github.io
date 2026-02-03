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
  final _regCtrl = TextEditingController();
  final _accCtrl = TextEditingController();
  
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

      // Hent data fra tax_identities tabellen
      // Vi kan ikke hente de krypterede felter (cpr, bank), men vi kan se om rækken findes
      final data = await Supabase.instance.client
          .from('tax_identities')
          .select('full_name, address, country')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null) {
        // Data findes -> Udfyld felter
        _addressCtrl.text = data['address'] ?? "";
        _country = data['country'] ?? "Danmark";
        
        // Split navn op igen hvis muligt
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
          _cprCtrl.text = "**********"; // Dummy tekst for at vise det er udfyldt
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vælg venligst fødselsdato")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw "Du er blevet logget ud.";

      // Hvis CPR er låst (allerede gemt), sender vi en tom streng.
      // SQL-funktionen (opdateret version) sørger for IKKE at overskrive med tom streng.
      String cprToSend = _isCprLocked ? "" : _cprCtrl.text;
      
      // Samme logik kan bruges på bank-info hvis du vil låse dem også, 
      // men her sender vi dem hver gang for at tillade opdatering af bank.
      
      await Supabase.instance.client.rpc('submit_tax_info', params: {
        'p_full_name': "${_fNameCtrl.text} ${_lNameCtrl.text}",
        'p_address': _addressCtrl.text,
        'p_country': _country,
        'p_cpr': cprToSend, 
        'p_bank_reg': _regCtrl.text,
        'p_bank_acc': _accCtrl.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Oplysninger opdateret og krypteret! 🔒"), 
          backgroundColor: Colors.green
        ));
        Navigator.pop(context);
      }

    } catch (e) {
      debugPrint("Sikkerhedsfejl: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Der skete en fejl. Prøv igen."), backgroundColor: Colors.red));
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
                        Text("Sikker Opbevaring", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        SizedBox(height: 4),
                        Text(
                          "Dine data krypteres øjeblikkeligt og bruges kun til lovpligtig indberetning.",
                          style: TextStyle(color: Colors.black87, fontSize: 13),
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
              title: const Text("Private individual", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text("Udfyld lovpligtige oplysninger", style: TextStyle(fontSize: 12, color: Colors.grey)),
              initiallyExpanded: true,
              collapsedBackgroundColor: const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(child: _buildInput(_fNameCtrl, "Fornavn")),
                        const SizedBox(width: 10),
                        Expanded(child: _buildInput(_lNameCtrl, "Efternavn")),
                      ]),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () async {
                          final d = await showDatePicker(context: context, firstDate: DateTime(1900), lastDate: DateTime.now(), initialDate: DateTime(2000));
                          if(d!=null) setState(() => _dob = d);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: "Fødselsdato", 
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            filled: true, fillColor: Colors.grey[50],
                          ),
                          child: Text(_dob == null ? "Vælg dato" : "${_dob!.day}/${_dob!.month}-${_dob!.year}"),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildInput(_addressCtrl, "Hjemstedsadresse"),
                      const SizedBox(height: 10),
                      DropdownButtonFormField(
                        value: _country,
                        items: const [DropdownMenuItem(value: "Danmark", child: Text("Danmark"))],
                        onChanged: (v) {},
                        decoration: InputDecoration(labelText: "Land", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.grey[50]),
                      ),
                      const SizedBox(height: 10),
                      
                      // --- CPR FELT (Med speciel logik) ---
                      TextFormField(
                        controller: _cprCtrl,
                        keyboardType: TextInputType.number,
                        readOnly: _isCprLocked, // Lås feltet hvis data findes
                        obscureText: !_isCprLocked, // Skjul kun hvis man indtaster
                        // Kun tillad tal og max 10 tegn
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (val) {
                          if (_isCprLocked) return null; // Ingen validering hvis låst (allerede gemt)
                          if (val == null || val.length != 10) return "Skal være præcis 10 tal";
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: _isCprLocked ? "CPR (Gemt)" : "CPR Nummer (10 cifre)", 
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), 
                          isDense: true,
                          filled: true,
                          fillColor: _isCprLocked ? Colors.grey[200] : Colors.grey[50],
                          suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 10),
                      
                      const Align(alignment: Alignment.centerLeft, child: Text("Bankkonto til udbetaling", style: TextStyle(fontWeight: FontWeight.bold))),
                      const SizedBox(height: 10),
                      Row(children: [
                        SizedBox(width: 90, child: _buildInput(_regCtrl, "Reg. nr", isNumber: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildInput(_accCtrl, "Kontonummer", isNumber: true)),
                      ]),
                      
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitTaxInfo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor, 
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          child: _isLoading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("Gem & Krypter Oplysninger", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
            // FAQ Sektion (Beholdt som før)
            const Text("Ofte stillede spørgsmål", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildFAQ("Hvem er omfattet af kravet?", "Alle brugere, der modtager betaling for samkørsel via HoppOn, skal indsende deres skatteoplysninger. Dette gælder uanset omfanget af din kørsel. Oplysningspligten gælder både for private brugere og for brugere, der kører i erhvervsmæssig sammenhæng."),
            _buildFAQ("Hvorfor indsamler HoppOn disse oplysninger?", "HoppOn er, ligesom alle andre platforme for samkørsel i EU, pålagt at følge DAC7-direktivet. Det betyder, at vi ved lov er forpligtet til at:", [
              "Indsamle og verificere skatteoplysninger på vores brugere.",
              "Hvert år i januar indberette den samlede indtægt fra det foregående år til de relevante skattemyndigheder (i Danmark Skattestyrelsen).",
            ]),
            _buildFAQ("Konsekvenser ved manglende oplysninger", "Hvis du ikke har udfyldt de påkrævede informationer på din profil, vil følgende ske:", [
              "Påmindelser: Du vil modtage løbende påmindelser om at færdiggøre din profil.",
              "Blokering af udbetaling: HoppOn er juridisk forpligtet til at tilbageholde og blokere for udbetaling af dine tilgodehavender, indtil oplysningerne er indsendt.",
              "Genåbning: Når de korrekte oplysninger er registreret, vil der igen blive åbnet for udbetalinger til din bankkonto.",
            ]),
            _buildFAQ("Brugerens ansvar for korrekte data", "Det er dit eget ansvar at sikre, at dine informationer altid er opdaterede og korrekte (herunder adresse og CPR-nummer). HoppOn indberetter de data, du har indtastet, og vi påtager os intet ansvar for fejlindberetninger, der skyldes mangelfulde eller forældede oplysninger fra din side."),
            _buildFAQ("Fordeling af indkomst med partner eller ægtefælle", "Hvis du deles om kørslen og indtægten med en partner eller ægtefælle, skal du være opmærksom på:", [
              "Individuelt fradrag: I Danmark er det skattefrie fradrag for samkørsel individuelt.",
              "Korrekt fordeling: Det er dit ansvar at sikre, at din årsopgørelse hos Skattestyrelsen afspejler den korrekte fordeling af indkomsten mellem dig og din partner. HoppOn indberetter som udgangspunkt indtægten til den profil, der er registreret som chauffør på turen.",
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, {bool isNumber = false}) {
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

  Widget _buildFAQ(String title, String content, [List<String>? bullets]) {
    Widget contentWidget;
    
    if (bullets != null && bullets.isNotEmpty) {
      contentWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(content, style: TextStyle(color: Colors.grey[700], height: 1.5, fontSize: 14)),
          const SizedBox(height: 12),
          ...bullets.map((bullet) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 2),
                  child: Text("•", style: TextStyle(color: Colors.grey[700], fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Text(
                    bullet,
                    style: TextStyle(color: Colors.grey[700], height: 1.5),
                  ),
                ),
              ],
            ),
          )),
        ],
      );
    } else {
      contentWidget = Text(content, style: TextStyle(color: Colors.grey[700], height: 1.5));
    }
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: contentWidget,
          )
        ],
      ),
    );
  }
}