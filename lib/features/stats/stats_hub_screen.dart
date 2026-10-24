import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../../widgets/match_card.dart';
import '../matches/match_detail_screen.dart';
import '../players/players_screen.dart';
import '../tools/excel_import.dart';
import '../tournaments/tournament_detail_screen.dart';
import '../tournaments/tournament_insights_view.dart';

/// Stats hub: search players (career / tournament / match-by-match),
/// tournament-wise records and leaderboards, and per-match stats.
class StatsHubScreen extends StatefulWidget {
  const StatsHubScreen({super.key});
  @override
  State<StatsHubScreen> createState() => _StatsHubScreenState();
}

class _StatsHubScreenState extends State<StatsHubScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthService>().user?.canManage ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          if (_tabs.index == 0 && canManage)
            IconButton(
              tooltip: 'Import players from Excel',
              icon: const Icon(Icons.upload_file_rounded),
              onPressed: () => ExcelImportSheet.show(context, 'players'),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabAlignment: TabAlignment.fill,
          tabs: const [Tab(text: 'Players'), Tab(text: 'Tournaments'), Tab(text: 'Matches')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: const [
        PlayersScreen(embedded: true),
        _TournamentStatsList(),
        _MatchStatsList(),
      ]),
    );
  }
}

// ───────────────────────── Tournaments ─────────────────────────

class _TournamentStatsList extends StatefulWidget {
  const _TournamentStatsList();
  @override
  State<_TournamentStatsList> createState() => _TournamentStatsListState();
}

class _TournamentStatsListState extends State<_TournamentStatsList> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> f = context.api.tournaments();
  String q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AsyncBuilder<List<Map<String, dynamic>>>(
      future: f,
      onRetry: () => setState(() => f = context.api.tournaments()),
      builder: (c, all) {
        final list = all.where((t) => '${t['name']}'.toLowerCase().contains(q.toLowerCase())).toList();
        return RefreshIndicator(
          onRefresh: () async => setState(() => f = context.api.tournaments()),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
            TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tournament'), onChanged: (v) => setState(() => q = v)),
            const SizedBox(height: 12),
            if (list.isEmpty) const SizedBox(height: 300, child: EmptyView(icon: Icons.emoji_events_outlined, title: 'No tournaments')),
            for (final t in list)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: NetImage(t['logoUrl']?.toString(), size: 40, circle: false, fit: BoxFit.contain, fallback: const Icon(Icons.emoji_events, color: AppColors.cyan)),
                  title: Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${Fmt.date(t['startDate'])} – ${Fmt.date(t['endDate'])} • ${(t['matches'] as List?)?.length ?? 0} matches'),
                  trailing: const Icon(Icons.insights_outlined),
                  onTap: () => context.push(TournamentStatsScreen(tournament: t)),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Tournament-wise stats: records & leaderboards, points table, insights.
class TournamentStatsScreen extends StatelessWidget {
  const TournamentStatsScreen({super.key, required this.tournament});
  final Map<String, dynamic> tournament;

  @override
  Widget build(BuildContext context) {
    final id = tournament['id'].toString();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${tournament['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Open tournament',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => context.push(TournamentDetailScreen(tournamentId: id)),
            ),
          ],
          bottom: const TabBar(tabAlignment: TabAlignment.fill, tabs: [Tab(text: 'Leaders & records'), Tab(text: 'Points'), Tab(text: 'Insights')]),
        ),
        body: TabBarView(children: [
          TournamentStatsTab(tournamentId: id),
          PointsTableTab(tournamentId: id),
          TournamentInsightsView(tournamentId: id),
        ]),
      ),
    );
  }
}

// ───────────────────────── Matches ─────────────────────────

class _MatchStatsList extends StatefulWidget {
  const _MatchStatsList();
  @override
  State<_MatchStatsList> createState() => _MatchStatsListState();
}

