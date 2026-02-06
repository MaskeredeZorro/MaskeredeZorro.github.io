import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tax_info_screen.dart';
import 'package:intl/intl.dart';

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

  // Hjælper til at vise statusmeddelelser
  String _getPayoutLockReason() {
    if (!_isStripeReady) return "Mangler skatteoplysninger";
    if (_balance <= 0) return "Saldo er 0 kr.";
    return "Udbetal";
  }

  // --- HENT DATA (Opdateret til at tjekke user_stripe_data) ---
  Future<void> _fetchWalletData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Tjek om brugeren har færdiggjort Stripe onboarding (Skatteoplysninger)
      final stripeData = await Supabase.instance.client
          .from('user_stripe_data')
          .select('onboarding_completed')
          .eq('user_id', userId)
          .maybeSingle();

      // Hvis vi finder en række, og onboarding_completed er true -> Så er vi klar!
      bool isReady =
          stripeData != null && stripeData['onboarding_completed'] == true;

      // 2. Hent saldo fra din interne wallet tabel
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

      // Kald 'payout' funktionen i skyen
      // (Forudsætter at du har oprettet denne Edge Function - hvis ikke, så sig til!)
      final res = await Supabase.instance.client.functions.invoke(
        'payout',
        body: {'id': user.id, 'amount': _balance},
      );

      if (res.status == 200) {
        // Opdater profiles i databasen (sæt saldo til 0)
        await Supabase.instance.client
            .from('profiles')
            .update({'balance': 0})
            .eq('id', user.id);

        // Gem udbetalingen i historikken (transactions)
        await Supabase.instance.client.from('transactions').insert({
          'user_id': user.id,
          'amount': _balance, // Vi gemmer beløbet
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Kunne ikke udbetale: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                              // Knappen er KUN aktiv hvis saldo > 0 OG Stripe er klar
                              onPressed: (_balance > 0 && _isStripeReady)
                                  ? _payoutFunds
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                disabledBackgroundColor:
                                    Colors.white24, // Grå når inaktiv
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
                                  // Send brugeren til skatte-siden
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const TaxInfoScreen(),
                                    ),
                                  ).then(
                                    (_) => _fetchWalletData(),
                                  ); // Opdater når de kommer tilbage
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
                      () =>
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TaxInfoScreen(),
                            ),
                          ).then(
                            (_) => _fetchWalletData(),
                          ), // Opdater data når man kommer tilbage
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
                    // --- HER SLUTTER HISTORIK-SEGMENTET ---
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
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
    );
  }
}
