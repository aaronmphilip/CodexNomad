import 'dart:async';
import 'dart:convert';

import 'package:codex_nomad/core/config/app_config.dart';
import 'package:codex_nomad/core/services/crypto_service.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class RelayEvent {
  const RelayEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

class RelayService {
  RelayService(this.config);

  final AppConfig config;
  WebSocketChannel? _channel;
  CryptoService? _crypto;
  PairingPayload? _pairing;
  final _events = StreamController<RelayEvent>.broadcast();
  Timer? _pingTimer;

  Stream<RelayEvent> get events => _events.stream;

  Future<void> connect(PairingPayload pairing) async {
    if (pairing.isExpired) {
      throw StateError('Pairing QR expired. Start a new daemon session.');
    }
    await close();
    _pairing = pairing;
    _crypto = await CryptoService.create()
      ..setPeerPublicKey(pairing.publicKey);

    final uri = await _relayUri(pairing);
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      _handleRaw,
      onError: (dynamic error) {
        _events.add(RelayEvent('disconnect', {'error': '$error'}));
      },
      onDone: () {
        _events.add(const RelayEvent('disconnect', {}));
      },
      cancelOnError: false,
    );

    _sendPlain({
      'type': 'mobile_hello',
      'sid': pairing.sessionId,
      'role': 'mobile',
      'public_key': _crypto!.publicKey,
    });

    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _sendPlain({'type': 'ping', 'sid': pairing.sessionId, 'role': 'mobile'});
    });
  }

  Future<Uri> _relayUri(PairingPayload pairing) async {
    final relayUri = Uri.parse(pairing.relayUrl);
    if (config.appSharedToken.isEmpty || config.backendBaseUrl.isEmpty) {
      return relayUri;
    }
    final response = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/relay/tickets'),
      headers: {
        'Content-Type': 'application/json',
        'X-CodexNomad-Token': config.appSharedToken,
      },
      body: jsonEncode({
        'session_id': pairing.sessionId,
        'role': 'mobile',
        'ttl_seconds': 900,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return relayUri;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final ticket = json['ticket'] as String?;
    if (ticket == null || ticket.isEmpty) return relayUri;
    return relayUri.replace(
      queryParameters: {
        ...relayUri.queryParameters,
        'ticket': ticket,
      },
    );
  }

  Future<void> sendCommand(String type, Map<String, dynamic> data) async {
    final pairing = _pairing;
    final crypto = _crypto;
    if (pairing == null || crypto == null) {
      throw StateError('No active relay session.');
    }
    final env = crypto.seal(
      sessionId: pairing.sessionId,
      type: type,
      data: data,
    );
    _sendPlain({
      'type': 'ciphertext',
      'sid': pairing.sessionId,
      'role': 'mobile',
      'payload': env,
    });
  }

  void _sendPlain(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _handleRaw(dynamic raw) {
    final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = decoded['type'] as String? ?? '';
    if (type == 'daemon_ready') {
      final key = decoded['public_key'] as String?;
      if (key != null && key.isNotEmpty) {
        _crypto?.setPeerPublicKey(key);
      }
      _events.add(const RelayEvent('session_ready', {}));
      return;
    }
    if (type != 'ciphertext') {
      _events.add(RelayEvent(type, decoded));
      return;
    }
    final payload = decoded['payload'];
    if (payload is! Map) return;
    final message = _crypto!.open(payload.cast<String, dynamic>());
    _events.add(RelayEvent(message.type, message.data));
  }

  Future<void> close() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _channel?.sink.close();
    _channel = null;
    _crypto?.dispose();
    _crypto = null;
  }
}
