import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/image_upload_field.dart';
import '../../widgets/location_fields.dart';

class TeamFormScreen extends StatefulWidget {
  const TeamFormScreen({super.key, this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<TeamFormScreen> createState() => _TeamFormScreenState();
}

class _TeamFormScreenState extends State<TeamFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?['name']?.toString());
  late final short = TextEditingController(text: widget.existing?['shortName']?.toString());
  late final city = TextEditingController(text: widget.existing?['city']?.toString());
  late final state = TextEditingController(text: widget.existing?['state']?.toString());
  late String? country = widget.existing?['country']?.toString() ?? 'India';
  late String? logo = widget.existing?['logoUrl']?.toString();
  late String color = widget.existing?['themeColor']?.toString() ?? '#2F6BFF';
  bool saving = false;

  static const palette = [
    '#2F6BFF', '#0EA5E9', '#22D3EE', '#14B8A6', '#22C55E', '#84CC16', '#EAB308', '#F59E0B',
    '#F97316', '#EF4444', '#E11D48', '#EC4899', '#A855F7', '#7C3AED', '#6366F1', '#64748B',
    '#FACC15', '#1E3A8A', '#991B1B', '#065F46',
  ];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (city.text.trim().isEmpty) {
      context.toast('Pick the team city', error: true);
      return;
    }
    setState(() => saving = true);
    final data = {
      'name': name.text.trim(),
      'shortName': short.text.trim().isEmpty ? null : short.text.trim().toUpperCase(),
      'city': city.text.trim(),
      'state': state.text.trim().isEmpty ? null : state.text.trim(),
      'country': country ?? 'India',
      'logoUrl': logo,
      'themeColor': color,
    };
    try {
      dynamic res;
      if (widget.existing?['id'] != null) {
        await context.api.updateTeam(widget.existing!['id'].toString(), data);
        res = {...widget.existing!, ...data};
      } else {
        res = await context.api.createTeam(data);
      }
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New team' : 'Edit team')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Saving…' : 'Save team')),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: ImageUploadField(label: 'Team logo', url: logo, folder: 'teams', logo: true, onChanged: (u) => setState(() => logo = u))),
          const SizedBox(height: 20),
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Team name'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: short, maxLength: 5, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Short name (e.g. MI)')),
          const SizedBox(height: 4),
          LocationFields(
            country: country,
            state: state.text.isEmpty ? null : state.text,
            city: city.text.isEmpty ? null : city.text,
            onChanged: (co, st, ci) => setState(() {
              country = co;
              state.text = st ?? '';
              city.text = ci ?? '';
            }),
          ),
          const SectionTitle('Team colour', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in palette)
              GestureDetector(
                onTap: () => setState(() => color = c),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.fromHex(c),
                    border: Border.all(color: color.toUpperCase() == c ? Colors.white : Colors.transparent, width: 3),
                  ),
                  child: color.toUpperCase() == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              ),
          ]),
          const SizedBox(height: 22),
          Center(child: TeamBadge(name: name.text.isEmpty ? 'Team' : name.text, logoUrl: logo, color: color, size: 72)),
        ]),
      ),
    );
  }
}
