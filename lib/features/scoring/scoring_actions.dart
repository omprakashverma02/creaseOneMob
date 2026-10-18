import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'scoring_extras.dart';
import 'scoring_screen.dart';
import 'scoring_sheets.dart';

/// "More" menu of the scoring console — match-control features from the web ControlPanel.
Future<void> showScoringMenu(ScoringScreenState st) async {
  final context = st.context;
  final s = st.snap!;
  final completed = s.match.isCompleted;
  final items = <(IconData, String, Future<void> Function(), Color?)>[
    if (!completed) ...[
      (Icons.swap_horiz_rounded, 'Change bowler', st.changeBowlerMidOver, null),
      (Icons.person_off_outlined, 'Retire / other dismissal', st.wicketTapped, null),
      (Icons.sync_alt_rounded, 'Replace batter', () => _replaceBatter(st), null),
      (Icons.flag_outlined, 'End innings / Declare', () => _endInnings(st), AppColors.warning),
      (Icons.water_drop_outlined, 'Reduce overs (rain / DLS)', () => _reduceOvers(st), null),
      (Icons.local_cafe_outlined, 'Interval / break', () => _interval(st), null),
      (Icons.gavel_rounded, 'Penalty runs', () => _penalty(st), null),
      (Icons.add_circle_outline, 'Bonus runs', () => _bonus(st), null),
      if (s.tournament['impactPlayerRule'] == true) (Icons.bolt_rounded, 'Impact player', () => _impactPlayer(st), AppColors.cyan),
      (Icons.healing_outlined, 'Concussion replacement', () => _concussion(st), null),
      if (s.tournament['drsEnabled'] == true) (Icons.tv_rounded, 'DRS review', () => _drs(st), null),
    ],
    (Icons.edit_note_rounded, 'Edit a past ball', () => showRectifyBalls(st), AppColors.warning),
    (Icons.auto_awesome, 'AI commentary', () => showAiCommentary(st.context, st.widget.matchId), AppColors.cyan),
    if (!st.widget.scorerOnly) (Icons.swap_horizontal_circle_outlined, 'Transfer scoring', () => showScoringTransfer(st), null),
    if (completed && s.tournament['bonusPointsEnabled'] == true) (Icons.military_tech_outlined, 'Bonus point team', () => _bonusTeam(st), null),
    (Icons.star_outline_rounded, 'Change captain / WK', () => _captainWk(st), null),
    (Icons.sticky_note_2_outlined, 'Score note', () => _scoreNote(st), null),
    if (!st.widget.scorerOnly) (Icons.key_outlined, 'Share scorer access', () => _scorerAccess(st), null),
    if (!completed) (Icons.cancel_outlined, 'Abandon / walkover / delay', () => _endOutcome(st), AppColors.live),
    if (completed && !s.match.scoringLocked) (Icons.lock_outline, 'Lock scoring', () => _lock(st), null),
    if (st.widget.scorerOnly) (Icons.logout, 'Sign out', () => context.auth.signOut(), AppColors.live),
  ];
  final picked = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.05,
          children: [
            for (var i = 0; i < items.length; i++)
              Material(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(c, i),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(items[i].$1, color: items[i].$4 ?? AppColors.textHi, size: 26),
                      const SizedBox(height: 8),
                      Text(items[i].$2, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return;
  try {
    await items[picked].$3();
  } catch (e) {
    if (st.mounted) st.context.toast(e.toString(), error: true);
  }
}

Future<String?> _pickTeam(BuildContext context, Snapshot s, String title) async {
  final r = await pickFromList(
    context,
    title: title,
    items: [s.match.team1.raw, s.match.team2.raw],
    label: (t) => t['name']?.toString() ?? '-',
    leading: (t) => TeamBadge(name: t['name'] ?? '', logoUrl: t['logoUrl'], color: t['themeColor'], size: 34),
  );
  return r?['id']?.toString();
}

Future<void> _replaceBatter(ScoringScreenState st) async {
  final s = st.snap!;
  final from = await pickPlayer(st.context, title: 'Batter to replace', xi: s.xiFor(s.battingTeamId).where((x) => x['playerId'].toString() == st.strikerId || x['playerId'].toString() == st.nonStrikerId).toList());
  if (from == null || !st.mounted) return;
  final to = await pickPlayer(st.context, title: 'Replace ${s.playerName(from)} with', xi: st.availableBatters());
  if (to == null || !st.mounted) return;
  await st.context.api.replaceBatter(st.widget.matchId, fromPlayerId: from, toPlayerId: to, innings: s.currentInningsNumber);
  await st.context.api.persistCrease(st.widget.matchId,
      innings: s.currentInningsNumber, strikerId: st.strikerId == from ? to : st.strikerId, nonStrikerId: st.nonStrikerId == from ? to : st.nonStrikerId);
  await st.reload();
}

Future<void> _endInnings(ScoringScreenState st) async {
  if (!await confirmDialog(st.context, title: 'End this innings?', message: 'Use this for a declaration or when the innings is closed. You will then pick openers for the next innings.', ok: 'End innings')) {
    return;
  }
  await showInningsBreak(st, forced: true);
}

Future<void> _reduceOvers(ScoringScreenState st) async {
  final s = st.snap!;
  final res = await showModalBottomSheet<Map<String, dynamic>>(
    context: st.context,
    isScrollControlled: true,
    builder: (c) => RainRuleSheet(snap: s),
  );
  if (res == null || !st.mounted) return;
  final r = await st.context.api.reduceOvers(st.widget.matchId, res['overs'] as int,
      revisedTarget: res['target'] as int?, inningsNumber: s.currentInningsNumber <= 2 ? s.currentInningsNumber : null, method: res['method'] as String?);
  if (st.mounted) {
    st.context.toast('Overs set to ${r['reducedOvers'] ?? res['overs']}${r['revisedTarget'] != null ? ' • Target ${r['revisedTarget']}' : ''}', success: true);
  }
  await st.reload();
}

/// Reduce overs with built-in DLS (Standard Edition) and VJD calculators (web dlsCalculator / vjdCalculator).
class RainRuleSheet extends StatefulWidget {
  const RainRuleSheet({super.key, required this.snap});
  final Snapshot snap;
  @override
  State<RainRuleSheet> createState() => _RainRuleSheetState();
}

class _RainRuleSheetState extends State<RainRuleSheet> {
  late final s = widget.snap;
  late final overs = TextEditingController(text: '${s.scheduledOvers}');
  final manualTarget = TextEditingController();
  final t1OversLeft = TextEditingController(text: '0');
  final suspLeft = TextEditingController();
  final resumeLeft = TextEditingController();
  String method = 'pro_rata';
  bool lowerLevel = true;
  bool midChase = false;
  RainTarget? calc;

  bool get chasing => s.currentInningsNumber >= 2 && !s.isSuperOver;
  int get team1Score => asInt(s.innings.isNotEmpty ? s.innings.first['runs'] : 0);
  int get team1Wkts => asInt(s.innings.isNotEmpty ? s.innings.first['wickets'] : 0);

  @override
  void initState() {
    super.initState();
    if (chasing) _compute();
  }

  void _compute() {
    final o = double.tryParse(overs.text) ?? s.match.overs.toDouble();
    if (method == 'dls') {
      calc = Dls.target(
        team1Score: team1Score,
        team1StartOvers: s.match.overs.toDouble(),
        team2Overs: midChase ? s.match.overs.toDouble() : o,
        team1OversLeftAtEnd: double.tryParse(t1OversLeft.text) ?? 0,
        team1Wickets: team1Wkts,
        interrupt: midChase ? (double.tryParse(suspLeft.text) ?? 0, s.wickets, double.tryParse(resumeLeft.text) ?? 0) : null,
        lowerLevel: lowerLevel,
      );
    } else if (method == 'vjd') {
      calc = Vjd.target(team1Score: team1Score, scheduledOvers: s.match.overs, team2Overs: o);
    } else if (method == 'pro_rata') {
      final t = (team1Score * o / s.match.overs).ceil() + 1;
      calc = RainTarget(method: 'Pro-rata', target: t, par: t - 1, formula: 'ceil($team1Score x $o / ${s.match.overs}) + 1');
    } else {
      calc = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Reduce overs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(
            controller: overs,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: chasing ? 'Overs for the chase' : 'Overs for this innings'),
            onChanged: (_) => _compute(),
          ),
          if (chasing) ...[
            const SizedBox(height: 12),
            Text('Team 1 scored $team1Score/$team1Wkts in ${s.match.overs} scheduled overs', style: const TextStyle(color: AppColors.textMid)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'pro_rata', label: Text('Pro-rata')),
                ButtonSegment(value: 'dls', label: Text('DLS')),
                ButtonSegment(value: 'vjd', label: Text('VJD')),
                ButtonSegment(value: 'manual', label: Text('Manual')),
              ],
              selected: {method},
              onSelectionChanged: (v) {
                method = v.first;
                _compute();
              },
            ),
            if (method == 'dls') ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: lowerLevel,
                title: const Text('Non-international / lower level (G50 = 200)'),
                onChanged: (v) {
                  lowerLevel = v;
                  _compute();
                },
              ),
              TextField(
                controller: t1OversLeft,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Overs team 1 lost at the end of their innings'),
                onChanged: (_) => _compute(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: midChase,
                title: const Text('Interruption during this chase'),
                onChanged: (v) {
                  midChase = v;
                  _compute();
                },
              ),
              if (midChase) ...[
                TextField(controller: suspLeft, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Overs left when play stopped'), onChanged: (_) => _compute()),
                const SizedBox(height: 8),
                TextField(controller: resumeLeft, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Overs left when play resumes'), onChanged: (_) => _compute()),
              ],
            ],
            if (method == 'manual') ...[
              const SizedBox(height: 10),
              TextField(controller: manualTarget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Revised target')),
            ],
            if (calc != null) ...[
              const SizedBox(height: 12),
              GradientCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${calc!.method} target: ${calc!.target}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.cyan)),
                  Text('Par score ${calc!.par}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (calc!.r1 != null) Text('R1 ${calc!.r1!.toStringAsFixed(1)}% • R2 ${calc!.r2!.toStringAsFixed(1)}%', style: const TextStyle(color: AppColors.textMid)),
                  const SizedBox(height: 4),
                  Text(calc!.formula, style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final o = asInt(overs.text);
              if (o < 1) return;
              int? target;
              if (chasing) target = method == 'manual' ? int.tryParse(manualTarget.text) : calc?.target;
              Navigator.pop(context, {'overs': o, 'target': target, 'method': chasing ? method : null});
            },
            child: const Text('Apply'),
          ),
        ]),
      ),
    );
  }
}

