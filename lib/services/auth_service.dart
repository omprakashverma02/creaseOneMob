import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config.dart';
import '../core/cricket.dart';
import '../data/api_client.dart';
import '../data/crease_api.dart';
import '../data/models.dart';

enum AuthStatus { loading, signedOut, needsProfile, signedIn, guest }

class AuthService extends ChangeNotifier {
  AuthService(this.api) {
    api.client.onUnauthorized = () {
      if (status == AuthStatus.signedIn) signOut();
    };
  }

  final CreaseApi api;
  final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: AppConfig.googleWebClientId,
  );

  AuthStatus status = AuthStatus.loading;
  AuthUser? user;

  /// When signed in with match-scoped scorer credentials.
  String? scorerMatchId;

  /// Pending Google credential + profile while the user picks a role.
  String? pendingCredential;
  Map<String, dynamic>? pendingUser;

  bool get isScorerSession => scorerMatchId != null;

  Future<void> bootstrap() async {
    final token = await api.client.readToken();
    if (token == null || token.isEmpty) {
      _set(AuthStatus.signedOut);
      return;
    }
    try {
      final me = await api.me();
      _applyMe(me);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await api.client.clearToken();
        _set(AuthStatus.signedOut);
      } else {
        // Offline: keep the token, show the app; screens surface their own errors.
        user = AuthUser({'id': '', 'email': '', 'name': 'Offline', 'role': 'viewer'});
        _set(AuthStatus.signedIn);
      }
    }
  }

  void _applyMe(Map<String, dynamic> me) {
    if (me['scorer'] == true) {
      final m = asMap(me['match']);
      scorerMatchId = m['id']?.toString();
      user = AuthUser({'id': 'scorer', 'email': '', 'name': 'Match Scorer #${m['matchSeq'] ?? ''}', 'role': 'scorer'});
    } else {
      scorerMatchId = null;
      user = AuthUser(asMap(me['user'] ?? me));
    }
    _set(AuthStatus.signedIn);
  }

  Future<void> _completeLogin(Map<String, dynamic> res) async {
    final token = res['token']?.toString();
    if (token == null || token.isEmpty) throw ApiException(res['error']?.toString() ?? 'Sign-in failed');
    await api.client.saveToken(token);
    scorerMatchId = null;
    user = AuthUser(asMap(res['user']));
    pendingCredential = null;
    pendingUser = null;
    _set(AuthStatus.signedIn);
  }

  /// Native Google account picker → ID token for the Web client → backend JWT.
  Future<void> signInWithGoogle() async {
    GoogleSignInAccount? account;
    try {
      await _google.signOut(); // always show the account chooser
      account = await _google.signIn();
    } on PlatformException catch (e) {
      throw ApiException(_explainGoogleError(e));
    }
    if (account == null) throw ApiException('Google sign-in was cancelled');
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw ApiException('Google did not return an ID token. Check that the Web client ID is configured as serverClientId.');
    }
    final res = await api.googleLogin(idToken);
    if (res['needsRoleSelection'] == true) {
      pendingCredential = idToken;
      pendingUser = asMap(res['user']);
      _set(AuthStatus.needsProfile);
      return;
    }
    await _completeLogin(res);
  }

  String _explainGoogleError(PlatformException e) {
    final msg = '${e.code} ${e.message ?? ''}';
    if (msg.contains('sign_in_canceled')) return 'Google sign-in was cancelled';
    if (msg.contains('network_error')) return 'Network error during Google sign-in';
    if (msg.contains('10') || msg.toLowerCase().contains('developer_error') || msg.contains('sign_in_failed')) {
      return 'Google sign-in is not configured for this build. Register the app\'s SHA-1 for package '
          'com.creaseone.cticker on the Android OAuth client in Google Cloud Console. ($msg)';
    }
    return 'Google sign-in failed: $msg';
  }

  Future<void> completeProfile({required String role, String? contactNumber, Map<String, dynamic>? playerData}) async {
    final cred = pendingCredential;
    if (cred == null) throw ApiException('Session expired. Please sign in with Google again.');
    final res = await api.completeProfile({
      'credential': cred,
      'role': role,
      if (contactNumber != null && contactNumber.isNotEmpty) 'contactNumber': contactNumber,
      if (playerData != null) 'playerData': playerData,
    });
    await _completeLogin(res);
  }

  Future<void> signInWithEmail(String email, String password) async => _completeLogin(await api.signIn(email, password));

  Future<void> signUpWithEmail({required String name, required String email, required String password, required String role, required String contact}) async {
    await _completeLogin(await api.signUp({'name': name, 'email': email.trim(), 'password': password, 'role': role, 'contactNumber': contact}));
  }

  Future<void> scorerLogin({required String match, required String username, required String password}) async {
    final res = await api.scorerLogin(match: match, username: username, password: password);
    final token = res['token']?.toString();
    if (token == null) throw ApiException('Scorer login failed');
    await api.client.saveToken(token);
    final m = asMap(res['match']);
    scorerMatchId = m['id']?.toString();
    user = AuthUser({'id': 'scorer', 'email': '', 'name': 'Match Scorer #${m['matchSeq'] ?? ''}', 'role': 'scorer'});
    _set(AuthStatus.signedIn);
  }

  Future<void> refreshMe() async {
    try {
      _applyMe(await api.me());
    } catch (_) {}
  }

  Future<void> cancelProfile() async {
    pendingCredential = null;
    pendingUser = null;
    await _google.signOut().catchError((_) => null);
    _set(AuthStatus.signedOut);
  }

  /// Read-only public mode (no login): live/public scorecards, tournaments, points tables.
  void continueAsGuest() => _set(AuthStatus.guest);

  void leaveGuest() => _set(AuthStatus.signedOut);

  Future<void> signOut() async {
    await api.client.clearToken();
    try {
      await _google.signOut();
    } catch (_) {}
    user = null;
    scorerMatchId = null;
    _set(AuthStatus.signedOut);
  }

  void _set(AuthStatus s) {
    status = s;
    notifyListeners();
  }
}
