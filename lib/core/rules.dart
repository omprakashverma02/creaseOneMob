import 'dart:math' as math;

import 'cricket.dart';
import 'dls_table.dart';

/// Format-specific rule engines ported from the web (`matchRules.ts`,
/// `optionalPowerplay.ts`, `dlsCalculator.ts`, `vjdCalculator.ts`,
/// `nrrAnalyzer.ts`, `fieldingAreas.ts`, `wagonWheelShots.ts`).

// ───────────────────────── Format detection ─────────────────────────

class FormatInfo {
  FormatInfo(this.tournament);
  final Map<String, dynamic> tournament;

  String get type => (tournament['type'] ?? 'T20').toString();
  String get oversFormat => (tournament['oversFormat'] ?? '').toString();
  int get bpo => Cricket.ballsPerOver(tournament);
  bool get isTest => type.toUpperCase() == 'TEST';
  bool get isBox => type == 'Box';
  bool get isBallCentric => type == 'Hundred' || type == 'Balls' || Cricket.ballsBasedFormats.contains(oversFormat);

  /// Free hit follows a no-ball in limited-overs cricket (ICC 21.19). Not in Tests.
  bool get hasFreeHit => !isTest;

  /// Sets bowled from one end before ends (and strike) change. Balls formats: 2 sets; otherwise every over.
  int get setsPerChangeOfEnds {
    if (type == 'Balls' || Cricket.ballsBasedFormats.contains(oversFormat)) return 2;
    if (type == 'Hundred' && bpo <= 5) return 2;
    return 1;
  }

  /// Consecutive-ball stint options for balls formats (ECB: 5 or 10 in a row).
  List<int> get stintOptions {
    switch (oversFormat) {
      case 'The Sixty':
      case 'The Ninty':
        return [6, 12];
      default:
        return [5, 10];
    }
  }

  bool endsChangeAfterSet(int completedSetNumber) => completedSetNumber > 0 && completedSetNumber % setsPerChangeOfEnds == 0;

  String get rateLabel => isBallCentric ? 'RPB' : 'RR';

  /// Run rate (per over) or runs-per-ball for ball-centric formats (as the web shows).
  String runRate(int runs, int legalBalls) {
    if (legalBalls <= 0) return isBallCentric ? '0.00' : '0.00';
    return isBallCentric ? (runs / legalBalls).toStringAsFixed(2) : ((runs / legalBalls) * bpo).toStringAsFixed(2);
  }

  String requiredRate(int need, int ballsLeft) {
    if (ballsLeft <= 0) return need > 0 ? '99.99' : '0.00';
    return isBallCentric ? (need / ballsLeft).toStringAsFixed(2) : ((need / ballsLeft) * bpo).toStringAsFixed(2);
  }

  /// Follow-on can be enforced when the side batting second trails by this many (Tests).
  int get followOnThreshold => isTest ? 200 : 0;
}

// ───────────────────────── Powerplay ─────────────────────────

class PpRange {
  const PpRange(this.from, this.to);
  final double from;
  final double to;
  bool get isSet => to > 0 && to >= from;
  static const none = PpRange(0, 0);
}

class PowerplayRanges {
  const PowerplayRanges(this.p1, this.p2, this.p3);
  final PpRange p1;
  final PpRange p2;
  final PpRange p3;
}

class Powerplay {
  Powerplay._();

  static int t20P1End(int overs) => math.max(1, (0.3 * overs).round());

  static PowerplayRanges odiRanges(int overs) {
    if (overs <= 0) return const PowerplayRanges(PpRange.none, PpRange.none, PpRange.none);
    final ratio = overs / 50;
    final p1End = math.max(1, (10 * ratio).round());
    final p3Start = math.max(p1End + 2, (41 * ratio).round());
    return PowerplayRanges(PpRange(0.1, p1End.toDouble()), PpRange(p1End + 1, p3Start - 1), PpRange(p3Start.toDouble(), overs.toDouble()));
  }