Future<void> _interval(ScoringScreenState st) async {
  const types = ['Drinks', 'Innings Break', 'Lunch', 'Tea', 'Rain', 'Bad Light', 'Stumps', 'Others'];
  final picked = await pickFromList(st.context, title: 'Interval', items: [for (final t in types) {'t': t}], label: (m) => m['t']);
  if (picked == null || !st.mounted) return;
  String? custom;
  if (picked['t'] == 'Others') {
    custom = await promptText(st.context, title: 'Describe the interval');
    if (custom == null || custom.isEmpty) return;
  }
  final s = st.snap!;
  await st.context.api.setInterval(st.widget.matchId, {
    'type': picked['t'],
    if (custom != null) 'customLabel': custom,
    'innings': s.currentInningsNumber,
    'overNumber': s.completedOvers,
    'ballNumber': s.ballsInOver,
  });
  if (st.mounted) st.context.toast('${picked['t']} recorded', success: true);
}

Future<void> _penalty(ScoringScreenState st) async {
  final s = st.snap!;
  final team = await _pickTeam(st.context, s, 'Award 5 penalty runs to');
  if (team == null || !st.mounted) return;
  const reasons = {
    'ball_hits_helmet': 'Ball hit fielding helmet on the ground',
    'illegal_fielding': 'Illegal fielding',
    'damaging_pitch': 'Damaging the pitch',
    'time_wasting': 'Time wasting',
    'unfair_play': 'Unfair play / misconduct',
    'other': 'Other',
  };
  final r = await pickFromList(st.context, title: 'Reason', items: [for (final e in reasons.entries) {'k': e.key, 'v': e.value}], label: (m) => m['v']);
  if (r == null || !st.mounted) return;
  await st.context.api.addPenaltyRuns(st.widget.matchId, awardedToTeamId: team, reasonCode: r['k'], reasonLabel: r['v']);
  await st.reload();
}

