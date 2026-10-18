import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Schedule a match (web CreateMatchWizard without ticker-theme steps).
class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key, this.tournamentId, this.existing});
  final String? tournamentId;
  final Map<String, dynamic>? existing;
  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  List<Map<String, dynamic>> tournaments = [];
  List<Map<String, dynamic>> teams = [];
  Map<String, dynamic>? tournament;
  String? team1Id;
  String? team2Id;
  String stage = 'League';
  final group = TextEditingController();
  final venue = TextEditingController();
  final overs = TextEditingController(text: '20');
  final pp1 = TextEditingController(text: '6');
  final pp1From = TextEditingController(text: '0.1');
  final pp2From = TextEditingController(text: '0');
  final pp2To = TextEditingController(text: '0');
  final pp2Dur = TextEditingController(text: '0');
  final pp3From = TextEditingController(text: '0');
  final pp3To = TextEditingController(text: '0');
  final pp3Dur = TextEditingController(text: '0');
  final comm = List.generate(3, (_) => TextEditingController());
  final commHin = TextEditingController();
  final commReg = TextEditingController();
  final streamer = TextEditingController();

  /// Fill format-correct default powerplay ranges (web defaultPowerplayRanges).
  void _applyPpDefaults(int o) {
    final t = tournament;
    if (t == null) return;
    final d = Powerplay.defaults(t, o);
    String f(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    pp1From.text = f(d.p1.from);
    pp1.text = f(d.p1.to);
    pp2From.text = f(d.p2.from);
    pp2To.text = f(d.p2.to);
    pp3From.text = f(d.p3.from);
    pp3To.text = f(d.p3.to);
    pp2Dur.text = '0';
    pp3Dur.text = '0';
  }
  final umpire1 = TextEditingController();
  final umpire2 = TextEditingController();
  final referee = TextEditingController();
  final scorer = TextEditingController();
  DateTime when = DateTime.now().add(const Duration(hours: 1));
  bool loading = true;
  bool saving = false;
  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      team1Id = e['team1Id']?.toString();
      team2Id = e['team2Id']?.toString();
      stage = e['stage']?.toString() ?? stage;
      group.text = e['group']?.toString() ?? '';
      venue.text = e['venue']?.toString() ?? '';
      overs.text = '${e['overs'] ?? 20}';
      pp1.text = '${e['powerplay1To'] ?? 6}';
      pp1From.text = '${e['powerplay1From'] ?? 0.1}';
      pp2From.text = '${e['powerplay2From'] ?? 0}';
      pp2To.text = '${e['powerplay2To'] ?? 0}';
      pp2Dur.text = '${e['powerplay2Duration'] ?? 0}';
      pp3From.text = '${e['powerplay3From'] ?? 0}';
      pp3To.text = '${e['powerplay3To'] ?? 0}';
      pp3Dur.text = '${e['powerplay3Duration'] ?? 0}';
      for (var i = 0; i < 3; i++) {
        comm[i].text = e['commentator${i + 1}']?.toString() ?? '';
      }
      final byLang = asMap(e['commentatorsByLang'] ?? asMap(e['scorerMeta'])['commentators']);
      commHin.text = ((byLang['hin'] as List?) ?? const []).join(', ');
      commReg.text = ((byLang['reg'] as List?) ?? const []).join(', ');
      streamer.text = (e['liveStreamer'] ?? e['LiveStreamer'])?.toString() ?? '';
      umpire1.text = e['umpire1']?.toString() ?? '';
      umpire2.text = e['umpire2']?.toString() ?? '';
      referee.text = e['matchReferee']?.toString() ?? '';
      scorer.text = e['onlineScorer']?.toString() ?? asMap(asMap(e['scorerMeta'])['officials'])['onlineScorer']?.toString() ?? '';
      when = Fmt.parse(e['scheduledAt']) ?? when;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.api.tournaments();
      if (!mounted) return;
      tournaments = list;
      final tid = widget.tournamentId ?? widget.existing?['tournamentId']?.toString();
      final t = list.where((x) => x['id'].toString() == tid).firstOrNull;
      if (t != null) await _selectTournament(t, keepTeams: true);
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _selectTournament(Map<String, dynamic> t, {bool keepTeams = false}) async {
    setState(() {
      tournament = t;
      if (!keepTeams) {
        team1Id = null;
        team2Id = null;
      }
      if (!isEdit) {
        final o = Cricket.defaultOversFor(t['type']?.toString(), t['oversFormat']?.toString());
        overs.text = '$o';
        _applyPpDefaults(o);
        venue.text = t['ground']?.toString() ?? t['city']?.toString() ?? '';
      }
    });
    var ts = await context.api.tournamentTeams(t['id'].toString());
    if (ts.isEmpty) ts = await context.api.teams();
    if (mounted) setState(() => teams = ts);
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(context: context, initialDate: when, firstDate: DateTime(2015), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(when));
    setState(() => when = DateTime(d.year, d.month, d.day, t?.hour ?? when.hour, t?.minute ?? when.minute));
  }

  Future<void> _save() async {
    if (tournament == null || team1Id == null || team2Id == null) {
      context.toast('Pick a tournament and both teams', error: true);
      return;
    }
    if (team1Id == team2Id) {
      context.toast('Teams must be different', error: true);
      return;
    }
    final o = asInt(overs.text, 0);
    if (o < 1) {
      context.toast('Overs must be at least 1', error: true);
      return;
    }
    setState(() => saving = true);
    final data = <String, dynamic>{
      'tournamentId': tournament!['id'],
      'team1Id': team1Id,
      'team2Id': team2Id,
      'stage': stage,
      'group': group.text.trim(),
      'venue': venue.text.trim(),
      'overs': o,
      'scheduledAt': when.toUtc().toIso8601String(),
      'powerplay1From': double.tryParse(pp1From.text) ?? 0,
      'powerplay1To': double.tryParse(pp1.text) ?? 0,
      'powerplay2From': double.tryParse(pp2From.text) ?? 0,
      'powerplay2To': double.tryParse(pp2To.text) ?? 0,
      'powerplay2Duration': asInt(pp2Dur.text),
      'powerplay3From': double.tryParse(pp3From.text) ?? 0,
      'powerplay3To': double.tryParse(pp3To.text) ?? 0,
      'powerplay3Duration': asInt(pp3Dur.text),
      for (var i = 0; i < 3; i++) 'commentator${i + 1}': comm[i].text.trim(),
      'commentatorsByLang': {
        'eng': comm.map((c) => c.text.trim()).where((x) => x.isNotEmpty).toList(),
        'hin': commHin.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
        'reg': commReg.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      },
      'liveStreamer': streamer.text.trim(),
      'umpire1': umpire1.text.trim(),
      'umpire2': umpire2.text.trim(),
      'matchReferee': referee.text.trim(),
      'onlineScorer': scorer.text.trim(),
      if (!isEdit) 'status': 'scheduled',
    };
    try {
      if (isEdit) {
        await context.api.updateMatch(widget.existing!['id'].toString(), data);
      } else {
        await context.api.createMatch(data);
      }
      if (mounted) {
        context.toast(isEdit ? 'Match updated' : 'Match scheduled', success: true);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit match' : 'New match')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: saving || loading ? null : _save, child: Text(saving ? 'Saving…' : (isEdit ? 'Save changes' : 'Schedule match'))),
        ),
      ),
      body: loading
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (tournaments.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Create a tournament first — every match belongs to one.', style: TextStyle(color: AppColors.warning)),
                ),
              DropdownButtonFormField<String>(
                value: tournament?['id']?.toString(),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tournament', prefixIcon: Icon(Icons.emoji_events_outlined)),
                items: tournaments.map((t) => DropdownMenuItem(value: t['id'].toString(), child: Text(t['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
                onChanged: isEdit ? null : (v) => _selectTournament(tournaments.firstWhere((t) => t['id'].toString() == v)),
              ),
              const SectionTitle('Teams', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
              Row(children: [
                Expanded(child: _teamPicker('Team A', team1Id, (v) => setState(() => team1Id = v))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan))),
                Expanded(child: _teamPicker('Team B', team2Id, (v) => setState(() => team2Id = v))),
              ]),
              const SectionTitle('Match details', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: Cricket.matchStages.contains(stage) ? stage : null,
                    decoration: const InputDecoration(labelText: 'Stage'),
                    items: Cricket.matchStages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => stage = v ?? stage),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: group, decoration: const InputDecoration(labelText: 'Group (optional)'))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: overs,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: FormatInfo(tournament ?? const {}).isBallCentric ? 'Sets per side' : 'Overs per side'),
                onChanged: (v) {
                  final o = asInt(v);
                  if (o > 0) setState(() => _applyPpDefaults(o));
                },
              ),
              SectionTitle(
                'Powerplays',
                padding: const EdgeInsets.fromLTRB(0, 22, 0, 6),
                trailing: Text(
                  FormatInfo(tournament ?? const {}).isBallCentric ? 'ball numbers' : 'overs (0.1 = first ball)',
                  style: const TextStyle(color: AppColors.textLo, fontSize: 11),
                ),
              ),
              _ppRow('P1 (mandatory)', pp1From, pp1),
              if (tournament != null && Powerplay.usesOptional(tournament!, asInt(overs.text, 20))) ...[
                _ppRow('Batting PP window', pp2From, pp2To, dur: pp2Dur),
                _ppRow('Bowling PP window', pp3From, pp3To, dur: pp3Dur),
                const Text('Set a window + length to let the batting / bowling side take an optional powerplay during the innings.',
                    style: TextStyle(color: AppColors.textLo, fontSize: 11.5)),
              ] else ...[
                _ppRow('P2', pp2From, pp2To),
                _ppRow('P3', pp3From, pp3To),
              ],
              const SizedBox(height: 12),
              TextField(controller: venue, decoration: const InputDecoration(labelText: 'Venue', prefixIcon: Icon(Icons.place_outlined))),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickWhen,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date & time', prefixIcon: Icon(Icons.schedule)),
                  child: Text(Fmt.dateTime(when.toIso8601String())),
                ),
              ),
              const SectionTitle('Officials (optional)', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
              Row(children: [
                Expanded(child: TextField(controller: umpire1, decoration: const InputDecoration(labelText: 'Umpire 1'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: umpire2, decoration: const InputDecoration(labelText: 'Umpire 2'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: referee, decoration: const InputDecoration(labelText: 'Match referee'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: scorer, decoration: const InputDecoration(labelText: 'Scorer'))),
              ]),
              const SectionTitle('Commentary & streaming (optional)', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(controller: comm[i], decoration: InputDecoration(labelText: 'English commentator ${i + 1}')),
                ),
              TextField(controller: commHin, decoration: const InputDecoration(labelText: 'Hindi commentators (comma separated)')),
              const SizedBox(height: 10),
              TextField(controller: commReg, decoration: const InputDecoration(labelText: 'Regional commentators (comma separated)')),
              const SizedBox(height: 10),
              TextField(controller: streamer, decoration: const InputDecoration(labelText: 'Live streamer')),
            ]),
    );
  }

  Widget _ppRow(String label, TextEditingController from, TextEditingController to, {TextEditingController? dur}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
          Expanded(child: TextField(controller: from, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'From', isDense: true))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: to, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'To', isDense: true))),
          if (dur != null) ...[
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: dur, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Length', isDense: true))),
          ],
        ]),
      );

  Widget _teamPicker(String label, String? value, ValueChanged<String?> onChanged) {
    final t = teams.where((x) => x['id'].toString() == value).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: tournament == null
          ? () => context.toast('Select a tournament first')
          : () async {
              final r = await pickFromList(
                context,
                title: 'Select $label',
                items: teams,
                label: (x) => x['name'].toString(),
                subtitle: (x) => x['city']?.toString() ?? '',
                leading: (x) => TeamBadge(name: x['name'] ?? '', logoUrl: x['logoUrl'], color: x['themeColor'], size: 34),
              );
              if (r != null) onChanged(r['id'].toString());
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          t == null
              ? const CircleAvatar(radius: 24, backgroundColor: AppColors.surface, child: Icon(Icons.add, color: AppColors.textMid))
              : TeamBadge(name: t['name'] ?? '', logoUrl: t['logoUrl'], color: t['themeColor'], size: 48),
          const SizedBox(height: 8),
          Text(t?['name']?.toString() ?? label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
