import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../services/live_socket.dart';
import '../../widgets/common.dart';
import '../scoring/match_setup_screen.dart';
import '../scoring/scoring_screen.dart';
import 'commentary_view.dart';
import 'create_match_screen.dart';
import 'insights_view.dart';
import 'live_widgets.dart';
import 'scorecard_view.dart';

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;
  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  Snapshot? snap;
  Map<String, dynamic>? summary;
  String? error;
  LiveMatchSocket? _socket;
  StreamSubscription? _sub;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await context.api.snapshot(widget.matchId);
      if (!mounted) return;
      if (s == null) {
        setState(() => error = 'Match not found');
        return;
      }
      setState(() {
        snap = Snapshot(s);
        error = null;
        _rev++;
      });
      if (snap!.match.isCompleted) {
        context.api.summary(widget.matchId).then((v) {
          if (mounted) setState(() => summary = v);
        });
      }
      if (snap!.match.isLive && _socket == null) {
        _socket = LiveMatchSocket(matchId: widget.matchId, token: context.api.client.token)..connect();
        _sub = _socket!.snapshots.listen((data) {
          if (!mounted) return;
          setState(() {
            snap = Snapshot(data);
            _rev++;
          });
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _openScoring() async {
    final s = snap!;
    final Widget page = s.hasStarted ? ScoringScreen(matchId: widget.matchId) : MatchSetupScreen(matchId: widget.matchId);
    await context.push(page);
    _load();
  }

  void _share() {
    final s = snap!;
    final m = s.match;
    final b = StringBuffer('🏏 ${m.team1.name} vs ${m.team2.name}');
    if (m.tournamentName.isNotEmpty) b.write(' — ${m.tournamentName}');
    b.writeln();
    for (final i in s.innings) {
      b.writeln('${m.teamById(i['battingTeamId']?.toString()).shortName} ${asInt(i['runs'])}/${asInt(i['wickets'])} (${Cricket.oversText(asDouble(i['overs']))} ov)');
    }
    if (m.isCompleted && m.resultText.isNotEmpty) b.writeln(m.resultText);
    if (m.seq != null) b.writeln('Match #${m.seq} • Live on CreaseOne');
    SharePlus.instance.share(ShareParams(text: b.toString()));
  }

  Future<void> _menu(String v) async {
    final api = context.api;
    switch (v) {
      case 'edit':
        final r = await context.push<bool>(CreateMatchScreen(existing: snap!.matchRaw));
        if (r == true) _load();
      case 'share':
        _share();
      case 'delete':
        if (!await confirmDialog(context, title: 'Delete match?', message: 'All balls and stats for this match will be removed.', danger: true, ok: 'Delete')) return;
        try {
          await api.deleteMatch(widget.matchId);
          if (mounted) Navigator.pop(context);
        } catch (e) {
          if (mounted) context.toast(e.toString(), error: true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    if (snap == null) return Scaffold(appBar: AppBar(), body: error != null ? ErrorView(message: error!, onRetry: _load) : const LoadingView());
    final s = snap!;
    final m = s.match;
    final canScore = (user?.canManage ?? false) && !m.isCompleted && !m.scoringLocked;
    return DefaultTabController(
      length: 5,
      initialIndex: s.hasStarted ? 0 : 4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m.team1.shortName} vs ${m.team2.shortName}'),
            Text([if (m.seq != null) 'Match #${m.seq}', if (m.tournamentName.isNotEmpty) m.tournamentName].join(' • '),
                style: const TextStyle(fontSize: 12, color: AppColors.textMid, fontWeight: FontWeight.w600)),
          ]),
          actions: [
            IconButton(onPressed: _share, icon: const Icon(Icons.share_outlined)),
            if (user?.canManage ?? false)
              PopupMenuButton<String>(
                onSelected: _menu,
                itemBuilder: (c) => [
                  if (!m.isCompleted) const PopupMenuItem(value: 'edit', child: Text('Edit match details')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete match', style: TextStyle(color: AppColors.live))),
                ],
              ),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Live'),
            Tab(text: 'Scorecard'),
            Tab(text: 'Commentary'),
            Tab(text: 'Insights'),
            Tab(text: 'Info'),
          ]),
        ),
        floatingActionButton: canScore
            ? FloatingActionButton.extended(
                onPressed: _openScoring,
                backgroundColor: AppColors.primary,
                icon: Icon(s.hasStarted ? Icons.sports_cricket : Icons.play_arrow_rounded),
                label: Text(s.hasStarted ? 'Resume scoring' : 'Start match', style: const TextStyle(fontWeight: FontWeight.w900)),
              )
            : null,
        body: TabBarView(children: [
          RefreshIndicator(onRefresh: _load, child: _liveTab(s)),
          RefreshIndicator(onRefresh: _load, child: ScorecardView(snap: s)),
          CommentaryView(
            matchId: widget.matchId,
            teamNames: {m.team1.id: m.team1.name, m.team2.id: m.team2.name},
            bpo: s.bpo,
            refreshKey: _rev,
            events: asMapList(m.scorerMeta['events']),
            allowAi: context.read<AuthService>().user != null,
          ),
          InsightsView(matchId: widget.matchId, refreshKey: _rev),
          _infoTab(s),
        ]),
      ),
    );
  }

  Widget _liveTab(Snapshot s) {
    final m = s.match;
    if (!s.hasStarted) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _versusCard(m),
        const SizedBox(height: 16),
        const EmptyView(icon: Icons.timer_outlined, title: 'Match yet to begin', subtitle: 'Live score, crease and this-over details will appear here.'),
      ]);
    }
    final res = summary;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
      if (m.isCompleted) ...[
        _resultCard(m, res),
        const SizedBox(height: 12),
      ],
      LiveScoreHeader(snap: s),
      if (s.innings.length > 1) ...[
        const SizedBox(height: 10),
        Card(
          child: Column(children: [
            for (final i in s.innings)
              ListTile(
                dense: true,
                leading: TeamBadge(name: m.teamById(i['battingTeamId']?.toString()).name, logoUrl: m.teamById(i['battingTeamId']?.toString()).logoUrl, color: m.teamById(i['battingTeamId']?.toString()).color, size: 28),
                title: Text('${m.teamById(i['battingTeamId']?.toString()).name}${i['isSuperOver'] == true ? ' (Super Over)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text('${asInt(i['runs'])}/${asInt(i['wickets'])} (${Cricket.oversText(asDouble(i['overs']))})', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
          ]),
        ),
      ],
      if (!m.isCompleted) ...[
        const SizedBox(height: 10),
        CreasePanel(snap: s),
        const SizedBox(height: 10),
        ThisOverStrip(snap: s),
      ],
      if (s.fallOfWickets.isNotEmpty) ...[
        const SectionTitle('Last wicket', padding: EdgeInsets.fromLTRB(4, 18, 4, 8)),
        Builder(builder: (_) {
          final f = s.fallOfWickets.last;
          return Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: AppColors.wicket, child: Text('W', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white))),
              title: Text('${f['playerName']} ${f['runs']} (${f['balls']})', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${f['dismissalStatus']} • ${f['scoreAtWicket']} in ${f['overAtWicket']} ov'),
            ),
          );
        }),
      ],
    ]);
  }

  Widget _resultCard(MatchView m, Map<String, dynamic>? sum) {
    final mr = asMap(sum?['matchResult']);
    final awards = asMap(mr['awards']);
    final pom = asMap(awards['playerOfTheMatch']);
    final mom = pom.isNotEmpty
        ? {'name': pom['playerName']}
        : asMap(mr['manOfTheMatchName'] != null ? {'name': mr['manOfTheMatchName']} : asMap(m.result['manOfTheMatch']));
    const labels = {'bestBatter': 'Best batter', 'bestBowler': 'Best bowler', 'bestFielder': 'Best fielder', 'fighter': 'Fighter of the match'};
    final extraAwards = [
      for (final e in labels.entries)
        if (asMap(awards[e.key]).isNotEmpty) (e.value, asMap(awards[e.key])),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.emoji_events, color: Colors.white),
          SizedBox(width: 8),
          Text('RESULT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white70)),
        ]),
        const SizedBox(height: 8),
        Text(m.resultText.isEmpty ? 'Match completed' : m.resultText, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
        if (mom['name'] != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFDE047)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Player of the match: ${mom['name']}${pom['statLine'] != null ? ' • ${pom['statLine']}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ]),
        ],
        for (final a in extraAwards)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${a.$1}: ${a.$2['playerName']}${a.$2['statLine'] != null ? ' (${a.$2['statLine']})' : ''}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
      ]),
    );
  }

  Widget _versusCard(MatchView m) {
    Widget side(TeamRef t) => Expanded(
          child: Column(children: [
            TeamBadge(name: t.name, logoUrl: t.logoUrl, color: t.color, size: 64),
            const SizedBox(height: 8),
            Text(t.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
        );
    return GradientCard(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          side(m.team1),
          const Text('VS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.cyan)),
          side(m.team2),
        ]),
        const SizedBox(height: 16),
        Text('${m.overs} overs • ${Fmt.dateTime(m.scheduledAt)}', style: const TextStyle(color: AppColors.textMid, fontWeight: FontWeight.w700)),
        if (m.venue.isNotEmpty) Text(m.venue, style: const TextStyle(color: AppColors.textLo)),
      ]),
    );
  }

  Widget _infoTab(Snapshot s) {
    final m = s.match;
    final raw = s.matchRaw;
    final toss = m.tossWinnerId == null ? '' : '${m.teamById(m.tossWinnerId).name} won the toss and chose to ${m.tossDecision == 'bowl' ? 'bowl' : 'bat'}';
    Widget xi(TeamRef t) {
      final list = s.xiFor(t.id);
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.shortName, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
          const SizedBox(height: 6),
          if (list.isEmpty) const Text('Not announced', style: TextStyle(color: AppColors.textLo)),
          for (final x in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${asMap(x['player'])['name'] ?? '-'}${x['isCaptain'] == true ? ' (c)' : ''}${x['isKeeper'] == true ? ' (wk)' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ]),
      );
    }

    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
      _versusCard(m),
      const SizedBox(height: 12),
      GradientCard(
        child: Column(children: [
          KeyValueRow('Tournament', m.tournamentName),
          KeyValueRow('Stage', [m.stage, m.group].where((e) => e.isNotEmpty).join(' • ')),
          KeyValueRow('Format', '${m.overs} overs • ${s.tournament['type'] ?? ''}'),
          KeyValueRow('Date', Fmt.dateTime(m.scheduledAt)),
          KeyValueRow('Venue', m.venue),
          if (toss.isNotEmpty) KeyValueRow('Toss', toss),
          KeyValueRow('Umpires', [raw['umpire1'], raw['umpire2']].where((e) => e != null && '$e'.isNotEmpty).join(', ')),
          KeyValueRow('Referee', '${raw['matchReferee'] ?? ''}'),
        ]),
      ),
      if (m.venue.isNotEmpty || (s.tournament['city'] ?? '').toString().isNotEmpty) ...[
        const SectionTitle('Weather', padding: EdgeInsets.fromLTRB(4, 18, 4, 10)),
        FutureBuilder<Map<String, dynamic>>(
          future: context.api.weather(m.venue.isNotEmpty ? m.venue : s.tournament['city'].toString(), fallback: s.tournament['city']?.toString()),
          builder: (c, w) {
            if (w.connectionState != ConnectionState.done) return const SizedBox(height: 60, child: LoadingView());
            if (w.hasError || w.data == null) return const Text('Weather unavailable for this venue', style: TextStyle(color: AppColors.textLo));
            final d = w.data!;
            return GradientCard(
              child: Row(children: [
                const Icon(Icons.wb_sunny_outlined, size: 34, color: Color(0xFFFDE047)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${d['temperature'] ?? '—'} • ${d['condition'] ?? ''}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    Text([d['location'], if (d['humidity'] != null) 'Humidity ${d['humidity']}', 'Wind ${d['windSpeed'] ?? '—'}'].where((e) => e != null).join(' • '),
                        style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
                  ]),
                ),
              ]),
            );
          },
        ),
      ],
      const SectionTitle('Playing XI', padding: EdgeInsets.fromLTRB(4, 18, 4, 10)),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [xi(m.team1), const SizedBox(width: 12), xi(m.team2)]),
        ),
      ),
    ]);
  }
}
