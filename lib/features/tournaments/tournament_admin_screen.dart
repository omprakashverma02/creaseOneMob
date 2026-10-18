import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cricket.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/image_upload_field.dart';
import '../tools/excel_import.dart';

/// Tournament administration hub (web TournamentHubSections / SetupPanel admin pieces):
/// structure, officials, scorer admins, scoring access, live streamers, sponsors,
/// NRR analyzer, Excel imports and team invite links.
class TournamentAdminScreen extends StatelessWidget {
  const TournamentAdminScreen({super.key, required this.tournament, required this.teams});
  final Map<String, dynamic> tournament;
  final List<Map<String, dynamic>> teams;

  String get id => tournament['id'].toString();

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String sub, Widget page) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Icon(i, color: AppColors.cyan),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(page),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Manage tournament')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        tile(Icons.account_tree_outlined, 'Groups & stages', 'Pools, rounds and knockout stages', _StructureScreen(tournamentId: id, teams: teams)),
        tile(Icons.sports, 'Officials', 'Umpires, referees, scorers, commentators', _OfficialsScreen(tournamentId: id)),
        tile(Icons.admin_panel_settings_outlined, 'Scorer admins', 'People who can score this tournament', _ScorerAdminsScreen(tournamentId: id)),
        tile(Icons.key_outlined, 'Scoring access', 'Grant scoring by email or phone', _AccessScreen(tournamentId: id)),
        tile(Icons.videocam_outlined, 'Live streamers', 'Streamers covering this tournament', _StreamersScreen(tournamentId: id)),
        tile(Icons.campaign_outlined, 'Sponsors', 'Title, associate and partner sponsors', _SponsorsScreen(tournamentId: id)),
        tile(Icons.calculate_outlined, 'NRR analyzer', 'What you need to beat a net run rate', NrrAnalyzerScreen(tournament: tournament)),
        tile(Icons.link_rounded, 'Team invite links', 'Players join a squad from the app', _InvitesScreen(tournament: tournament, teams: teams)),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.table_view_outlined, color: AppColors.cyan),
              title: const Text('Import teams (Excel)', style: TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => ExcelImportSheet.show(context, 'teams', tournamentId: id),
            ),
            const Divider(indent: 56),
            ListTile(
              leading: const Icon(Icons.table_view_outlined, color: AppColors.cyan),
              title: const Text('Import matches / schedule (Excel)', style: TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => ExcelImportSheet.show(context, 'matches', tournamentId: id),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Structure ─────────────────────────

class _StructureScreen extends StatefulWidget {
  const _StructureScreen({required this.tournamentId, required this.teams});
  final String tournamentId;
  final List<Map<String, dynamic>> teams;
  @override
  State<_StructureScreen> createState() => _StructureScreenState();
}

class _StructureScreenState extends State<_StructureScreen> {
  List<Map<String, dynamic>> groups = [];
  List<String> stages = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    context.api.tournamentStructure(widget.tournamentId).then((d) {
      if (!mounted) return;
      final details = asMapList(d['groupDetails']);
      setState(() {
        groups = details.isNotEmpty
            ? details.map((g) => {'name': g['name'], 'roundName': g['roundName'], 'teamIds': List<String>.from((g['teamIds'] as List? ?? []).map((e) => e.toString()))}).toList()
            : ((d['groups'] as List?) ?? []).map((n) => <String, dynamic>{'name': n.toString(), 'teamIds': <String>[]}).toList();
        stages = ((d['stages'] as List?) ?? []).map((e) => e.toString()).toList();
        loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => loading = false);
    });
  }

  Future<void> _save() async {
    try {
      await context.api.saveTournamentStructure(widget.tournamentId, groups: groups, stages: stages);
      if (mounted) {
        context.toast('Structure saved', success: true);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  Future<void> _editGroup([int? index]) async {
    final g = index == null ? <String, dynamic>{'name': 'Group ${String.fromCharCode(65 + groups.length)}', 'teamIds': <String>[]} : Map<String, dynamic>.from(groups[index]);
    final name = TextEditingController(text: g['name']);
    final round = TextEditingController(text: g['roundName']?.toString() ?? '');
    final sel = Set<String>.from(g['teamIds'] as List);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Group name')),
            const SizedBox(height: 10),
            TextField(controller: round, decoration: const InputDecoration(labelText: 'Round (optional, e.g. League)')),
            const SectionTitle('Teams', padding: EdgeInsets.fromLTRB(0, 16, 0, 6)),
            for (final t in widget.teams)
              CheckboxListTile(
                value: sel.contains(t['id'].toString()),
                title: Text('${t['name']}'),
                onChanged: (v) => setS(() => v == true ? sel.add(t['id'].toString()) : sel.remove(t['id'].toString())),
              ),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Done')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      final updated = {'name': name.text.trim(), 'roundName': round.text.trim().isEmpty ? null : round.text.trim(), 'teamIds': sel.toList()};
      if (index == null) {
        groups.add(updated);
      } else {
        groups[index] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups & stages'), actions: [TextButton(onPressed: _save, child: const Text('Save'))]),
      body: loading
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.all(16), children: [
              SectionTitle('Groups', padding: EdgeInsets.zero, trailing: TextButton.icon(onPressed: () => _editGroup(), icon: const Icon(Icons.add), label: const Text('Group'))),
              for (var i = 0; i < groups.length; i++)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text('${groups[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(widget.teams.where((t) => (groups[i]['teamIds'] as List).contains(t['id'].toString())).map((t) => t['name']).join(', ')),
                    onTap: () => _editGroup(i),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => groups.removeAt(i))),
                  ),
                ),
              const SizedBox(height: 20),
              SectionTitle('Stages', padding: EdgeInsets.zero, trailing: TextButton.icon(
                onPressed: () async {
                  final v = await promptText(context, title: 'Stage name', hint: 'e.g. Semi Final');
                  if (v != null && v.isNotEmpty) setState(() => stages.add(v));
                },
                icon: const Icon(Icons.add),
                label: const Text('Stage'),
              )),
              Wrap(spacing: 8, children: [
                for (final st in Cricket.matchStages.where((x) => !stages.contains(x)))
                  ActionChip(label: Text('+ $st'), onPressed: () => setState(() => stages.add(st))),
              ]),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (a, b) => setState(() {
                  final x = stages.removeAt(a);
                  stages.insert(b > a ? b - 1 : b, x);
                }),
                children: [
                  for (var i = 0; i < stages.length; i++)
                    ListTile(
                      key: ValueKey('st$i${stages[i]}'),
                      leading: const Icon(Icons.drag_indicator),
                      title: Text(stages[i]),
                      trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => stages.removeAt(i))),
                    ),
                ],
              ),
            ]),
    );
  }
}

