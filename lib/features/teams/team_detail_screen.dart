import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../players/player_detail_screen.dart';
import '../players/player_form_screen.dart';
import '../players/player_search_sheet.dart';
import 'team_form_screen.dart';

/// Team profile + squad management (per tournament, like the web Setup Panel).
class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId, this.tournamentId});
  final String teamId;
  final String? tournamentId;
  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  Map<String, dynamic>? team;
  List<Map<String, dynamic>> squad = [];
  List<Map<String, dynamic>> tournaments = [];
  late String? tournamentId = widget.tournamentId;
  String? error;
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.api;
      final r = await Future.wait([
        api.team(widget.teamId),
        api.teamPlayers(teamId: widget.teamId),
        api.tournaments(mine: true).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        team = r[0] as Map<String, dynamic>;
        squad = r[1] as List<Map<String, dynamic>>;
        tournaments = r[2] as List<Map<String, dynamic>>;
        error = null;
      });
      // Anyone can view a team; edit / squad controls only for its owner or tournament managers.
      final canEdit = await api.canEditTeam(widget.teamId);
      if (mounted) setState(() => _canEdit = canEdit);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _visible {
    final list = squad.where((a) => tournamentId == null || a['tournamentId']?.toString() == tournamentId).toList();
    // De-duplicate players listed under multiple tournaments when viewing "All".
    final seen = <String>{};
    return list.where((a) => seen.add(a['playerId'].toString())).toList()
      ..sort((a, b) => '${asMap(a['player'])['name']}'.compareTo('${asMap(b['player'])['name']}'));
  }

  Future<void> _addPlayers() async {
    final existing = _visible.map((a) => a['playerId'].toString()).toSet();
    // One team per player per tournament: lock players already in another squad.
    final taken = tournamentId == null
        ? const <String, String>{}
        : await context.api.playersTakenInTournament(tournamentId!, exceptTeamId: widget.teamId).catchError((_) => <String, String>{});
    if (!mounted) return;
    final picked = await showPlayerMultiSearch(context, exclude: existing, takenBy: taken, title: 'Add players to ${team?['name'] ?? 'team'}');
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      await context.api.assignPlayersToTeam(teamId: widget.teamId, tournamentId: tournamentId, playerIds: picked);
      if (mounted) context.toast('${picked.length} player(s) added', success: true);
      _load();
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  Future<void> _createPlayer() async {
    final p = await context.push<Map<String, dynamic>>(const PlayerFormScreen());
    if (p == null || p['id'] == null || !mounted) return;
    try {
      await context.api.assignPlayersToTeam(teamId: widget.teamId, tournamentId: tournamentId, playerIds: [p['id'].toString()]);
      _load();
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = (context.watch<AuthService>().user?.canManage ?? false) && _canEdit;
    if (team == null) return Scaffold(appBar: AppBar(), body: error != null ? ErrorView(message: error!, onRetry: _load) : const LoadingView());
    final t = team!;
    final color = AppColors.fromHex(t['themeColor']);
    final tIds = squad.map((a) => a['tournamentId']?.toString()).whereType<String>().toSet();
    final tOptions = tournaments.where((x) => tIds.contains(x['id'].toString()) || x['id'].toString() == widget.tournamentId).toList();
    final visible = _visible;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 210,
            actions: [
              if (canManage)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final r = await context.push(TeamFormScreen(existing: t));
                    if (r != null) _load();
                  },
                ),
              if (canManage)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await confirmDialog(context, title: 'Delete ${t['name']}?', message: 'Teams with matches cannot be deleted.', danger: true, ok: 'Delete')) return;
                    if (!mounted) return;
                    try {
                      await context.api.deleteTeam(widget.teamId);
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) context.toast(e.toString(), error: true);
                    }
                  },
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withValues(alpha: 0.55), AppColors.bg], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                padding: const EdgeInsets.fromLTRB(16, 90, 16, 16),
                child: Row(children: [
                  TeamBadge(name: t['name'] ?? '', logoUrl: t['logoUrl'], color: t['themeColor'], size: 78),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(t['name'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      Text([t['shortName'], t['city'], t['state']].where((e) => e != null && '$e'.isNotEmpty).join(' • '), style: const TextStyle(color: AppColors.textMid)),
                      const SizedBox(height: 6),
                      Pill('${visible.length} players', color: AppColors.cyan, icon: Icons.groups),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<String?>(
                  value: tOptions.any((x) => x['id'].toString() == tournamentId) ? tournamentId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Squad for tournament', prefixIcon: Icon(Icons.emoji_events_outlined)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All squads')),
                    ...tOptions.map((x) => DropdownMenuItem<String?>(value: x['id'].toString(), child: Text(x['name'].toString(), overflow: TextOverflow.ellipsis))),
                    ...tournaments
                        .where((x) => !tOptions.contains(x))
                        .map((x) => DropdownMenuItem<String?>(value: x['id'].toString(), child: Text('${x['name']} (new squad)', overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => tournamentId = v),
                ),
                if (canManage) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: FilledButton.icon(onPressed: _addPlayers, icon: const Icon(Icons.person_search), label: const Text('Add players'))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(onPressed: _createPlayer, icon: const Icon(Icons.person_add_alt_1), label: const Text('New player'))),
                  ]),
                ],
              ]),
            ),
          ),
          if (visible.isEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 300, child: EmptyView(icon: Icons.groups_outlined, title: 'No players in this squad'))),
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) => _playerRow(visible[i], canManage),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ]),
      ),
    );
  }

  Widget _playerRow(Map<String, dynamic> a, bool canManage) {
    final p = asMap(a['player']);
    final tags = <Widget>[
      if (a['isCaptain'] == true) const Pill('C', color: Color(0xFFF59E0B)),
      if (a['isKeeper'] == true) const Pill('WK', color: AppColors.cyan),
      if (a['hasLoggedIn'] == true) const Pill('APP', color: AppColors.success, icon: Icons.verified),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: PlayerAvatar(name: p['name'] ?? '', imageUrl: p['imageUrl'], size: 44),
      title: Row(children: [
        Flexible(child: Text(p['name']?.toString() ?? '-', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(width: 6),
        ...tags.expand((w) => [w, const SizedBox(width: 4)]),
      ]),
      subtitle: Text([Cricket.roleLabel(a['playingRole'] ?? p['role']), p['battingStyle'], p['bowlingStyle']].where((e) => e != null && '$e'.isNotEmpty && e != 'None').join(' • '),
          style: const TextStyle(fontSize: 12)),
      onTap: () => context.push(PlayerDetailScreen(playerId: p['id'].toString())),
      trailing: canManage
          ? PopupMenuButton<String>(
              onSelected: (v) async {
                final api = context.api;
                try {
                  if (v == 'c') await api.updateTeamPlayer(a['id'].toString(), {'isCaptain': !(a['isCaptain'] == true)});
                  if (v == 'wk') await api.updateTeamPlayer(a['id'].toString(), {'isKeeper': !(a['isKeeper'] == true)});
                  if (v == 'rm') {
                    if (!mounted || !await confirmDialog(context, title: 'Remove ${p['name']} from squad?', danger: true, ok: 'Remove')) return;
                    await api.removeTeamPlayer(a['id'].toString());
                  }
                  _load();
                } catch (e) {
                  if (mounted) context.toast(e.toString(), error: true);
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 'c', child: Text(a['isCaptain'] == true ? 'Remove captaincy' : 'Make captain')),
                PopupMenuItem(value: 'wk', child: Text(a['isKeeper'] == true ? 'Remove as keeper' : 'Make wicket-keeper')),
                const PopupMenuItem(value: 'rm', child: Text('Remove from squad', style: TextStyle(color: AppColors.live))),
              ],
            )
          : null,
    );
  }
}