class _MatchStatsListState extends State<_MatchStatsList> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> f = context.api.matches();
  String q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AsyncBuilder<List<Map<String, dynamic>>>(
      future: f,
      onRetry: () => setState(() => f = context.api.matches()),
      builder: (c, raw) {
        final ql = q.toLowerCase();
        final list = raw.map(MatchView.new).where((m) {
          if (m.status == 'scheduled') return false; // stats exist once a ball is bowled
          if (ql.isEmpty) return true;
          return '${m.team1.name} ${m.team2.name} ${m.tournamentName} ${m.seq ?? ''}'.toLowerCase().contains(ql);
        }).toList()
          ..sort((a, b) => (Fmt.parse(b.scheduledAt) ?? DateTime(1970)).compareTo(Fmt.parse(a.scheduledAt) ?? DateTime(1970)));
        return RefreshIndicator(
          onRefresh: () async => setState(() => f = context.api.matches()),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
            TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Team, tournament or match #'), onChanged: (v) => setState(() => q = v)),
            const SizedBox(height: 12),
            if (list.isEmpty) const SizedBox(height: 300, child: EmptyView(icon: Icons.sports_cricket, title: 'No matches with stats yet')),
            for (final m in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MatchCard(match: m, onTap: () => context.push(MatchStatsScreen(matchId: m.id))),
              ),
          ]),
        );
      },
    );
  }
}

/// Per-match stats: top batters / bowlers per innings, match records, partnerships.
class MatchStatsScreen extends StatelessWidget {
  const MatchStatsScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match stats'), actions: [
        IconButton(
          tooltip: 'Match centre',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => context.push(MatchDetailScreen(matchId: matchId)),
        ),
      ]),
      body: AsyncBuilder<List<dynamic>>(
        future: Future.wait([
          context.api.snapshot(matchId),
          context.api.insights(matchId),
        ]),
        builder: (c, r) {
          final raw = r[0] as Map<String, dynamic>?;
          if (raw == null) return const EmptyView(icon: Icons.error_outline, title: 'Match not found');
          final s = Snapshot(raw);
          final ins = (r[1] as Map<String, dynamic>?) ?? const {};
          return _MatchStatsBody(snap: s, insights: ins);
        },
      ),
    );
  }
}

class _MatchStatsBody extends StatelessWidget {
  const _MatchStatsBody({required this.snap, required this.insights});
  final Snapshot snap;
  final Map<String, dynamic> insights;

  @override
  Widget build(BuildContext context) {
    final s = snap;
    final m = s.match;
    final bpo = s.bpo;
    final bats = s.battingStats.where((b) => asInt(b['balls']) > 0 || asInt(b['runs']) > 0).toList();
    final bowls = s.bowlingStats.where((b) => asDouble(b['overs']) > 0 || asInt(b['runsConceded']) > 0).toList();

    Map<String, dynamic>? best(List<Map<String, dynamic>> list, num Function(Map<String, dynamic>) score, {bool Function(Map<String, dynamic>)? where}) {
      final l = list.where(where ?? (_) => true).toList();
      if (l.isEmpty) return null;
      l.sort((a, b) => score(b).compareTo(score(a)));
      return l.first;
    }

    String name(Map<String, dynamic>? r) => asMap(r?['player'])['name']?.toString() ?? '-';
    final topScore = best(bats, (b) => asInt(b['runs']) * 1000 - asInt(b['balls']));
    final mostSixes = best(bats, (b) => asInt(b['sixes']), where: (b) => asInt(b['sixes']) > 0);
    final bestSr = best(bats, (b) => asInt(b['runs']) / asInt(b['balls']), where: (b) => asInt(b['balls']) >= 10);
    final bestFig = best(bowls, (b) => asInt(b['wickets']) * 1000 - asInt(b['runsConceded']));
    final bestEco = best(bowls, (b) => -asInt(b['runsConceded']) / Cricket.oversToBalls(asDouble(b['overs']), bpo),
        where: (b) => Cricket.oversToBalls(asDouble(b['overs']), bpo) >= 2 * bpo);
    final mostDots = best(bowls, (b) => asInt(b['dotBalls']), where: (b) => asInt(b['dotBalls']) > 0);

    final teamBoundaries = <String, (int, int)>{};
    for (final b in bats) {
      final t = b['teamId']?.toString() ?? '';
      final prev = teamBoundaries[t] ?? (0, 0);
      teamBoundaries[t] = (prev.$1 + asInt(b['fours']), prev.$2 + asInt(b['sixes']));
    }

    final parts = <Map<String, dynamic>>[
      for (final e in asMap(insights['partnerships']).entries) ...asMapList(e.value).map((p) => {...p, '_inn': e.key}),
    ]..sort((a, b) => asInt(b['runs']).compareTo(asInt(a['runs'])));

    Widget record(String label, String value, {Color? color}) => ListTile(
          dense: true,
          title: Text(label, style: const TextStyle(color: AppColors.textMid)),
          trailing: Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: color ?? AppColors.textHi)),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
      MatchCard(match: m),
      const SectionTitle('Match highlights', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
      Card(
        child: Column(children: [
          if (topScore != null) record('Top score', '${name(topScore)} ${asInt(topScore['runs'])} (${asInt(topScore['balls'])})'),
          if (bestFig != null) record('Best bowling', '${name(bestFig)} ${asInt(bestFig['wickets'])}/${asInt(bestFig['runsConceded'])}', color: AppColors.cyan),
          if (mostSixes != null) record('Most sixes', '${name(mostSixes)} ${asInt(mostSixes['sixes'])}', color: AppColors.six),
          if (bestSr != null) record('Best strike rate (10+ balls)', '${name(bestSr)} ${Cricket.strikeRate(asInt(bestSr['runs']), asInt(bestSr['balls']))}'),
          if (bestEco != null) record('Best economy (2+ overs)', '${name(bestEco)} ${Cricket.economy(asInt(bestEco['runsConceded']), asDouble(bestEco['overs']), bpo)}'),
          if (mostDots != null) record('Most dot balls', '${name(mostDots)} ${asInt(mostDots['dotBalls'])}'),
          for (final e in teamBoundaries.entries)
            if (e.key.isNotEmpty) record('${m.teamById(e.key).shortName} boundaries', '${e.value.$1} × 4   ${e.value.$2} × 6'),
          if (topScore == null && bestFig == null) const Padding(padding: EdgeInsets.all(16), child: Text('No stats yet', style: TextStyle(color: AppColors.textMid))),
        ]),
      ),
      for (final inn in s.innings.where((i) => i['isSuperOver'] != true)) ..._inningsLeaders(s, inn),
      if (parts.isNotEmpty) ...[
        const SectionTitle('Top partnerships', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
        Card(
          child: Column(children: [
            for (final p in parts.take(5))
              ListTile(
                dense: true,
                title: Text('${p['bat1']} & ${p['bat2']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Innings ${p['_inn']} • ${p['wicket']}${_ord(asInt(p['wicket']))} wicket'),
                trailing: Text('${p['runs']} (${p['balls']})', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
              ),
          ]),
        ),
      ],
    ]);
  }

