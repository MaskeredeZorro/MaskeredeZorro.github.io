import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; 
import '../features/rides/create_ride_screen.dart';
import '../features/rides/ride_detail_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // --- SØGE STATE (Løftet herop så vi kan dele data mellem faner) ---
  String? _searchOrigin;
  String? _searchDest;
  DateTime? _searchDate;

  // Funktion til at starte en søgning fra SearchTab
  void _performSearch(String origin, String dest, DateTime date) {
    setState(() {
      _searchOrigin = origin;
      _searchDest = dest;
      _searchDate = date;
      _currentIndex = 1; // Skift til "Alle lift" fanen
    });
  }

  // Nulstil søgning (Vis alle)
  void _clearSearch() {
    setState(() {
      _searchOrigin = null;
      _searchDest = null;
      _searchDate = null;
    });
  }

  void _onTabTapped(int index) async {
    if (index == 2) {
      // Opret Tur
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRideScreen()));
      setState(() {}); // Opdater UI når man kommer tilbage
    } else {
      // Hvis man trykker på "Alle lift" (index 1) direkte, nulstiller vi evt. søgningen? 
      // Eller beholder den? Lad os beholde den for nu, men man kan lave en knap til at rydde.
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Slate farve
    final Color activeColor = const Color(0xFF0F172A);

    // Vi bygger listen af sider dynamisk for at sende data med
    final List<Widget> pages = [
      SearchTab(onSearch: _performSearch),  // Sender søge-funktionen med
      RidesTab(
        filterOrigin: _searchOrigin, 
        filterDest: _searchDest, 
        filterDate: _searchDate,
        onClearFilters: _clearSearch,
      ),
      const SizedBox(),   // Placeholder
      const Center(child: Text("Beskeder (Kommer snart)")),
      const ProfileTab(), 
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: activeColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 8,
        backgroundColor: Colors.white,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.search), label: "Søg"),
          const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Alle lift"),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(shape: BoxShape.circle, color: activeColor, boxShadow: [BoxShadow(color: activeColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ), 
            label: "" 
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: "Beskeder"),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Profil"),
        ],
      ),
    );
  }
}

// ==========================================
// 1. SEARCH TAB (FORSIDEN)
// ==========================================
class SearchTab extends StatefulWidget {
  final Function(String, String, DateTime) onSearch; // Callback til parent