  static const _ppBallsByFormat = {'The Fifty': 15, 'The Sixty': 18, 'The Ninty': 24, 'The Hundred': 25};
  static const _totalBallsByFormat = {'The Fifty': 50, 'The Sixty': 60, 'The Ninty': 90, 'The Hundred': 100};

  /// Default ranges per format (web `defaultPowerplayRanges`). Balls formats use ball numbers.
  static PowerplayRanges defaults(Map<String, dynamic> tournament, int scheduledOvers) {
    final f = FormatInfo(tournament);
    final type = f.type;
    if (f.isBallCentric) {
      final total = _totalBallsByFormat[f.oversFormat] ?? scheduledOvers * f.bpo;
      final pp = _ppBallsByFormat[f.oversFormat] ?? (type == 'Hundred' ? 25 : 15);
      final innBalls = math.max(1, scheduledOvers * f.bpo);
      final ppBalls = innBalls < total ? math.max(1, (pp * innBalls / total).round()) : pp;
      return PowerplayRanges(PpRange(1, ppBalls.toDouble()), PpRange.none, PpRange.none);
    }
    if (f.isTest) return const PowerplayRanges(PpRange.none, PpRange.none, PpRange.none);
    if (type == 'Box') {
      return PowerplayRanges(PpRange(0.1, math.max(1, (scheduledOvers * 0.33).round()).toDouble()), PpRange.none, PpRange.none);
    }
    // T20 / Custom ≤ 20 overs → single mandatory PP (30%); ODI-style (> 20 overs) → 3 phases.
    if (type == 'ODI' || scheduledOvers > 20) return odiRanges(scheduledOvers);
    return PowerplayRanges(PpRange(0.1, t20P1End(scheduledOvers).toDouble()), PpRange.none, PpRange.none);
  }

  /// Uses mandatory P1 + optional batting / bowling powerplays (BTPP / BWPP).
  static bool usesOptional(Map<String, dynamic> tournament, int scheduledOvers) {
    final type = FormatInfo(tournament).type;
    return (type == 'T20' || type == 'Balls' || type == 'Hundred' || type == 'Box' || type == 'Custom') && scheduledOvers <= 20;
  }

  /// Legal-ball window [start, endExclusive) for a range.
  static (int, int)? window(PpRange r, FormatInfo f) {
    if (!r.isSet) return null;
    final bpo = f.bpo;
    if (f.isBallCentric) {
      // Ball-number ranges (e.g. 1–25) when larger than the set count.
      if (r.to > 20) return ((r.from - 1).round().clamp(0, 9999), r.to.round());
      return (((r.from - 1) * bpo).round().clamp(0, 9999), (r.to * bpo).round());
    }
    int mark(double v, bool isFrom) {
      final over = v.floor();
      final ball = ((v - over) * 10).round();
      if (over == 0) return isFrom ? math.max(0, ball - 1) : ball;
      if (ball == 0) return isFrom ? (over - 1) * bpo : over * bpo;
      return isFrom ? over * bpo + ball - 1 : over * bpo + ball;
    }

    return (mark(r.from, true), mark(r.to, false));
  }

  /// Active powerplay label for the next legal ball, or null.
  static String? activeLabel(PowerplayRanges r, FormatInfo f, int legalBalls, {bool superOver = false, Map<String, dynamic>? taken}) {
    if (superOver) return null;
    bool inR(PpRange x) {
      final w = window(x, f);
      return w != null && legalBalls >= w.$1 && legalBalls < w.$2;
    }

    final odi = f.type == 'ODI' || !usesOptional(f.tournament, 99);
    if (inR(r.p1)) return odi ? 'P1' : 'POWERPLAY';
    final t = taken ?? const {};
    PpRange fromTaken(String k) {
      final m = asMap(t[k]);
      return m.isEmpty ? PpRange.none : PpRange(asDouble(m['from']), asDouble(m['to']));
    }

    final p2 = t.isNotEmpty ? fromTaken('p2') : r.p2;
    final p3 = t.isNotEmpty ? fromTaken('p3') : r.p3;
    if (inR(p2)) return odi ? 'P2' : 'BTPP';
    if (inR(p3)) return odi ? 'P3' : 'BWPP';
    return null;
  }

