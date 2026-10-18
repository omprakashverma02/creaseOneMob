import 'package:flutter/material.dart';

import '../core/cricket.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, this.onTap, this.trailing});
  final MatchView match;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final header = [
      if (m.seq != null) 'Match #${m.seq}',
      if (m.stage.isNotEmpty) m.stage,
      if (m.tournamentName.isNotEmpty) m.tournamentName,
    ].join(' • ');
    return GradientCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(header, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          _status(m),
        ]),
        const SizedBox(height: 10),
        _teamRow(m.team1, m),
        const SizedBox(height: 8),
        _teamRow(m.team2, m),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              m.isCompleted
                  ? (m.resultText.isEmpty ? 'Completed' : m.resultText)
                  : m.isLive
                      ? _liveLine(m)
                      : '${Fmt.dateTime(m.scheduledAt)}${m.venue.isNotEmpty ? ' • ${m.venue}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: m.isCompleted ? AppColors.cyan : (m.isLive ? AppColors.warning : AppColors.textMid),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      ]),
    );
  }

  String _liveLine(MatchView m) {
    final inns = m.innings.where((i) => i['isSuperOver'] != true).toList();
    if (inns.length >= 2) {
      final t = asInt(inns[1]['target'] ?? inns[1]['revisedTarget']);
      final need = (t > 0 ? t : asInt(inns[0]['runs']) + 1) - asInt(inns[1]['runs']);
      final team = m.teamById(inns[1]['battingTeamId']?.toString()).shortName;
      return need > 0 ? '$team need $need runs' : 'Live';
    }
    if (m.tossWinnerId != null && inns.isEmpty) {
      return '${m.teamById(m.tossWinnerId).shortName} won the toss and chose to ${m.tossDecision == 'bowl' ? 'bowl' : 'bat'}';
    }
    return '${m.overs} overs match • In progress';
  }

  Widget _status(MatchView m) {
    if (m.isLive) return const LiveDot();
    if (m.status == 'abandoned') return const Pill('ABANDONED', color: AppColors.textLo);
    if (m.isCompleted) return const Pill('RESULT', color: AppColors.success);
    return const Pill('UPCOMING', color: AppColors.cyan);
  }

  Widget _teamRow(TeamRef t, MatchView m) {
    final score = m.scoreFor(t.id);
    final overs = m.oversFor(t.id);
    final winner = m.result['winnerTeamId']?.toString() == t.id;
    return Row(children: [
      TeamBadge(name: t.name, logoUrl: t.logoUrl, color: t.color, size: 30),
      const SizedBox(width: 10),
      Expanded(
        child: Text(t.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: winner ? FontWeight.w900 : FontWeight.w700, color: AppColors.textHi)),
      ),
      if (score.isNotEmpty) ...[
        Text(score, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: winner ? AppColors.cyan : AppColors.textHi)),
        const SizedBox(width: 6),
        Text('($overs)', style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
      ],
    ]);
  }
}