Future<void> _bonus(ScoringScreenState st) async {
  final s = st.snap!;
  final team = await _pickTeam(st.context, s, 'Bonus runs to');
  if (team == null || !st.mounted) return;
  final runs = await promptText(st.context, title: 'Bonus runs', keyboard: TextInputType.number);
  final n = int.tryParse(runs ?? '');
  if (n == null || n <= 0 || !st.mounted) return;
  final reason = await promptText(st.context, title: 'Reason', initial: 'Bonus runs');
  if (!st.mounted) return;
  await st.context.api.addBonusRuns(st.widget.matchId, teamId: team, runs: n, reason: reason ?? 'Bonus runs', innings: s.currentInningsNumber);
  await st.reload();
}

Future<List<Map<String, dynamic>>> _benchFor(ScoringScreenState st, String teamId) async {
  final s = st.snap!;
  final inXi = s.xiFor(teamId).map((x) => x['playerId'].toString()).toSet();
  final tid = s.match.tournamentId;
  var rows = await st.context.api.teamPlayers(teamId: teamId, tournamentId: tid.isEmpty ? null : tid);
  if (rows.isEmpty) rows = await st.context.api.teamPlayers(teamId: teamId);
  final seen = <String>{};
  return rows
      .where((r) => !inXi.contains(r['playerId'].toString()) && seen.add(r['playerId'].toString()))
      .map((r) => {'playerId': r['playerId'], 'player': r['player']})
      .toList();
}