// ───────────────────────── Generic people list ─────────────────────────

class _PeopleList extends StatefulWidget {
  const _PeopleList({required this.title, required this.load, required this.add, required this.remove, required this.subtitle, this.header});
  final String title;
  final Future<List<Map<String, dynamic>>> Function() load;
  final Future<void> Function(BuildContext) add;
  final Future<void> Function(Map<String, dynamic>) remove;
  final String Function(Map<String, dynamic>) subtitle;
  final Widget Function(List<Map<String, dynamic>>)? header;
  @override
  State<_PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends State<_PeopleList> {
  late Future<List<Map<String, dynamic>>> f = widget.load();
  void reload() => setState(() => f = widget.load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            await widget.add(context);
            reload();
          } catch (e) {
            if (context.mounted) context.toast(e.toString(), error: true);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: AsyncBuilder<List<Map<String, dynamic>>>(
        future: f,
        onRetry: reload,
        builder: (c, list) => ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
          if (widget.header != null) widget.header!(list),
          if (list.isEmpty) const SizedBox(height: 300, child: EmptyView(icon: Icons.person_outline, title: 'Nobody added yet')),
          for (final p in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: PlayerAvatar(name: '${p['name'] ?? p['email'] ?? p['contactNumber'] ?? '?'}', imageUrl: p['photoUrl']?.toString(), size: 38),
                title: Text('${p['name'] ?? p['email'] ?? p['contactNumber'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(widget.subtitle(p)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.live),
                  onPressed: () async {
                    if (!await confirmDialog(context, title: 'Remove?', danger: true, ok: 'Remove')) return;
                    try {
                      await widget.remove(p);
                      reload();
                    } catch (e) {
                      if (context.mounted) context.toast(e.toString(), error: true);
                    }
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

Future<Map<String, String>?> _form(BuildContext context, String title, List<(String, String, TextInputType?)> fields, {List<String>? roles, String? photoFolder}) {
  final ctrls = {for (final f in fields) f.$1: TextEditingController()};
  String? role = roles?.first;
  String? photo;
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (photoFolder != null) Center(child: ImageUploadField(label: 'Photo', url: photo, folder: photoFolder, size: 72, onChanged: (u) => setS(() => photo = u))),
            if (roles != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 10),
                child: DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setS(() => role = v),
                ),
              ),
            for (final f in fields)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: ctrls[f.$1], keyboardType: f.$3, decoration: InputDecoration(labelText: f.$2))),
            FilledButton(
              onPressed: () => Navigator.pop(c, {
                for (final e in ctrls.entries) e.key: e.value.text.trim(),
                if (role != null) 'role': role!,
                if (photo != null) 'photoUrl': photo!,
              }),
              child: const Text('Add'),
            ),
          ]),
        ),
      ),
    ),
  );
}

