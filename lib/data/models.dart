import '../core/cricket.dart';

/// Lightweight read-only views over backend JSON. The backend schema evolves
/// quickly, so we keep raw maps and expose typed getters instead of strict
/// deserialisation that would break on new fields.

class AuthUser {
  AuthUser(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id']?.toString() ?? '';
  String get email => raw['email']?.toString() ?? '';
  String get name => (raw['name']?.toString().trim().isNotEmpty ?? false) ? raw['name'].toString() : email.split('@').first;
  String get role => raw['role']?.toString() ?? 'viewer';
  String? get contactNumber => asStr(raw['contactNumber']);
  String? get playerId => asStr(raw['playerId']);
  Map<String, dynamic> get subscription => asMap(raw['subscription']);
  bool get isScorer => role == 'scorer';
  bool get canManage => role == 'admin' || role == 'broadcaster' || isScorer;
  bool get isAdmin => role == 'admin';

  static const roles = {
    'broadcaster': 'Organiser / Broadcaster',
    'admin': 'Admin',
    'player': 'Player',
    'umpire': 'Umpire',
    'referee': 'Match Referee',
    'commentator': 'Commentator',
  };
}

class TeamRef {
  TeamRef(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id']?.toString() ?? '';
  String get name => raw['name']?.toString() ?? 'Team';
  String get shortName {
    final s = raw['shortName']?.toString().trim();
    return (s == null || s.isEmpty) ? Fmt.shortName(name) : s;
  }

  String? get logoUrl => asStr(raw['logoUrl']);
  String? get color => asStr(raw['themeColor']);
  String get city => raw['city']?.toString() ?? '';
}

class MatchView {
  MatchView(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['id']?.toString() ?? '';
  int? get seq => raw['matchSeq'] == null ? null : asInt(raw['matchSeq']);
  String get status => raw['status']?.toString() ?? 'scheduled';
  bool get isLive => status == 'live';
  bool get isCompleted => status == 'completed' || status == 'abandoned';
  TeamRef get team1 => TeamRef(asMap(raw['team1'])..putIfAbsent('id', () => raw['team1Id']));
  TeamRef get team2 => TeamRef(asMap(raw['team2'])..putIfAbsent('id', () => raw['team2Id']));
  Map<String, dynamic> get tournament => asMap(raw['tournament']);
  String get tournamentId => raw['tournamentId']?.toString() ?? tournament['id']?.toString() ?? '';
  String get tournamentName => tournament['name']?.toString() ?? '';
  int get overs => asInt(raw['overs'], 20);
  String get venue => raw['venue']?.toString() ?? '';
  String get stage => raw['stage']?.toString() ?? '';
  String get group => raw['group']?.toString() ?? '';
  dynamic get scheduledAt => raw['scheduledAt'];
  List<Map<String, dynamic>> get innings => asMapList(raw['innings'])..sort((a, b) => asInt(a['number']).compareTo(asInt(b['number'])));
  Map<String, dynamic> get result => asMap(raw['result']);
  Map<String, dynamic> get scorerMeta => asMap(raw['scorerMeta']);
  bool get scoringLocked => scorerMeta['scoringLocked'] == true;

  /// Server flag on list rows: may the signed-in user score this match?
  bool get viewerCanScore => raw['viewerCanScore'] == true;
  String? get tossWinnerId => asStr(raw['tossWinnerId']);
  String? get tossDecision => asStr(raw['tossDecision']);
  String? get firstBattingTeamId => asStr(raw['firstBattingTeamId']);

  TeamRef teamById(String? id) => id == team2.id ? team2 : team1;

  Map<String, dynamic>? inningsFor(String teamId) {
    for (final i in innings) {
      if (i['battingTeamId']?.toString() == teamId && i['isSuperOver'] != true) return i;
    }
    return null;
  }

  String scoreFor(String teamId) {
    final i = inningsFor(teamId);
    if (i == null) return '';
    return '${asInt(i['runs'])}/${asInt(i['wickets'])}';
  }

  String oversFor(String teamId) {
    final i = inningsFor(teamId);
    if (i == null) return '';
    return Cricket.oversText(asDouble(i['overs']));
  }

  String get resultText {
    final summary = asStr(asMap(scorerMeta['matchOutcome'])['summaryText']);
    if (summary != null) return summary;
    final r = result;
    if (r.isEmpty) return '';
    final type = r['resultType']?.toString() ?? '';
    final margin = r['margin'] == null ? null : asInt(r['margin']);
    final winnerId = r['winnerTeamId']?.toString();
    if (type == 'tie') return 'Match tied';
    if (type == 'draw') return 'Match drawn';
    if (type == 'no_result' || type == 'abandoned') return 'No result';
    if (winnerId == null) return type;
    final w = teamById(winnerId).name;
    switch (type) {
      case 'runs':
        return margin == null ? '$w won' : '$w won by $margin run${margin == 1 ? '' : 's'}';
      case 'wickets':
        return margin == null ? '$w won' : '$w won by $margin wicket${margin == 1 ? '' : 's'}';
      case 'innings':
        return margin == null ? '$w won by an innings' : '$w won by an innings and $margin runs';
      case 'super_over':
        return '$w won the Super Over';
      case 'walkover':
        return '$w won by walkover';
      default:
        return margin == null ? '$w won' : '$w won by $margin';
    }
  }
}

/// Live snapshot from GET /matches/:id/snapshot (also pushed over WebSocket).
class Snapshot {
  Snapshot(this.raw);
  final Map<String, dynamic> raw;