Future<void> _impactPlayer(ScoringScreenState st) async {
  final s = st.snap!;
  final team = await _pickTeam(st.context, s, 'Impact player for');
  if (team == null || !st.mounted) return;
  final out = await pickPlayer(st.context, title: 'Player going out', xi: s.xiFor(team));
  if (out == null || !st.mounted) return;
  final bench = await _benchFor(st, team);
  if (!st.mounted) return;
  final inn = await pickPlayer(st.context, title: 'Impact player coming in', xi: bench);
  if (inn == null || !st.mounted) return;
  await st.context.api.registerImpactSub({
    'matchId': st.widget.matchId,
    'teamId': team,
    'inningsNumber': s.currentInningsNumber,
    'outPlayerId': out,
    'inPlayerId': inn,
    'trigger': s.legalBalls == 0 ? 'innings_start' : 'over_end',
  });
  if (st.mounted) st.context.toast('Impact player registered', success: true);
  await st.reload();
}

Future<void> _concussion(ScoringScreenState st) async {
  final s = st.snap!;
  final team = await _pickTeam(st.context, s, 'Concussion replacement for');
  if (team == null || !st.mounted) return;
  final out = await pickPlayer(st.context, title: 'Concussed player', xi: s.xiFor(team));
  if (out == null || !st.mounted) return;
  final bench = await _benchFor(st, team);
  if (!st.mounted) return;
  final sub = await pickPlayer(st.context, title: 'Like-for-like replacement', xi: bench);
  if (sub == null || !st.mounted) return;
  await st.context.api.concussionReplacement({
    'matchId': st.widget.matchId,
    'teamId': team,
    'replacedPlayerId': out,
    'substitutePlayerId': sub,
    'inningsNumber': s.currentInningsNumber,
  });
  await st.reload();
}

Future<void> _bonusTeam(ScoringScreenState st) async {
  final s = st.snap!;
  final r = await pickFromList(st.context, title: 'Bonus point goes to', items: [
    {...s.match.team1.raw, 'k': 'one'},
    {...s.match.team2.raw, 'k': 'one'},
    {'id': 'both', 'name': 'Both teams', 'k': 'both'},
    {'id': 'none', 'name': 'No bonus', 'k': 'none'},
  ], label: (t) => t['name']?.toString() ?? '-');
  if (r == null || !st.mounted) return;
  await st.context.api.setBonusTeam(st.widget.matchId, r['k'] == 'one' ? r['id'].toString() : null, both: r['k'] == 'both');
  if (st.mounted) st.context.toast('Bonus point saved', success: true);
}

/// Reviews remaining per team for an innings (scorerMeta.drsReviews).
String drsSummary(Snapshot s) {
  final total = asInt(s.tournament['drsReviewsPerInnings'], 2);
  final bucket = asMap(asMap(s.match.scorerMeta['drsReviews'])['${s.currentInningsNumber}']);
  String side(String key, TeamRef t) => '${t.shortName} ${asMap(bucket[key]).isEmpty ? total : asInt(asMap(bucket[key])['remaining'])}/$total';
  return 'DRS left: ${side('team1', s.match.team1)} • ${side('team2', s.match.team2)}';
}

