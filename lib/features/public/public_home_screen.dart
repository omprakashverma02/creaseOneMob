import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/live_socket.dart';
import '../../widgets/common.dart';
import '../matches/commentary_view.dart';
import '../matches/insights_view.dart';
import '../matches/live_widgets.dart';
import '../matches/scorecard_view.dart';

/// Public, read-only viewer (web Landing / public scorecard pages). Uses only
/// endpoints the backend serves without login.
class PublicHomeScreen extends StatefulWidget {
  const PublicHomeScreen({super.key});
  @override
  State<PublicHomeScreen> createState() => _PublicHomeScreenState();
}

class _PublicHomeScreenState extends State<PublicHomeScreen> {
  late Future<List<Map<String, dynamic>>> _future = context.api.publicTournaments();
  void _reload() => setState(() => _future = context.api.publicTournaments());

  Future<void> _openBySeq() async {
    final v = await promptText(context, title: 'Open match', hint: 'Match # e.g. 128', keyboard: TextInputType.number);
    final seq = int.tryParse(v ?? '');
    if (seq == null || !mounted) return;
    context.push(PublicMatchScreen(matchSeq: seq));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [Image.asset('assets/images/logo.png', height: 32), const SizedBox(width: 10), const Text('Live scores')]),
        actions: [
          IconButton(onPressed: _openBySeq, icon: const Icon(Icons.search_rounded)),
          TextButton(onPressed: () => context.auth.leaveGuest(), child: const Text('Sign in')),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const LoadingView();
          if (s.hasError) return ErrorView(message: s.error.toString(), onRetry: _reload);
          final ts = s.data!;
          final allMatches = [
            for (final t in ts)
              for (final m in asMapList(t['matches'])) {...m, '_tournament': t['name']}
          ];
          final live = allMatches.where((m) => m['status'] == 'live').toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              if (live.isNotEmpty) ...[
                const SectionTitle('Live now', padding: EdgeInsets.fromLTRB(0, 8, 0, 8)),
                for (final m in live) Padding(padding: const EdgeInsets.only(bottom: 10), child: PublicMatchTile(m: m)),
              ],
              const SectionTitle('Tournaments', padding: EdgeInsets.fromLTRB(0, 12, 0, 8)),
              if (ts.isEmpty) const SizedBox(height: 300, child: EmptyView(icon: Icons.emoji_events_outlined, title: 'No public tournaments')),
              for (final t in ts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GradientCard(
                    onTap: () => context.push(PublicTournamentScreen(t: t)),
                    child: Row(children: [
                      NetImage(t['logoUrl'], size: 48, circle: false, fit: BoxFit.contain, fallback: const Icon(Icons.emoji_events, color: AppColors.cyan)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                          Text('${Fmt.date(t['startDate'])} – ${Fmt.date(t['endDate'])} • ${asMapList(t['matches']).length} matches',
                              style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textLo),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class PublicMatchTile extends StatelessWidget {
  const PublicMatchTile({super.key, required this.m});
  final Map<String, dynamic> m;
  @override
  Widget build(BuildContext context) {
    final inns = asMapList(m['innings']);
    String score(String? short) {
      final i = inns.where((x) => x['teamShortName'] == short).toList();
      if (i.isEmpty) return '';
      return i.map((x) => '${x['runs']}/${x['wickets']} (${Cricket.oversText(asDouble(x['overs']))})').join(' & ');
    }

    Widget row(Map<String, dynamic> t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            TeamBadge(name: '${t['name']}', logoUrl: t['logoUrl'], size: 26),
            const SizedBox(width: 8),
            Expanded(child: Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(score(t['shortName']?.toString()), style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
        );
    final status = m['status']?.toString() ?? 'scheduled';
    final result = asMap(m['result'])['summaryText']?.toString();
    return GradientCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push(PublicMatchScreen(matchId: m['matchId']?.toString())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(['Match #${m['matchSeq'] ?? '-'}', m['stage'], m['_tournament']].where((e) => e != null && '$e'.isNotEmpty).join(' • '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
          ),
          if (status == 'live') const LiveDot() else if (status == 'completed') const Pill('RESULT', color: AppColors.success) else const Pill('UPCOMING', color: AppColors.cyan),
        ]),
        const SizedBox(height: 6),
        row(asMap(m['team1'])),
        row(asMap(m['team2'])),
        if (result != null && result.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(result, style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ] else if (status == 'scheduled')
          Text(Fmt.dateTime(m['scheduledAt']), style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
      ]),
    );
  }
}

class PublicTournamentScreen extends StatelessWidget {
  const PublicTournamentScreen({super.key, required this.t});
  final Map<String, dynamic> t;
  @override
  Widget build(BuildContext context) {
    final id = (t['tournamentId'] ?? t['id']).toString();
    final matches = asMapList(t['matches']);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${t['name']}'),
          bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Matches'), Tab(text: 'Points Table'), Tab(text: 'Stats')]),
        ),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(16), children: [
            if (matches.isEmpty) const SizedBox(height: 300, child: EmptyView(icon: Icons.calendar_month_outlined, title: 'No matches')),
            for (final m in matches) Padding(padding: const EdgeInsets.only(bottom: 10), child: PublicMatchTile(m: {...m, '_tournament': ''})),
          ]),
          AsyncBuilder<Map<String, dynamic>>(
            future: context.api.pointsTable(id),
            builder: (c, d) {
              final rows = asMapList(d['teams'])..sort((a, b) => asInt(b['points']).compareTo(asInt(a['points'])));
              if (rows.isEmpty) return const EmptyView(icon: Icons.table_chart_outlined, title: 'No standings yet');
              return ListView(padding: const EdgeInsets.all(12), children: [
                Card(
                  child: Column(children: [
                    for (var i = 0; i < rows.length; i++)
                      ListTile(
                        leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                        title: Text('${rows[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('P ${asInt(rows[i]['played'])} • W ${asInt(rows[i]['won'])} • L ${asInt(rows[i]['lost'])} • NRR ${rows[i]['nrrDisplay'] ?? '—'}'),
                        trailing: Text('${asInt(rows[i]['points'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.cyan)),
                      ),
                  ]),
                ),
              ]);
            },
          ),
          AsyncBuilder<Map<String, dynamic>>(
            future: context.api.tournamentStats(id),
            builder: (c, s) {
              final bat = asMapList(s['topRunScorers']);
              final bowl = asMapList(s['topWicketTakers']);
              if (bat.isEmpty && bowl.isEmpty) return const EmptyView(icon: Icons.insights_outlined, title: 'No stats yet');
              Widget list(String title, List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) v) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SectionTitle(title, padding: const EdgeInsets.fromLTRB(4, 12, 4, 8)),
                    Card(
                      child: Column(children: [
                        for (final r in rows.take(10))
                          ListTile(dense: true, title: Text('${r['player']}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${r['team'] ?? ''}'), trailing: Text(v(r), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan))),
                      ]),
                    ),
                  ]);
              return ListView(padding: const EdgeInsets.all(12), children: [
                list('Most runs', bat, (r) => '${r['runs']}'),
                list('Most wickets', bowl, (r) => '${r['wickets']}'),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// Converts GET /matches/complete-public into the snapshot shape the scorecard widgets use.
Map<String, dynamic> snapshotFromPublic(Map<String, dynamic> d) {
  final info = asMap(d['matchInfo']);
  final batting = asMapList(d['battingStats']).map((b) => {
        ...b,
        'player': {'id': b['playerId'], 'name': b['playerName'], 'shortName': b['playerShortName'], 'battingStyle': b['playerBattingStyle']},
      }).toList();
  int scoreAt(int inn, int idx, List<Map<String, dynamic>> balls) {
    var r = 0;
    for (var i = 0; i <= idx && i < balls.length; i++) {
      final b = balls[i];
      if (asInt(b['innings']) != inn) continue;
      r += asInt(b['batRuns']) + asInt(b['extraRuns']) + asInt(b['overthrowRuns']);
    }
    return r;
  }

  final balls = asMapList(d['ballByBall']);
  final fow = <Map<String, dynamic>>[];
  final wkts = <int, int>{};
  for (var i = 0; i < balls.length; i++) {
    final b = balls[i];
    if (b['wicket'] != true) continue;
    final wt = (b['wicketType'] ?? '').toString().toLowerCase();
    if (wt.contains('retired hurt') || wt.contains('absent hurt')) continue;
    final inn = asInt(b['innings']);
    wkts[inn] = (wkts[inn] ?? 0) + 1;
    final pid = b['dismissedPlayerId']?.toString();
    final st = batting.where((x) => x['playerId']?.toString() == pid).firstOrNull ?? {};
    final bowler = asMap(b['bowler'])['name'] ?? '';
    final fielder = asMap(b['fielder'])['name'];
    fow.add({
      'innings': inn,
      'playerId': pid,
      'playerName': asMap(b['dismissedPlayer'])['name'] ?? '-',
      'scoreAtWicket': '${scoreAt(inn, i, balls)}/${wkts[inn]}',
      'overAtWicket': '${asInt(b['overNumber']) - 1}.${asInt(b['ballNumber'])}',
      'runs': st['runs'] ?? 0,
      'balls': st['balls'] ?? 0,
      'dismissalStatus': wt.contains('run out')
          ? 'run out${fielder != null ? ' ($fielder)' : ''}'
          : wt.contains('caught')
              ? 'c ${fielder ?? ''} b $bowler'
              : wt.contains('stump')
                  ? 'st ${fielder ?? ''} b $bowler'
                  : wt.contains('lbw')
                      ? 'lbw b $bowler'
                      : 'b $bowler',
    });
  }
  final innings = asMapList(d['innings']);
  final last = innings.isEmpty ? null : innings.last;
  final lastNo = asInt(last?['number']);
  final overBalls = balls.where((b) => asInt(b['innings']) == lastNo).toList();
  final lastOver = overBalls.isEmpty ? <Map<String, dynamic>>[] : overBalls.where((b) => b['overNumber'] == overBalls.last['overNumber']).toList();
  return {
    'match': {...info, 'team1Id': asMap(info['team1'])['id'], 'team2Id': asMap(info['team2'])['id'], 'playingXI': const []},
    'innings': innings,
    'battingStats': batting,
    'bowlingStats': d['bowlingStats'],
    'fallOfWickets': fow,
    'lastBall': lastOver,
    'liveCrease': const {},
    'extrasByInnings': const {},
  };
}

class PublicMatchScreen extends StatefulWidget {
  const PublicMatchScreen({super.key, this.matchId, this.matchSeq});
  final String? matchId;
  final int? matchSeq;
  @override
  State<PublicMatchScreen> createState() => _PublicMatchScreenState();
}

class _PublicMatchScreenState extends State<PublicMatchScreen> {
  Snapshot? snap;
  String? error;
  LiveMatchSocket? socket;
  StreamSubscription? sub;
  int rev = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    sub?.cancel();
    socket?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.api.completePublic(matchId: widget.matchId, matchSeq: widget.matchSeq);
      if (!mounted) return;
      setState(() {
        snap = Snapshot(snapshotFromPublic(d));
        rev++;
        error = null;
      });
      if (snap!.match.isLive && socket == null) {
        socket = LiveMatchSocket(matchId: snap!.match.id)..connect();
        sub = socket!.snapshots.listen((data) {
          if (mounted) {
            setState(() {
              snap = Snapshot(data);
              rev++;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (snap == null) return Scaffold(appBar: AppBar(), body: error != null ? ErrorView(message: error!, onRetry: _load) : const LoadingView());
    final s = snap!;
    final m = s.match;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${m.team1.shortName} vs ${m.team2.shortName}'),
          bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Live'), Tab(text: 'Scorecard'), Tab(text: 'Commentary'), Tab(text: 'Insights')]),
        ),
        body: TabBarView(children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (m.isCompleted && m.resultText.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(18)),
                  child: Text(m.resultText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
                ),
              if (s.hasStarted) LiveScoreHeader(snap: s) else const EmptyView(icon: Icons.timer_outlined, title: 'Match yet to begin'),
              if (s.lastBall.isNotEmpty) ...[const SizedBox(height: 10), ThisOverStrip(snap: s)],
            ]),
          ),
          ScorecardView(snap: s),
          CommentaryView(matchId: m.id, teamNames: const {}, bpo: s.bpo, refreshKey: rev),
          InsightsView(matchId: m.id, refreshKey: rev),
        ]),
      ),
    );
  }
}
