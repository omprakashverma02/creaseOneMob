import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/image_upload_field.dart';
import '../../widgets/location_fields.dart';

/// Create / edit tournament — same fields as the web Setup Panel (minus ticker graphics).
class TournamentFormScreen extends StatefulWidget {
  const TournamentFormScreen({super.key, this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<TournamentFormScreen> createState() => _TournamentFormScreenState();
}

class _TournamentFormScreenState extends State<TournamentFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> d;
  final _c = <String, TextEditingController>{};
  bool _saving = false;

  TextEditingController ctl(String key) => _c.putIfAbsent(key, () => TextEditingController(text: d[key]?.toString() ?? ''));

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    d = {
      'type': 'T20',
      'matchKind': 'Limited Overs',
      'oversFormat': 'T20',
      'format': 'league_format',
      'ballType': 'Leather',
      'ballColor': 'White',
      'pitchType': 'TURF',
      'category': 'Community',
      'scoringType': 'only_scoring',
      'startDate': now.toIso8601String(),
      'endDate': now.add(const Duration(days: 14)).toIso8601String(),
      'pointsWin': 2,
      'pointsTie': 1,
      'pointsLoss': 0,
      'pointsBonus': 0,
      'bonusPointsEnabled': false,
      'wideRuns': 1,
      'noBallRuns': 1,
      'wideCountsAsLegalBall': false,
      'noBallCountsAsLegalBall': false,
      'impactPlayerRule': false,
      'superOver': true,
      'drsEnabled': false,
      'drsReviewsPerInnings': 2,
      'shotSelectionEnabled': true,
      ...?widget.existing,
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(String key) async {
    final cur = Fmt.parse(d[key]) ?? DateTime.now();
    final r = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2015), lastDate: DateTime(2100));
    if (r != null) setState(() => d[key] = DateTime(r.year, r.month, r.day, 12).toUtc().toIso8601String());
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    for (final e in _c.entries) {
      final numeric = const {'pointsWin', 'pointsTie', 'pointsLoss', 'pointsBonus', 'wideRuns', 'noBallRuns', 'drsReviewsPerInnings'};
      d[e.key] = numeric.contains(e.key) ? asInt(e.value.text) : e.value.text.trim();
    }
    d['location'] = [d['ground'], d['city']].where((e) => e != null && e.toString().isNotEmpty).join(', ');
    final payload = Map<String, dynamic>.from(d)
      ..removeWhere((k, v) => const {'id', 'createdAt', 'updatedAt', 'teams', 'matches', 'sponsors', 'structure', 'createdBy', '_count'}.contains(k) || v is Map || v is List);
    setState(() => _saving = true);
    try {
      final res = widget.existing?['id'] != null
          ? await context.api.updateTournament(widget.existing!['id'].toString(), payload)
          : await context.api.createTournament(payload);
      if (mounted) {
        context.toast(widget.existing == null ? 'Tournament created' : 'Tournament updated', success: true);
        Navigator.pop(context, res);
      }
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dropdown(String key, String label, List<String> items, {Map<String, String>? labels, ValueChanged<String>? after}) {
    final value = items.contains(d[key]) ? d[key] as String : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(labels?[e] ?? e))).toList(),
        onChanged: (v) {
          setState(() => d[key] = v);
          if (v != null) after?.call(v);
        },
      ),
    );
  }

  Widget _text(String key, String label, {bool required = false, TextInputType? kb}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: ctl(key),
          keyboardType: kb,
          decoration: InputDecoration(labelText: label),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
        ),
      );

  Widget _switch(String key, String title, {String? subtitle}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d[key] == true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
        onChanged: (v) => setState(() => d[key] = v),
      );

  @override
  Widget build(BuildContext context) {
    final kind = d['matchKind']?.toString() ?? 'Limited Overs';
    final formatOptions = kind == 'Multi Days'
        ? Cricket.multiDayFormats
        : kind == 'Balls-Based Limited Overs'
            ? Cricket.ballsBasedFormats
            : Cricket.oversFormats;
    final colors = Cricket.ballColors[d['ballType']] ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New tournament' : 'Edit tournament')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Save tournament'),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            ImageUploadField(label: 'Logo', url: d['logoUrl'], folder: 'tournaments', logo: true, onChanged: (u) => setState(() => d['logoUrl'] = u)),
            ImageUploadField(label: 'Organiser logo', url: d['organiserLogoUrl'], folder: 'tournaments', logo: true, onChanged: (u) => setState(() => d['organiserLogoUrl'] = u)),
          ]),
          const SectionTitle('Basics', padding: EdgeInsets.fromLTRB(0, 20, 0, 12)),
          _text('name', 'Tournament name', required: true),
          _text('organiserName', 'Organiser name'),
          Row(children: [
            Expanded(child: _text('organiserNumber', 'Organiser phone', kb: TextInputType.phone)),
            const SizedBox(width: 10),
            Expanded(child: _text('organiserEmail', 'Organiser email', kb: TextInputType.emailAddress)),
          ]),
          LocationFields(
            country: d['country']?.toString(),
            state: d['state']?.toString(),
            city: ctl('city').text.isEmpty ? null : ctl('city').text,
            onChanged: (co, st, ci) => setState(() {
              d['country'] = co;
              d['state'] = st;
              ctl('city').text = ci ?? '';
            }),
          ),
          _text('ground', 'Ground / venue'),
          Row(children: [
            Expanded(child: _dateTile('Start date', 'startDate')),
            const SizedBox(width: 10),
            Expanded(child: _dateTile('End date', 'endDate')),
          ]),
          const SectionTitle('Format', padding: EdgeInsets.fromLTRB(0, 20, 0, 12)),
          _dropdown('matchKind', 'Match kind', Cricket.matchKinds, after: (v) {
            setState(() {
              if (v == 'Multi Days') {
                d['type'] = 'TEST';
                d['oversFormat'] = 'Test Match';
              } else if (v == 'Balls-Based Limited Overs') {
                d['type'] = 'Balls';
                d['oversFormat'] = 'The Hundred';
              } else if (v == 'Box/Turf Cricket') {
                d['type'] = 'Box';
                d['oversFormat'] = 'T10';
              } else {
                d['type'] = 'T20';
                d['oversFormat'] = 'T20';
              }
            });
          }),
          _dropdown('oversFormat', 'Overs format', formatOptions, after: (v) {
            setState(() {
              if (v == 'ODI' || v == 'One Day' || v == 'Pro40') {
                d['type'] = 'ODI';
              } else if (Cricket.oversFormats.contains(v) && d['type'] != 'Box') {
                d['type'] = v == 'T5' || v == 'T10' ? 'Custom' : 'T20';
              }
            });
          }),
          _dropdown('type', 'Match type (rules engine)', Cricket.matchTypes),
          _dropdown('format', 'Tournament structure', Cricket.tournamentFormats.keys.toList(), labels: Cricket.tournamentFormats),
          _dropdown('category', 'Category', Cricket.tournamentCategories),
          Row(children: [
            Expanded(child: _dropdown('ballType', 'Ball', Cricket.ballTypes, after: (v) => setState(() => d['ballColor'] = Cricket.ballColors[v]!.first))),
            const SizedBox(width: 10),
            Expanded(child: _dropdown('ballColor', 'Ball colour', colors)),
          ]),
          _dropdown('pitchType', 'Pitch', Cricket.pitchTypes),
          const SectionTitle('Points table', padding: EdgeInsets.fromLTRB(0, 20, 0, 12)),
          Row(children: [
            Expanded(child: _text('pointsWin', 'Win', kb: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: _text('pointsTie', 'Tie / NR', kb: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: _text('pointsLoss', 'Loss', kb: TextInputType.number)),
          ]),
          _switch('bonusPointsEnabled', 'Bonus points'),
          if (d['bonusPointsEnabled'] == true) _text('pointsBonus', 'Bonus points value', kb: TextInputType.number),
          const SectionTitle('Playing conditions', padding: EdgeInsets.fromLTRB(0, 20, 0, 12)),
          Row(children: [
            Expanded(child: _text('wideRuns', 'Wide runs', kb: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: _text('noBallRuns', 'No-ball runs', kb: TextInputType.number)),
          ]),
          _switch('wideCountsAsLegalBall', 'Wide counts as a legal ball', subtitle: 'Common in tennis-ball / box cricket'),
          _switch('noBallCountsAsLegalBall', 'No-ball counts as a legal ball'),
          _switch('superOver', 'Super Over on tie'),
          _switch('impactPlayerRule', 'Impact Player rule'),
          _switch('drsEnabled', 'DRS reviews'),
          if (d['drsEnabled'] == true) _text('drsReviewsPerInnings', 'Reviews per innings', kb: TextInputType.number),
          _switch('shotSelectionEnabled', 'Wagon wheel shot capture', subtitle: 'Ask for shot direction after scoring runs'),
        ]),
      ),
    );
  }

  Widget _dateTile(String label, String key) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pickDate(key),
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month_outlined)),
            child: Text(Fmt.date(d[key])),
          ),
        ),
      );
}
