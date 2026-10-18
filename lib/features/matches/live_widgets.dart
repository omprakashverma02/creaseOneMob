import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';

/// Big score header used on the match page and the scoring console.
class LiveScoreHeader extends StatelessWidget {
  const LiveScoreHeader({super.key, required this.snap, this.compact = false});
  final Snapshot snap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = snap;
    final m = s.match;
    final batting = m.teamById(s.battingTeamId);
    final bowling = m.teamById(s.bowlingTeamId);
    final bpo = s.bpo;
    final legal = s.legalBalls;
    final f = FormatInfo(s.tournament);
    final crr = f.runRate(s.runs, legal);
    final target = s.target ?? (s.currentInningsNumber == 2 ? asInt(s.innings.first['runs']) + 1 : null);
    final quota = s.scheduledOvers * bpo;
    final need = target == null ? null : target - s.runs;
    final left = quota - legal;
    final rrr = (need != null && left > 0) ? f.requiredRate(need, left) : null;
    final soInns = s.isSuperOver && s.currentInningsNumber >= 3 && !f.isTest;
    final pp = (m.isLive && !s.currentInningsCompleted)
        ? Powerplay.activeLabel(
            Powerplay.fromMatch(s.matchRaw, s.tournament, s.scheduledOvers),
            f,
            legal,
            superOver: soInns,
            taken: asMap(asMap(m.scorerMeta['powerplayOptional'])['${s.currentInningsNumber}']),
          )
        : null;
    final first = s.innings.isNotEmpty ? s.innings.first : null;
    final isChase = s.currentInningsNumber >= 2 && target != null && !Cricket.isTest(s.tournament);
    final color = AppColors.fromHex(batting.color);
    return Container(
      padding: EdgeInsets.fromLTRB(16, compact ? 12 : 16, 16, compact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.35), const Color(0xFF0B1328)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          TeamBadge(name: batting.name, logoUrl: batting.logoUrl, color: batting.color, size: compact ? 34 : 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(batting.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 14 : 16)),
              Text('vs ${bowling.shortName} • ${s.isSuperOver && s.currentInningsNumber >= 3 ? 'Super Over' : 'Innings ${s.currentInningsNumber}'}',
                  style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
            ]),
          ),
          if (pp != null) ...[Pill(pp, color: AppColors.warning), const SizedBox(width: 6)],
          if (m.isLive && !s.currentInningsCompleted) const LiveDot(),
        ]),
        SizedBox(height: compact ? 8 : 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${s.runs}/${s.wickets}', style: TextStyle(fontSize: compact ? 34 : 44, fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('(${Cricket.ballsToOvers(legal, bpo)}/${s.scheduledOvers})', style: const TextStyle(fontSize: 16, color: AppColors.textMid, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('C${f.rateLabel} $crr', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (isChase && rrr != null) Text('Req ${f.rateLabel} $rrr', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
          ]),
        ]),
        if (isChase && need != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
            child: Text(
              need <= 0 ? '${batting.name} reached the target' : '${batting.shortName} need $need run${need == 1 ? '' : 's'} from $left ball${left == 1 ? '' : 's'} • Target $target',
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.cyan, fontSize: 13),
            ),
          ),
        ] else if (s.currentInningsNumber >= 2 && first != null && Cricket.isTest(s.tournament)) ...[
          const SizedBox(height: 8),
          Text('1st inns: ${m.teamById(first['battingTeamId']?.toString()).shortName} ${asInt(first['runs'])}/${asInt(first['wickets'])}',
              style: const TextStyle(color: AppColors.textMid)),
        ],
      ]),
    );
  }
}

/// Batters + bowler block shown under the score header.
class CreasePanel extends StatelessWidget {
  const CreasePanel({super.key, required this.snap, this.onTapStriker, this.onTapNonStriker, this.onTapBowler, this.strikerId, this.nonStrikerId, this.bowlerId});
  final Snapshot snap;
  final VoidCallback? onTapStriker;
  final VoidCallback? onTapNonStriker;
  final VoidCallback? onTapBowler;
  final String? strikerId;
  final String? nonStrikerId;
  final String? bowlerId;