  static PowerplayRanges fromMatch(Map<String, dynamic> match, Map<String, dynamic> tournament, int scheduledOvers) {
    PpRange rr(String a, String b) => PpRange(asDouble(match[a]), asDouble(match[b]));
    final db = PowerplayRanges(rr('powerplay1From', 'powerplay1To'), rr('powerplay2From', 'powerplay2To'), rr('powerplay3From', 'powerplay3To'));
    final d = defaults(tournament, scheduledOvers);
    return PowerplayRanges(db.p1.isSet ? db.p1 : d.p1, db.p2.isSet ? db.p2 : d.p2, db.p3.isSet ? db.p3 : d.p3);
  }
}

/// Optional (take-window) powerplay prompt, web `findOptionalPpPrompt`.
class OptionalPpPrompt {
  OptionalPpPrompt({required this.slot, required this.start, required this.end, required this.unit});
  final String slot; // p2 | p3
  final int start;
  final int end;
  final String unit; // overs | balls
  String get kind => slot == 'p2' ? 'Batting powerplay (BTPP)' : 'Bowling powerplay (BWPP)';
}

OptionalPpPrompt? findOptionalPpPrompt({
  required Map<String, dynamic> match,
  required Map<String, dynamic> tournament,
  required int scheduledOvers,
  required int legalBalls,
  required int innings,
  bool superOver = false,
}) {
  if (superOver || !Powerplay.usesOptional(tournament, scheduledOvers)) return null;
  final f = FormatInfo(tournament);
  final windows = {
    'p2': PpRange(asDouble(match['powerplay2From']), asDouble(match['powerplay2To'])),
    'p3': PpRange(asDouble(match['powerplay3From']), asDouble(match['powerplay3To'])),
  };
  final durations = {'p2': asInt(match['powerplay2Duration']), 'p3': asInt(match['powerplay3Duration'])};
  final takenAll = asMap(asMap(match['scorerMeta'])['powerplayOptional']);
  final taken = asMap(takenAll['$innings']);
  final bpo = f.bpo;
  for (final slot in ['p2', 'p3']) {
    final w = windows[slot]!;
    final dur = durations[slot]!;
    if (!w.isSet || dur <= 0) continue;
    if (asMap(taken[slot]).isNotEmpty) continue;
    final declined = asInt(taken[slot == 'p2' ? 'declinedP2Until' : 'declinedP3Until']);
    if (f.isBallCentric) {
      final next = legalBalls + 1;
      if (next < w.from || next > w.to - dur + 1) continue;
      if (declined > 0 && next <= declined) continue;
      return OptionalPpPrompt(slot: slot, start: next, end: next + dur - 1, unit: 'balls');
    }
    if (legalBalls % bpo != 0) continue;
    final nextOver = legalBalls ~/ bpo + 1;
    final fromOver = w.from.floor();
    final toOver = w.to.floor();
    if (nextOver < fromOver || nextOver > toOver - dur + 1) continue;
    if (declined > 0 && nextOver <= declined) continue;
    return OptionalPpPrompt(slot: slot, start: nextOver, end: nextOver + dur - 1, unit: 'overs');
  }
  return null;
}

// ───────────────────────── Rain rules: DLS & VJD ─────────────────────────

class RainTarget {
  RainTarget({required this.method, required this.target, required this.par, required this.formula, this.r1, this.r2});
  final String method;
  final int target;
  final int par;
  final String formula;
  final double? r1;
  final double? r2;
}

class Dls {
  Dls._();

  static double resource(double oversLeft, int wicketsLost) {
    final o = oversLeft.clamp(0, 50).toDouble();
    final w = wicketsLost.clamp(0, 9);
    final lo = o.floor();
    final hi = o.ceil();
    final a = dlsResourceTable[lo][w];
    if (lo == hi) return a;
    final b = dlsResourceTable[hi][w];
    return a + (b - a) * (o - lo);
  }