const _officialRoles = [
  'On-field Umpire', 'Third Umpire', 'Fourth Umpire', 'Reserve Umpire', 'Match Referee', 'Online Scorer', 'Manual Scorer',
  'English Commentator', 'Hindi Commentator', 'Regional Commentator', 'Live Streamer',
];

String _roleGroup(String role) {
  if (role.contains('Commentator')) return 'Commentators';
  if (role == 'Live Streamer') return 'Live Streamer';
  return 'Officials';
}

class _OfficialsScreen extends StatelessWidget {
  const _OfficialsScreen({required this.tournamentId});
  final String tournamentId;
  @override
  Widget build(BuildContext context) => _PeopleList(
        title: 'Officials',
        load: () => context.api.tournamentOfficials(tournamentId),
        subtitle: (p) => [p['role'], p['mobile']].where((e) => e != null && '$e'.isNotEmpty).join(' • '),
        remove: (p) => context.api.removeTournamentOfficial(tournamentId, p['id'].toString()),
        add: (ctx) async {
          final r = await _form(ctx, 'Add official', [('name', 'Name', null), ('mobile', 'Mobile', TextInputType.phone)], roles: _officialRoles, photoFolder: 'officials');
          if (r == null || (r['name'] ?? '').isEmpty || !ctx.mounted) return;
          await ctx.api.addTournamentOfficial(tournamentId, {...r, 'roleGroup': _roleGroup(r['role'] ?? '')});
        },
      );
}

class _ScorerAdminsScreen extends StatelessWidget {
  const _ScorerAdminsScreen({required this.tournamentId});
  final String tournamentId;
  @override
  Widget build(BuildContext context) => _PeopleList(
        title: 'Scorer admins',
        load: () => context.api.scorerAdmins(tournamentId),
        subtitle: (p) => [p['mobile'], p['email']].where((e) => e != null && '$e'.isNotEmpty).join(' • '),
        remove: (p) => context.api.removeScorerAdmin(tournamentId, p['id'].toString()),
        add: (ctx) async {
          final r = await _form(ctx, 'Add scorer admin', [('name', 'Name', null), ('mobile', 'Mobile', TextInputType.phone), ('email', 'Email', TextInputType.emailAddress)]);
          if (r == null || (r['name'] ?? '').isEmpty || !ctx.mounted) return;
          await ctx.api.addScorerAdmin(tournamentId, {...r, 'countryCode': '+91'});
        },
      );
}

