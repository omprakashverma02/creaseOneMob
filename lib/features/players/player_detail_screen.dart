import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import 'player_form_screen.dart';

/// Player profile with career / tournament batting & bowling quick stats.
class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key, required this.playerId});
  final String playerId;
  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  Map<String, dynamic>? p;
  List<Map<String, dynamic>> memberships = [];
  String? tournamentId;
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
      final r = await Future.wait([api.player(widget.playerId), api.teamPlayers(playerId: widget.playerId).catchError((_) => <Map<String, dynamic>>[])]);
      if (!mounted) return;
      setState(() {
        p = r[0] as Map<String, dynamic>;
        memberships = r[1] as List<Map<String, dynamic>>;
        error = null;
        _rev++;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthService>().user?.canManage ?? false;
    if (p == null) return Scaffold(appBar: AppBar(), body: error != null ? ErrorView(message: error!, onRetry: _load) : const LoadingView());
    final x = p!;
    final tournaments = <String, String>{};
    final teams = <String, Map<String, dynamic>>{};
    for (final m in memberships) {
      final t = asMap(m['tournament']);
      if (m['tournamentId'] != null) tournaments[m['tournamentId'].toString()] = t['name']?.toString() ?? 'Tournament';
      final tm = asMap(m['team']);
      if (tm['id'] != null) teams[tm['id'].toString()] = tm;
    }
    final category = tournamentId == null ? 'career' : 'tournament';
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          actions: [
            if (canManage)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final r = await context.push(PlayerFormScreen(existing: x));
                  if (r != null) _load();
                },
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF173A86), AppColors.bg], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              padding: const EdgeInsets.fromLTRB(16, 86, 16, 16),
              child: Column(children: [
                PlayerAvatar(name: x['name'] ?? '', imageUrl: x['imageUrl'], size: 86),
                const SizedBox(height: 10),
                Text(x['name']?.toString() ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  [Cricket.roleLabel(x['role']), x['battingStyle'], if (x['bowlingStyle'] != null && x['bowlingStyle'] != 'None') x['bowlingStyle']].where((e) => e != null).join(' • '),
                  style: const TextStyle(color: AppColors.textMid),
                ),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (teams.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in teams.values)
                    Chip(
                      avatar: TeamBadge(name: t['name'] ?? '', logoUrl: t['logoUrl'], color: t['themeColor'], size: 22),
                      label: Text(t['name']?.toString() ?? ''),
                    ),
                ]),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ChoiceChip(label: const Text('Career'), selected: tournamentId == null, onSelected: (_) => setState(() => tournamentId = null)),
                  for (final e in tournaments.entries)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(label: Text(e.value), selected: tournamentId == e.key, onSelected: (_) => setState(() => tournamentId = e.key)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: _StatsBlock(
            key: ValueKey('bat$tournamentId$_rev'),
            title: 'Batting',
            icon: Icons.sports_cricket,
            future: context.api.playerQuickStats(playerId: widget.playerId, type: 'bat', category: category, tournamentId: tournamentId),
            tiles: (s) => [
              ('Matches', '${s['matches'] ?? 0}'),
              ('Innings', '${s['innings'] ?? 0}'),
              ('Runs', '${s['runs'] ?? 0}'),
              ('Average', '${s['average'] ?? '-'}'),
              ('Strike rate', '${s['strikeRate'] ?? '-'}'),
              ('Best', '${s['bestScore'] ?? '-'}'),
              ('50s', '${s['fifties'] ?? '-'}'),
              ('100s', '${s['hundreds'] ?? '-'}'),
              ('4s / 6s', '${s['fours'] ?? 0} / ${s['sixes'] ?? 0}'),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: _StatsBlock(
            key: ValueKey('bowl$tournamentId$_rev'),
            title: 'Bowling',
            icon: Icons.sports_baseball_outlined,
            future: context.api.playerQuickStats(playerId: widget.playerId, type: 'ball', category: category, tournamentId: tournamentId),
            tiles: (s) => [
              ('Matches', '${s['matches'] ?? 0}'),
              ('Wickets', '${s['wickets'] ?? 0}'),
              ('Runs', '${s['runsConceded'] ?? 0}'),
              ('Economy', '${s['economy'] ?? '-'}'),
              ('Average', '${s['average'] ?? '-'}'),
              ('Best', '${s['bestSpell'] ?? s['best'] ?? '-'}'),
              ('3W', '${s['threeWickets'] ?? '-'}'),
              ('5W', '${s['fiveWickets'] ?? '-'}'),
              ('Overs', '${s['overs'] ?? s['totalOvers'] ?? '-'}'),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GradientCard(
              child: Column(children: [
                KeyValueRow('Gender', '${x['gender'] ?? '-'}'),
                KeyValueRow('Date of birth', x['dob'] == null ? '-' : Fmt.date(x['dob'])),
                KeyValueRow('Short name', '${x['shortName'] ?? '-'}'),
                KeyValueRow('Created by', '${asMap(x['createdBy'])['name'] ?? x['createdByName'] ?? '-'}'),
              ]),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 30)),
      ]),
    );
  }
}

class _StatsBlock extends StatelessWidget {
  const _StatsBlock({super.key, required this.title, required this.icon, required this.future, required this.tiles});
  final String title;
  final IconData icon;
  final Future<Map<String, dynamic>> future;
  final List<(String, String)> Function(Map<String, dynamic>) tiles;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(title),
      FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const SizedBox(height: 120, child: LoadingView());
          if (s.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text(s.error.toString(), style: const TextStyle(color: AppColors.textMid)));
          final t = tiles(s.data!);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.45,
              children: [for (final e in t) StatTile(label: e.$1, value: e.$2)],
            ),
          );
        },
      ),
    ]);
  }
}