  /// DLS Standard Edition target. [team1OversLeftAtEnd]/[team1Wickets] when team 1 was cut short;
  /// [interrupt] = (oversLeftAtSuspension, wicketsLost, oversLeftAtResumption) for team 2.
  static RainTarget target({
    required int team1Score,
    required double team1StartOvers,
    required double team2Overs,
    double team1OversLeftAtEnd = 0,
    int team1Wickets = 0,
    (double, int, double)? interrupt,
    bool lowerLevel = false,
  }) {
    final g50 = lowerLevel ? 200 : 245;
    final startR1 = resource(team1StartOvers, 0);
    var r1 = startR1;
    if (team1OversLeftAtEnd > 0) r1 = startR1 - resource(team1OversLeftAtEnd, team1Wickets);
    r1 = r1.clamp(0, 100).toDouble();
    var r2 = resource(team2Overs, 0);
    if (interrupt != null) {
      final lost = math.max(0.0, resource(interrupt.$1, interrupt.$2) - resource(interrupt.$3, interrupt.$2));
      r2 = math.max(0, r2 - lost);
    }
    int t;
    String formula;
    if (r2 < r1 - 1e-9) {
      t = (team1Score * r2 / r1).floor() + 1;
      formula = 'T = ⌊$team1Score × ${r2.toStringAsFixed(1)} / ${r1.toStringAsFixed(1)}⌋ + 1';
    } else if ((r2 - r1).abs() < 1e-9) {
      t = team1Score + 1;
      formula = 'T = $team1Score + 1 (R1 = R2)';
    } else {
      t = (team1Score + (r2 - r1) * g50 / 100).floor() + 1;
      formula = 'T = ⌊$team1Score + (${r2.toStringAsFixed(1)} − ${r1.toStringAsFixed(1)}) × $g50/100⌋ + 1';
    }
    if (t < 1) t = 1;
    return RainTarget(method: 'DLS', target: t, par: t - 1, formula: formula, r1: r1, r2: r2);
  }
}

class Vjd {
  Vjd._();
  static const _targetTable = {0: 0.0, 20: 29.8, 40: 53.5, 50: 63.4, 60: 72.3, 80: 87.6, 100: 100.0};

  static double _poly(double o) {
    final x = o.clamp(0, 100).toDouble();
    return (1.6631192 * x - 0.009254 * x * x + 0.0000261 * x * x * x).clamp(0, 100).toDouble();
  }

  static double _table(double x) {
    final keys = _targetTable.keys.toList()..sort();
    if (x <= keys.first) return _targetTable[keys.first]!;
    if (x >= keys.last) return _targetTable[keys.last]!;
    for (var i = 0; i < keys.length - 1; i++) {
      final k0 = keys[i], k1 = keys[i + 1];
      if (x >= k0 && x <= k1) {
        final t = (x - k0) / (k1 - k0);
        return _targetTable[k0]! + (_targetTable[k1]! - _targetTable[k0]!) * t;
      }
    }
    return 100;
  }

  static RainTarget target({required int team1Score, required int scheduledOvers, required double team2Overs}) {
    final pct = (team2Overs / math.max(1, scheduledOvers)) * 100;
    final runPct = (_table(pct) + _poly(pct)) / 2;
    final t = math.max(1, (team1Score * runPct / 100).round());
    return RainTarget(
      method: 'VJD',
      target: t,
      par: math.max(0, t - 1),
      formula: 'T = round($team1Score × ${runPct.toStringAsFixed(1)}% ) [${pct.toStringAsFixed(1)}% of $scheduledOvers ov]',
    );
  }
}

// ───────────────────────── Net run rate ─────────────────────────

class Nrr {
  Nrr._();

  static double? compute(num rs, num bf, num rc, num bb, {int bpo = 6, bool ballCentric = false}) {
    if (bf <= 0 || bb <= 0) return null;
    if (ballCentric) return rs / bf - rc / bb;
    return rs / (bf / bpo) - rc / (bb / bpo);
  }

