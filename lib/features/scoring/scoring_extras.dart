import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'scoring_screen.dart';
import 'scoring_sheets.dart';

/// Edit a ball that was already scored (web RectifyScorecardModal → POST /balls/rectify).
Future<void> showRectifyBalls(ScoringScreenState st) async {
  final s = st.snap!;
  List<Map<String, dynamic>> balls;
  try {
    balls = await st.context.api.balls(st.widget.matchId, innings: s.currentInningsNumber);
  } catch (e) {
    if (st.mounted) st.context.toast(e.toString(), error: true);
    return;
  }
  if (!st.mounted) return;
  if (balls.isEmpty) {
    st.context.toast('No balls in this innings yet');
    return;
  }
  final picked = await showModalBottomSheet<Map<String, dynamic>>(
    context: st.context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (c, sc) => Column(children: [
        const Text('Pick the ball to correct', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Expanded(
          child: ListView.builder(
            controller: sc,
            itemCount: balls.length,
            itemBuilder: (c, i) {
              final b = balls[balls.length - 1 - i];
              return ListTile(
                leading: BallPip(_pip(b)),
                title: Text('${asInt(b['overNumber']) - 1}.${asInt(b['ballNumber'])}  ${asMap(b['bowler'])['name'] ?? ''} to ${asMap(b['striker'])['name'] ?? ''}'),
                subtitle: b['wicket'] == true ? Text('${b['wicketType'] ?? 'out'} — ${asMap(b['dismissedPlayer'])['name'] ?? ''}') : null,
                onTap: () => Navigator.pop(c, b),
              );
            },
          ),
        ),
      ]),
    ),
  );
  if (picked == null || !st.mounted) return;
  final ok = await showModalBottomSheet<bool>(
    context: st.context,
    isScrollControlled: true,
    builder: (c) => _RectifySheet(snap: s, ball: picked, matchId: st.widget.matchId),
  );
  if (ok == true) await st.reload();
}

String _pip(Map<String, dynamic> b) {
  final total = asInt(b['batRuns']) + asInt(b['extraRuns']) + asInt(b['overthrowRuns']);
  final ex = (b['extraType'] ?? '').toString().toUpperCase();
  if (b['wicket'] == true) return 'W';
  if (ex == 'WD') return 'Wd$total';
  if (ex == 'NB') return 'Nb$total';
  if (ex == 'B') return 'B$total';
  if (ex == 'LB') return 'Lb$total';
  return '$total';
}

class _RectifySheet extends StatefulWidget {
  const _RectifySheet({required this.snap, required this.ball, required this.matchId});
  final Snapshot snap;
  final Map<String, dynamic> ball;
  final String matchId;
  @override
  State<_RectifySheet> createState() => _RectifySheetState();
}

class _RectifySheetState extends State<_RectifySheet> {
  late final b = widget.ball;
  late int batRuns = asInt(b['batRuns']);
  late int extraRuns = asInt(b['extraRuns']);
  late String? extraType = (b['extraType']?.toString().isEmpty ?? true) ? null : b['extraType'].toString().toUpperCase();
  late String? wicketType = b['wicket'] == true ? b['wicketType']?.toString().split('|').first : null;
  late String? strikerId = b['strikerId']?.toString();
  late String? nonStrikerId = b['nonStrikerId']?.toString();
  late String? bowlerId = b['bowlerId']?.toString();
  late String? dismissedId = b['dismissedPlayerId']?.toString();
  String bowlerScope = 'this';
  bool replaceBatterEverywhere = false;
  bool saving = false;

