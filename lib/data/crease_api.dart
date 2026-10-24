import 'dart:io';

import '../core/cricket.dart';
import 'api_client.dart';

/// All CreaseOne backend endpoints used by the mobile app.
/// Mirrors `cricketTicker/services/api.ts` (minus broadcast-graphics endpoints).
class CreaseApi {
  CreaseApi(this.client);
  final ApiClient client;

  List<Map<String, dynamic>> _list(dynamic data, [String? key]) {
    if (data is List) return asMapList(data);
    if (key != null && data is Map && data[key] is List) return asMapList(data[key]);
    return const [];
  }

  // ───────────── Auth ─────────────
  Future<Map<String, dynamic>> googleLogin(String idToken) async =>
      asMap(await client.post('/auth/google', data: {'credential': idToken}));

  Future<Map<String, dynamic>> completeProfile(Map<String, dynamic> body) async =>
      asMap(await client.post('/auth/complete-profile', data: body));

  Future<Map<String, dynamic>> signIn(String email, String password) async =>
      asMap(await client.post('/auth/signin', data: {'email': email.trim(), 'password': password}));

  Future<Map<String, dynamic>> signUp(Map<String, dynamic> body) async => asMap(await client.post('/auth/signup', data: body));

  Future<Map<String, dynamic>> me() async => asMap(await client.get('/auth/me'));

  Future<Map<String, dynamic>> scorerLogin({required String match, required String username, required String password}) async {
    final isSeq = int.tryParse(match.trim()) != null;
    return asMap(await client.post('/auth/scorer-login', data: {
      if (isSeq) 'matchSeq': match.trim() else 'matchId': match.trim(),
      'username': username.trim(),
      'password': password,
    }));
  }

  Future<void> updateMyProfile(String userId, Map<String, dynamic> data) => client.put('/users/$userId', data: data);

  Future<Map<String, dynamic>> billingStatus() async => asMap(await client.get('/billing/status'));
  Future<List<Map<String, dynamic>>> billingPlans() async => _list(await client.get('/billing/plans'), 'plans');

  // ───────────── Uploads ─────────────
  Future<String> uploadImage(File f, {String folder = 'misc'}) => client.uploadImage(f, folder: folder);

  // ───────────── Tournaments ─────────────
  /// All tournaments (each carries `viewerCanManage`). [mine] → only tournaments I manage.
  Future<List<Map<String, dynamic>>> tournaments({bool mine = false}) async =>
      _list(await client.get('/tournaments', query: {if (!mine) 'scope': 'all'}), 'tournaments');
  Future<List<Map<String, dynamic>>> publicTournaments() async => _list(await client.get('/tournaments/list-public'), 'tournaments');
  Future<Map<String, dynamic>> tournament(String id) async => asMap(await client.get('/tournaments/$id'));
  Future<Map<String, dynamic>> createTournament(Map<String, dynamic> d) async => asMap(await client.post('/tournaments', data: d));
  Future<Map<String, dynamic>> updateTournament(String id, Map<String, dynamic> d) async =>
      asMap(await client.put('/tournaments/$id', data: d));
  Future<void> deleteTournament(String id) => client.delete('/tournaments/$id');
  Future<void> wipeSchedule(String id) => client.delete('/tournaments/$id/schedule');

  Future<List<Map<String, dynamic>>> tournamentTeams(String id) async {
    final rows = _list(await client.get('/tournament-teams', query: {'tournamentId': id}));
    return rows.map((r) => asMap(r['team'])).where((t) => t['id'] != null).toList();
  }

  Future<void> addTeamsToTournament(String tournamentId, List<String> teamIds) =>
      client.post('/tournament-teams', data: {'tournamentId': tournamentId, 'teamIds': teamIds});

  Future<void> removeTeamFromTournament(String tournamentId, String teamId) =>
      client.delete('/tournament-teams', query: {'tournamentId': tournamentId, 'teamId': teamId});

  Future<Map<String, dynamic>> pointsTable(String id) async => asMap(await client.get('/tournaments/$id/points-table'));
  Future<Map<String, dynamic>> tournamentStats(String id) async => asMap(await client.get('/tournament-stats/$id'));
  Future<Map<String, dynamic>> tournamentInsights(String id) async => asMap(await client.get('/tournament-stats/$id/insights'));
  Future<dynamic> topPerformers(String id, {int n = 5}) => client.get('/tournaments/$id/top-performers', query: {'n': n});
  Future<Map<String, dynamic>> tournamentStructure(String id) async => asMap(await client.get('/tournaments/$id/structure'));

