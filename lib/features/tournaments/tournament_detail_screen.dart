import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../../widgets/match_card.dart';
import '../matches/create_match_screen.dart';
import '../matches/match_detail_screen.dart';
import '../teams/team_detail_screen.dart';
import 'tournament_admin_screen.dart';
import 'tournament_form_screen.dart';
import 'tournament_insights_view.dart';

class TournamentDetailScreen extends StatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});
  final String tournamentId;
  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  Map<String, dynamic>? t;
  List<Map<String, dynamic>> teams = [];
  List<MatchView> matches = [];
  String? error;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.api;
      final r = await Future.wait([
        api.tournament(widget.tournamentId),
        api.tournamentTeams(widget.tournamentId),
        api.matches(tournamentId: widget.tournamentId),
      ]);
      if (!mounted) return;
      setState(() {
        t = r[0] as Map<String, dynamic>;
        teams = r[1] as List<Map<String, dynamic>>;
        matches = (r[2] as List<Map<String, dynamic>>)
            .where((m) => m['tournamentId']?.toString() == widget.tournamentId || asMap(m['tournament'])['id']?.toString() == widget.tournamentId)
            .map(MatchView.new)
            .toList()
          ..sort((a, b) => (Fmt.parse(a.scheduledAt) ?? DateTime(2100)).compareTo(Fmt.parse(b.scheduledAt) ?? DateTime(2100)));
        error = null;
        _rev++;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _addTeams() async {
    final all = await context.api.teams();
    if (!mounted) return;
    final existing = teams.map((e) => e['id'].toString()).toSet();
    final selected = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (c, sc) => Column(children: [
            const Text('Add teams', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Expanded(
              child: ListView(controller: sc, children: [
                for (final tm in all)
                  CheckboxListTile(
                    value: existing.contains(tm['id'].toString()) || selected.contains(tm['id'].toString()),
                    onChanged: existing.contains(tm['id'].toString())
                        ? null
                        : (v) => setS(() => v == true ? selected.add(tm['id'].toString()) : selected.remove(tm['id'].toString())),
                    secondary: TeamBadge(name: tm['name'] ?? '', logoUrl: tm['logoUrl'], color: tm['themeColor'], size: 34),
                    title: Text(tm['name']?.toString() ?? ''),
                    subtitle: Text(tm['city']?.toString() ?? ''),
                  ),
              ]),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Add ${selected.length} team(s)')),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok == true && selected.isNotEmpty && mounted) {
      try {
        await context.api.addTeamsToTournament(widget.tournamentId, selected.toList());
        _load();
      } catch (e) {
        if (mounted) context.toast(e.toString(), error: true);
      }
    }
  }

  Future<void> _menu(String v) async {
    final api = context.api;
    switch (v) {
      case 'edit':
        final r = await context.push(TournamentFormScreen(existing: t));
        if (r != null) _load();
      case 'manage':
        await context.push(TournamentAdminScreen(tournament: t!, teams: teams));
        _load();
      case 'share':
        SharePlus.instance.share(ShareParams(text: '${t!['name']} on CreaseOne — ${teams.length} teams, ${matches.length} matches. Follow live scores in the CreaseOne app.'));
      case 'wipe':
        if (await confirmDialog(context, title: 'Delete upcoming schedule?', message: 'All scheduled (not started) matches will be removed. Live and finished matches are kept.', danger: true, ok: 'Delete')) {
          try {
            await api.wipeSchedule(widget.tournamentId);
            _load();
          } catch (e) {
            if (mounted) context.toast(e.toString(), error: true);
          }
        }
      case 'delete':
        if (await confirmDialog(context, title: 'Delete tournament?', message: 'This cannot be undone.', danger: true, ok: 'Delete')) {
          try {
            await api.deleteTournament(widget.tournamentId);
            if (mounted) Navigator.pop(context);
          } catch (e) {
            if (mounted) context.toast(e.toString(), error: true);
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthService>().user?.canManage ?? false;
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: error != null ? ErrorView(message: error!, onRetry: _load) : const LoadingView());
    }
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (c, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 200,
              actions: [
                PopupMenuButton<String>(
                  onSelected: _menu,
                  itemBuilder: (c) => [
                    const PopupMenuItem(value: 'share', child: Text('Share')),
                    if (canManage) const PopupMenuItem(value: 'manage', child: Text('Manage (officials, groups, sponsors…)')),
                    if (canManage) const PopupMenuItem(value: 'edit', child: Text('Edit tournament')),
                    if (canManage) const PopupMenuItem(value: 'wipe', child: Text('Delete upcoming schedule')),
                    if (canManage) const PopupMenuItem(value: 'delete', child: Text('Delete tournament', style: TextStyle(color: AppColors.live))),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF14306E), AppColors.bg], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  padding: const EdgeInsets.fromLTRB(16, 90, 16, 56),
                  child: Row(children: [
                    NetImage(t!['logoUrl'], size: 64, circle: false, fit: BoxFit.contain, fallback: const Icon(Icons.emoji_events, size: 40, color: AppColors.cyan)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(t!['name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('${Fmt.date(t!['startDate'])} – ${Fmt.date(t!['endDate'])}', style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
                      ]),
                    ),
                  ]),
                ),
              ),
              bottom: const TabBar(isScrollable: true, tabs: [
                Tab(text: 'Matches'),
                Tab(text: 'Points Table'),
                Tab(text: 'Stats'),
                Tab(text: 'Insights'),
                Tab(text: 'Teams'),
                Tab(text: 'Info'),
              ]),
            ),
          ],
          body: TabBarView(children: [
            _matchesTab(canManage),
            _PointsTableTab(key: ValueKey('pt$_rev'), tournamentId: widget.tournamentId),
            _StatsTab(key: ValueKey('st$_rev'), tournamentId: widget.tournamentId),
            TournamentInsightsView(key: ValueKey('ti$_rev'), tournamentId: widget.tournamentId),
            _teamsTab(canManage),
            _infoTab(),
          ]),
        ),
      ),
    );
  }

  Widget _matchesTab(bool canManage) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        if (canManage)
          FilledButton.icon(
            onPressed: () async {
              final r = await context.push<bool>(CreateMatchScreen(tournamentId: widget.tournamentId));
              if (r == true) _load();
            },
            icon: const Icon(Icons.add),
            label: const Text('Schedule a match'),
          ),
        if (matches.isEmpty) const SizedBox(height: 300, child: EmptyView(icon: Icons.calendar_month_outlined, title: 'No matches scheduled')),
        for (final m in matches)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: MatchCard(
              match: m,
              onTap: () async {
                await context.push(MatchDetailScreen(matchId: m.id));
                _load();
              },
            ),
          ),
      ]),
    );
  }

  Widget _teamsTab(bool canManage) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      if (canManage) OutlinedButton.icon(onPressed: _addTeams, icon: const Icon(Icons.group_add_outlined), label: const Text('Add teams')),
      if (teams.isEmpty) const SizedBox(height: 300, child: EmptyView(icon: Icons.shield_outlined, title: 'No teams yet')),
      for (final tm in teams)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GradientCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => context.push(TeamDetailScreen(teamId: tm['id'].toString(), tournamentId: widget.tournamentId)),
            child: Row(children: [
              TeamBadge(name: tm['name'] ?? '', logoUrl: tm['logoUrl'], color: tm['themeColor'], size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tm['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(tm['city']?.toString() ?? '', style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
                ]),
              ),
              if (canManage)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.textLo),
                  onPressed: () async {
                    if (!await confirmDialog(context, title: 'Remove ${tm['name']}?', danger: true, ok: 'Remove')) return;
                    if (!mounted) return;
                    try {
                      await context.api.removeTeamFromTournament(widget.tournamentId, tm['id'].toString());
                      _load();
                    } catch (e) {
                      if (mounted) context.toast(e.toString(), error: true);
                    }
                  },
                )
              else
                const Icon(Icons.chevron_right, color: AppColors.textLo),
            ]),
          ),
        ),
    ]);
  }

  Widget _infoTab() {
    final x = t!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      GradientCard(
        child: Column(children: [
          KeyValueRow('Format', [x['matchKind'], x['oversFormat']].where((e) => e != null).join(' • ')),
          KeyValueRow('Structure', Cricket.tournamentFormats[x['format']] ?? '${x['format'] ?? ''}'),
          KeyValueRow('Category', [x['category'], x['categorySubType']].where((e) => e != null).join(' • ')),
          KeyValueRow('Ball', [x['ballType'], x['ballColor']].where((e) => e != null).join(' • ')),
          KeyValueRow('Pitch', '${x['pitchType'] ?? ''}'),
          KeyValueRow('Location', '${x['location'] ?? x['city'] ?? ''}'),
          KeyValueRow('Organiser', [x['organiserName'], x['organiserNumber']].where((e) => e != null && '$e'.isNotEmpty).join(' • ')),
          KeyValueRow('Points (W/T/L)', '${x['pointsWin'] ?? 2} / ${x['pointsTie'] ?? 1} / ${x['pointsLoss'] ?? 0}'),
          KeyValueRow('Wide / NB runs', '${x['wideRuns'] ?? 1} / ${x['noBallRuns'] ?? 1}'),
          KeyValueRow('Impact player', x['impactPlayerRule'] == true ? 'Yes' : 'No'),
          KeyValueRow('DRS', x['drsEnabled'] == true ? '${x['drsReviewsPerInnings'] ?? 2} per innings' : 'No'),
        ]),
      ),
    ]);
  }
}