  static String format(double? v) => v == null ? '—' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(3)}';

  /// Batting first: max opposition score that still reaches [targetNrr].
  static String batFirst({required int rs, required int bf, required int rc, required int bb, required int yourScore, required double matchOvers, required double targetNrr, int bpo = 6, bool ballCentric = false}) {
    final mb = math.max(1, (matchOvers * bpo).round());
    final rs2 = rs + yourScore, bf2 = bf + mb, ob2 = bb + mb;
    double cap = ballCentric ? rs2 / bf2 - targetNrr : rs2 / (bf2 / bpo) - targetNrr;
    final maxRc2 = ballCentric ? cap * ob2 : cap * (ob2 / bpo);
    final maxOpp = (maxRc2 - rc).floor();
    if (maxOpp < 0) return 'With $yourScore you cannot reach NRR ${format(targetNrr)} even by bowling them out for 0.';
    final useMax = math.min(maxOpp, math.max(0, yourScore - 1));
    final proj = compute(rs2, bf2, rc + useMax, ob2, bpo: bpo, ballCentric: ballCentric);
    if (maxOpp >= yourScore) {
      return 'Win and restrict them to ${math.max(0, yourScore - 1)} or fewer — NRR stays above ${format(targetNrr)} (projected ${format(proj)}).';
    }
    return 'Restrict the opposition to $maxOpp or fewer (win by ${yourScore - maxOpp}+ runs) to reach NRR ${format(targetNrr)}. Projected ${format(proj)}.';
  }

  /// Chasing: fastest the target must be reached to hit [targetNrr].
  static String chase({required int rs, required int bf, required int rc, required int bb, required int opponentScore, required double matchOvers, required double targetNrr, int bpo = 6, bool ballCentric = false}) {
    final mb = math.max(1, (matchOvers * bpo).round());
    final tr = opponentScore + 1;
    final rs2 = rs + tr, rc2 = rc + opponentScore, ob2 = bb + mb;
    final denom = ballCentric ? targetNrr + rc2 / ob2 : (targetNrr + rc2 / (ob2 / bpo)) / bpo;
    if (!(denom > 0)) return 'Chase $tr within the full $matchOvers overs — NRR ${format(targetNrr)} is already reachable.';
    final maxBf2 = rs2 / denom;
    final add = maxBf2.floor() - bf;
    if (add < 1) return 'Even chasing $tr in 1 ball may not reach NRR ${format(targetNrr)}.';
    final capped = math.min(add, mb);
    final proj = compute(rs2, bf + capped, rc2, ob2, bpo: bpo, ballCentric: ballCentric);
    if (capped >= mb) return 'Chase $tr in up to the full ${Cricket.ballsToOvers(mb, bpo)} overs — projected NRR ${format(proj)}.';
    return ballCentric
        ? 'Chase $tr in $capped balls or fewer to reach NRR ${format(targetNrr)} (projected ${format(proj)}).'
        : 'Chase $tr in ${Cricket.ballsToOvers(capped, bpo)} overs or fewer to reach NRR ${format(targetNrr)} (projected ${format(proj)}).';
  }
}

// ───────────────────────── Fielding areas & shots ─────────────────────────

class _Sector {
  const _Sector(this.from, this.to, this.close, this.short, this.ring, this.deep);
  final int from, to;
  final String close, short, ring, deep;
}