  const SearchTab({super.key, required this.onSearch});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _originController = TextEditingController();
  final _destController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateDisplayController = TextEditingController(text: "I dag");

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _accentColor = const Color(0xFF6366F1);
  final Color _bgLight = const Color(0xFFF8FAFC);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2030), initialDate: DateTime.now());
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateDisplayController.text = DateFormat('d. MMM yyyy').format(picked);
      });
    }
  }

  void _handleSearch() {
    // Vi kalder funktionen i HomeScreen med værdierne
    // Her trimmer vi teksten, men vi sender den rå tekst videre
    // Supabase .ilike vil så matche "Tune" mod "Byagervej 11, 4030 Tune"
    widget.onSearch(
      _originController.text.trim(), 
      _destController.text.trim(), 
      _selectedDate
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- TOP HEADER ---
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Hej!", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                        Text("Hvor skal du hen?", style: TextStyle(color: _primaryColor, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(Icons.person, color: Colors.grey),
                    )
                  ],
                ),
              ),

              // --- SØGE FORM ---
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _bgLight,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildInputField(Icons.radio_button_checked, "Fra (By)", "F.eks. Tune", _originController),
                    const Padding(padding: EdgeInsets.only(left: 40), child: Divider(height: 30)),
                    _buildInputField(Icons.location_on, "Til (By)", "F.eks. Aalborg", _destController),
                    const Padding(padding: EdgeInsets.only(left: 40), child: Divider(height: 30)),
                    _buildInputField(Icons.calendar_today, "Hvornår?", "I dag", _dateDisplayController, isReadOnly: true, onTap: _pickDate),
                    
                    const SizedBox(height: 30),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _handleSearch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 5,
                          shadowColor: _primaryColor.withOpacity(0.3),
                        ),
                        child: const Text("Søg efter lift", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // --- ILLUSTRATION ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: 20, bottom: 20,
                        child: Icon(Icons.directions_car_filled, size: 80, color: _accentColor.withOpacity(0.2)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Kør grønt", style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text("Spar penge og\nmiljøet sammen.", style: TextStyle(color: _primaryColor, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(IconData icon, String label, String hint, TextEditingController controller, {bool isReadOnly = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: Icon(icon, color: const Color(0xFF6366F1), size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
                isReadOnly 
                ? Text(controller.text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                : TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// 2. RIDES TAB (LISTEN - MED FILTRERING)
// ==========================================
class RidesTab extends StatefulWidget {
  final String? filterOrigin;
  final String? filterDest;
  final DateTime? filterDate;
  final VoidCallback? onClearFilters;

  const RidesTab({super.key, this.filterOrigin, this.filterDest, this.filterDate, this.onClearFilters});

  @override
  State<RidesTab> createState() => _RidesTabState();
}

class _RidesTabState extends State<RidesTab> {
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRides();
  }

  @override
  void didUpdateWidget(covariant RidesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Hvis filtrene ændrer sig, henter vi data igen
    if (oldWidget.filterOrigin != widget.filterOrigin || oldWidget.filterDest != widget.filterDest) {
      _fetchRides();
    }
  }

  Future<void> _fetchRides() async {
    setState(() => _isLoading = true);
    try {
      // 1. Start query UDEN at sortere endnu. 
      // Nu er 'query' en PostgrestFilterBuilder, som vi kan bruge .ilike på.
      var query = Supabase.instance.client
          .from('rides')
          .select('*, profiles(*), origin_location::text, destination_location::text');

      // 2. Påfør filtre dynamisk
      if (widget.filterOrigin != null && widget.filterOrigin!.isNotEmpty) {
        query = query.ilike('origin_city', '%${widget.filterOrigin}%');
      }

      if (widget.filterDest != null && widget.filterDest!.isNotEmpty) {
        query = query.ilike('destination_city', '%${widget.filterDest}%');
      }

      // 3. TIL SIDST sorterer vi og henter data (await)
      final response = await query.order('departure_time', ascending: true);
      
      if (mounted) {
        setState(() {
          _rides = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fejl: $e");
      if(mounted) setState(() => _isLoading = false);
    }
  }

  String _getCleanCarModel(dynamic rawData) {
    if (rawData == null) return 'Bil';
    try {
      final Map<String, dynamic> data = jsonDecode(rawData.toString());
      return data['make'] ?? 'Bil'; 
    } catch (e) {
      return rawData.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tjek om vi søger
    bool isSearching = (widget.filterOrigin != null && widget.filterOrigin!.isNotEmpty) || 
                       (widget.filterDest != null && widget.filterDest!.isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(isSearching ? "Søgeresultater" : "Alle Lift", style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          if (isSearching)
            TextButton(
              onPressed: widget.onClearFilters, 
              child: const Text("Nulstil", style: TextStyle(color: Colors.red))
            )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : _rides.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 15),
                  Text("Ingen lift fundet fra ${widget.filterOrigin ?? ''} til ${widget.filterDest ?? ''}", 
                    style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  TextButton(onPressed: widget.onClearFilters, child: const Text("Vis alle lift"))
                ],
              ),
            )
          : ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _rides.length,
            itemBuilder: (context, index) {
              return _buildRideCard(_rides[index]);
            },
          ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    DateTime depTime = DateTime.parse(ride['departure_time']);
    DateTime arrTime = ride['arrival_time'] != null 
        ? DateTime.parse(ride['arrival_time']) 
        : depTime.add(const Duration(hours: 2));
    
    final driver = ride['profiles'];
    final carName = _getCleanCarModel(ride['car_model']);
    final isFerry = ride['is_ferry'] == true;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("I dag, ${DateFormat('HH:mm').format(depTime)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                  Text("DKK ${ride['price_dkk']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A))),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(border: Border.all(color: const Color(0xFF6366F1), width: 2), shape: BoxShape.circle)),
                      Container(width: 2, height: 25, color: Colors.grey[200]),
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(2))),
                    ],
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Her klipper vi også visuelt til bare Byen
                        Text(ride['origin_city'].split(',')[0], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 18),
                        Text(ride['destination_city'].split(',')[0], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 15),

              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: driver['avatar_url'] != null ? NetworkImage(driver['avatar_url']) : null,
                    child: driver['avatar_url'] == null ? Text(driver['full_name'][0]) : null,
                  ),
                  const SizedBox(width: 10),
                  Text(driver['full_name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const Spacer(),
                  if (ride['instant_booking'] == true) 
                    const Icon(Icons.bolt, color: Colors.amber, size: 20),
                  const SizedBox(width: 5),
                  Text("$carName", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. PROFILE TAB
// ==========================================
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _myOfferedRides = [];
  List<Map<String, dynamic>> _myBookedRides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchMyActivity();
  }

  Future<void> _fetchMyActivity() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    
    try {
      final driverRes = await Supabase.instance.client
          .from('rides')
          .select('*, profiles(*)')
          .eq('driver_id', user.id)
          .order('departure_time', ascending: false);

      final passengerRes = await Supabase.instance.client
          .from('bookings')
          .select('*, rides(*, profiles(*))') 
          .eq('passenger_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _myOfferedRides = List<Map<String, dynamic>>.from(driverRes);
          _myBookedRides = List<Map<String, dynamic>>.from(passengerRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Profil fejl: $e");
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Min Aktivitet", style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF6366F1),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF6366F1),
          tabs: const [
            Tab(text: "Kører selv"),
            Tab(text: "Passager"),
          ],
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : TabBarView(
            controller: _tabController,
            children: [
              _buildList(_myOfferedRides, isDriver: true),
              _buildList(_myBookedRides, isDriver: false),
            ],
          ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, {required bool isDriver}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isDriver ? Icons.directions_car_outlined : Icons.hail, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 15),
            Text(isDriver ? "Du har ikke tilbudt nogen ture endnu" : "Du har ikke booket nogen ture endnu", 
              style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final ride = isDriver ? item : item['rides']; 
        
        if (ride == null) return const SizedBox(); 

        DateTime time = DateTime.parse(ride['departure_time']);

        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("${ride['origin_city'].split(',')[0]} → ${ride['destination_city'].split(',')[0]}", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(DateFormat('d. MMM • HH:mm').format(time)),
            trailing: Chip(
              label: Text(isDriver ? "${ride['price_dkk']} kr." : (item['status'] ?? 'pending')),
              backgroundColor: isDriver ? Colors.green.shade50 : Colors.blue.shade50,
              labelStyle: TextStyle(color: isDriver ? Colors.green : Colors.blue, fontSize: 12),
            ),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride)));
            },
          ),
        );
      },
    );
  }
}