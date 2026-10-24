import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../players/player_search_sheet.dart';
import 'scoring_screen.dart';

/// Pre-match flow: Playing XI (both teams) → Toss → Openers & opening bowler.
class MatchSetupScreen extends StatefulWidget {
  const MatchSetupScreen({super.key, required this.matchId});
  final String matchId;
  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _XiPick {
  _XiPick(this.player);
  final Map<String, dynamic> player;
  bool captain = false;
  bool keeper = false;
  String get id => player['id'].toString();
  String get name => player['name']?.toString() ?? '-';
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  int step = 0;
  MatchView? match;
  Map<String, List<Map<String, dynamic>>> squads = {};
  final Map<String, List<_XiPick>> xi = {};
  String? tossWinner;
  String tossDecision = 'bat';
  String? strikerId;
  String? nonStrikerId;
  String? bowlerId;
  bool loading = true;
  bool busy = false;
  String? error;

  int get maxXi => match?.tournament['impactPlayerRule'] == true ? 16 : 13;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.api;
      final m = MatchView(await api.match(widget.matchId));
      final tid = m.tournamentId.isEmpty ? null : m.tournamentId;
      Future<List<Map<String, dynamic>>> squad(String teamId) async {
        var rows = await api.teamPlayers(teamId: teamId, tournamentId: tid);
        if (rows.isEmpty) rows = await api.teamPlayers(teamId: teamId);
        final seen = <String>{};
        return rows.map((r) => {...asMap(r['player']), '_isCaptain': r['isCaptain'], '_isKeeper': r['isKeeper']}).where((p) => p['id'] != null && seen.add(p['id'].toString())).toList();
      }

      final r = await Future.wait([
        squad(m.team1.id),
        squad(m.team2.id),
        api.playingXI(m.id, m.team1.id).catchError((_) => <Map<String, dynamic>>[]),
        api.playingXI(m.id, m.team2.id).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      squads = {m.team1.id: r[0], m.team2.id: r[1]};
      // Pre-fill from an existing Playing XI if one was saved on the web.
      for (final pair in [(m.team1.id, r[2]), (m.team2.id, r[3])]) {
        final saved = pair.$2;
        if (saved.isNotEmpty) {
          xi[pair.$1] = saved.map((x) {
            final p = _XiPick({...asMap(x['player']), 'id': x['playerId']});
            p.captain = x['isCaptain'] == true;
            p.keeper = x['isKeeper'] == true;
            return p;
          }).toList();
        } else {
          xi[pair.$1] = [];
        }
      }
      setState(() {
        match = m;
        tossWinner = m.tossWinnerId;
        tossDecision = m.tossDecision ?? 'bat';
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  String get battingTeamId {
    final m = match!;
    if (tossWinner == null) return m.team1.id;
    final other = tossWinner == m.team1.id ? m.team2.id : m.team1.id;
    return tossDecision == 'bat' ? tossWinner! : other;
  }

  String get bowlingTeamId => battingTeamId == match!.team1.id ? match!.team2.id : match!.team1.id;

  Future<void> _addFromRegistry(String teamId) async {
    final tid = match!.tournamentId;
    final taken = tid.isEmpty
        ? const <String, String>{}
        : await context.api.playersTakenInTournament(tid, exceptTeamId: teamId).catchError((_) => <String, String>{});
    if (!mounted) return;
    final ids = await showPlayerMultiSearch(context, exclude: squads[teamId]!.map((p) => p['id'].toString()).toSet(), takenBy: taken, title: 'Add players to squad');
    if (ids == null || ids.isEmpty || !mounted) return;
    try {
      await context.api.assignPlayersToTeam(teamId: teamId, tournamentId: match!.tournamentId.isEmpty ? null : match!.tournamentId, playerIds: ids);
      setState(() => loading = true);
      await _load();
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  Future<void> _next() async {
    final m = match!;
    if (step <= 1) {
      final teamId = step == 0 ? m.team1.id : m.team2.id;
      final picks = xi[teamId]!;
      if (picks.length < 2) {
        context.toast('Select at least 2 players', error: true);
        return;
      }
      setState(() => busy = true);
      try {
        await context.api.savePlayingXI(m.id, teamId, [
          for (final p in picks) {'playerId': p.id, 'teamId': teamId, 'isCaptain': p.captain, 'isViceCaptain': false, 'isKeeper': p.keeper},
        ]);
        setState(() => step++);
      } catch (e) {
        if (mounted) context.toast(e.toString(), error: true);
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    if (step == 2) {
      if (tossWinner == null) {
        context.toast('Who won the toss?', error: true);
        return;
      }
      setState(() => step = 3);
      return;
    }
    if (strikerId == null || nonStrikerId == null || bowlerId == null) {
      context.toast('Pick both openers and the opening bowler', error: true);
      return;
    }
    if (strikerId == nonStrikerId) {
      context.toast('Striker and non-striker must be different', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final api = context.api;
      await api.updateToss(m.id, tossWinner!, tossDecision);
      await api.startInnings({
        'matchId': m.id,
        'battingTeamId': battingTeamId,
        'number': 1,
        'target': null,
        'strikerId': strikerId,
        'nonStrikerId': nonStrikerId,
        'bowlerId': bowlerId,
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ScoringScreen(matchId: m.id)));
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return Scaffold(appBar: AppBar(title: const Text('Match setup')), body: const LoadingView());
    if (error != null) return Scaffold(appBar: AppBar(title: const Text('Match setup')), body: ErrorView(message: error!, onRetry: _load));
    final m = match!;
    const titles = ['Playing XI', 'Playing XI', 'Toss', 'Openers'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[step]),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => step == 0 ? Navigator.pop(context) : setState(() => step--)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(value: (step + 1) / 4, minHeight: 3, backgroundColor: AppColors.surfaceHigh),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: busy ? null : _next,
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(step == 3 ? 'Start scoring 🏏' : 'Continue'),
          ),
        ),
      ),
      body: switch (step) {
        0 => _xiStep(m.team1),
        1 => _xiStep(m.team2),
        2 => _tossStep(m),
        _ => _openersStep(m),
      },
    );
  }

  Widget _xiStep(TeamRef team) {
    final squad = squads[team.id]!;
    final picks = xi[team.id]!;
    final pickedIds = picks.map((p) => p.id).toSet();
    final extras = picks.where((p) => !squad.any((s) => s['id'].toString() == p.id)).map((p) => p.player).toList();
    final all = [...squad, ...extras];
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 30), children: [
      Row(children: [
        TeamBadge(name: team.name, logoUrl: team.logoUrl, color: team.color, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(team.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text('${picks.length} selected • max $maxXi', style: TextStyle(color: picks.length >= 11 ? AppColors.success : AppColors.textMid)),
          ]),
        ),
        TextButton.icon(onPressed: () => _addFromRegistry(team.id), icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Add')),
      ]),
      const SizedBox(height: 4),
      const Text('Tap to select. Long-press a selected player to set Captain / Wicket-keeper. Order of selection = batting order.',
          style: TextStyle(color: AppColors.textLo, fontSize: 12)),
      const SizedBox(height: 10),
      if (all.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No players in this squad yet. Use "Add" to pick registered players or create new ones.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid)),
        ),
      for (final p in all)
        Builder(builder: (_) {
          final id = p['id'].toString();
          final sel = pickedIds.contains(id);
          final pick = sel ? picks.firstWhere((x) => x.id == id) : null;
          final order = sel ? picks.indexOf(pick!) + 1 : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: sel ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sel ? AppColors.primary : AppColors.border)),
                leading: sel
                    ? CircleAvatar(radius: 18, backgroundColor: AppColors.primary, child: Text('$order', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)))
                    : PlayerAvatar(name: p['name'] ?? '', imageUrl: p['imageUrl'], size: 36),
                title: Text(p['name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(Cricket.roleLabel(p['role']?.toString()), style: const TextStyle(fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (pick?.captain == true) const Pill('C', color: Color(0xFFF59E0B)),
                  if (pick?.keeper == true) ...[const SizedBox(width: 4), const Pill('WK', color: AppColors.cyan)],
                  if (sel)
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _roleSheet(pick!, picks),
                    ),
                ]),
                onTap: () => setState(() {
                  if (sel) {
                    picks.removeWhere((x) => x.id == id);
                  } else if (picks.length < maxXi) {
                    final np = _XiPick(p);
                    np.captain = p['_isCaptain'] == true && !picks.any((x) => x.captain);
                    np.keeper = p['_isKeeper'] == true && !picks.any((x) => x.keeper);
                    picks.add(np);
                  } else {
                    context.toast('Maximum $maxXi players');
                  }
                }),
                onLongPress: sel ? () => _roleSheet(pick!, picks) : null,
              ),
            ),
          );
        }),
    ]);
  }

  void _roleSheet(_XiPick pick, List<_XiPick> picks) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(pick.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
            title: Text(pick.captain ? 'Remove as captain' : 'Make captain'),
            onTap: () {
              setState(() {
                final v = !pick.captain;
                for (final x in picks) {
                  x.captain = false;
                }
                pick.captain = v;
              });
              Navigator.pop(c);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sports_handball, color: AppColors.cyan),
            title: Text(pick.keeper ? 'Remove as wicket-keeper' : 'Make wicket-keeper'),
            onTap: () {
              setState(() {
                final v = !pick.keeper;
                for (final x in picks) {
                  x.keeper = false;
                }
                pick.keeper = v;
              });
              Navigator.pop(c);
            },
          ),
          ListTile(
            leading: const Icon(Icons.vertical_align_top),
            title: const Text('Move up in batting order'),
            onTap: () {
              setState(() {
                final i = picks.indexOf(pick);
                if (i > 0) {
                  picks.removeAt(i);
                  picks.insert(i - 1, pick);
                }
              });
              Navigator.pop(c);
            },
          ),
        ]),
      ),
    );
  }

  Widget _tossStep(MatchView m) {
    Widget teamTile(TeamRef t) {
      final sel = tossWinner == t.id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => tossWinner = t.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
            ),
            child: Column(children: [
              TeamBadge(name: t.name, logoUrl: t.logoUrl, color: t.color, size: 60),
              const SizedBox(height: 10),
              Text(t.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      );
    }

    Widget decision(String v, String label, String asset) {
      final sel = tossDecision == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => tossDecision = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
            ),
            child: Column(children: [
              Image.asset(asset, height: 80),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(child: Image.asset('assets/images/gold-coin.png', height: 110)),
      const SizedBox(height: 10),
      const Text('Who won the toss?', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 14),
      Row(children: [teamTile(m.team1), const SizedBox(width: 12), teamTile(m.team2)]),
      const SizedBox(height: 24),
      const Text('Elected to', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 14),
      Row(children: [decision('bat', 'BAT', 'assets/images/batting.png'), const SizedBox(width: 12), decision('bowl', 'BOWL', 'assets/images/bowling.png')]),
      if (tossWinner != null) ...[
        const SizedBox(height: 18),
        Text('${m.teamById(tossWinner).name} won the toss and elected to $tossDecision first',
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800)),
      ],
    ]);
  }

  Widget _openersStep(MatchView m) {
    final bat = xi[battingTeamId]!;
    final bowl = xi[bowlingTeamId]!;
    Widget picker(String label, String? value, List<_XiPick> list, ValueChanged<String> onPick, {Set<String> disabled = const {}}) {
      final cur = list.where((p) => p.id == value).firstOrNull;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GradientCard(
          onTap: () async {
            final r = await pickFromList(
              context,
              title: label,
              items: list.map((p) => p.player).toList(),
              label: (p) => p['name']?.toString() ?? '-',
              subtitle: (p) => Cricket.roleLabel(p['role']?.toString()),
              leading: (p) => PlayerAvatar(name: p['name'] ?? '', imageUrl: p['imageUrl'], size: 34),
              disabled: (p) => disabled.contains(p['id'].toString()),
            );
            if (r != null) onPick(r['id'].toString());
          },
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            cur == null
                ? const CircleAvatar(backgroundColor: AppColors.surfaceHigh, child: Icon(Icons.add, color: AppColors.textMid))
                : PlayerAvatar(name: cur.name, imageUrl: cur.player['imageUrl'], size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w700)),
                Text(cur?.name ?? 'Tap to select', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cur == null ? AppColors.textLo : null)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${m.teamById(battingTeamId).name} batting', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 12),
      picker('Striker', strikerId, bat, (v) => setState(() => strikerId = v), disabled: {if (nonStrikerId != null) nonStrikerId!}),
      picker('Non-striker', nonStrikerId, bat, (v) => setState(() => nonStrikerId = v), disabled: {if (strikerId != null) strikerId!}),
      const SizedBox(height: 10),
      Text('${m.teamById(bowlingTeamId).name} bowling', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 12),
      picker('Opening bowler', bowlerId, bowl, (v) => setState(() => bowlerId = v)),
    ]);
  }
}