const _sectors = <_Sector>[
  _Sector(0, 20, 'Silly Mid Off', 'Short Mid Off', 'Mid Off', 'Long Off'),
  _Sector(20, 40, 'Silly Extra Cover', 'Short Extra Cover', 'Extra Cover', 'Deep Extra Cover'),
  _Sector(40, 60, 'Silly Cover', 'Short Cover', 'Cover', 'Deep Cover'),
  _Sector(60, 80, 'Silly Cover Point', 'Short Cover Point', 'Cover Point', 'Deep Cover Point'),
  _Sector(80, 100, 'Silly Point', 'Short Point', 'Point', 'Deep Point'),
  _Sector(100, 120, 'Short Backward Point', 'Short Backward Point', 'Backward Point', 'Deep Backward Point'),
  _Sector(120, 140, 'Gully', 'Gully', 'Deep Gully', 'Deep Backward Point'),
  _Sector(140, 165, 'Short Third Man', 'Short Third Man', 'Short Third Man', 'Third Man'),
  _Sector(165, 180, 'Slip', 'Slip', 'Fly Slip', 'Fine Third Man'),
  _Sector(180, 195, 'Leg Slip', 'Leg Slip', 'Short Fine Leg', 'Fine Leg'),
  _Sector(195, 220, 'Short Fine Leg', 'Short Fine Leg', 'Fine Leg', 'Deep Fine Leg'),
  _Sector(220, 245, 'Short Backward Square', 'Backward Square Leg', 'Backward Square Leg', 'Deep Backward Square'),
  _Sector(245, 270, 'Short Leg', 'Short Square Leg', 'Square Leg', 'Deep Square Leg'),
  _Sector(270, 290, 'Forward Short Leg', 'Short Square Leg', 'Forward Square Leg', 'Deep Square Leg'),
  _Sector(290, 315, 'Silly Mid Wicket', 'Short Mid Wicket', 'Mid Wicket', 'Deep Mid Wicket'),
  _Sector(315, 340, 'Short Mid Wicket', 'Short Mid Wicket', 'Wide Mid On', 'Cow Corner'),
  _Sector(340, 360, 'Silly Mid On', 'Short Mid On', 'Mid On', 'Long On'),
];

/// Fielding position name for a wagon angle (0° = straight, 90° = off side for RHB) and distance 0–1.
String fieldingArea(double angle, double distance) {
  final a = ((angle % 360) + 360) % 360;
  final close = distance < 0.28, short = distance < 0.42, ring = distance < 0.58;
  if (short) {
    final d180 = math.min((a - 180).abs(), 360 - (a - 180).abs());
    if (d180 <= 14) return 'Wicket-Keeper';
  }
  final s = _sectors.firstWhere((x) => x.from <= a && a < x.to, orElse: () => _sectors.last);
  if (close) return s.close;
  if (short) return s.short;
  if (ring) return s.ring;
  return s.deep;
}

/// Mirror an angle for left-handers (web `toDisplayWagonAngle`).
double mirrorForHand(double angle, String? hand) => hand == 'LHB' ? (360 - ((angle % 360) + 360) % 360) % 360 : ((angle % 360) + 360) % 360;

const cricketShots = <(String, double)>[
  ('Straight Drive', 2), ('Lofted Straight', 6), ('Off Drive', 25), ('On Drive', 348), ('Lofted Off Drive', 30),
  ('Lofted On Drive', 344), ('Lofted Cover', 48), ('Cover Drive', 52), ('Extra Cover Drive', 32), ('Square Drive', 85),
  ('Cut Shot', 95), ('Square Cut', 105), ('Late Cut', 138), ('Upper Cut', 150), ('Steer / Guide', 130),
  ('Back-foot Punch', 68), ('Flick', 308), ('Whip', 312), ('Mid-wicket Hit', 300), ('Pull Shot', 282),
  ('Hook Shot', 252), ('Sweep', 262), ('Paddle Sweep', 230), ('Slog Sweep', 298), ('Leg Glance', 212),
  ('Nudge / Work', 296), ('Cow Corner Hit', 328), ('Third Man', 152), ('Fine Leg', 205), ('Behind Wicket', 180),
  ('Ramp', 196), ('Scoop', 188), ('Paddle Scoop', 200), ('Dilscoop', 184), ('Reverse Ramp', 170),
  ('Reverse Sweep', 108), ('Switch Hit', 70), ('Slog', 322), ('Helicopter Shot', 342), ('Inside-out', 45),
  ('Natraj Shot', 258), ('Reverse Pull', 112), ('Lap Shot', 226), ('Forward Defence', 8), ('Back Defence', 353),
];

/// Shots whose natural direction is within [tolerance]° of [angle].
List<String> shotsNear(double angle, {double tolerance = 30}) {
  double diff(double a, double b) {
    final d = ((a - b) % 360 + 360) % 360;
    return d > 180 ? 360 - d : d;
  }

  final list = cricketShots.where((s) => diff(s.$2, angle) <= tolerance).toList()..sort((a, b) => diff(a.$2, angle).compareTo(diff(b.$2, angle)));
  return list.map((e) => e.$1).toList();
}
