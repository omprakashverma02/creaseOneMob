import 'package:intl/intl.dart';

/// Cricket rules & formatting shared across the app.
/// Mirrors the web `matchRules.ts` and backend `bowlingFigures.js` where it matters.
class Cricket {
  Cricket._();

  static const matchTypes = ['T20', 'ODI', 'TEST', 'Box', 'Hundred', 'Balls', 'Custom'];

  static const ballsBasedFormats = ['The Fifty', 'The Sixty', 'The Ninty', 'The Hundred'];

  static const _ballsFormatBpo = {'The Fifty': 5, 'The Sixty': 6, 'The Ninty': 6, 'The Hundred': 5};
  static const _ballsFormatQuotaBalls = {'The Fifty': 10, 'The Sixty': 12, 'The Ninty': 18, 'The Hundred': 20};
  static const _limitedOversChips = {'T10', 'T5', 'T20', 'T20I', 'Pro40', 'One Day', 'ODI'};

  /// Balls per over / set — same resolution as backend `resolveBallsPerOverFromTournament`.
  static int ballsPerOver(Map<String, dynamic>? tournament) {
    final type = (tournament?['type'] ?? '').toString().trim().toLowerCase();
    final fmt = (tournament?['oversFormat'] ?? '').toString().trim();
    const standard = {'t20', 'odi', 'test', 'box', 'custom'};
    if (standard.contains(type) || _limitedOversChips.contains(fmt)) return 6;
    if (type == 'hundred' && fmt != 'The Hundred') return 10;
    if (_ballsFormatBpo[fmt] != null) return _ballsFormatBpo[fmt]!;
    if (type == 'balls') return 5;
    if (type == 'hundred') return 10;
    return 6;
  }

  static bool isTest(Map<String, dynamic>? tournament) =>
      (tournament?['type'] ?? '').toString().toUpperCase() == 'TEST';

  /// Max legal balls one bowler may deliver in an innings (null = unlimited).
  static int? maxBallsPerBowler(Map<String, dynamic>? tournament, int scheduledOvers, {bool superOver = false}) {
    if (superOver) return null;
    final type = (tournament?['type'] ?? 'T20').toString();
    final fmt = (tournament?['oversFormat'] ?? '').toString();
    final bpo = ballsPerOver(tournament);
    if (type == 'Hundred' || type == 'Balls') {
      return _ballsFormatQuotaBalls[fmt] ?? 20;
    }
    if (type == 'TEST') return null;
    if (type == 'Box') return ((scheduledOvers / 3).ceil()) * bpo;
    if (scheduledOvers <= 0) return null;
    // T20 / ODI / Custom: one fifth of the overs (rounded up for odd counts).
    return ((scheduledOvers / 5).ceil()) * bpo;
  }

  /// Converts backend cricket-decimal overs (e.g. 3.4) to legal balls.
  static int oversToBalls(num? overs, int bpo) {
    final o = (overs ?? 0).toDouble();
    final whole = o.floor();
    final part = ((o - whole) * 10).round();
    return whole * bpo + part;
  }

  static String ballsToOvers(int balls, int bpo) => '${balls ~/ bpo}.${balls % bpo}';

  static String oversText(num? overs) {
    final o = (overs ?? 0).toDouble();
    final whole = o.floor();
    final part = ((o - whole) * 10).round();
    return part == 0 ? '$whole' : '$whole.$part';
  }

  static String strikeRate(num runs, num balls) => balls <= 0 ? '-' : ((runs / balls) * 100).toStringAsFixed(1);

  static String economy(num runs, num overs, int bpo) {
    final balls = oversToBalls(overs, bpo);
    if (balls <= 0) return '-';
    return ((runs / balls) * bpo).toStringAsFixed(2);
  }

  static String runRate(num runs, int balls, int bpo) => balls <= 0 ? '0.00' : ((runs / balls) * bpo).toStringAsFixed(2);

  static const dismissalTypes = <String, String>{
    'caught': 'Caught',
    'caught behind': 'Caught Behind',
    'bowled': 'Bowled',
    'lbw': 'LBW',
    'run out': 'Run Out',
    'stumped': 'Stumped',
    'c&b': 'Caught & Bowled',
    'hit wicket': 'Hit Wicket',
    'run out (mankaded)': 'Run Out (Mankad)',
    'retired hurt': 'Retired Hurt',
    'retired out': 'Retired Out',
    'retired': 'Retired',
    'absent hurt': 'Absent Hurt',
    'hit the ball twice': 'Hit the Ball Twice',
    'obstructing the ball': 'Obstructing the Field',
    'timed out': 'Timed Out',
  };