  Future<List<Map<String, dynamic>>> tournamentOfficials(String id) async => _list(await client.get('/tournaments/$id/officials'));
  Future<void> addTournamentOfficial(String id, Map<String, dynamic> body) => client.post('/tournaments/$id/officials', data: body);
  Future<void> removeTournamentOfficial(String id, String officialId) => client.delete('/tournaments/$id/officials/$officialId');

  Future<Map<String, dynamic>> scoringAccess(String id) async => asMap(await client.get('/tournaments/$id/scoring-access'));
  Future<void> addScoringAccess(String id, Map<String, dynamic> body) => client.post('/tournaments/$id/scoring-access', data: body);
  Future<void> removeScoringAccess(String id, String accessId) => client.delete('/tournaments/$id/scoring-access/$accessId');

  // ───────────── Teams ─────────────
  /// All teams for viewing (each has `viewerIsOwner`); [mine] → only teams I created (for edit pickers).
  Future<List<Map<String, dynamic>>> teams({bool mine = false}) async => _list(await client.get('/teams', query: {if (!mine) 'scope': 'all'}));

  Future<bool> canEditTeam(String id) async => _perm('/teams/$id/permissions', 'canEdit');
  Future<bool> canEditPlayer(String id) async => _perm('/players/$id/permissions', 'canEdit');
  Future<bool> canManageTournament(String id) async => _perm('/tournaments/$id/permissions', 'canManage');

  Future<bool> _perm(String path, String key) async {
    try {
      return asMap(await client.get(path))[key] == true;
    } on ApiException {
      return false;
    }
  }
  Future<Map<String, dynamic>> team(String id) async => asMap(await client.get('/teams/$id'));
  Future<Map<String, dynamic>> createTeam(Map<String, dynamic> d) async => asMap(await client.post('/teams', data: d));
  Future<void> updateTeam(String id, Map<String, dynamic> d) => client.put('/teams/$id', data: d);
  Future<void> deleteTeam(String id) => client.delete('/teams/$id');

  Future<List<Map<String, dynamic>>> teamPlayers({String? teamId, String? tournamentId, String? playerId}) async =>
      _list(await client.get('/team-players', query: {'teamId': teamId, 'tournamentId': tournamentId, 'playerId': playerId}));

  Future<void> assignPlayersToTeam({required String teamId, String? tournamentId, required List<String> playerIds}) =>
      client.post('/team-players', data: {'teamId': teamId, if (tournamentId != null) 'tournamentId': tournamentId, 'playerIds': playerIds});

  /// playerId → team name for everyone already in a team of [tournamentId] other than [exceptTeamId].
  Future<Map<String, String>> playersTakenInTournament(String tournamentId, {required String exceptTeamId}) async {
    final rows = await teamPlayers(tournamentId: tournamentId);
    return {
      for (final r in rows)
        if (r['teamId']?.toString() != exceptTeamId && r['tournamentId']?.toString() == tournamentId)
          r['playerId'].toString(): asMap(r['team'])['name']?.toString() ?? 'another team',
    };
  }

  Future<void> updateTeamPlayer(String id, Map<String, dynamic> d) => client.put('/team-players/$id', data: d);
  Future<void> removeTeamPlayer(String id) => client.delete('/team-players/$id');
  Future<Map<String, dynamic>> joinTeamInvite(String tournamentId, String teamId) async =>
      asMap(await client.post('/team-players/join-invite', data: {'tournamentId': tournamentId, 'teamId': teamId}));

  // ───────────── Players ─────────────
  Future<List<Map<String, dynamic>>> players({String? q, String? tournamentId, bool mine = false, String? role}) async =>
      _list(await client.get('/players', query: {'q': q, 'tournamentId': tournamentId, if (mine) 'mine': 'true', 'role': role}));