  @override
  Widget build(BuildContext context) {
    final s = snap;
    final c = s.liveCrease;
    final sid = strikerId ?? c['strikerId']?.toString();
    final nid = nonStrikerId ?? c['nonStrikerId']?.toString();
    final bid = bowlerId ?? c['bowlerId']?.toString();
    final bpo = s.bpo;
    Widget batter(String? id, bool striker, VoidCallback? onTap) {
      final st = s.battingStatFor(id) ?? {};
      final p = s.playerById(id);
      final runs = asInt(st['runs']);
      final balls = asInt(st['balls']);
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(children: [
            Icon(Icons.sports_cricket, size: 16, color: striker ? AppColors.cyan : Colors.transparent),
            const SizedBox(width: 6),
            PlayerAvatar(name: p['name']?.toString() ?? '?', imageUrl: p['imageUrl']?.toString(), size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(id == null ? 'Select batter' : (p['name']?.toString() ?? '-'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: striker ? FontWeight.w900 : FontWeight.w700, color: id == null ? AppColors.warning : null)),
            ),
            Text('$runs', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(' ($balls)', style: const TextStyle(color: AppColors.textMid)),
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              child: Text('${asInt(st['fours'])}×4 ${asInt(st['sixes'])}×6', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: AppColors.textMid)),
            ),
          ]),
        ),
      );
    }

    final bst = s.bowlingStatFor(bid) ?? {};
    final bp = s.playerById(bid);
    final part = s.partnership;
    return Card(
      child: Column(children: [
        batter(sid, true, onTapStriker),
        const Divider(indent: 12, endIndent: 12),
        batter(nid, false, onTapNonStriker),
        const Divider(),
        InkWell(
          onTap: onTapBowler,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(children: [
              const Icon(Icons.sports_baseball, size: 16, color: AppColors.ball),
              const SizedBox(width: 6),
              PlayerAvatar(name: bp['name']?.toString() ?? '?', imageUrl: bp['imageUrl']?.toString(), size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(bid == null ? 'Select bowler' : (bp['name']?.toString() ?? '-'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: bid == null ? AppColors.warning : null)),
              ),
              Text('${Cricket.oversText(asDouble(bst['overs']))}-${asInt(bst['maidens'])}-${asInt(bst['runsConceded'])}-${asInt(bst['wickets'])}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text('Eco ${Cricket.economy(asInt(bst['runsConceded']), asDouble(bst['overs']), bpo)}',
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: AppColors.textMid)),
              ),
            ]),
          ),
        ),
        if (asInt(part['totalRuns']) > 0 || asInt(part['totalBalls']) > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
            decoration: const BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
            child: Text('Partnership ${asInt(part['totalRuns'])} (${asInt(part['totalBalls'])})',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMid)),
          ),
      ]),
    );
  }
}

class ThisOverStrip extends StatelessWidget {
  const ThisOverStrip({super.key, required this.snap});
  final Snapshot snap;
  @override
  Widget build(BuildContext context) {
    final pips = snap.lastBall.isEmpty ? const <String>[] : snap.currentOverPips.isNotEmpty ? snap.currentOverPips : snap.lastBall.map(_pip).toList();
    final overNo = snap.lastBall.isEmpty ? snap.completedOvers + 1 : asInt(snap.lastBall.first['overNumber']);
    final runs = snap.lastBall.fold<int>(0, (a, b) => a + asInt(b['batRuns']) + asInt(b['extraRuns']) + asInt(b['overthrowRuns']));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text('Over $overNo', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.textMid, fontSize: 12)),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: pips.isEmpty ? [const Text('—', style: TextStyle(color: AppColors.textLo))] : pips.map((p) => BallPip(p, size: 28)).toList()),
          ),
        ),
        Text('$runs', style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    );
  }

  static String _pip(Map<String, dynamic> b) {
    final total = asInt(b['batRuns']) + asInt(b['extraRuns']) + asInt(b['overthrowRuns']);
    final ex = (b['extraType'] ?? '').toString().toUpperCase();
    if (b['wicket'] == true) return 'W';
    if (ex == 'WD') return 'Wd$total';
    if (ex == 'NB') return 'Nb$total';
    if (ex == 'B') return 'B$total';
    if (ex == 'LB') return 'Lb$total';
    return '$total';
  }
}