  static bool needsFielder(String t) =>
      t == 'caught' || t == 'caught behind' || t == 'stumped' || t == 'run out' || t == 'run out (mankaded)';

  static bool isKeeperDismissal(String t) => t == 'caught behind' || t == 'stumped';

  static bool isRunOut(String t) => t.startsWith('run out');

  static bool isRetirement(String t) =>
      t == 'retired' || t == 'retired hurt' || t == 'retired out' || t == 'absent hurt';

  /// Dismissals where the non-striker can be the one out.
  static bool canDismissNonStriker(String t) =>
      t == 'run out' || t == 'run out (mankaded)' || isRetirement(t) || t == 'obstructing the ball' || t == 'timed out';

  static const playerRoles = ['batsman', 'bowler', 'allrounder', 'wk', 'wk Batsmen'];
  static String roleLabel(String? r) {
    switch (r) {
      case 'batsman':
        return 'Batter';
      case 'bowler':
        return 'Bowler';
      case 'allrounder':
        return 'All-rounder';
      case 'wk':
        return 'Wicket-keeper';
      case 'wk Batsmen':
        return 'WK Batter';
      default:
        return r ?? '-';
    }
  }

  static const battingStyles = ['RHB', 'LHB'];
  static const bowlingStyles = [
    'Right Arm Fast',
    'Right Arm Medium',
    'Right Arm Off Spin',
    'Right Arm Leg Spin',
    'Left Arm Fast',
    'Left Arm Medium',
    'Left Arm Orthodox',
    'Left Arm Chinaman',
    'None',
  ];

  static const tournamentFormats = <String, String>{
    'league_format': 'League',
    'round_robin': 'Round Robin',
    'double_round_robin': 'Double Round Robin',
    'league_cum_knockouts': 'League + Knockouts',
    'playoffs_format': 'Playoffs',
    'bilateral': 'Bilateral Series',
    'group_stage': 'Group Stage',
    'knockout': 'Knockout',
    'group_plus_knockout': 'Groups + Knockout',
  };

  static const tournamentCategories = ['Senior', 'Age Group', 'Corporate', 'Community', 'Series', 'Other'];
  static const ballTypes = ['Leather', 'Tennis', 'Soft ball'];
  static const ballColors = {
    'Leather': ['Red', 'White', 'Pink'],
    'Tennis': ['Green', 'Yellow', 'Red'],
    'Soft ball': ['Optic Yellow', 'Green'],
  };
  static const pitchTypes = ['TURF', 'MATTING', 'CEMENT', 'ASTROTURF', 'SOIL DUST'];
  static const matchKinds = ['Limited Overs', 'Multi Days', 'Balls-Based Limited Overs', 'Box/Turf Cricket', 'Pair Cricket'];
  static const oversFormats = ['T5', 'T10', 'T20', 'T20I', 'Pro40', 'One Day', 'ODI'];
  static const multiDayFormats = ['2-Day', '3-Day', '4-Day', '5-Day', 'Test Match', 'Unofficial Test Match'];
  static const matchStages = ['League', 'Group', 'Quarter Final', 'Semi Final', 'Eliminator', 'Qualifier 1', 'Qualifier 2', 'Final', 'Friendly'];

  static int defaultOversFor(String? matchType, String? oversFormat) {
    switch (oversFormat) {
      case 'T5':
        return 5;
      case 'T10':
        return 10;
      case 'T20':
      case 'T20I':
        return 20;
      case 'Pro40':
        return 40;
      case 'One Day':
      case 'ODI':
        return 50;
      case 'The Fifty':
        return 10;
      case 'The Sixty':
        return 10;
      case 'The Ninty':
        return 15;
      case 'The Hundred':
        return 20;
    }
    switch (matchType) {
      case 'ODI':
        return 50;
      case 'TEST':
        return 90;
      case 'Box':
        return 6;
      default:
        return 20;
    }
  }
}

class Fmt {
  Fmt._();
  static final _date = DateFormat('d MMM yyyy');
  static final _dateTime = DateFormat('d MMM, h:mm a');
  static final _day = DateFormat('EEE, d MMM');

  static DateTime? parse(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  static String date(dynamic v) {
    final d = parse(v);
    return d == null ? '-' : _date.format(d);
  }

  static String dateTime(dynamic v) {
    final d = parse(v);
    return d == null ? '-' : _dateTime.format(d);
  }

  static String day(dynamic v) {
    final d = parse(v);
    return d == null ? '-' : _day.format(d);
  }

  static String initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String shortName(String? name, [int max = 4]) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '-';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length > 1) return parts.map((p) => p[0]).join().toUpperCase();
    return n.substring(0, n.length > max ? max : n.length).toUpperCase();
  }
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.toInt() ?? fallback;
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

String? asStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