Future<void> _drs(ScoringScreenState st) async {
  final s = st.snap!;
  st.context.toast(drsSummary(s));
  final team = await _pickTeam(st.context, s, 'Review taken by');
  if (team == null || !st.mounted) return;
  final r = await pickFromList(st.context, title: 'Outcome', items: const [
    {'k': 'successful', 'v': 'Successful (review retained)'},
    {'k': 'umpires_call', 'v': "Umpire's call (retained)"},
    {'k': 'lost', 'v': 'Unsuccessful (review lost)'},
  ], label: (m) => m['v']);
  if (r == null || !st.mounted) return;
  await st.context.api.recordDrs(st.widget.matchId, {
    'outcome': r['k'],
    'innings': s.currentInningsNumber,
    'teamId': team,
    'teamKey': team == s.match.team1.id ? 'team1' : 'team2',
  });
  if (st.mounted) st.context.toast('Review recorded', success: true);
}

Future<void> _captainWk(ScoringScreenState st) async {
  final s = st.snap!;
  final team = await _pickTeam(st.context, s, 'Team');
  if (team == null || !st.mounted) return;
  final which = await pickFromList(st.context, title: 'Change', items: const [{'k': 'c', 'v': 'Captain'}, {'k': 'wk', 'v': 'Wicket-keeper'}], label: (m) => m['v']);
  if (which == null || !st.mounted) return;
  final p = await pickPlayer(st.context, title: 'New ${which['v']}', xi: s.xiFor(team));
  if (p == null || !st.mounted) return;
  if (which['k'] == 'c') {
    await st.context.api.changeCaptain(st.widget.matchId, team, p);
  } else {
    await st.context.api.changeWk(st.widget.matchId, team, p);
  }
  await st.reload();
}

Future<void> _scoreNote(ScoringScreenState st) async {
  final cur = st.snap!.match.scorerMeta['scoreNote']?.toString() ?? st.snap!.matchRaw['scoreNote']?.toString();
  final v = await promptText(st.context, title: 'Score note', initial: cur, hint: 'e.g. Play delayed due to wet outfield', maxLines: 3);
  if (v == null || !st.mounted) return;
  await st.context.api.saveScoreNote(st.widget.matchId, v);
  if (st.mounted) st.context.toast('Note saved', success: true);
}

