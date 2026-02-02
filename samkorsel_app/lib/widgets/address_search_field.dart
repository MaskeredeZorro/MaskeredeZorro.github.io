import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AddressSearchField extends StatefulWidget {
  final String label;
  final Function(String) onSelected;

  const AddressSearchField({super.key, required this.label, required this.onSelected});

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final _controller = TextEditingController();
  List<dynamic> _suggestions = [];
  bool _isLoading = false;

  Future<void> _searchAddress(String query) async {
    if (query.length < 3) return;
    
    // Vi bruger DAWA's autocomplete API
    final url = Uri.parse('https://api.dataforsyningen.dk/adresser/autocomplete?q=$query');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _suggestions = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint("DAWA Fejl: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.map),
            suffixIcon: _isLoading ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) : null,
          ),
          onChanged: (val) {
             _searchAddress(val);
          },
        ),
        if (_suggestions.isNotEmpty)
          Container(
            height: 200, // Begræns højden på listen
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0,2))]
            ),
            child: ListView.separated(
              itemCount: _suggestions.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _suggestions[index];
                final text = item['tekst'];
                
                return ListTile(
                  dense: true,
                  title: Text(text),
                  onTap: () {
                    _controller.text = text; // Sæt teksten
                    widget.onSelected(text); // Send tilbage til forældren
                    setState(() => _suggestions = []); // Skjul listen
                    FocusScope.of(context).unfocus(); // Luk tastaturet
                  },
                );
              },
            ),
          )
      ],
    );
  }
}