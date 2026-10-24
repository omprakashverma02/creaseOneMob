import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../matches/match_detail_screen.dart';

/// One row per match a player featured in: batting + bowling figures, opponent,
/// tournament and date. Optional [tournamentId] filter. Shows a recent-form chart.
class PlayerMatchLog extends StatefulWidget {
  const PlayerMatchLog({super.key, required this.playerId, this.tournamentId});
  final String playerId;
  final String? tournamentId;
  @override
  State<PlayerMatchLog> createState() => _PlayerMatchLogState();
}

class _MatchLine {
  _MatchLine(this.matchId);
  final String matchId;
  Map<String, dynamic>? bat;
  Map<String, dynamic>? bowl;
  MatchView? match;
  String? teamId;
  DateTime? get when => Fmt.parse(match?.scheduledAt ?? bat?['createdAt'] ?? bowl?['createdAt']);
}

class _PlayerMatchLogState extends State<PlayerMatchLog> {
  late final Future<List<_MatchLine>> _future = _load();

  Future<List<_MatchLine>> _load() async {
    final api = context.api;
    final r = await Future.wait([
      api.playerBattingRows(widget.playerId).catchError((_) => <Map<String, dynamic>>[]),
      api.playerBowlingRows(widget.playerId).catchError((_) => <Map<String, dynamic>>[]),
      api.matches().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    final byMatch = {for (final m in r[2]) m['id'].toString(): MatchView(m)};
    final lines = <String, _MatchLine>{};
    for (final b in r[0]) {
      final l = lines.putIfAbsent(b['matchId'].toString(), () => _MatchLine(b['matchId'].toString()));
      l.bat = b;
      l.teamId ??= b['teamId']?.toString();
    }
    for (final b in r[1]) {
      final l = lines.putIfAbsent(b['matchId'].toString(), () => _MatchLine(b['matchId'].toString()));
      l.bowl = b;
      // Bowling row's team is the player's own side too.
      l.teamId ??= b['teamId']?.toString();
    }
    for (final l in lines.values) {
      l.match = byMatch[l.matchId] ?? (l.bat?['match'] != null ? MatchView(asMap(l.bat!['match'])) : (l.bowl?['match'] != null ? MatchView(asMap(l.bowl!['match'])) : null));
    }
    final list = lines.values.toList()..sort((a, b) => (b.when ?? DateTime(1970)).compareTo(a.when ?? DateTime(1970)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_MatchLine>>(
      future: _future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const SizedBox(height: 120, child: LoadingView());
        final all = s.data ?? const <_MatchLine>[];
        final list = widget.tournamentId == null ? all : all.where((l) => l.match?.tournamentId == widget.tournamentId).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Match by match'),
          if (list.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No matches played yet', style: TextStyle(color: AppColors.textMid))),
          if (list.where((l) => l.bat != null).length >= 2) _formChart(list),
          for (final l in list.take(40)) _tile(l),
        ]);
      },
    );
  }

  Widget _formChart(List<_MatchLine> list) {
    final innings = list.where((l) => l.bat != null).take(10).toList().reversed.toList();
    final maxRuns = innings.fold<int>(10, (a, l) => asInt(l.bat!['runs']) > a ? asInt(l.bat!['runs']) : a);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recent form (runs, last 10 innings)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: BarChart(BarChartData(
                maxY: maxRuns * 1.15,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 18,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= innings.length) return const SizedBox.shrink();
                        final out = (innings[i].bat!['outType'] ?? '').toString().isEmpty;
                        return Text('${asInt(innings[i].bat!['runs'])}${out ? '*' : ''}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800));
                      },
                    ),
                  ),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                barGroups: [
                  for (var i = 0; i < innings.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: asDouble(innings[i].bat!['runs']),
                        width: 14,
                        color: asInt(innings[i].bat!['runs']) >= 50 ? AppColors.cyan : AppColors.primary,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ]),
                ],
              )),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(_MatchLine l) {
    final m = l.match;
    final opp = m == null ? null : (l.teamId == m.team1.id ? m.team2 : m.team1);
    final bat = l.bat;
    final bowl = l.bowl;
    final batText = bat == null
        ? null
        : '${asInt(bat['runs'])}${(bat['outType'] ?? '').toString().isEmpty ? '*' : ''} (${asInt(bat['balls'])})'
            '${asInt(bat['fours']) + asInt(bat['sixes']) > 0 ? '  ${asInt(bat['fours'])}×4 ${asInt(bat['sixes'])}×6' : ''}';
    final bowlText = bowl == null || (asDouble(bowl['overs']) == 0 && asInt(bowl['runsConceded']) == 0)
        ? null
        : '${Cricket.oversText(asDouble(bowl['overs']))}-${asInt(bowl['maidens'])}-${asInt(bowl['runsConceded'])}-${asInt(bowl['wickets'])}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GradientCard(
        padding: const EdgeInsets.all(12),
        onTap: m == null ? null : () => context.push(MatchDetailScreen(matchId: m.id)),
        child: Row(children: [
          if (opp != null) TeamBadge(name: opp.name, logoUrl: opp.logoUrl, color: opp.color, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(opp == null ? 'Match' : 'vs ${opp.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text([if ((m?.tournamentName ?? '').isNotEmpty) m!.tournamentName, if (l.when != null) Fmt.date(l.when!.toIso8601String())].join(' • '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (batText != null) Text('Bat  $batText', style: const TextStyle(fontWeight: FontWeight.w900)),
            if (bowlText != null) Text('Bowl  $bowlText', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.cyan)),
          ]),
        ]),
      ),
    );
  }
}