Future<void> _scorerAccess(ScoringScreenState st) async {
  final u = TextEditingController(text: 'scorer${st.snap!.match.seq ?? ''}');
  final p = TextEditingController();
  final ok = await showDialog<bool>(
    context: st.context,
    builder: (c) => AlertDialog(
      title: const Text('Scorer access'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Give another scorer temporary access to this match only.', style: TextStyle(color: AppColors.textMid)),
        const SizedBox(height: 12),
        TextField(controller: u, decoration: const InputDecoration(labelText: 'Username')),
        const SizedBox(height: 10),
        TextField(controller: p, decoration: const InputDecoration(labelText: 'Password (min 4)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true || !st.mounted) return;
  final res = await st.context.api.setScorerAccess(st.widget.matchId, u.text.trim(), p.text);
  if (st.mounted) {
    st.context.toast('Scorer access saved (Match #${st.snap!.match.seq ?? ''}, expires ${Fmt.dateTime(asMap(res['scorerAccess'])['expiresAt'])})', success: true);
  }
}

Future<void> _endOutcome(ScoringScreenState st) async {
  final s = st.snap!;
  final r = await pickFromList(st.context, title: 'End match as', items: const [
    {'k': 'abandoned', 'v': 'Abandoned / No result'},
    {'k': 'walkover', 'v': 'Walkover / Forfeit'},
    {'k': 'delayed', 'v': 'Delayed / Stopped (resume later)'},
  ], label: (m) => m['v']);
  if (r == null || !st.mounted) return;
  final note = await promptText(st.context, title: 'Reason / note', maxLines: 2);
  if (!st.mounted) return;
  Map<String, dynamic> body;
  if (r['k'] == 'walkover') {
    final team = await _pickTeam(st.context, s, 'Winning team');
    if (team == null) return;
    body = {'outcome': 'walkover', 'winningTeamId': team, 'winningTeamKey': team == s.match.team1.id ? 'team1' : 'team2', 'mode': 'walkover', 'reasonNote': note};
  } else if (r['k'] == 'abandoned') {
    body = {'outcome': 'abandoned', 'reason': 'abandoned', 'reasonNote': note};
  } else {
    body = {'outcome': 'delayed', 'mode': s.hasStarted ? 'stopped' : 'not_started', 'reasonNote': (note == null || note.isEmpty) ? 'Play delayed' : note};
  }
  if (!st.mounted || !await confirmDialog(st.context, title: 'Confirm: ${r['v']}?', danger: true)) return;
  if (!st.mounted) return;
  final res = await st.context.api.endMatchOutcome(st.widget.matchId, body);
  if (st.mounted) st.context.toast(res['summaryText']?.toString() ?? 'Match updated', success: true);
  await st.reload();
}

Future<void> _lock(ScoringScreenState st) async {
  if (!await confirmDialog(st.context, title: 'Lock scoring?', message: 'No more balls or undo will be allowed for this match.', ok: 'Lock')) return;
  if (!st.mounted) return;
  await st.context.api.setScoringLock(st.widget.matchId, true);
  await st.reload();
}

// ───────────────────────── Innings break & result ─────────────────────────

/// Start the next innings (2nd innings, Test innings 3/4 or Super Over).
Future<void> showInningsBreak(ScoringScreenState st, {bool forced = false}) async {
  final s = st.snap!;
  final m = s.match;
  final cur = s.currentInnings;
  final curNo = s.currentInningsNumber;
  final isTest = Cricket.isTest(s.tournament);
  final superOver = s.isSuperOver;

  if (!isTest && !superOver && curNo >= 2 && !forced) {
    await showMatchResult(st);
    return;
  }
  if ((isTest && curNo >= 4) || (superOver && curNo >= 4 && curNo.isEven && !forced)) {
    await showMatchResult(st);
    return;
  }

  final nextNo = curNo + 1;
  var battingTeam = cur?['battingTeamId']?.toString() == m.team1.id ? m.team2.id : m.team1.id;
  int? target;
  if (!isTest && (nextNo == 2 || (superOver && nextNo.isEven))) {
    target = asInt(cur?['runs']) + 1;
  }
  if (isTest && nextNo == 4) {
    int total(String teamId) => s.innings.where((i) => i['battingTeamId']?.toString() == teamId).fold(0, (a, i) => a + asInt(i['runs']));
    final other = battingTeam == m.team1.id ? m.team2.id : m.team1.id;
    target = total(other) - total(battingTeam) + 1;
  }

  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: st.context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (c) => _NextInningsSheet(snap: s, nextNo: nextNo, battingTeamId: battingTeam, target: target, allowFollowOn: isTest && nextNo == 3),
  );
  if (result == null || !st.mounted) return;
  battingTeam = result['battingTeamId'];
  await st.context.api.startInnings({
    'matchId': st.widget.matchId,
    'battingTeamId': battingTeam,
    'number': nextNo,
    'target': result['target'],
    'strikerId': result['strikerId'],
    'nonStrikerId': result['nonStrikerId'],
    'bowlerId': result['bowlerId'],
  });
  if (st.mounted) st.context.toast('Innings $nextNo started', success: true);
  await st.reload();
}

class _NextInningsSheet extends StatefulWidget {
  const _NextInningsSheet({required this.snap, required this.nextNo, required this.battingTeamId, this.target, this.allowFollowOn = false});
  final Snapshot snap;
  final int nextNo;
  final String battingTeamId;
  final int? target;
  final bool allowFollowOn;
  @override
  State<_NextInningsSheet> createState() => _NextInningsSheetState();
}

class _NextInningsSheetState extends State<_NextInningsSheet> {
  late String batting = widget.battingTeamId;
  late final target = TextEditingController(text: widget.target?.toString() ?? '');
  String? striker;
  String? nonStriker;
  String? bowler;

  @override
  Widget build(BuildContext context) {
    final s = widget.snap;
    final m = s.match;
    final bowling = batting == m.team1.id ? m.team2.id : m.team1.id;
    final batXi = s.xiFor(batting);
    final bowlXi = s.xiFor(bowling);
    final isSo = s.isSuperOver;
    Widget slot(String label, String? id, List<Map<String, dynamic>> xi, ValueChanged<String> set, {String? exclude}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: id == null ? const CircleAvatar(child: Icon(Icons.add)) : PlayerAvatar(name: s.playerName(id), size: 40),
          title: Text(id == null ? 'Select $label' : s.playerName(id), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final r = await pickPlayer(context, title: label, xi: xi, disabled: (x) => x['playerId'].toString() == exclude);
            if (r != null) setState(() => set(r));
          },
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isSo && widget.nextNo >= 3 ? 'Super Over — innings ${widget.nextNo}' : 'Innings ${widget.nextNo}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${m.teamById(batting).name} to bat', style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800)),
          if (widget.allowFollowOn)
            Builder(builder: (_) {
              // Law 14 / Test playing conditions: follow-on available when the side batting first leads by 200+.
              int total(String id) => s.innings.where((i) => i['battingTeamId']?.toString() == id).fold(0, (a, i) => a + asInt(i['runs']));
              final other = widget.battingTeamId == m.team1.id ? m.team2.id : m.team1.id;
              final lead = total(other) - total(widget.battingTeamId);
              final threshold = FormatInfo(s.tournament).followOnThreshold;
              return Text(
                lead >= threshold
                    ? '${m.teamById(other).shortName} lead by $lead — follow-on can be enforced'
                    : '${m.teamById(other).shortName} lead by $lead — follow-on needs $threshold+',
                style: TextStyle(color: lead >= threshold ? AppColors.success : AppColors.textMid, fontSize: 12.5),
              );
            }),
          if (widget.allowFollowOn)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: batting != widget.battingTeamId,
              title: const Text('Follow-on enforced'),
              onChanged: (v) => setState(() {
                batting = v ? (widget.battingTeamId == m.team1.id ? m.team2.id : m.team1.id) : widget.battingTeamId;
                striker = nonStriker = bowler = null;
              }),
            ),
          if (widget.target != null || widget.nextNo == 2) ...[
            const SizedBox(height: 10),
            TextField(controller: target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target', prefixIcon: Icon(Icons.flag_outlined))),
          ],
          const SizedBox(height: 8),
          slot('Striker', striker, batXi, (v) => striker = v, exclude: nonStriker),
          slot('Non-striker', nonStriker, batXi, (v) => nonStriker = v, exclude: striker),
          slot('Opening bowler', bowler, bowlXi, (v) => bowler = v),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: striker == null || nonStriker == null || bowler == null
                ? null
                : () => Navigator.pop(context, {
                      'battingTeamId': batting,
                      'target': int.tryParse(target.text),
                      'strikerId': striker,
                      'nonStrikerId': nonStriker,
                      'bowlerId': bowler,
                    }),
            child: const Text('Start innings'),
          ),
        ]),
      ),
    );
  }
}

