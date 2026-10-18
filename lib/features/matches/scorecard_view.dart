import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../players/player_detail_screen.dart';

/// Full scorecard for every innings in the snapshot.
class ScorecardView extends StatefulWidget {
  const ScorecardView({super.key, required this.snap});
  final Snapshot snap;
  @override
  State<ScorecardView> createState() => _ScorecardViewState();
}

class _ScorecardViewState extends State<ScorecardView> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    final s = widget.snap;
    final inns = s.innings;
    if (inns.isEmpty) return const EmptyView(icon: Icons.list_alt_rounded, title: 'Scorecard not available', subtitle: 'The match has not started yet.');
    final sel = selected ?? asInt(s.currentInnings?['number'], 1);
    final inn = inns.firstWhere((i) => asInt(i['number']) == sel, orElse: () => inns.last);
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      SizedBox(
        height: 54,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), children: [
          for (final i in inns)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: asInt(i['number']) == asInt(inn['number']),
                onSelected: (_) => setState(() => selected = asInt(i['number'])),
                label: Text('${s.match.teamById(i['battingTeamId']?.toString()).shortName}${i['isSuperOver'] == true || asInt(i['number']) >= 3 && !Cricket.isTest(s.tournament) ? ' (SO)' : ''} ${asInt(i['runs'])}/${asInt(i['wickets'])}'),
              ),
            ),
        ]),
      ),
      InningsCard(snap: s, innings: inn),
    ]);
  }
}

class InningsCard extends StatelessWidget {
  const InningsCard({super.key, required this.snap, required this.innings});
  final Snapshot snap;
  final Map<String, dynamic> innings;

  @override
  Widget build(BuildContext context) {
    final s = snap;
    final number = asInt(innings['number']);
    final batId = innings['battingTeamId']?.toString();
    final bowlId = batId == s.match.team1.id ? s.match.team2.id : s.match.team1.id;
    final team = s.match.teamById(batId);
    final fow = s.fallOfWickets.where((f) => asInt(f['innings']) == number).toList();
    final fowByPlayer = {for (final f in fow) f['playerId']?.toString(): f};
    final batting = s.battingStats.where((b) => b['teamId']?.toString() == batId).toList()
      ..sort((a, b) => asInt(a['playingSeqActual'], 99).compareTo(asInt(b['playingSeqActual'], 99)));
    final bowling = s.bowlingStats.where((b) => b['teamId']?.toString() == bowlId && (asDouble(b['overs']) > 0 || asInt(b['balls']) > 0 || asInt(b['runsConceded']) > 0)).toList();
    final batted = batting.map((b) => b['playerId'].toString()).toSet();
    final dnb = s.xiFor(batId).where((x) => !batted.contains(x['playerId'].toString())).map((x) => asMap(x['player'])['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
    final ex = s.extrasFor(number);
    final crease = s.liveCrease;
    final isLiveInnings = number == s.currentInningsNumber && !s.currentInningsCompleted && s.match.isLive;
    final bpo = s.bpo;
    final legal = Cricket.oversToBalls(asDouble(innings['overs']), bpo);

    TextStyle head = const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.textMid);
    Widget num(String v, {double w = 34, bool bold = false}) =>
        SizedBox(width: w, child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, fontSize: 13.5)));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GradientCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            TeamBadge(name: team.name, logoUrl: team.logoUrl, color: team.color, size: 40),
            const SizedBox(width: 12),
            Expanded(child: Text(team.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${asInt(innings['runs'])}/${asInt(innings['wickets'])}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text('${Cricket.oversText(asDouble(innings['overs']))} ov • RR ${Cricket.runRate(asInt(innings['runs']), legal, bpo)}',
                  style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(children: [
                Expanded(child: Text('BATTER', style: head)),
                for (final h in ['R', 'B', '4s', '6s']) SizedBox(width: 34, child: Text(h, textAlign: TextAlign.right, style: head)),
                SizedBox(width: 50, child: Text('SR', textAlign: TextAlign.right, style: head)),
              ]),
            ),
            const Divider(),
            for (final b in batting)
              InkWell(
                onTap: () => context.push(PlayerDetailScreen(playerId: b['playerId'].toString())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${asMap(b['player'])['name'] ?? '-'}${isLiveInnings && (b['playerId'].toString() == crease['strikerId']?.toString()) ? ' *' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: b['outType'] == null ? AppColors.cyan : AppColors.textHi,
                          ),
                        ),
                        Text(
                          _dismissal(b, fowByPlayer[b['playerId'].toString()]),
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMid),
                        ),
                      ]),
                    ),
                    num('${asInt(b['runs'])}', bold: true),
                    num('${asInt(b['balls'])}'),
                    num('${asInt(b['fours'])}'),
                    num('${asInt(b['sixes'])}'),
                    num(Cricket.strikeRate(asInt(b['runs']), asInt(b['balls'])), w: 50),
                  ]),
                ),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Expanded(child: Text('Extras', style: TextStyle(fontWeight: FontWeight.w700))),
                Text('${asInt(ex['total'])}  ', style: const TextStyle(fontWeight: FontWeight.w900)),
                Text('(wd ${asInt(ex['wd'])}, nb ${asInt(ex['nb'])}, b ${asInt(ex['b'])}, lb ${asInt(ex['lb'])}${asInt(ex['pen']) > 0 ? ', pen ${asInt(ex['pen'])}' : ''})',
                    style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(children: [
                const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
                Text('${asInt(innings['runs'])}/${asInt(innings['wickets'])} (${Cricket.oversText(asDouble(innings['overs']))} ov)',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ]),
            ),
            if (dnb.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Yet to bat: ', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: dnb.join(', '), style: const TextStyle(color: AppColors.textMid)),
                ])),
              ),
          ]),
        ),
        if (fow.isNotEmpty) ...[
          const SectionTitle('Fall of wickets', padding: EdgeInsets.fromLTRB(4, 18, 4, 8)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in fow)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
                    child: Text('${f['scoreAtWicket']} • ${f['playerName']} (${f['overAtWicket']})', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ),
        ],
        const SectionTitle('Bowling', padding: EdgeInsets.fromLTRB(4, 18, 4, 8)),
        Card(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(children: [
                Expanded(child: Text('BOWLER', style: head)),
                for (final h in ['O', 'M', 'R', 'W', '0s']) SizedBox(width: 34, child: Text(h, textAlign: TextAlign.right, style: head)),
                SizedBox(width: 46, child: Text('ECO', textAlign: TextAlign.right, style: head)),
              ]),
            ),
            const Divider(),
            if (bowling.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No bowling yet', style: TextStyle(color: AppColors.textMid))),
            for (final b in bowling)
              InkWell(
                onTap: () => context.push(PlayerDetailScreen(playerId: b['playerId'].toString())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${asMap(b['player'])['name'] ?? '-'}${isLiveInnings && b['playerId'].toString() == crease['bowlerId']?.toString() ? ' *' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    num(Cricket.oversText(asDouble(b['overs']))),
                    num('${asInt(b['maidens'])}'),
                    num('${asInt(b['runsConceded'])}'),
                    num('${asInt(b['wickets'])}', bold: true),
                    num('${asInt(b['dotBalls'])}'),
                    num(Cricket.economy(asInt(b['runsConceded']), asDouble(b['overs']), bpo), w: 46),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  String _dismissal(Map<String, dynamic> b, Map<String, dynamic>? f) {
    final out = b['outType']?.toString();
    if (out == null || out.isEmpty) return 'not out';
    if (f != null && f['dismissalStatus'] != null) return f['dismissalStatus'].toString();
    return out;
  }
}
