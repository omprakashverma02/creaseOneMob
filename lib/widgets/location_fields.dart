import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:flutter/material.dart';

import 'common.dart';

/// Country → State → City pickers (web TeamLocationFields / country-state-city).
class LocationFields extends StatefulWidget {
  const LocationFields({super.key, this.country, this.state, this.city, required this.onChanged});
  final String? country;
  final String? state;
  final String? city;
  final void Function(String? country, String? state, String? city) onChanged;
  @override
  State<LocationFields> createState() => _LocationFieldsState();
}

class _LocationFieldsState extends State<LocationFields> {
  late String? country = widget.country ?? 'India';
  late String? state = widget.state;
  late String? city = widget.city;
  String? _countryCode;
  String? _stateCode;

  void _emit() => widget.onChanged(country, state, city);

  Future<void> _pickCountry() async {
    final all = await csc.getAllCountries();
    if (!mounted) return;
    final r = await pickFromList(
      context,
      title: 'Country',
      items: [for (final c in all) {'name': c.name, 'code': c.isoCode, 'flag': c.flag}],
      label: (m) => '${m['flag']}  ${m['name']}',
    );
    if (r == null) return;
    setState(() {
      country = r['name'];
      _countryCode = r['code'];
      state = null;
      city = null;
    });
    _emit();
  }

  Future<String?> _codeForCountry() async {
    if (_countryCode != null) return _countryCode;
    final all = await csc.getAllCountries();
    _countryCode = all.where((c) => c.name == country).firstOrNull?.isoCode;
    return _countryCode;
  }

  Future<void> _pickState() async {
    final code = await _codeForCountry();
    if (code == null || !mounted) return;
    final states = await csc.getStatesOfCountry(code);
    if (!mounted) return;
    final r = await pickFromList(context, title: 'State', items: [for (final s in states) {'name': s.name, 'code': s.isoCode}], label: (m) => m['name']);
    if (r == null) return;
    setState(() {
      state = r['name'];
      _stateCode = r['code'];
      city = null;
    });
    _emit();
  }

  Future<void> _pickCity() async {
    final code = await _codeForCountry();
    if (code == null || !mounted) return;
    var sc = _stateCode;
    if (sc == null && state != null) {
      final states = await csc.getStatesOfCountry(code);
      sc = states.where((s) => s.name == state).firstOrNull?.isoCode;
      _stateCode = sc;
    }
    final cities = sc == null ? await csc.getCountryCities(code) : await csc.getStateCities(code, sc);
    if (!mounted) return;
    final r = await pickFromList(
      context,
      title: 'City',
      items: [
        {'name': '✎ Type a city name'},
        for (final c in cities) {'name': c.name},
      ],
      label: (m) => m['name'],
    );
    if (r == null || !mounted) return;
    var name = r['name'] as String;
    if (name.startsWith('✎')) {
      final typed = await promptText(context, title: 'City', initial: city);
      if (typed == null || typed.isEmpty) return;
      name = typed;
    }
    setState(() => city = name);
    _emit();
  }

  Widget _field(String label, String? value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(value ?? 'Select', style: TextStyle(color: value == null ? Colors.white38 : null)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(children: [
        _field('Country', country, _pickCountry),
        Row(children: [
          Expanded(child: _field('State', state, _pickState)),
          const SizedBox(width: 10),
          Expanded(child: _field('City', city, _pickCity)),
        ]),
      ]);
}