Future<void> showMatchResult(ScoringScreenState st) async {
  final s = st.snap!;
  final m = s.match;
  final tie = m.result['resultType']?.toString() == 'tie';
  final superOverAllowed = s.tournament['superOver'] != false && !Cricket.isTest(s.tournament);
  final action = await showDialog<String>(
    context: st.context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.emoji_events, color: Color(0xFFF59E0B), size: 44),
      title: Text(m.resultText.isEmpty ? (m.isCompleted ? 'Match completed' : 'Innings complete') : m.resultText, textAlign: TextAlign.center),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final i in s.innings)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text('${m.teamById(i['battingTeamId']?.toString()).name}${i['isSuperOver'] == true ? ' (SO)' : ''}')),
              Text('${asInt(i['runs'])}/${asInt(i['wickets'])} (${Cricket.oversText(asDouble(i['overs']))})', style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
      ]),
      actions: [
        if (tie && superOverAllowed) TextButton(onPressed: () => Navigator.pop(c, 'so'), child: const Text('Play Super Over')),
        if (tie) TextButton(onPressed: () => Navigator.pop(c, 'tie'), child: const Text('End as tie')),
        if (!m.isCompleted) TextButton(onPressed: () => Navigator.pop(c, 'next'), child: const Text('Start next innings')),
        if (m.isCompleted && !m.scoringLocked) TextButton(onPressed: () => Navigator.pop(c, 'lock'), child: const Text('Lock scoring')),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
      ],
    ),
  );
  if (!st.mounted) return;
  switch (action) {
    case 'so':
      final r = await st.context.api.superOver(st.widget.matchId);
      if (!st.mounted) return;
      st.context.toast('Super Over ${r['superOverRound'] ?? ''} — pick players', success: true);
      await st.reload();
      if (st.mounted) await showInningsBreak(st, forced: true);
    case 'tie':
      await st.context.api.endTie(st.widget.matchId);
      await st.reload();
    case 'next':
      await showInningsBreak(st, forced: true);
    case 'lock':
      await st.context.api.setScoringLock(st.widget.matchId, true);
      await st.reload();
  }
}
