import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// HUSK ATRETTE DENNE IMPORT, SÅ DEN PASSER TIL DIN FILSTRUKTUR
import 'tax_info_screen.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _isLoading = true;
  bool _isStripeReady = false; // Styrer om vi må udbetale
  double _balance = 0.00;

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
  }

  // --- HENT DATA ---
  Future<void> _fetchWalletData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Tjek om brugeren har færdiggjort Stripe onboarding
      final stripeData = await Supabase.instance.client
          .from('user_stripe_data')
          .select('onboarding_completed')
          .eq('user_id', userId)
          .maybeSingle();

      bool isReady =
          stripeData != null && stripeData['onboarding_completed'] == true;

      // 2. Hent saldo fra profiles
      final wallet = await Supabase.instance.client
          .from('profiles')
          .select('balance')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isStripeReady = isReady;
          _balance = wallet != null
              ? (wallet['balance'] as num).toDouble()
              : 0.00;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fejl i wallet fetch: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UDBETAL PENGE ---
  Future<void> _payoutFunds() async {
    if (_balance <= 0) return;

    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;

      final res = await Supabase.instance.client.functions.invoke(
        'payout',
        body: {'id': user.id, 'amount': _balance},
      );

      if (res.status == 200) {
        // Nulstil saldo lokalt og i DB
        await Supabase.instance.client
            .from('profiles')
            .update({'balance': 0})
            .eq('id', user.id);

        // Gem udbetaling i historik
        await Supabase.instance.client.from('transactions').insert({
          'user_id': user.id,
          'amount': _balance,
          'type': 'payout',
          'description': 'Udbetaling til bankkonto',
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Pengene er på vej! 💸"),
              backgroundColor: Colors.green,
            ),
          );
          _fetchWalletData();
        }
      } else {
        throw "Udbetaling fejlede på serveren. Status: ${res.status}";
      }
    } catch (e) {
      debugPrint("Udbetalingsfejl: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Kunne ikke udbetale: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIK: VIS DETALJERET REGNING (Sheet) ---
  void _showRideBreakdown(
    BuildContext context,
    String rideId,
    double totalAmount,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // HER var fejlen. Vi tilføjer <dynamic> for at fixe type-fejlen.
        return FutureBuilder<List<dynamic>>(
          future: Future.wait<dynamic>([
            Supabase.instance.client
                .from('rides')
                .select('price_dkk, origin_city, destination_city')
                .eq('id', rideId)
                .single(),
            Supabase.instance.client
                .from('bookings')
                .select('id')
                .eq('ride_id', rideId)
                .eq('status', 'approved'),
          ]),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 250,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            // Udpak data
            final rideData = snapshot.data![0] as Map<String, dynamic>;
            final bookings = snapshot.data![1] as List;

            final double pricePerPerson = (rideData['price_dkk'] as num)
                .toDouble();
            final int passengerCount = bookings.length;
            final double feePerPerson = 15.0; // Det faste gebyr du nævnte

            final double totalGross = pricePerPerson * passengerCount;
            final double totalFees = feePerPerson * passengerCount;
            final double netIncome = totalGross - totalFees;

            // Design stilarter
            const labelStyle = TextStyle(fontSize: 14, color: Colors.grey);
            const valueStyle = TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            );
            const mathStyle = TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
              color: Colors.black87,
            );

            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    "${rideData['origin_city']} ➝ ${rideData['destination_city']}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Specifikation af indtjening",
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const Divider(height: 30),

                  // 1. Turpris pr. person
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Turpris pr. person", style: labelStyle),
                      Text(
                        "${pricePerPerson.toStringAsFixed(0)} kr.",
                        style: valueStyle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. Passagerer * Pris (Brutto)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 4),
                          Text("x $passengerCount", style: mathStyle),
                        ],
                      ),
                      Text(
                        "= ${totalGross.toStringAsFixed(0)} kr.",
                        style: valueStyle,
                      ),
                    ],
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(),
                  ),

                  // 3. Gebyr beregning
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "x $passengerCount  x  -15 kr.",
                            style: mathStyle,
                          ),
                        ],
                      ),
                      Text(
                        "- ${totalFees.toStringAsFixed(0)} kr.",
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Platformgebyr fratrukket",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(thickness: 2),
                  ),

                  // 4. Endeligt regnestykke
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${totalGross.toInt()} - ${totalFees.toInt()}",
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        "${netIncome.toStringAsFixed(0)} kr.",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text("Indtægt til dig", style: labelStyle),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Betalinger & Skat"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchWalletData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- SALDO KORT ---
                    Container(
                      padding: const EdgeInsets.all(24),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF334155)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueGrey.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Tilgængelig saldo",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "${_balance.toStringAsFixed(2)} kr.",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // --- UDBETAL KNAP ---
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (_balance > 0 && _isStripeReady)
                                  ? _payoutFunds
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                disabledBackgroundColor: Colors.white24,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                _isStripeReady ? "Udbetal" : "Udbetaling låst",
                                style: TextStyle(
                                  color: (_balance > 0 && _isStripeReady)
                                      ? Colors.black
                                      : Colors.white54,
                                ),
                              ),
                            ),
                          ),

                          // --- ADVARSEL HVIS IKKE KLAR ---
                          if (!_isStripeReady)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const TaxInfoScreen(),
                                    ),
                                  ).then((_) => _fetchWalletData());
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orangeAccent,
                                      size: 16,
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      "Mangler skatteoplysninger",
                                      style: TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 12,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                    const Text(
                      "Indstillinger",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _buildSettingsTile(
                      context,
                      "Skatteoplysninger (DAC7)",
                      _isStripeReady
                          ? "Oplysninger godkendt ✅"
                          : "Påkrævet for udbetaling ⚠️",
                      Icons.account_balance,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TaxInfoScreen(),
                        ),
                      ).then((_) => _fetchWalletData()),
                    ),

                    // --- HER STARTER HISTORIK-SEGMENTET ---
                    const SizedBox(height: 30),
                    const Text(
                      "Historik",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: Supabase.instance.client
                          .from('transactions')
                          .stream(primaryKey: ['id'])
                          .eq(
                            'user_id',
                            Supabase.instance.client.auth.currentUser!.id,
                          )
                          .order('created_at', ascending: false),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        final transactions = snapshot.data!;

                        if (transactions.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              "Ingen historik endnu.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        return Column(
                          children: transactions
                              .map((tx) => _buildTransactionItem(tx))
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    String title,
    String sub,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF0F172A)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          sub,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final bool isEarnings = tx['type'] == 'ride_earnings';
    final DateTime date = DateTime.parse(tx['created_at']).toLocal();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // Sæt onTap til at vise detaljer HVIS det er en indtjening
          onTap: isEarnings && tx['ride_id'] != null
              ? () => _showRideBreakdown(
                  context,
                  tx['ride_id'],
                  (tx['amount'] as num).toDouble(),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isEarnings
                      ? Colors.green.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  child: Icon(
                    isEarnings
                        ? Icons.add_circle_outline
                        : Icons.account_balance_wallet_outlined,
                    color: isEarnings ? Colors.green : Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx['description'] ?? "Transaktion",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "${date.day}/${date.month}/${date.year} kl. ${date.hour}:${date.minute.toString().padLeft(2, '0')}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      if (isEarnings)
                        const Padding(
                          padding: EdgeInsets.only(top: 4.0),
                          child: Text(
                            "Tryk for specifikation",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  "${isEarnings ? '+' : ''}${tx['amount']} kr.",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isEarnings ? Colors.green[700] : Colors.black,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
