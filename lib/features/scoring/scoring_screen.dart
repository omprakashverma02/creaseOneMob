import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cricket.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../matches/live_widgets.dart';
import '../matches/match_detail_screen.dart';
import '../matches/scorecard_view.dart';
import 'scoring_actions.dart';
import 'scoring_sheets.dart';

/// Ball-by-ball scoring console. The server is authoritative for totals, stats
/// and strike rotation; the console posts deliveries and reacts to the
/// refreshed snapshot (new batter, end of over, end of innings, result).
class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key, required this.matchId, this.scorerOnly = false});
  final String matchId;

  /// Match-scoped scorer login (no access to the rest of the app).
  final bool scorerOnly;
  @override
  State<ScoringScreen> createState() => ScoringScreenState();
}

class ScoringScreenState extends State<ScoringScreen> {
  Snapshot? snap;
  String? error;
  bool busy = false;

  // Crease
  String? strikerId;
  String? nonStrikerId;
  String? bowlerId;

  // Modifiers for the next delivery
  String? extra; // WD | NB | B | LB
  String nbSub = 'bat'; // bat | bye | lb (for NB)
  int overthrow = 0;
  bool wagonEnabled = true;

  /// Balls this console posted (undo is allowed for any ball; this only drives hints).
  int postedThisSession = 0;

  @override
  void initState() {
    super.initState();
    reload(initial: true);
  }

  Map<String, dynamic> get rules => snap?.tournament ?? const {};
  int get wideRuns => asInt(rules['wideRuns'], 1);
  int get noBallRuns => asInt(rules['noBallRuns'], 1);