  /// Search by name, mobile, email or unique id — same strategy as the web.
  Future<List<Map<String, dynamic>>> searchPlayers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return players();
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final futures = <Future<dynamic>>[client.get('/players', query: {'q': q})];
    if (q.contains('@')) futures.add(client.get('/players', query: {'email': q}));
    if (digits.length >= 4) {
      futures.add(client.get('/players', query: {'mobile': digits.length > 10 ? digits.substring(digits.length - 10) : digits}));
    }
    if (!q.contains('@') && digits.length < 8) futures.add(client.get('/players', query: {'uniqueId': q}));
    final results = await Future.wait(futures.map((f) => f.catchError((_) => <dynamic>[])));
    final seen = <String, Map<String, dynamic>>{};
    for (final r in results) {
      for (final p in _list(r)) {
        final key = (p['id'] ?? p['mobileNumber'] ?? p['name']).toString();
        seen.putIfAbsent(key, () => p);
      }
    }
    return seen.values.take(60).toList();
  }

  Future<Map<String, dynamic>> player(String id) async => asMap(await client.get('/players/$id'));
  Future<Map<String, dynamic>> createPlayer(Map<String, dynamic> d) async => asMap(await client.post('/players', data: d));
  Future<void> updatePlayer(String id, Map<String, dynamic> d) => client.put('/players/$id', data: d);
  Future<void> deletePlayer(String id) => client.delete('/players/$id');

  Future<Map<String, dynamic>> playerQuickStats({
    required String playerId,
    required String type, // bat | ball
    required String category, // match | tournament | career
    String? matchId,
    String? tournamentId,
  }) async =>
      asMap(await client.get('/players/quick-stats', query: {
        'playerId': playerId,
        'type': type,
        'category': category,
        'matchId': matchId,
        'tournamentId': tournamentId,
      }));

  Future<dynamic> playerProfiles(Map<String, dynamic> query) => client.get('/player-profiles', query: query);

  /// Every match innings the player batted in (rows include `match`).
  Future<List<Map<String, dynamic>>> playerBattingRows(String playerId) async =>
      _list(await client.get('/batting-stats', query: {'playerId': playerId}));

  /// Every match the player bowled in (rows include `match`).
  Future<List<Map<String, dynamic>>> playerBowlingRows(String playerId) async =>
      _list(await client.get('/bowling-stats', query: {'playerId': playerId}));

  // ───────────── Matches ─────────────
  /// Every match on the platform (each carries `viewerCanScore`). [mine] → only matches I manage.
  Future<List<Map<String, dynamic>>> matches({String? status, String? tournamentId, bool mine = false}) async =>
      _list(await client.get('/matches', query: {'status': status, 'tournamentId': tournamentId, if (!mine) 'scope': 'all'}));

  /// Whether the signed-in user may score this match (server-enforced).
  Future<bool> canScoreMatch(String matchId) async {
    try {
      return asMap(await client.get('/matches/$matchId/permissions'))['canScore'] == true;
    } on ApiException {
      return false;
    }
  }

  // ───────────── World cricket (international feed via backend) ─────────────
  Future<Map<String, dynamic>> worldMatches() async => asMap(await client.get('/world/matches'));
  Future<Map<String, dynamic>> worldMatch(String id) async => asMap(await client.get('/world/matches/$id'));
  Future<Map<String, dynamic>> worldSeries() async => asMap(await client.get('/world/series'));

  Future<Map<String, dynamic>> match(String id) async => asMap(await client.get('/matches/$id'));
  Future<Map<String, dynamic>> matchBySeq(int seq) async => asMap(await client.get('/matches/by-seq/$seq'));
  Future<Map<String, dynamic>> createMatch(Map<String, dynamic> d) async => asMap(await client.post('/matches', data: d));
  Future<void> updateMatch(String id, Map<String, dynamic> d) => client.put('/matches/$id', data: d);
  Future<void> deleteMatch(String id) => client.delete('/matches/$id');

  Future<void> updateToss(String matchId, String tossWinnerId, String decision) =>
      client.put('/matches/$matchId', data: {'tossWinnerId': tossWinnerId, 'tossDecision': decision == 'field' ? 'bowl' : decision});

  Future<Map<String, dynamic>?> snapshot(String id) async {
    final d = asMap(await client.get('/matches/$id/snapshot'));
    return d['match'] == null ? null : d;
  }

  Future<Map<String, dynamic>> scoreboard(String id) async => asMap(await client.get('/matches/$id/scoreboard'));
  Future<Map<String, dynamic>?> summary(String id) async {
    try {
      final d = asMap(await client.get('/matches/$id/summary'));
      return d['innings1'] == null ? null : d;
    } on ApiException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> result(String id) async {
    try {
      final d = await client.get('/matches/$id/result');
      return d is Map ? asMap(d) : null;
    } on ApiException {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> balls(String matchId, {int? innings}) async =>
      _list(await client.get('/balls', query: {'matchId': matchId, 'innings': innings}));

  Future<void> setScoringLock(String matchId, bool locked) => client.post('/matches/$matchId/scoring-lock', data: {'locked': locked});
  Future<Map<String, dynamic>> setScorerAccess(String matchId, String username, String password) async =>
      asMap(await client.post('/matches/$matchId/scorer-access', data: {'username': username, 'password': password}));
  Future<Map<String, dynamic>> scoringTransfer(String matchId) async => asMap(await client.get('/matches/$matchId/scoring-transfer'));
  Future<void> transferScoring(String matchId, Map<String, dynamic> body) => client.post('/matches/$matchId/scoring-transfer', data: body);
  Future<void> setBonusTeam(String matchId, String? teamId, {bool both = false}) =>
      client.post('/matches/$matchId/bonus-team', data: {'bonusTeamId': teamId, 'bonusBothTeams': both});

  // ───────────── Playing XI ─────────────
  Future<List<Map<String, dynamic>>> playingXI(String matchId, String teamId) async =>
      _list(await client.get('/playing-xi', query: {'matchId': matchId, 'teamId': teamId}));

  Future<void> savePlayingXI(String matchId, String teamId, List<Map<String, dynamic>> players) =>
      client.post('/playing-xi', data: {'matchId': matchId, 'teamId': teamId, 'players': players});

  // ───────────── Scoring ─────────────
  Future<Map<String, dynamic>> startInnings(Map<String, dynamic> body) async {
    try {
      return asMap(await client.post('/innings', data: body));
    } on ApiException catch (e) {
      if (e.statusCode == 409) return {'ok': true, 'number': body['number']};
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> innings(String matchId) async => _list(await client.get('/innings', query: {'matchId': matchId}));

  Future<Map<String, dynamic>> postBall(Map<String, dynamic> payload) async => asMap(await client.post('/balls', data: payload));

  Future<Map<String, dynamic>> undoBall(String matchId, {int? innings}) async =>
      asMap(await client.post('/balls/undo', data: {'matchId': matchId, if (innings != null) 'innings': innings}));

  Future<void> updateBallWagon(Map<String, dynamic> body) => client.post('/balls/wagon', data: body);

  Future<void> rectifyBall(Map<String, dynamic> body) => client.post('/balls/rectify', data: body);

  Future<void> persistCrease(String matchId, {int? innings, String? strikerId, String? nonStrikerId, String? bowlerId}) =>
      client.post('/matches/$matchId/settings/crease', data: {
        if (innings != null) 'innings': innings,
        if (strikerId != null) 'strikerId': strikerId,
        if (nonStrikerId != null) 'nonStrikerId': nonStrikerId,
        if (bowlerId != null) 'bowlerId': bowlerId,
      });

  Future<Map<String, dynamic>> matchSettings(String matchId) async => asMap(await client.get('/matches/$matchId/settings'));

  Future<void> changeBowler(String matchId, {String? fromPlayerId, required String toPlayerId, int? innings, String scope = 'current_over'}) =>
      client.post('/matches/$matchId/settings/change-bowler', data: {
        if (fromPlayerId != null) 'fromPlayerId': fromPlayerId,
        'toPlayerId': toPlayerId,
        if (innings != null) 'innings': innings,
        'scope': scope,
      });

  Future<void> replaceBatter(String matchId, {required String fromPlayerId, required String toPlayerId, int? innings}) =>
      client.post('/matches/$matchId/settings/replace-batter',
          data: {'fromPlayerId': fromPlayerId, 'toPlayerId': toPlayerId, if (innings != null) 'innings': innings});

  Future<void> changePlayingXi(String matchId, {required String teamId, required String fromPlayerId, required String toPlayerId}) =>
      client.post('/matches/$matchId/settings/change-playing-xi', data: {'teamId': teamId, 'fromPlayerId': fromPlayerId, 'toPlayerId': toPlayerId});

  Future<void> changeWk(String matchId, String teamId, String playerId) =>
      client.post('/matches/$matchId/settings/change-wk', data: {'teamId': teamId, 'playerId': playerId});

  Future<void> changeCaptain(String matchId, String teamId, String playerId) =>
      client.post('/matches/$matchId/settings/change-captain', data: {'teamId': teamId, 'playerId': playerId});

  Future<void> saveScoreNote(String matchId, String note) => client.put('/matches/$matchId/settings/score-note', data: {'scoreNote': note});

  Future<void> setInterval(String matchId, Map<String, dynamic> body) => client.post('/matches/$matchId/settings/interval', data: body);

  Future<void> addBonusRuns(String matchId, {required String teamId, required int runs, required String reason, int? innings}) =>
      client.post('/matches/$matchId/settings/bonus-runs',
          data: {'teamId': teamId, 'runs': runs, 'reason': reason, if (innings != null) 'innings': innings});

  Future<void> addPenaltyRuns(String matchId, {required String awardedToTeamId, required String reasonCode, String? reasonLabel, int runs = 5}) =>
      client.post('/matches/$matchId/settings/penalty-runs',
          data: {'awardedToTeamId': awardedToTeamId, 'reasonCode': reasonCode, 'reasonLabel': reasonLabel, 'runs': runs});

  Future<void> concussionReplacement(Map<String, dynamic> body) =>
      client.post('/matches/${body['matchId']}/settings/concussion-replacement', data: body);

  Future<Map<String, dynamic>> reduceOvers(String matchId, int reducedOvers, {int? revisedTarget, int? inningsNumber, String? method}) async =>
      asMap(await client.patch('/innings/$matchId/reduce-overs', data: {
        'reducedOvers': reducedOvers,
        if (revisedTarget != null) 'revisedTarget': revisedTarget,
        if (inningsNumber != null) 'inningsNumber': inningsNumber,
        if (method != null) 'method': method,
      }));

  Future<Map<String, dynamic>> superOver(String matchId) async => asMap(await client.patch('/innings/$matchId/super-over', data: {}));
  Future<void> endTie(String matchId) => client.patch('/innings/$matchId/end-tie', data: {});

  Future<Map<String, dynamic>> endMatchOutcome(String matchId, Map<String, dynamic> body) async =>
      asMap(await client.post('/matches/$matchId/end-outcome', data: body));

  Future<void> recordDrs(String matchId, Map<String, dynamic> body) => client.post('/matches/$matchId/drs-review', data: body);

  Future<List<Map<String, dynamic>>> impactSubs(String matchId) async => _list(await client.get('/impact-player/$matchId'));
  Future<void> registerImpactSub(Map<String, dynamic> body) => client.post('/impact-player', data: body);

  // ───────────── Analytics ─────────────
  Future<Map<String, dynamic>?> insights(String matchId) async {
    try {
      return asMap(await client.get('/match-analytics/$matchId/insights'));
    } on ApiException {
      return null;
    }
  }

  Future<Map<String, dynamic>> overSummary(String matchId) async => asMap(await client.get('/match-analytics/$matchId/over-summary'));
  Future<Map<String, dynamic>> partnerships(String matchId) async => asMap(await client.get('/match-analytics/$matchId/partnerships'));
  Future<Map<String, dynamic>> bowlerAnalytics(String matchId) async => asMap(await client.get('/match-analytics/$matchId/bowler-stats'));

  // ───────────── Users (officials search) ─────────────
  Future<List<Map<String, dynamic>>> users({String? role, String? q}) async =>
      _list(await client.get('/users', query: {'role': role, 'q': q}));

  // ───────────── Sponsors ─────────────
  Future<List<Map<String, dynamic>>> sponsors() async => _list(await client.get('/sponsors'));
  Future<List<Map<String, dynamic>>> tournamentSponsors(String tournamentId) async {
    final rows = _list(await client.get('/tournament-sponsors', query: {'tournamentId': tournamentId}));
    return rows.map((r) => {...asMap(r['sponsor']), 'type': r['type']}).where((s) => s['id'] != null).toList();
  }

  Future<Map<String, dynamic>> createSponsor(Map<String, dynamic> d) async => asMap(await client.post('/sponsors', data: d));
  Future<void> linkSponsor(String tournamentId, String sponsorId, {String? type}) =>
      client.post('/tournament-sponsors', data: {'tournamentId': tournamentId, 'sponsorId': sponsorId, if (type != null) 'type': type});
  Future<void> unlinkSponsor(String tournamentId, String sponsorId) => client.delete('/tournament-sponsors/$tournamentId/$sponsorId');
  Future<void> updateSponsor(String id, Map<String, dynamic> d) => client.put('/sponsors/$id', data: d);
  Future<void> deleteSponsor(String id) => client.delete('/sponsors/$id');
  Future<void> updateTournamentSponsorType(String tournamentId, String sponsorId, String? type) =>
      client.put('/tournament-sponsors/$tournamentId/$sponsorId', data: {'type': type});

  // ───────────── Tournament structure & staff ─────────────
  Future<void> saveTournamentStructure(String id, {required List<Map<String, dynamic>> groups, required List<String> stages}) =>
      client.put('/tournaments/$id/structure', data: {'groups': groups, 'stages': stages});

  Future<List<Map<String, dynamic>>> scorerAdmins(String id) async => _list(await client.get('/tournaments/$id/scorer-admins'));
  Future<void> addScorerAdmin(String id, Map<String, dynamic> body) => client.post('/tournaments/$id/scorer-admins', data: body);
  Future<void> removeScorerAdmin(String id, String staffId) => client.delete('/tournaments/$id/scorer-admins/$staffId');

  Future<Map<String, dynamic>> liveStreamers(String id) async => asMap(await client.get('/tournaments/$id/live-streamers'));
  Future<void> addLiveStreamer(String id, Map<String, dynamic> body) => client.post('/tournaments/$id/live-streamers', data: body);
  Future<void> removeLiveStreamer(String id, String streamerId) => client.delete('/tournaments/$id/live-streamers/$streamerId');

  // ───────────── Scoring extras ─────────────
  Future<void> persistOptionalPowerplay(String matchId, Map<String, dynamic> body) =>
      client.post('/matches/$matchId/settings/optional-powerplay', data: body);
  Future<void> matchEndMeta(String matchId, Map<String, dynamic> body) => client.post('/matches/$matchId/match-end-meta', data: body);
  Future<Map<String, dynamic>> aiCommentary(String matchId, {String lang = 'en'}) async =>
      asMap(await client.post('/matches/$matchId/ai-commentary', data: {'lang': lang}));
  Future<Map<String, dynamic>> fallOfLastWicket(String matchId) async => asMap(await client.get('/matches/$matchId/fall-of-last-wicket'));

  // ───────────── Users / admin ─────────────
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> body) async => asMap(await client.post('/users', data: body));
  Future<void> updateUser(String id, Map<String, dynamic> body) => client.put('/users/$id', data: body);
  Future<void> deleteUser(String id) => client.delete('/users/$id');

  Future<Map<String, dynamic>> billingPlansRaw() async => asMap(await client.get('/billing/plans'));
  Future<Map<String, dynamic>> subscribe(String planId) async => asMap(await client.post('/billing/subscribe', data: {'planId': planId}));

  // ───────────── Imports / uploads ─────────────
  Future<List<int>> template(String kind) => client.downloadBytes('/$kind/import/template');
  Future<Map<String, dynamic>> importExcel(String kind, File file, {String? tournamentId}) async =>
      asMap(await client.uploadFile('/$kind/import', file, fields: {if (tournamentId != null) 'tournamentId': tournamentId}));
  Future<Map<String, dynamic>> uploadHistoricalMatch(File file) async => asMap(await client.uploadFile('/historical-match/upload', file));
  Future<List<int>> formatProfilesTemplate(String format, List<String> playerIds) =>
      client.downloadBytes('/player-format-profiles/template', data: {'format': format, 'playerIds': playerIds});
  Future<Map<String, dynamic>> uploadFormatProfiles(String format, File file) async =>
      asMap(await client.uploadFile('/player-format-profiles/upload', file, fields: {'format': format}));

  // ───────────── Public (no login) ─────────────
  Future<Map<String, dynamic>> completePublic({String? matchId, int? matchSeq}) async =>
      asMap(await client.get('/matches/complete-public', query: {'matchId': matchId, 'matchSeq': matchSeq}));
  Future<Map<String, dynamic>> weather(String input, {String? fallback}) async =>
      asMap(await client.get('/weather/resolve', query: {'input': input, 'fallback': fallback}));
}