  Future<void> _save() async {
    setState(() => saving = true);
    final patch = {
      'batRuns': batRuns,
      'extraRuns': extraType == null ? 0 : extraRuns,
      'extraType': extraType,
      'wicketType': wicketType,
      'wicket': wicketType != null,
      'strikerId': strikerId,
      'nonStrikerId': nonStrikerId,
      'bowlerId': bowlerId,
      'dismissedPlayerId': wicketType == null ? null : (dismissedId ?? strikerId),
    };
    final origBowler = b['bowlerId']?.toString();
    final origStriker = b['strikerId']?.toString();
    try {
      await context.api.rectifyBall({
        'ballId': b['id'].toString(),
        'patch': patch,
        if (bowlerId != origBowler && origBowler != null && bowlerId != null)
          'replaceBowler': {'fromPlayerId': origBowler, 'toPlayerId': bowlerId, 'scope': bowlerScope},
        if (replaceBatterEverywhere && strikerId != origStriker && origStriker != null && strikerId != null)
          'replaceBatter': {'fromPlayerId': origStriker, 'toPlayerId': strikerId},
        'cascadeStrike': true,
      });
      if (mounted) {
        context.toast('Ball corrected — scorecard recalculated', success: true);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snap;
    final batTeam = b['teamId']?.toString() ?? s.battingTeamId;
    final bowlTeam = batTeam == s.match.team1.id ? s.match.team2.id : s.match.team1.id;
    Widget pick(String label, String? id, String? teamId, ValueChanged<String> on) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(label, style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
          subtitle: Text(s.playerName(id), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: () async {
            final r = await pickPlayer(context, title: label, xi: s.xiFor(teamId));
            if (r != null) setState(() => on(r));
          },
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text('Correct ball ${asInt(b['overNumber']) - 1}.${asInt(b['ballNumber'])}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SectionTitle('Runs off the bat', padding: EdgeInsets.fromLTRB(0, 14, 0, 6)),
        Wrap(spacing: 6, children: [for (var r = 0; r <= 7; r++) ChoiceChip(label: Text('$r'), selected: batRuns == r, onSelected: (_) => setState(() => batRuns = r))]),
        const SectionTitle('Extra', padding: EdgeInsets.fromLTRB(0, 14, 0, 6)),
        Wrap(spacing: 6, children: [
          for (final e in [null, 'WD', 'NB', 'B', 'LB'])
            ChoiceChip(label: Text(e ?? 'None'), selected: extraType == e, onSelected: (_) => setState(() => extraType = e)),
        ]),
        if (extraType != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            const Text('Extra runs: '),
            for (var r = 0; r <= 7; r++) ChoiceChip(label: Text('$r'), selected: extraRuns == r, onSelected: (_) => setState(() => extraRuns = r)),
          ]),
        ],
        const SectionTitle('Wicket', padding: EdgeInsets.fromLTRB(0, 14, 0, 6)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(label: const Text('Not out'), selected: wicketType == null, onSelected: (_) => setState(() => wicketType = null)),
          for (final t in Cricket.dismissalTypes.keys)
            ChoiceChip(label: Text(Cricket.dismissalTypes[t]!), selected: wicketType == t, onSelected: (_) => setState(() => wicketType = t)),
        ]),
        if (wicketType != null) pick('Dismissed batter', dismissedId ?? strikerId, batTeam, (v) => dismissedId = v),
        const SectionTitle('Players', padding: EdgeInsets.fromLTRB(0, 14, 0, 6)),
        pick('Striker (faced the ball)', strikerId, batTeam, (v) => strikerId = v),
        if (strikerId != b['strikerId']?.toString())
          SwitchListTile(contentPadding: EdgeInsets.zero, value: replaceBatterEverywhere, title: const Text('Wrong batter everywhere — replace in all balls'), onChanged: (v) => setState(() => replaceBatterEverywhere = v)),
        pick('Non-striker', nonStrikerId, batTeam, (v) => nonStrikerId = v),
        pick('Bowler', bowlerId, bowlTeam, (v) => bowlerId = v),
        if (bowlerId != b['bowlerId']?.toString())
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'this', label: Text('This ball')), ButtonSegment(value: 'over', label: Text('Whole over')), ButtonSegment(value: 'all', label: Text('Everywhere'))],
            selected: {bowlerScope},
            onSelectionChanged: (v) => setState(() => bowlerScope = v.first),
          ),
        const SizedBox(height: 18),
        FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Saving…' : 'Save correction')),
      ]),
    );
  }
}


/// Transfer scoring of this match to another CreaseOne account (max 10 transfers).
Future<void> showScoringTransfer(ScoringScreenState st) async {
  final api = st.context.api;
  Map<String, dynamic> status;
  try {
    status = await api.scoringTransfer(st.widget.matchId);
  } catch (e) {
    if (st.mounted) st.context.toast(e.toString(), error: true);
    return;
  }
  if (!st.mounted) return;
  final email = TextEditingController();
  final ok = await showDialog<bool>(
    context: st.context,
    builder: (c) => AlertDialog(
      title: const Text('Transfer scoring'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Current scorer: ${status['scoringOwnerEmail'] ?? '-'}'),
        Text('Transfers left: ${status['remaining'] ?? 0} of ${status['maxTransfers'] ?? 10}', style: const TextStyle(color: AppColors.textMid)),
        const SizedBox(height: 12),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'New scorer\'s CreaseOne email')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: status['transferEnabled'] == false ? null : () => Navigator.pop(c, true), child: const Text('Transfer')),
      ],
    ),
  );
  if (ok != true || !st.mounted) return;
  try {
    await api.transferScoring(st.widget.matchId, {'email': email.text.trim()});
    if (st.mounted) st.context.toast('Scoring transferred to ${email.text.trim()}', success: true);
  } catch (e) {
    if (st.mounted) st.context.toast(e.toString(), error: true);
  }
}

/// AI commentary for the current state (server-side Gemini; English or Hindi).
Future<void> showAiCommentary(BuildContext context, String matchId) async {
  String lang = 'en';
  String? text;
  bool loading = false;
  await showModalBottomSheet(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      Future<void> gen() async {
        setS(() => loading = true);
        try {
          final r = await context.api.aiCommentary(matchId, lang: lang);
          setS(() => text = r['text']?.toString());
        } catch (e) {
          setS(() => text = 'Could not generate: $e');
        } finally {
          setS(() => loading = false);
        }
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.auto_awesome, color: AppColors.cyan),
              SizedBox(width: 8),
              Text('AI commentary', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'hi', label: Text('हिन्दी'))],
              selected: {lang},
              onSelectionChanged: (v) => setS(() => lang = v.first),
            ),
            const SizedBox(height: 14),
            if (text != null) GradientCard(child: Text(text!, style: const TextStyle(fontSize: 15, height: 1.4))),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: loading ? null : gen, icon: const Icon(Icons.mic), label: Text(loading ? 'Thinking…' : 'Generate')),
          ]),
        ),
      );
    }),
  );
}