class _PointsTableTab extends StatelessWidget {
  const _PointsTableTab({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    return AsyncBuilder<Map<String, dynamic>>(
      future: context.api.pointsTable(tournamentId),
      builder: (c, data) {
        final groups = asMapList(data['groups']).where((g) => asMapList(g['teams']).isNotEmpty).toList();
        final sections = groups.isNotEmpty ? groups : [{'name': 'Standings', 'teams': data['teams']}];
        final hasRows = sections.any((s) => asMapList(s['teams']).isNotEmpty);
        if (!hasRows) return const EmptyView(icon: Icons.table_chart_outlined, title: 'No standings yet', subtitle: 'Points appear once matches are completed.');
        return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
          for (final g in sections) ...[
            SectionTitle(g['name']?.toString() ?? 'Standings', padding: const EdgeInsets.fromLTRB(4, 8, 4, 8)),
            _table(asMapList(g['teams'])),
          ],
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('P Played • W Won • L Lost • T Tied • NR No result • NRR Net run rate', style: TextStyle(color: AppColors.textLo, fontSize: 11)),
          ),
        ]);
      },
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final p = asInt(b['points']).compareTo(asInt(a['points']));
      if (p != 0) return p;
      return asDouble(b['nrr'], -99).compareTo(asDouble(a['nrr'], -99));
    });
    const h = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.textMid);
    Widget cell(String s, {bool bold = false, double w = 30, Color? color}) =>
        SizedBox(width: w, child: Text(s, textAlign: TextAlign.center, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: color)));
    return Card(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            const SizedBox(width: 22, child: Text('#', style: h)),
            const Expanded(child: Text('TEAM', style: h)),
            for (final x in ['P', 'W', 'L', 'T', 'NR']) SizedBox(width: 26, child: Text(x, textAlign: TextAlign.center, style: h)),
            const SizedBox(width: 52, child: Text('NRR', textAlign: TextAlign.center, style: h)),
            const SizedBox(width: 34, child: Text('PTS', textAlign: TextAlign.center, style: h)),
          ]),
        ),
        const Divider(),
        for (var i = 0; i < rows.length; i++)
          Container(
            color: i < 2 ? AppColors.primary.withValues(alpha: 0.06) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(color: AppColors.textMid, fontWeight: FontWeight.w800))),
              Expanded(child: Text(rows[i]['name']?.toString() ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              cell('${asInt(rows[i]['played'])}', w: 26),
              cell('${asInt(rows[i]['won'])}', w: 26),
              cell('${asInt(rows[i]['lost'])}', w: 26),
              cell('${asInt(rows[i]['tied'])}', w: 26),
              cell('${asInt(rows[i]['noResult'])}', w: 26),
              cell(rows[i]['nrrDisplay']?.toString() ?? (rows[i]['nrr'] == null ? '—' : asDouble(rows[i]['nrr']).toStringAsFixed(3)), w: 52),
              cell('${asInt(rows[i]['points'])}', bold: true, w: 34, color: AppColors.cyan),
            ]),
          ),
      ]),
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    return AsyncBuilder<Map<String, dynamic>>(
      future: context.api.tournamentStats(tournamentId),
      builder: (c, s) {
        final totals = asMap(s['totals']);
        final hs = asMap(s['highestScore']);
        final bf = asMap(s['bestFigures']);
        final ht = asMap(s['highestTeamTotal']);
        final lt = asMap(s['lowestTeamTotal']);
        final hp = asMap(s['highestPartnership']);
        final wr = asMap(s['winRatio']);
        if (totals.isEmpty && hs.isEmpty && asMapList(s['topRunScorers']).isEmpty) {
          return const EmptyView(icon: Icons.insights_outlined, title: 'No stats yet', subtitle: 'Stats build up as balls are scored.');
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          if (totals.isNotEmpty) ...[
            const SectionTitle('Tournament totals', padding: EdgeInsets.fromLTRB(0, 12, 0, 10)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.35,
              children: [
                StatTile(label: 'Matches', value: '${asInt(totals['matches'])}'),
                StatTile(label: 'Runs', value: '${asInt(totals['runs'])}'),
                StatTile(label: 'Wickets', value: '${asInt(totals['wickets'])}', color: AppColors.wicket),
                StatTile(label: 'Fours', value: '${asInt(totals['fours'])}', color: AppColors.four),
                StatTile(label: 'Sixes', value: '${asInt(totals['sixes'])}', color: AppColors.six),
                StatTile(label: '50s / 100s', value: '${asInt(totals['fifties'])}/${asInt(totals['hundreds'])}'),
                StatTile(label: 'Extras', value: '${asInt(totals['extras'])}', color: AppColors.extra),
                StatTile(label: 'Maidens', value: '${asInt(totals['maidens'])}'),
                StatTile(label: 'Dot ball %', value: '${asDouble(totals['dotBallPct']).toStringAsFixed(1)}'),
              ],
            ),
          ],
          const SectionTitle('Records', padding: EdgeInsets.fromLTRB(0, 18, 0, 10)),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                if (hs.isNotEmpty) KeyValueRow('Highest score', '${hs['player']} ${hs['runs']}${hs['notOut'] == true ? '*' : ''} (${hs['balls']}) • ${hs['team']}'),
                if (bf.isNotEmpty) KeyValueRow('Best figures', '${bf['player']} ${bf['wickets']}/${bf['runs']} (${bf['overs']}) • ${bf['team']}'),
                if (ht.isNotEmpty) KeyValueRow('Highest total', '${ht['team']} ${ht['runs']}/${ht['wickets']} (${ht['overs']})'),
                if (lt.isNotEmpty) KeyValueRow('Lowest total', '${lt['team']} ${lt['runs']}/${lt['wickets']} (${lt['overs']})'),
                if (hp.isNotEmpty) KeyValueRow('Best partnership', '${hp['runs']} (${hp['balls']}) • ${hp['bat1']} & ${hp['bat2']}'),
                if (asMap(s['most4s']).isNotEmpty) KeyValueRow('Most 4s', '${s['most4s']['player']} • ${s['most4s']['count']}'),
                if (asMap(s['most6s']).isNotEmpty) KeyValueRow('Most 6s', '${s['most6s']['player']} • ${s['most6s']['count']}'),
                if (wr.isNotEmpty)
                  KeyValueRow('Win ratio',
                      'Bat 1st ${asMap(wr['batting1st'])['wins'] ?? 0}/${asMap(wr['batting1st'])['total'] ?? 0} • Chase ${asMap(wr['batting2nd'])['wins'] ?? 0}/${asMap(wr['batting2nd'])['total'] ?? 0}'),
              ]),
            ),
          ),
          _leaders('Most runs', asMapList(s['topRunScorers']), (r) => '${r['runs']}', (r) => '${r['matches']} M • SR ${r['strikeRate'] ?? '-'} • ${r['fours']}×4 ${r['sixes']}×6'),
          _leaders('Most wickets', asMapList(s['topWicketTakers']), (r) => '${r['wickets']}', (r) => '${r['matches']} M • Econ ${r['economy'] ?? '-'} • ${r['runs']} runs'),
          _leaders('Most sixes', asMapList(s['topSixHitters']), (r) => '${r['count']}', (r) => r['team']?.toString() ?? ''),
          _leaders('Most fours', asMapList(s['topFourHitters']), (r) => '${r['count']}', (r) => r['team']?.toString() ?? ''),
          _leaders('Most catches', asMapList(s['topCatchers']), (r) => '${r['count']}', (r) => r['team']?.toString() ?? ''),
        ]);
      },
    );
  }

  Widget _leaders(String title, List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) value, String Function(Map<String, dynamic>) sub) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(title, padding: const EdgeInsets.fromLTRB(0, 18, 0, 10)),
      Card(
        child: Column(children: [
          for (var i = 0; i < rows.length && i < 10; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 15,
                backgroundColor: i == 0 ? const Color(0xFFF59E0B) : AppColors.surfaceHigh,
                child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: i == 0 ? Colors.black : AppColors.textHi, fontSize: 12)),
              ),
              title: Text('${rows[i]['player']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${rows[i]['team'] ?? ''}${sub(rows[i]).isNotEmpty && rows[i]['team'] != sub(rows[i]) ? ' • ${sub(rows[i])}' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(value(rows[i]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.cyan)),
            ),
        ]),
      ),
    ]);
  }
}