  MatchView get match => MatchView(asMap(raw['match']));
  Map<String, dynamic> get matchRaw => asMap(raw['match']);
  Map<String, dynamic> get tournament => asMap(matchRaw['tournament']);
  int get bpo => Cricket.ballsPerOver(tournament);
  List<Map<String, dynamic>> get innings =>
      asMapList(raw['innings'])..sort((a, b) => asInt(a['number']).compareTo(asInt(b['number'])));
  List<Map<String, dynamic>> get battingStats => asMapList(raw['battingStats']);
  List<Map<String, dynamic>> get bowlingStats => asMapList(raw['bowlingStats']);
  List<Map<String, dynamic>> get fallOfWickets => asMapList(raw['fallOfWickets']);
  List<Map<String, dynamic>> get lastBall => asMapList(raw['lastBall']);
  Map<String, dynamic> get liveCrease => asMap(raw['liveCrease']);
  Map<String, dynamic> get ticker => asMap(raw['ticker']);
  Map<String, dynamic> get extrasByInnings => asMap(raw['extrasByInnings']);
  Map<String, dynamic> get partnership => asMap(raw['partnership']);
  List<String> get currentOverPips => (raw['currentOverBalls'] is List) ? (raw['currentOverBalls'] as List).map((e) => e.toString()).toList() : const [];
  List<Map<String, dynamic>> get playingXI => asMapList(matchRaw['playingXI']);
  bool get isSuperOver => matchRaw['isSuperOver'] == true;

  Map<String, dynamic>? get currentInnings {
    final inns = innings;
    if (inns.isEmpty) return null;
    for (final i in inns.reversed) {
      if (i['isCompleted'] != true) return i;
    }
    return inns.last;
  }

  int get currentInningsNumber => asInt(currentInnings?['number'], 0);
  bool get hasStarted => innings.isNotEmpty;
  bool get currentInningsCompleted => currentInnings?['isCompleted'] == true;

  String? get battingTeamId => asStr(currentInnings?['battingTeamId']);
  String? get bowlingTeamId {
    final b = battingTeamId;
    if (b == null) return null;
    return b == match.team1.id ? match.team2.id : match.team1.id;
  }

  int get scheduledOvers {
    final ci = currentInnings;
    if (isSuperOver && currentInningsNumber >= 3) return 1;
    if (ci?['reducedOvers'] != null) return asInt(ci!['reducedOvers']);
    return match.overs;
  }

  int get legalBalls => Cricket.oversToBalls(asDouble(currentInnings?['overs']), bpo);
  int get completedOvers => legalBalls ~/ bpo;
  int get ballsInOver => legalBalls % bpo;
  int get runs => asInt(currentInnings?['runs']);
  int get wickets => asInt(currentInnings?['wickets']);
  int? get target {
    final ci = currentInnings;
    final t = ci?['revisedTarget'] ?? ci?['target'];
    return t == null ? null : asInt(t);
  }

  /// XI members (with nested `player`) for a team.
  List<Map<String, dynamic>> xiFor(String? teamId) =>
      playingXI.where((x) => x['teamId']?.toString() == teamId).toList()
        ..sort((a, b) => asInt(a['playingSeq'], 99).compareTo(asInt(b['playingSeq'], 99)));

  Map<String, dynamic>? battingStatFor(String? playerId) {
    for (final s in battingStats) {
      if (s['playerId']?.toString() == playerId) return s;
    }
    return null;
  }

  Map<String, dynamic>? bowlingStatFor(String? playerId) {
    for (final s in bowlingStats) {
      if (s['playerId']?.toString() == playerId) return s;
    }
    return null;
  }

  String playerName(String? id) {
    if (id == null) return '-';
    for (final x in playingXI) {
      if (x['playerId']?.toString() == id) return asMap(x['player'])['name']?.toString() ?? '-';
    }
    final b = battingStatFor(id) ?? bowlingStatFor(id);
    return asMap(b?['player'])['name']?.toString() ?? '-';
  }

  Map<String, dynamic> playerById(String? id) {
    for (final x in playingXI) {
      if (x['playerId']?.toString() == id) return asMap(x['player']);
    }
    return {'id': id, 'name': playerName(id)};
  }

  /// Persisted crease (already rotated by the server after each delivery).
  Map<String, dynamic> get metaCrease {
    final c = asMap(match.scorerMeta['crease']);
    if (c.isEmpty) return c;
    if (asInt(c['innings']) != currentInningsNumber) return {};
    return c;
  }

  Map<String, dynamic> extrasFor(int innings) => asMap(extrasByInnings['$innings']);
}
