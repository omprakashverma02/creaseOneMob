import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../scoring/scoring_extras.dart' show showAiCommentary;

/// Ball-by-ball commentary generated from GET /balls (newest first), with fielding
/// areas, shot names and scorer events (breaks, DRS, delays) like the web.
class CommentaryView extends StatefulWidget {
  const CommentaryView({super.key, required this.matchId, required this.teamNames, required this.bpo, this.refreshKey = 0, this.events = const [], this.allowAi = false});
  final String matchId;
  final Map<String, String> teamNames;
  final int bpo;
  final int refreshKey;

  /// scorerMeta.events (intervals, DRS, outcomes…)
  final List<Map<String, dynamic>> events;
  final bool allowAi;
  @override
  State<CommentaryView> createState() => _CommentaryViewState();
}

class _CommentaryViewState extends State<CommentaryView> {
  late Future<List<Map<String, dynamic>>> _future = context.api.balls(widget.matchId);
  int? innings;
  bool boundariesOnly = false;
  bool wicketsOnly = false;

  @override
  void didUpdateWidget(covariant CommentaryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) _future = context.api.balls(widget.matchId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done && !s.hasData) return const LoadingView();
        if (s.hasError) return ErrorView(message: s.error.toString(), onRetry: () => setState(() => _future = context.api.balls(widget.matchId)));
        final all = s.data ?? [];
        if (all.isEmpty) return const EmptyView(icon: Icons.mic_none_rounded, title: 'No commentary yet', subtitle: 'Ball-by-ball updates appear once scoring starts.');
        final inningsList = all.map((b) => asInt(b['innings'])).toSet().toList()..sort();
        final balls = all.where((b) {
          if (innings != null && asInt(b['innings']) != innings) return false;
          final bat = asInt(b['batRuns']);
          if (boundariesOnly && bat != 4 && bat != 6) return false;
          if (wicketsOnly && b['wicket'] != true) return false;
          return true;
        }).toList();
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final b in balls) {
          groups.putIfAbsent('${b['innings']}|${b['overNumber']}', () => []).add(b);
        }
        final keys = groups.keys.toList().reversed.toList();
        final evts = widget.events.where((e) => innings == null || e['innings'] == null || asInt(e['innings']) == innings).toList().reversed.toList();
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 40),
          itemCount: keys.length + 1,
          itemBuilder: (c, i) {
            if (i == 0) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  height: 50,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), children: [
                    ChoiceChip(label: const Text('All'), selected: innings == null, onSelected: (_) => setState(() => innings = null)),
                    for (final n in inningsList)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(label: Text(n >= 3 ? 'Inns $n (SO)' : 'Inns $n'), selected: innings == n, onSelected: (_) => setState(() => innings = n)),
                      ),
                    const SizedBox(width: 10),
                    FilterChip(label: const Text('4s & 6s'), selected: boundariesOnly, onSelected: (v) => setState(() => boundariesOnly = v)),
                    const SizedBox(width: 6),
                    FilterChip(label: const Text('Wickets'), selected: wicketsOnly, onSelected: (v) => setState(() => wicketsOnly = v)),
                  ]),
                ),
                if (widget.allowAi)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: OutlinedButton.icon(
                      onPressed: () => showAiCommentary(context, widget.matchId),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('AI commentary (English / हिन्दी)'),
                    ),
                  ),
                for (final e in evts.take(6)) _eventRow(e),
              ]);
            }
            final list = groups[keys[i - 1]]!;
            final first = list.first;
            final inn = asInt(first['innings']);
            final over = asInt(first['overNumber']);
            final runs = list.fold<int>(0, (a, b) => a + asInt(b['batRuns']) + asInt(b['extraRuns']) + asInt(b['overthrowRuns']));
            final wkts = list.where((b) => b['wicket'] == true).length;
            final bowler = asMap(first['bowler'])['name'] ?? '';
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                margin: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(gradient: AppColors.cardGradient, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Text('Over $over', style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('• Inns $inn • $bowler', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMid, fontSize: 12))),
                  if (!boundariesOnly && !wicketsOnly)
                    Text('$runs run${runs == 1 ? '' : 's'}${wkts > 0 ? ', $wkts wkt' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.cyan)),
                ]),
              ),
              for (final b in list.reversed) _ballRow(b),
            ]);
          },
        );
      },
    );
  }

  Widget _eventRow(Map<String, dynamic> e) {
    final type = (e['type'] ?? '').toString();
    final text = e['summaryText'] ?? e['label'] ?? e['headline'] ??
        (type == 'drs' ? 'DRS review — ${e['outcome']} (${e['remaining']}/${e['total']} left)' : type.replaceAll('_', ' '));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(type == 'drs' ? Icons.tv_rounded : type == 'interval' ? Icons.local_cafe_outlined : Icons.info_outline, color: AppColors.warning, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('$text', style: const TextStyle(fontWeight: FontWeight.w700))),
        if (e['at'] != null) Text(Fmt.dateTime(e['at']), style: const TextStyle(color: AppColors.textLo, fontSize: 11)),
      ]),
    );
  }

  Widget _ballRow(Map<String, dynamic> b) {
    final over = asInt(b['overNumber']);
    final ball = asInt(b['ballNumber']);
    final label = _pip(b);
    final striker = asMap(b['striker'])['name'] ?? 'Batter';
    final bowler = asMap(b['bowler'])['name'] ?? 'Bowler';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 38, child: Text('${over - 1}.$ball', style: const TextStyle(color: AppColors.textMid, fontWeight: FontWeight.w700))),
        BallPip(label, size: 30),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$bowler to $striker', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(_text(b), style: TextStyle(color: b['wicket'] == true ? AppColors.wicket : AppColors.textMid, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }

  String _pip(Map<String, dynamic> b) {
    final total = asInt(b['batRuns']) + asInt(b['extraRuns']) + asInt(b['overthrowRuns']);
    final ex = (b['extraType'] ?? '').toString().toUpperCase();
    if (b['wicket'] == true) return 'W';
    if (ex == 'WD') return 'Wd${total > 1 ? total : ''}';
    if (ex == 'NB') return 'Nb${total > 1 ? total : ''}';
    if (ex == 'B') return 'B$total';
    if (ex == 'LB') return 'Lb$total';
    return '$total';
  }

  String _text(Map<String, dynamic> b) {
    final bat = asInt(b['batRuns']);
    final extra = asInt(b['extraRuns']);
    final ot = asInt(b['overthrowRuns']);
    final ex = (b['extraType'] ?? '').toString().toUpperCase();
    final parts = <String>[];
    if (b['wicket'] == true) {
      final who = asMap(b['dismissedPlayer'])['name'] ?? asMap(b['striker'])['name'] ?? '';
      final wt = (b['wicketType'] ?? 'out').toString().split('|').first;
      final f = asMap(b['fielder'])['name'];
      parts.add('OUT! $who — ${Cricket.dismissalTypes[wt] ?? wt}${f != null ? ' ($f)' : ''}');
    }
    switch (ex) {
      case 'WD':
        parts.add('Wide${extra > 1 ? ', $extra runs' : ''}');
      case 'NB':
        parts.add('No ball${bat > 0 ? ', $bat off the bat' : ''}');
      case 'B':
        parts.add('$extra bye${extra == 1 ? '' : 's'}');
      case 'LB':
        parts.add('$extra leg bye${extra == 1 ? '' : 's'}');
      default:
        if (b['wicket'] != true || bat > 0) {
          if (bat == 4) {
            parts.add('FOUR! Cracking shot to the fence');
          } else if (bat == 6) {
            parts.add('SIX! That is out of here');
          } else if (bat == 0) {
            parts.add('No run, dot ball');
          } else {
            parts.add('$bat run${bat == 1 ? '' : 's'}');
          }
        }
    }
    if (ot > 0) parts.add('+$ot overthrow${ot == 1 ? '' : 's'}');
    if (b['shotName'] != null) parts.add('${b['shotName']}');
    if (b['wagonAngle'] != null) {
      final dist = b['wagonDistance'] == null ? (bat >= 4 ? 1.0 : 0.6) : asDouble(b['wagonDistance']);
      parts.add('to ${fieldingArea(asDouble(b['wagonAngle']), dist)}');
    }
    return parts.join(' • ');
  }
}