class _AccessScreen extends StatelessWidget {
  const _AccessScreen({required this.tournamentId});
  final String tournamentId;
  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> meta = {};
    return _PeopleList(
      title: 'Scoring access',
      load: () async {
        meta = await context.api.scoringAccess(tournamentId);
        return asMapList(meta['access']);
      },
      header: (_) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text('${asInt(meta['count'])} of ${asInt(meta['max'], 10)} used — these CreaseOne users can score every match of this tournament.',
            style: const TextStyle(color: AppColors.textMid)),
      ),
      subtitle: (p) => 'Granted ${Fmt.date(p['createdAt'])}',
      remove: (p) => context.api.removeScoringAccess(tournamentId, p['id'].toString()),
      add: (ctx) async {
        final v = await promptText(ctx, title: 'Email or mobile of the scorer', keyboard: TextInputType.emailAddress);
        if (v == null || v.isEmpty || !ctx.mounted) return;
        await ctx.api.addScoringAccess(tournamentId, v.contains('@') ? {'email': v} : {'phone': v});
      },
    );
  }
}

class _StreamersScreen extends StatelessWidget {
  const _StreamersScreen({required this.tournamentId});
  final String tournamentId;
  @override
  Widget build(BuildContext context) => _PeopleList(
        title: 'Live streamers',
        load: () async => asMapList((await context.api.liveStreamers(tournamentId))['liveStreamers']),
        subtitle: (p) => [p['contactNumber'], p['email'], if (p['planActive'] == true) 'Plan active'].where((e) => e != null && '$e'.isNotEmpty).join(' • '),
        remove: (p) => context.api.removeLiveStreamer(tournamentId, p['id'].toString()),
        add: (ctx) async {
          final r = await _form(ctx, 'Add live streamer', [('name', 'Name', null), ('phone', 'Mobile', TextInputType.phone), ('email', 'Email', TextInputType.emailAddress)]);
          if (r == null || (r['phone'] ?? '').isEmpty || !ctx.mounted) return;
          await ctx.api.addLiveStreamer(tournamentId, r);
        },
      );
}

class _SponsorsScreen extends StatelessWidget {
  const _SponsorsScreen({required this.tournamentId});
  final String tournamentId;
  static const types = ['Title Sponsor', 'Powered By', 'Associate Sponsor', 'Official Partner', 'Media Partner', 'Other'];

  @override
  Widget build(BuildContext context) => _PeopleList(
        title: 'Sponsors',
        load: () => context.api.tournamentSponsors(tournamentId),
        subtitle: (p) => [p['type'], p['website']].where((e) => e != null && '$e'.isNotEmpty).join(' • '),
        remove: (p) => context.api.unlinkSponsor(tournamentId, p['id'].toString()),
        add: (ctx) async {
          final r = await _form(ctx, 'Add sponsor', [('name', 'Sponsor name', null), ('website', 'Website', TextInputType.url)], roles: types, photoFolder: 'sponsors');
          if (r == null || (r['name'] ?? '').isEmpty || !ctx.mounted) return;
          final created = await ctx.api.createSponsor({'name': r['name'], 'website': r['website'], 'logoUrl': r['photoUrl']});
          if (created['id'] != null && ctx.mounted) await ctx.api.linkSponsor(tournamentId, created['id'].toString(), type: r['role']);
        },
      );
}

// ───────────────────────── Team invites ─────────────────────────

class _InvitesScreen extends StatelessWidget {
  const _InvitesScreen({required this.tournament, required this.teams});
  final Map<String, dynamic> tournament;
  final List<Map<String, dynamic>> teams;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team invite links')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Share a code with players. They open Profile → "Join a team" in the CreaseOne app and paste it to join the squad.',
            style: TextStyle(color: AppColors.textMid)),
        const SizedBox(height: 12),
        for (final t in teams)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: TeamBadge(name: '${t['name']}', logoUrl: t['logoUrl'], color: t['themeColor'], size: 36),
              title: Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(inviteCode(tournament['id'].toString(), t['id'].toString()), style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.share_outlined),
              onTap: () => SharePlus.instance.share(ShareParams(
                text: 'Join ${t['name']} in ${tournament['name']} on CreaseOne.\nOpen the app → Profile → Join a team and paste this code:\n${inviteCode(tournament['id'].toString(), t['id'].toString())}',
              )),
            ),
          ),
      ]),
    );
  }
}

