import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';

/// Subscribes to `/live` WebSocket for one match and emits snapshot payloads.
/// Reconnects with back-off; callers should still fetch the REST snapshot
/// first so the UI does not depend on the socket.
class LiveMatchSocket {
  LiveMatchSocket({required this.matchId, this.token});

  final String matchId;
  final String? token;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _ping;
  bool _closed = false;
  int _attempt = 0;

  Stream<Map<String, dynamic>> get snapshots => _controller.stream;

  void connect() {
    if (_closed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));
      if (token != null && token!.isNotEmpty) {
        _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      }
      _channel!.sink.add(jsonEncode({'matchId': matchId}));
      _sub = _channel!.stream.listen(_onMessage, onDone: _scheduleReconnect, onError: (_) => _scheduleReconnect());
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    _attempt = 0;
    try {
      final data = jsonDecode(raw.toString());
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final m = map['match'];
      if (m is Map && m['id']?.toString() == matchId) _controller.add(map);
    } catch (_) {}
  }

  void _scheduleReconnect() {
    _sub?.cancel();
    _ping?.cancel();
    if (_closed) return;
    _retry?.cancel();
    _attempt = (_attempt + 1).clamp(1, 6);
    _retry = Timer(Duration(seconds: 2 * _attempt), connect);
  }

  void dispose() {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _controller.close();
  }
}
