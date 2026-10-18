import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../widgets/common.dart';
import '../../widgets/image_upload_field.dart';

/// Create / edit a player. Pops with the saved player map.
class PlayerFormScreen extends StatefulWidget {
  const PlayerFormScreen({super.key, this.existing, this.initialName});
  final Map<String, dynamic>? existing;
  final String? initialName;
  @override
  State<PlayerFormScreen> createState() => _PlayerFormScreenState();
}

class _PlayerFormScreenState extends State<PlayerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> e = widget.existing ?? {};
  late final name = TextEditingController(text: e['name']?.toString() ?? widget.initialName);
  late final short = TextEditingController(text: e['shortName']?.toString());
  late final mobile = TextEditingController(text: e['mobileNumber']?.toString());
  late final docId = TextEditingController(text: e['documentId']?.toString());
  late String? image = e['imageUrl']?.toString();
  late String role = Cricket.playerRoles.contains(e['role']) ? e['role'] : 'batsman';
  late String batting = Cricket.battingStyles.contains(e['battingStyle']) ? e['battingStyle'] : 'RHB';
  late String bowling = Cricket.bowlingStyles.contains(e['bowlingStyle']) ? e['bowlingStyle'] : 'None';
  late String gender = (e['gender'] ?? 'Male').toString();
  late String docType = (e['documentType'] ?? 'Other').toString();
  late DateTime? dob = Fmt.parse(e['dob']);
  bool saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => saving = true);
    final digits = mobile.text.replaceAll(RegExp(r'\D'), '');
    final data = {
      'name': name.text.trim(),
      'shortName': short.text.trim().isEmpty ? null : short.text.trim(),
      'mobileNumber': digits,
      'countryCode': e['countryCode'] ?? '+91',
      'documentType': docType,
      'documentId': docId.text.trim().isEmpty ? 'mob-$digits' : docId.text.trim(),
      'role': role,
      'gender': gender,
      'battingStyle': batting,
      'bowlingStyle': bowling == 'None' ? null : bowling,
      'imageUrl': image,
      'dob': dob?.toIso8601String(),
    };
    try {
      Map<String, dynamic> res;
      if (e['id'] != null) {
        await context.api.updatePlayer(e['id'].toString(), data);
        res = {...e, ...data};
      } else {
        res = await context.api.createPlayer(data);
      }
      if (mounted) Navigator.pop(context, res);
    } catch (err) {
      if (mounted) context.toast(err.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(e['id'] == null ? 'New player' : 'Edit player')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Saving…' : 'Save player')),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: ImageUploadField(label: 'Photo', url: image, folder: 'players', onChanged: (u) => setState(() => image = u))),
          const SizedBox(height: 18),
          TextFormField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: short, decoration: const InputDecoration(labelText: 'Short / scorecard name')),
          const SizedBox(height: 12),
          TextFormField(
            controller: mobile,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 '),
            validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Enter a 10 digit number' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => gender = v ?? gender),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final r = await showDatePicker(context: context, initialDate: dob ?? DateTime(2000), firstDate: DateTime(1940), lastDate: DateTime.now());
                  if (r != null) setState(() => dob = r);
                },
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Date of birth'), child: Text(dob == null ? '-' : Fmt.date(dob!.toIso8601String()))),
              ),
            ),
          ]),
          const SectionTitle('Cricket profile', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
          DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(labelText: 'Playing role'),
            items: Cricket.playerRoles.map((r) => DropdownMenuItem(value: r, child: Text(Cricket.roleLabel(r)))).toList(),
            onChanged: (v) => setState(() => role = v ?? role),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'RHB', label: Text('Right-hand bat')), ButtonSegment(value: 'LHB', label: Text('Left-hand bat'))],
            selected: {batting},
            onSelectionChanged: (s) => setState(() => batting = s.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: bowling,
            decoration: const InputDecoration(labelText: 'Bowling style'),
            items: Cricket.bowlingStyles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (v) => setState(() => bowling = v ?? bowling),
          ),
          const SectionTitle('Identity (optional)', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: const ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID', 'Other'].contains(docType) ? docType : 'Other',
                decoration: const InputDecoration(labelText: 'Document'),
                items: const ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => docType = v ?? docType),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: docId, decoration: const InputDecoration(labelText: 'Unique / document ID'))),
          ]),
        ]),
      ),
    );
  }
}