  Future<void> reload({bool initial = false}) async {
    try {
      final raw = await context.api.snapshot(widget.matchId);
      if (!mounted) return;
      if (raw == null) {
        setState(() => error = 'Match not found');
        return;
      }
      final s = Snapshot(raw);
      final mc = s.metaCrease;
      final lc = s.liveCrease;
      setState(() {
        snap = s;
        error = null;
        strikerId = asStr(mc['strikerId']) ?? asStr(lc['strikerId']);
        nonStrikerId = asStr(mc['nonStrikerId']) ?? asStr(lc['nonStrikerId']);
        bowlerId = asStr(mc['bowlerId']) ?? asStr(lc['bowlerId']);
        if (initial) wagonEnabled = rules['shotSelectionEnabled'] != false;
      });
      if (initial) await _resumeChecks();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  /// When re-opening a match: make sure the crease is complete.
  Future<void> _resumeChecks() async {
    final s = snap!;
    if (s.match.isCompleted || s.currentInningsCompleted) {
      await _handleInningsEnd();
      return;
    }
    final dismissed = _dismissedAtCrease();
    if (dismissed != null) {
      await _promptNewBatter(dismissed, overCompleted: false);
    }
    if (bowlerId == null || (s.ballsInOver == 0 && s.legalBalls > 0 && _lastBallBowler() == bowlerId && s.lastBall.isNotEmpty)) {
      if (bowlerId == null || await _overJustEnded()) await _overEnded();
    }
  }

  String? _lastBallBowler() => snap!.lastBall.isEmpty ? null : snap!.lastBall.last['bowlerId']?.toString();

  Future<bool> _overJustEnded() async {
    final s = snap!;
    if (s.lastBall.isEmpty) return false;
    final last = s.lastBall.last;
    return s.ballsInOver == 0 && asInt(last['overNumber']) == s.completedOvers;
  }

  /// A batter at the crease who is already out (e.g. after a wicket).
  String? _dismissedAtCrease() {
    final s = snap!;
    for (final id in [strikerId, nonStrikerId]) {
      if (id == null) continue;
      final out = s.battingStatFor(id)?['outType']?.toString();
      if (out != null && out.isNotEmpty) return id;
    }
    if (s.lastBall.isNotEmpty) {
      final last = s.lastBall.last;
      if (last['wicket'] == true) {
        final d = (last['dismissedPlayerId'] ?? last['strikerId'])?.toString();
        if (d != null && (d == strikerId || d == nonStrikerId)) return d;
      }
    }
    return null;
  }

  // ───────────────────────── Delivery ─────────────────────────

  Future<void> score(int runs, {WicketInfo? wicket}) async {
    final s = snap;
    if (s == null || busy) return;
    if (s.match.scoringLocked) {
      context.toast('Scoring is locked for this match', error: true);
      return;
    }
    if (strikerId == null || nonStrikerId == null) {
      context.toast('Select both batters first', error: true);
      return;
    }
    if (bowlerId == null) {
      await _promptBowler();
      if (bowlerId == null) return;
    }
    if (extra == 'NB' && runs > 0 && nbSub == 'bat' && wicket == null) {
      // fine — runs off the bat on a no-ball
    }
    final isWide = extra == 'WD';
    final isNb = extra == 'NB';
    final isBye = extra == 'B' || (isNb && nbSub == 'bye');
    final isLb = extra == 'LB' || (isNb && nbSub == 'lb');
    final running = wicket != null && Cricket.isRunOut(wicket.type) ? wicket.runs : runs;

    int batRuns = 0;
    int extraRuns = 0;
    if (isWide) {
      extraRuns = wideRuns + running;
    } else if (isNb) {
      if (isBye || isLb) {
        extraRuns = noBallRuns + running;
      } else {
        extraRuns = noBallRuns;
        batRuns = running;
      }
    } else if (isBye || isLb) {
      extraRuns = running;
    } else {
      batRuns = running;
    }

    final retirement = wicket != null && Cricket.isRetirement(wicket.type);
    final wideLegal = isWide && rules['wideCountsAsLegalBall'] == true;
    final nbLegal = isNb && rules['noBallCountsAsLegalBall'] == true;
    final legal = ((!isWide && !isNb) || wideLegal || nbLegal) && !(retirement && !wicket.countBall);
    final overCompletes = legal && s.ballsInOver + 1 >= s.bpo;

    final payload = <String, dynamic>{
      'matchId': widget.matchId,
      'innings': s.currentInningsNumber,
      'overNumber': s.completedOvers + 1,
      'ballNumber': s.ballsInOver + 1,
      'strikerId': strikerId,
      'nonStrikerId': nonStrikerId,
      'bowlerId': bowlerId,
      'batRuns': batRuns,
      'extraRuns': extraRuns,
      'overthrowRuns': overthrow,
      'wicket': wicket != null,
      'isLegal': legal,
      if (isWide) 'extraType': 'WD' else if (isNb) 'extraType': 'NB' else if (isBye) 'extraType': 'B' else if (isLb) 'extraType': 'LB',
      if (isBye) 'Byes': running,
      if (isLb) 'LegByes': running,
      if (wicket != null) ...{
        'wicketType': wicket.type,
        'dismissedPlayerId': wicket.dismissedId,
        if (wicket.fielderIds.isNotEmpty) 'fielderId': wicket.fielderIds.first,
        if (wicket.type == 'run out' && wicket.fielderIds.isNotEmpty) ...{
          'runOutFielderIds': wicket.fielderIds,
          'fielderNames': wicket.fielderNames,
        },
      },
    };

    setState(() => busy = true);
    HapticFeedback.lightImpact();
    String? ballId;
    try {
      final created = await context.api.postBall(payload);
      ballId = created['id']?.toString();
      postedThisSession++;
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        context.toast(e.toString(), error: true);
      }
      return;
    }
    final strikerName = s.playerName(strikerId);
    final strikerHand = s.playerById(strikerId)['battingStyle']?.toString();
    final wasFreeHit = freeHit;
    _resetModifiers();
    await reload();
    if (!mounted) return;
    setState(() => busy = false);

    // Celebration flash (web OnlineMobileScorePanel FOUR / SIX / WICKET).
    if (wicket != null && !Cricket.isRetirement(wicket.type)) {
      _flashFor('WICKET!', AppColors.wicket);
    } else if (batRuns == 6) {
      _flashFor('SIX!', AppColors.six);
    } else if (batRuns == 4) {
      _flashFor('FOUR!', AppColors.four);
    } else if (isNb && fmt.hasFreeHit) {
      _flashFor('FREE HIT NEXT', AppColors.extra);
    } else if (wasFreeHit && legal) {
      // free hit consumed
    }

    // Wagon wheel capture for scoring shots off the bat.
    if (wagonEnabled && batRuns > 0 && wicket == null) {
      final shot = await showWagonPicker(context, runs: batRuns, batter: strikerName, hand: strikerHand);
      if (shot != null && mounted) {
        context.api
            .updateBallWagon({
              'matchId': widget.matchId,
              if (ballId != null) 'ballId': ballId,
              'innings': s.currentInningsNumber,
              'wagonAngle': shot.angle,
              'wagonDistance': shot.distance,
              if (shot.shotName != null) 'shotName': shot.shotName,
              'batsmanName': strikerName,
            })
            .catchError((_) {});
      }
    }
    if (!mounted) return;
    await afterDelivery(wicket: wicket, overCompleted: overCompletes);
  }

  // ───────────────────────── Format rules ─────────────────────────

  FormatInfo get fmt => FormatInfo(rules);

  bool get isSuperOverInnings => (snap?.isSuperOver ?? false) && (snap?.currentInningsNumber ?? 0) >= 3 && !fmt.isTest;

  /// ICC 21.19: the delivery after a no-ball is a free hit (carries over wides / further no-balls).
  bool get freeHit {
    final s = snap;
    if (s == null || !fmt.hasFreeHit || s.currentInningsCompleted) return false;
    for (final b in s.lastBall.reversed) {
      final ex = (b['extraType'] ?? '').toString().toUpperCase();
      if (ex == 'WD') continue;
      return ex == 'NB';
    }
    return false;
  }

  String? flash;
  Color flashColor = AppColors.primary;
  Timer? _flashTimer;

  void _flashFor(String text, Color color) {
    _flashTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      flash = text;
      flashColor = color;
    });
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => flash = null);
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  /// Super Over: bowlers who already bowled, and batters already dismissed, in an earlier SO round are ineligible.
  Future<(Set<String>, Set<String>)> _superOverExclusions() async {
    if (!isSuperOverInnings) return (<String>{}, <String>{});
    try {
      final balls = await context.api.balls(widget.matchId);
      final cur = snap!.currentInningsNumber;
      final bowlers = <String>{};
      final dismissed = <String>{};
      for (final b in balls) {
        final inn = asInt(b['innings']);
        if (inn < 3) continue;
        if (inn != cur) bowlers.add(b['bowlerId'].toString());
        if (b['wicket'] == true && b['dismissedPlayerId'] != null) dismissed.add(b['dismissedPlayerId'].toString());
      }
      return (bowlers, dismissed);
    } catch (_) {
      return (<String>{}, <String>{});
    }
  }

  /// Ask for the batting hand when a batter has none (drives wagon-wheel mirroring), like the web prompt.
  Future<void> ensureBattingHand(String? playerId) async {
    if (playerId == null || !mounted) return;
    final p = snap!.playerById(playerId);
    final hand = p['battingStyle']?.toString() ?? '';
    if (hand == 'RHB' || hand == 'LHB') return;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${p['name'] ?? 'Batter'} bats'),
        content: const Text('Needed for the wagon wheel (off / leg side).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'LHB'), child: const Text('Left-handed')),
          FilledButton(onPressed: () => Navigator.pop(c, 'RHB'), child: const Text('Right-handed')),
        ],
      ),
    );
    if (r == null || !mounted) return;
    try {
      await context.api.updatePlayer(playerId, {'battingStyle': r});
      await reload();
    } catch (_) {}
  }

  /// End of an over / set: balls formats may keep the same bowler for a 10-ball stint at the same end.
  Future<void> _overEnded() async {
    final s = snap!;
    final f = fmt;
    final completedSet = s.completedOvers;
    if (f.setsPerChangeOfEnds > 1 && !f.endsChangeAfterSet(completedSet) && bowlerId != null) {
      final quota = Cricket.maxBallsPerBowler(s.tournament, s.scheduledOvers, superOver: isSuperOverInnings);
      final bowled = Cricket.oversToBalls(asDouble(s.bowlingStatFor(bowlerId)?['overs']), s.bpo);
      final canContinue = quota == null || bowled + s.bpo <= quota;
      if (canContinue) {
        final keep = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: Text('Set $completedSet complete'),
            content: Text('Ends do not change yet. ${s.playerName(bowlerId)} can bowl the next set from the same end '
                '(${f.stintOptions.last}-ball stint), or bring on a new bowler at this end.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('New bowler')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue stint')),
            ],
          ),
        );
        if (keep == true) {
          await _maybeOptionalPowerplay();
          return;
        }
      }
    }
    await _promptBowler(previous: bowlerId);
    await _maybeOptionalPowerplay();
  }

  /// Offer the optional batting / bowling powerplay when its take-window opens (web optionalPowerplay.ts).
  Future<void> _maybeOptionalPowerplay() async {
    final s = snap;
    if (s == null || !mounted) return;
    final p = findOptionalPpPrompt(
      match: s.matchRaw,
      tournament: s.tournament,
      scheduledOvers: s.scheduledOvers,
      legalBalls: s.legalBalls,
      innings: s.currentInningsNumber,
      superOver: isSuperOverInnings,
    );
    if (p == null) return;
    final take = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Take ${p.kind}?'),
        content: Text('Window open: ${p.unit} ${p.start}–${p.end}. Take it now, or keep it for later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Take powerplay')),
        ],
      ),
    );
    if (take == null || !mounted) return;
    try {
      await context.api.persistOptionalPowerplay(widget.matchId, {
        'innings': s.currentInningsNumber,
        'slot': p.slot,
        if (take) 'taken': {'from': p.start, 'to': p.end} else 'declinedUntil': p.start,
      });
      await reload();
      if (take && mounted) context.toast('${p.kind} taken (${p.unit} ${p.start}–${p.end})', success: true);
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  void _resetModifiers() {
    extra = null;
    nbSub = 'bat';
    overthrow = 0;
  }

  Future<void> afterDelivery({WicketInfo? wicket, bool overCompleted = false}) async {
    final s = snap!;
    if (s.match.isCompleted || s.currentInningsCompleted) {
      await _handleInningsEnd();
      return;
    }
    final endsChanged = overCompleted && fmt.endsChangeAfterSet(s.completedOvers);
    if (wicket != null) {
      final d = wicket.dismissedId;
      if (d == strikerId || d == nonStrikerId) {
        await _promptNewBatter(d, overCompleted: endsChanged);
      }
    }
    if (overCompleted) {
      await _overEnded();
    }
  }

  Future<void> _persistCrease() async {
    try {
      await context.api.persistCrease(widget.matchId,
          innings: snap!.currentInningsNumber, strikerId: strikerId, nonStrikerId: nonStrikerId, bowlerId: bowlerId);
    } catch (e) {
      if (mounted) context.toast('Could not save crease: $e', error: true);
    }
  }

  /// Batters still available to come in.
  List<Map<String, dynamic>> availableBatters({Set<String> exclude = const {}}) {
    final s = snap!;
    return s.xiFor(s.battingTeamId).where((x) {
      final id = x['playerId'].toString();
      if (exclude.contains(id) || id == strikerId || id == nonStrikerId) return false;
      final out = s.battingStatFor(id)?['outType']?.toString().toLowerCase();
      return out == null || out.isEmpty || out.contains('retired hurt') || out == 'retired';
    }).toList();
  }

  Future<void> _promptNewBatter(String dismissedId, {required bool overCompleted}) async {
    final s = snap!;
    final survivor = dismissedId == strikerId ? nonStrikerId : strikerId;
    final so = await _superOverExclusions();
    if (!mounted) return;
    final options = availableBatters(exclude: {dismissedId, ...so.$2});
    if (options.isEmpty) {
      context.toast('No batters left — end the innings from the menu');
      return;
    }
    final id = await pickPlayer(
      context,
      title: 'New batter (replacing ${s.playerName(dismissedId)})',
      xi: options,
      subtitle: (x) {
        final st = s.battingStatFor(x['playerId'].toString());
        return st == null ? Cricket.roleLabel(asMap(x['player'])['role']?.toString()) : 'Retired • ${asInt(st['runs'])} (${asInt(st['balls'])})';
      },
    );
    if (id == null || !mounted) return;
    // New batter takes the dismissed batter's end; ends swap if the over just finished.
    var newStrikerFacing = dismissedId == strikerId;
    if (overCompleted) newStrikerFacing = !newStrikerFacing;
    final onStrike = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Who faces the next ball?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(newStrikerFacing ? Icons.radio_button_checked : Icons.radio_button_off, color: AppColors.cyan),
            title: Text(s.playerName(id)),
            subtitle: const Text('New batter'),
            onTap: () => Navigator.pop(c, true),
          ),
          ListTile(
            leading: Icon(!newStrikerFacing ? Icons.radio_button_checked : Icons.radio_button_off, color: AppColors.cyan),
            title: Text(s.playerName(survivor)),
            onTap: () => Navigator.pop(c, false),
          ),
        ]),
      ),
    );
    final newFaces = onStrike ?? newStrikerFacing;
    setState(() {
      strikerId = newFaces ? id : survivor;
      nonStrikerId = newFaces ? survivor : id;
    });
    await _persistCrease();
    await reload();
    await ensureBattingHand(id);
  }

  Future<void> _promptBowler({String? previous}) async {
    final s = snap!;
    final quota = Cricket.maxBallsPerBowler(s.tournament, s.scheduledOvers, superOver: isSuperOverInnings);
    final bpo = s.bpo;
    final so = await _superOverExclusions();
    if (!mounted) return;
    final id = await pickPlayer(
      context,
      title: previous == null ? 'Select bowler' : (fmt.setsPerChangeOfEnds > 1 ? 'Next set — select bowler' : 'Next over — select bowler'),
      xi: s.xiFor(s.bowlingTeamId),
      subtitle: (x) {
        final st = s.bowlingStatFor(x['playerId'].toString());
        final balls = Cricket.oversToBalls(asDouble(st?['overs']), bpo);
        final fig = st == null ? 'Yet to bowl' : '${Cricket.oversText(asDouble(st['overs']))}-${asInt(st['maidens'])}-${asInt(st['runsConceded'])}-${asInt(st['wickets'])}';
        final left = quota == null ? '' : ' • ${Cricket.ballsToOvers((quota - balls).clamp(0, quota), bpo)} ov left';
        final soNote = so.$1.contains(x['playerId'].toString()) ? 'Bowled an earlier Super Over • ' : '';
        return '$soNote${x['playerId'].toString() == previous ? 'Bowled last over • ' : ''}$fig$left';
      },
      disabled: (x) {
        final id = x['playerId'].toString();
        if (previous != null && id == previous) return true;
        if (so.$1.contains(id)) return true;
        if (quota == null) return false;
        final st = s.bowlingStatFor(id);
        return Cricket.oversToBalls(asDouble(st?['overs']), bpo) >= quota;
      },
    );
    if (id == null || !mounted) return;
    setState(() => bowlerId = id);
    await _persistCrease();
    await reload();
  }

  Future<void> changeBowlerMidOver() async {
    final s = snap!;
    final id = await pickPlayer(context, title: 'Change bowler (rest of this over)', xi: s.xiFor(s.bowlingTeamId), disabled: (x) => x['playerId'].toString() == bowlerId);
    if (id == null || !mounted) return;
    try {
      if (s.ballsInOver > 0) {
        await context.api.changeBowler(widget.matchId, fromPlayerId: bowlerId, toPlayerId: id, innings: s.currentInningsNumber, scope: 'current_over');
      }
      setState(() => bowlerId = id);
      await _persistCrease();
      await reload();
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  Future<void> pickStriker({required bool striker}) async {
    final s = snap!;
    final current = striker ? strikerId : nonStrikerId;
    final id = await pickPlayer(
      context,
      title: striker ? 'Select striker' : 'Select non-striker',
      xi: [
        ...s.xiFor(s.battingTeamId).where((x) => x['playerId'].toString() == current || x['playerId'].toString() == (striker ? nonStrikerId : strikerId)),
        ...availableBatters(),
      ],
    );
    if (id == null || !mounted) return;
    setState(() {
      if (id == (striker ? nonStrikerId : strikerId)) {
        // Selecting the other batter swaps ends.
        final t = strikerId;
        strikerId = nonStrikerId;
        nonStrikerId = t;
      } else if (striker) {
        strikerId = id;
      } else {
        nonStrikerId = id;
      }
    });
    await _persistCrease();
    await reload();
    await ensureBattingHand(id);
  }

  Future<void> swapStrike() async {
    setState(() {
      final t = strikerId;
      strikerId = nonStrikerId;
      nonStrikerId = t;
    });
    HapticFeedback.selectionClick();
    await _persistCrease();
  }

  Future<void> undo() async {
    final s = snap;
    if (s == null || s.lastBall.isEmpty && s.legalBalls == 0) {
      context.toast('Nothing to undo');
      return;
    }
    if (s.match.scoringLocked) return;
    if (!await confirmDialog(context, title: 'Undo last ball?', ok: 'Undo')) return;
    setState(() => busy = true);
    try {
      await context.api.undoBall(widget.matchId, innings: s.currentInningsNumber);
      await reload();
      if (mounted) context.toast('Last ball removed', success: true);
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> wicketTapped() async {
    final s = snap!;
    if (strikerId == null || nonStrikerId == null || bowlerId == null) {
      context.toast('Complete the crease first', error: true);
      return;
    }
    final w = await showWicketSheet(context, snap: s, strikerId: strikerId!, nonStrikerId: nonStrikerId!, bowlerId: bowlerId!, extraType: extra, freeHit: freeHit);
    if (w == null) return;
    await score(0, wicket: w);
  }

  // ───────────────────────── Innings / match end ─────────────────────────

  Future<void> _handleInningsEnd() async {
    final s = snap!;
    if (s.match.isCompleted) {
      await showMatchResult(this);
      return;
    }
    await showInningsBreak(this);
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = snap;
    return PopScope(
      canPop: !widget.scorerOnly,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.scorerOnly,
          titleSpacing: widget.scorerOnly ? 16 : 0,
          title: s == null
              ? const Text('Scoring')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.match.team1.shortName} vs ${s.match.team2.shortName}'),
                  Text(
                    [if (s.match.seq != null) 'Match #${s.match.seq}', '${s.match.overs} ov', if (s.isSuperOver) 'SUPER OVER'].join(' • '),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMid, fontWeight: FontWeight.w600),
                  ),
                ]),
          actions: [
            IconButton(
              tooltip: 'Scorecard',
              icon: const Icon(Icons.list_alt_rounded),
              onPressed: s == null
                  ? null
                  : () => context.push(Scaffold(appBar: AppBar(title: const Text('Scorecard')), body: ScorecardView(snap: s))),
            ),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: () => reload()),
            if (s != null) IconButton(tooltip: 'More', icon: const Icon(Icons.more_vert), onPressed: () => showScoringMenu(this)),
          ],
        ),
        body: s == null
            ? (error != null ? ErrorView(message: error!, onRetry: () => reload(initial: true)) : const LoadingView(label: 'Loading match…'))
            : Stack(children: [
                _body(s),
                if (busy)
                  const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
                if (flash != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(flash),
                          tween: Tween(begin: 0.4, end: 1),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.elasticOut,
                          builder: (c, v, child) => Transform.scale(scale: v, child: child),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
                            decoration: BoxDecoration(
                              color: flashColor,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: flashColor.withValues(alpha: 0.6), blurRadius: 40, spreadRadius: 4)],
                            ),
                            child: Text(flash!, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }

  Widget _body(Snapshot s) {
    final ended = s.match.isCompleted || s.currentInningsCompleted;
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), children: [
            LiveScoreHeader(snap: s, compact: true),
            const SizedBox(height: 8),
            CreasePanel(
              snap: s,
              strikerId: strikerId,
              nonStrikerId: nonStrikerId,
              bowlerId: bowlerId,
              onTapStriker: ended ? null : () => pickStriker(striker: true),
              onTapNonStriker: ended ? null : () => pickStriker(striker: false),
              onTapBowler: ended ? null : changeBowlerMidOver,
            ),
            const SizedBox(height: 8),
            ThisOverStrip(snap: s),
            if (s.tournament['drsEnabled'] == true && !ended)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(child: Pill(drsSummary(s), color: AppColors.cyan, icon: Icons.tv_rounded)),
              ),
            if (asStr(s.match.scorerMeta['scoreNote']) != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('📝 ${s.match.scorerMeta['scoreNote']}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
              ),
            if (ended) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _handleInningsEnd,
                icon: Icon(s.match.isCompleted ? Icons.emoji_events : Icons.play_arrow_rounded),
                label: Text(s.match.isCompleted ? 'View result' : 'Start next innings'),
              ),
              if (s.match.isCompleted && !widget.scorerOnly) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: widget.matchId))),
                  child: const Text('Open match centre'),
                ),
              ],
            ],
          ]),
        ),
      ),
      if (!ended && freeHit)
        Container(
          width: double.infinity,
          color: AppColors.extra,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: const Text('FREE HIT — batter can only be out run out, obstructing the field or hitting the ball twice',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      if (!ended) _pad(s),
    ]);
  }

  Widget _pad(Snapshot s) {
    Widget mod(String key, String label) {
      final sel = extra == key;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: sel ? AppColors.extra : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => extra = sel ? null : key),
              child: SizedBox(
                height: 40,
                child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: sel ? Colors.black : AppColors.textHi))),
              ),
            ),
          ),
        ),
      );
    }

    Widget key(String label, {Color? color, Color? fg, VoidCallback? onTap, int flex = 1, double fontSize = 24}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Material(
              color: color ?? AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: busy ? null : onTap,
                child: Container(
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                  child: Text(label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: fg ?? AppColors.textHi)),
                ),
              ),
            ),
          ),
        );

    final hint = switch (extra) {
      'WD' => 'Wide (+$wideRuns): tap runs taken (0 = just the wide)',
      'NB' => 'No-ball (+$noBallRuns): tap runs ${nbSub == 'bat' ? 'off the bat' : nbSub == 'bye' ? 'as byes' : 'as leg byes'}',
      'B' => 'Byes: tap runs taken',
      'LB' => 'Leg byes: tap runs taken',
      _ => null,
    };

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [mod('WD', 'WIDE'), mod('NB', 'NO BALL'), mod('B', 'BYE'), mod('LB', 'LEG BYE')]),
          if (extra == 'NB')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'bat', label: Text('Off bat')), ButtonSegment(value: 'bye', label: Text('Byes')), ButtonSegment(value: 'lb', label: Text('Leg byes'))],
                selected: {nbSub},
                onSelectionChanged: (v) => setState(() => nbSub = v.first),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(hint ?? (overthrow > 0 ? '+$overthrow overthrow(s) on next ball' : 'Tap runs to record the delivery'),
                    style: TextStyle(fontSize: 12, color: hint != null || overthrow > 0 ? AppColors.extra : AppColors.textLo, fontWeight: FontWeight.w700)),
              ),
              InkWell(
                onTap: () => setState(() => overthrow = (overthrow + 1) % 7),
                onLongPress: () => setState(() => overthrow = 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Pill(overthrow > 0 ? 'OT +$overthrow' : 'OVERTHROW', color: overthrow > 0 ? AppColors.extra : AppColors.textMid),
                ),
              ),
              InkWell(
                onTap: () => setState(() => wagonEnabled = !wagonEnabled),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Pill('WAGON', color: wagonEnabled ? AppColors.success : AppColors.textLo, icon: wagonEnabled ? Icons.check : Icons.close),
                ),
              ),
            ]),
          ),
          Row(children: [
            key('0', color: AppColors.surfaceHigh, onTap: () => score(0)),
            key('1', onTap: () => score(1)),
            key('2', onTap: () => score(2)),
            key('3', onTap: () => score(3)),
          ]),
          Row(children: [
            key('4', color: AppColors.four, fg: Colors.white, onTap: () => score(4)),
            key('6', color: AppColors.six, fg: Colors.white, onTap: () => score(6)),
            key('5', onTap: () => score(5), fontSize: 20),
            key('…', onTap: _customRuns, fontSize: 20),
          ]),
          Row(children: [
            key('OUT', color: AppColors.wicket, fg: Colors.white, onTap: wicketTapped, flex: 2, fontSize: 20),
            key('⇄', onTap: swapStrike, fontSize: 22),
            key('UNDO', color: AppColors.surfaceHigh, fg: AppColors.warning, onTap: undo, fontSize: 15),
          ]),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Future<void> _customRuns() async {
    final v = await promptText(context, title: 'Runs (e.g. 7 for 3 + 4 overthrows)', keyboard: TextInputType.number);
    final n = int.tryParse(v ?? '');
    if (n != null && n >= 0 && n <= 12) await score(n);
  }
}
