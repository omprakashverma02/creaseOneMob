import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide configuration.
///
/// The REST base URL can be changed at runtime (login screen → server settings)
/// or at build time: `flutter run --dart-define=API_BASE=http://192.168.1.10:8080/api`.
class AppConfig {
  AppConfig._();

  static const String appName = 'CreaseOne';
  static const String tagline = 'Every ball. Every player. One platform.';

  /// Local crickDbModule (`npm start`, port 8080) as seen from the Android emulator.
  static const String localEmulatorApi = 'http://10.0.2.2:8080/api';

  /// Production Cloud Run backend used by the web app.
  static const String cloudApi = 'https://crickdbmodule-api-144271912366.asia-south1.run.app/api';

  static const String _defineApi = String.fromEnvironment('API_BASE');

  /// Debug runs (emulator / flutter run) → local crickDbModule; release APKs → deployed Cloud Run API.
  /// `--dart-define=API_BASE=...` overrides both.
  static String get _buildDefault => _defineApi.isNotEmpty ? _defineApi : (kReleaseMode ? cloudApi : localEmulatorApi);

  /// Separate saved override per build mode so a debug choice never leaks into a release build.
  static const _prefsKey = kReleaseMode ? 'creaseone_api_base_release_v1' : 'creaseone_api_base_debug_v1';

  static String _apiBase = _buildDefault;
  static String get apiBase => _apiBase;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_prefsKey);
      if (saved != null && saved.trim().isNotEmpty) _apiBase = saved.trim();
    } catch (_) {}
  }

  static Future<void> setApiBase(String url) async {
    var u = url.trim();
    if (u.isEmpty) u = _buildDefault;
    if (!u.startsWith('http')) u = 'http://$u';
    u = u.replaceFirst(RegExp(r'/+$'), '');
    if (!u.endsWith('/api')) u = '$u/api';
    _apiBase = u;
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, u);
  }

  /// Google **Web** OAuth client ID. The backend verifies ID tokens against this
  /// audience, so Android sign-in must request tokens for it (serverClientId).
  /// The Android OAuth client (package com.creaseone.cticker + SHA-1) is matched
  /// automatically by Google Play services and never appears in code.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '144271912366-iumk5ougdp8ub5g2cqv5beu58ifid7qj.apps.googleusercontent.com',
  );

  /// Android OAuth client registered for com.creaseone.cticker (reference only).
  static const String googleAndroidClientId = '144271912366-6ppg3st38oslpev4i21cr6jta9ornbjd.apps.googleusercontent.com';

  static String get apiOrigin => apiBase.replaceFirst(RegExp(r'/api/?$'), '');

  static String get wsUrl {
    final uri = Uri.parse(apiOrigin);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host}$port/live';
  }

  /// Resolve relative upload paths (`/uploads/x.png`) to absolute URLs.
  static String? resolveImage(String? url) {
    if (url == null) return null;
    final u = url.trim();
    if (u.isEmpty) return null;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('data:')) return null;
    return '$apiOrigin${u.startsWith('/') ? '' : '/'}$u';
  }
}
