import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'tax_info_screen.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _isLoading = true;
  bool _hasStripeAccount = false;
  double _balance = 0.00;
  String? _stripeAccountId;

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
  }

  Future<void> _fetchWalletData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Tjek om profil har Stripe ID
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('stripe_account_id, charges_enabled')
          .eq('id', userId)
          .single();

      _stripeAccountId = profile['stripe_account_id'];
      bool chargesEnabled = profile['charges_enabled'] ?? false;

      // 2. Hent saldo fra din interne wallet tabel
      // Vi bruger 'maybeSingle' i tilfælde af at wallet ikke er oprettet endnu
      final wallet = await Supabase.instance.client
          .from('wallets')
          .select('balance')
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _hasStripeAccount =
              _stripeAccountId != null &&
              chargesEnabled; // Skal være true for at udbetale
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

  // --- OPRET STRIPE KONTO ---
  Future<void> _connectStripe() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;

      // Kald 'connect-account' funktionen i skyen
      final res = await Supabase.instance.client.functions.invoke(
        'connect-account',
        body: {'user_id': user.id, 'email': user.email},
      );

      if (res.status == 200) {
        final data = res.data;
        final url = Uri.parse(data['url']);
        final accId = data['stripe_account_id'];

        // Gem Stripe ID i profilen hvis vi ikke har det
        if (_stripeAccountId == null) {
          await Supabase.instance.client
              .from('profiles')
              .update({'stripe_account_id': accId})
              .eq('id', user.id);
        }

        // --- RETTELSE: Brug inAppWebView for seamless oplevelse ---
        if (await canLaunchUrl(url)) {
          await launchUrl(
            url,
            mode: LaunchMode.inAppWebView, // Holder brugeren i appen
            webViewConfiguration: const WebViewConfiguration(
              enableJavaScript: true,
              enableDomStorage: true,
            ),
          );

          // Når brugeren lukker vinduet, opdaterer vi data for at se om de blev færdige
          await _fetchWalletData();
        }
      } else {
        throw "Kunne ikke forbinde til Stripe serveren.";
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fejl: $e")));
    } finally {
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
      final res = await Supabase.instance.client.functions.invoke(
        'payout',
        body: {'user_id': user.id, 'amount': _balance},
      );

      if (res.status == 200) {
        // Opdater wallet i databasen (sæt saldo til 0)
        await Supabase.instance.client
            .from('wallets')
            .update({'balance': 0})
            .eq('user_id', user.id);

        // Gem i historik
        final walletRes = await Supabase.instance.client
            .from('wallets')
            .select('id')
            .eq('user_id', user.id)
            .single();
        final walletId = walletRes['id'];

        await Supabase.instance.client.from('transactions').insert({
          'wallet_id': walletId,
          'amount': -_balance,
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
          _fetchWalletData(); // Opdater UI
        }
      } else {
        throw "Udbetaling fejlede på serveren.";
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Udbetalingsfejl: $e")));
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
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
                          style: TextStyle(color: Colors.white70, fontSize: 14),
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

                        if (_hasStripeAccount)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _balance > 0 ? _payoutFunds : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text("Udbetal"),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _connectStripe,
                              icon: const Icon(Icons.account_balance),
                              label: const Text("Opret Pung (Nødvendig)"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF6366F1,
                                ), // Indigo
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Text(
                    "Indstillinger",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  _buildSettingsTile(
                    context,
                    "Skatteoplysninger (DAC7)",
                    "Påkrævet for udbetaling",
                    Icons.account_balance,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TaxInfoScreen()),
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    "Betalingsmetoder",
                    "Kort og MobilePay",
                    Icons.credit_card,
                    () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Administreres via betaling."),
                      ),
                    ),
                  ),
                ],
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
}