  static String _ord(int n) => n == 1 ? 'st' : n == 2 ? 'nd' : n == 3 ? 'rd' : 'th';

  List<Widget> _inningsLeaders(Snapshot s, Map<String, dynamic> inn) {
    final batId = inn['battingTeamId']?.toString();
    final bowlId = batId == s.match.team1.id ? s.match.team2.id : s.match.team1.id;
    final bat = s.battingStats.where((b) => b['teamId']?.toString() == batId && (asInt(b['balls']) > 0 || asInt(b['runs']) > 0)).toList()
      ..sort((a, b) => asInt(b['runs']).compareTo(asInt(a['runs'])));
    final bowl = s.bowlingStats.where((b) => b['teamId']?.toString() == bowlId && asDouble(b['overs']) > 0).toList()
      ..sort((a, b) {
        final w = asInt(b['wickets']).compareTo(asInt(a['wickets']));
        return w != 0 ? w : asInt(a['runsConceded']).compareTo(asInt(b['runsConceded']));
      });
    final team = s.match.teamById(batId);
    return [
      SectionTitle('${team.name} — ${asInt(inn['runs'])}/${asInt(inn['wickets'])} (${Cricket.oversText(asDouble(inn['overs']))})',
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8)),
      Card(
        child: Column(children: [
          for (final b in bat.take(3))
            ListTile(
              dense: true,
              leading: const Icon(Icons.sports_cricket, size: 18, color: AppColors.textMid),
              title: Text('${asMap(b['player'])['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('SR ${Cricket.strikeRate(asInt(b['runs']), asInt(b['balls']))} • ${asInt(b['fours'])}×4 ${asInt(b['sixes'])}×6'),
              trailing: Text('${asInt(b['runs'])}${(b['outType'] ?? '').toString().isEmpty ? '*' : ''} (${asInt(b['balls'])})', style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          const Divider(),
          for (final b in bowl.take(3))
            ListTile(
              dense: true,
              leading: const Icon(Icons.sports_baseball_outlined, size: 18, color: AppColors.textMid),
              title: Text('${asMap(b['player'])['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Econ ${Cricket.economy(asInt(b['runsConceded']), asDouble(b['overs']), s.bpo)} • ${asInt(b['dotBalls'])} dots'),
              trailing: Text('${asInt(b['wickets'])}/${asInt(b['runsConceded'])} (${Cricket.oversText(asDouble(b['overs']))})',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
            ),
        ]),
      ),
    ];
  }
}
