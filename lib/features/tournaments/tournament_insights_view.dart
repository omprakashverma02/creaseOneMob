import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../matches/insights_view.dart';

/// Tournament-wide insights (web TournamentInsights.tsx).
class TournamentInsightsView extends StatefulWidget {
  const TournamentInsightsView({super.key, required this.tournamentId});
  final String tournamentId;
  @override
  State<TournamentInsightsView> createState() => _TournamentInsightsViewState();
}

class _TournamentInsightsViewState extends State<TournamentInsightsView> {
  late final Future<Map<String, dynamic>> _future = context.api.tournamentInsights(widget.tournamentId);
  String wagonTeam = 'all';

  @override
  Widget build(BuildContext context) {
    return AsyncBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (c, d) {
        final leaders = asMap(d['teamRunLeaders']);
        final bLeaders = asMap(d['boundaryLeaders']);
        final totals = asMap(d['boundaryTotals']);
        final dismissals = asMapList(d['dismissals']);
        final parts = asMapList(d['partnerships']);
        final teams = asMapList(d['wagonTeams']);
        final shots = asMapList(d['wagonShots']).where((s) => wagonTeam == 'all' || s['teamId']?.toString() == wagonTeam).toList();
        if (parts.isEmpty && dismissals.isEmpty && shots.isEmpty) {
          return const EmptyView(icon: Icons.insights_outlined, title: 'No insights yet', subtitle: 'Insights appear once matches have been scored.');
        }
        Widget leader(String label, Map<String, dynamic> l, Color color) => Expanded(
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(l.isEmpty ? '-' : '${l['count']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  Text(l.isEmpty ? '' : '${l['teamName']}', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMid)),
                ]),
              ),
            );
        const palette = [Color(0xFFEF4444), Color(0xFFF59E0B), Color(0xFF22D3EE), Color(0xFFA855F7), Color(0xFF22C55E), Color(0xFF3B82F6), Color(0xFFEC4899)];
        return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
          const SectionTitle('Team leaders', padding: EdgeInsets.fromLTRB(4, 8, 4, 6)),
          Row(children: [
            leader('Most 4s', asMap(bLeaders['fours']), AppColors.four),
            leader('Most 6s', asMap(bLeaders['sixes']), AppColors.six),
            leader('Most dots', asMap(leaders['dots']), AppColors.textMid),
          ]),
          Row(children: [
            leader('Most 1s', asMap(leaders['ones']), AppColors.textHi),
            leader('Most 2s', asMap(leaders['twos']), AppColors.cyan),
            leader('Most 3s', asMap(leaders['threes']), AppColors.success),
          ]),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text('Boundaries: ${asInt(totals['fours'])} fours • ${asInt(totals['sixes'])} sixes', style: const TextStyle(color: AppColors.textMid)),
          ),
          if (dismissals.isNotEmpty) ...[
            const SectionTitle('Dismissal types', padding: EdgeInsets.fromLTRB(4, 14, 4, 6)),
            Card(
              child: SizedBox(
                height: 190,
                child: Row(children: [
                  Expanded(
                    child: PieChart(PieChartData(centerSpaceRadius: 30, sectionsSpace: 2, sections: [
                      for (var i = 0; i < dismissals.length; i++)
                        PieChartSectionData(value: asDouble(dismissals[i]['count']), color: palette[i % palette.length], radius: 50, title: '${dismissals[i]['count']}',
                            titleStyle: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                    ])),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var i = 0; i < dismissals.length; i++)
                        Row(children: [
                          CircleAvatar(radius: 5, backgroundColor: palette[i % palette.length]),
                          const SizedBox(width: 6),
                          Text('${Cricket.dismissalTypes[dismissals[i]['type']] ?? dismissals[i]['type']} ${asDouble(dismissals[i]['pct']).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
                        ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
          if (parts.isNotEmpty) ...[
            const SectionTitle('Top partnerships', padding: EdgeInsets.fromLTRB(4, 14, 4, 6)),
            Card(
              child: Column(children: [
                for (final p in parts.take(10))
                  ListTile(
                    dense: true,
                    title: Text('${p['bat1']} & ${p['bat2']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${p['teamName']} • ${_ord(asInt(p['wicket']))} wicket'),
                    trailing: Text('${p['runs']} (${p['balls']})', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
                  ),
              ]),
            ),
          ],
          for (final pair in [('Fastest fifties', asMapList(d['fastestFifty'])), ('Fastest hundreds', asMapList(d['fastestHundred']))])
            if (pair.$2.isNotEmpty) ...[
              SectionTitle(pair.$1, padding: const EdgeInsets.fromLTRB(4, 14, 4, 6)),
              Card(
                child: Column(children: [
                  for (final r in pair.$2.take(5))
                    ListTile(dense: true, title: Text('${r['playerName']}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${r['teamName']}'), trailing: Text('${r['balls']} balls', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan))),
                ]),
              ),
            ],
          if (asMapList(d['wagonShots']).isNotEmpty) ...[
            const SectionTitle('Tournament wagon wheel', padding: EdgeInsets.fromLTRB(4, 14, 4, 6)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(label: const Text('All teams'), selected: wagonTeam == 'all', onSelected: (_) => setState(() => wagonTeam = 'all')),
                for (final t in teams)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(label: Text('${t['shortName'] ?? t['name']}'), selected: wagonTeam == t['id'].toString(), onSelected: (_) => setState(() => wagonTeam = t['id'].toString())),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            AspectRatio(aspectRatio: 1, child: CustomPaint(painter: WagonWheelPainter(shots))),
          ],
        ]);
      },
    );
  }

  String _ord(int n) => n == 1 ? '1st' : n == 2 ? '2nd' : n == 3 ? '3rd' : '${n}th';
}