String inviteCode(String tournamentId, String teamId) => 'CO1-$tournamentId:$teamId';

(String, String)? parseInviteCode(String code) {
  final m = RegExp(r'CO1-([0-9a-fA-F-]{8,}):([0-9a-fA-F-]{8,})').firstMatch(code.trim());
  return m == null ? null : (m.group(1)!, m.group(2)!);
}

// ───────────────────────── NRR analyzer ─────────────────────────

class NrrAnalyzerScreen extends StatefulWidget {
  const NrrAnalyzerScreen({super.key, required this.tournament});
  final Map<String, dynamic> tournament;
  @override
  State<NrrAnalyzerScreen> createState() => _NrrAnalyzerScreenState();
}

class _NrrAnalyzerScreenState extends State<NrrAnalyzerScreen> {
  late final Future<Map<String, dynamic>> f = context.api.pointsTable(widget.tournament['id'].toString());
  Map<String, dynamic>? team;
  bool batFirst = true;
  final score = TextEditingController();
  final overs = TextEditingController(text: '20');
  final target = TextEditingController();
  String? result;

  void _calc() {
    final t = team;
    if (t == null) return;
    final fmt = FormatInfo(widget.tournament);
    final bpo = fmt.bpo;
    final tn = double.tryParse(target.text) ?? 0;
    final o = double.tryParse(overs.text) ?? 20;
    final s = int.tryParse(score.text) ?? 0;
    final rs = asInt(t['runsScored']), bf = asInt(t['ballsFaced']), rc = asInt(t['runsConceded']), bb = asInt(t['ballsBowled']);
    setState(() {
      result = batFirst
          ? Nrr.batFirst(rs: rs, bf: bf, rc: rc, bb: bb, yourScore: s, matchOvers: o, targetNrr: tn, bpo: bpo, ballCentric: fmt.isBallCentric)
          : Nrr.chase(rs: rs, bf: bf, rc: rc, bb: bb, opponentScore: s, matchOvers: o, targetNrr: tn, bpo: bpo, ballCentric: fmt.isBallCentric);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NRR analyzer')),
      body: AsyncBuilder<Map<String, dynamic>>(
        future: f,
        builder: (c, d) {
          final rows = asMapList(d['teams']);
          return ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<String>(
              value: team?['teamId']?.toString(),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Your team'),
              items: rows.map((r) => DropdownMenuItem(value: r['teamId'].toString(), child: Text('${r['name']} • NRR ${r['nrrDisplay'] ?? '—'}'))).toList(),
              onChanged: (v) => setState(() => team = rows.firstWhere((r) => r['teamId'].toString() == v)),
            ),
            if (team != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'So far: ${team!['runsScored'] ?? 0} runs in ${Cricket.ballsToOvers(asInt(team!['ballsFaced']), FormatInfo(widget.tournament).bpo)} ov • conceded ${team!['runsConceded'] ?? 0} in ${Cricket.ballsToOvers(asInt(team!['ballsBowled']), FormatInfo(widget.tournament).bpo)} ov',
                  style: const TextStyle(color: AppColors.textMid, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Batting first')), ButtonSegment(value: false, label: Text('Chasing'))],
              selected: {batFirst},
              onSelectionChanged: (v) => setState(() => batFirst = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: score, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: batFirst ? 'Our expected score' : 'Opponent score')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: overs, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Match overs'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Target NRR (e.g. 0.450)'))),
            ]),
            const SizedBox(height: 14),
            FilledButton(onPressed: team == null ? null : _calc, child: const Text('Calculate')),
            if (result != null) ...[
              const SizedBox(height: 16),
              GradientCard(child: Text(result!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            ],
          ]);
        },
      ),
    );
  }
}
