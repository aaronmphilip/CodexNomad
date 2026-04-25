import 'dart:async';
import 'dart:convert';

import 'package:codex_nomad/core/config/app_config.dart';
import 'package:codex_nomad/core/services/crypto_service.dart';
import 'package:codex_nomad/core/services/local_device_key_store.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:flutter/foundation.dart';
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
  final LocalDeviceKeyStore _deviceKeyStore = LocalDeviceKeyStore();
  WebSocketChannel? _channel;
  CryptoService? _crypto;
  PairingPayload? _pairing;
  final _events = StreamController<RelayEvent>.broadcast();
  Timer? _pingTimer;

  Stream<RelayEvent> get events => _events.stream;

  bool canResume(PairingPayload pairing) {
    return _crypto != null && _pairing?.sessionId == pairing.sessionId;
  }

  Future<void> connect(PairingPayload pairing) async {
    final reuseCrypto = canResume(pairing);
    await _closeSocket();
    _pairing = pairing;
    if (!reuseCrypto) {
      _crypto?.dispose();
      final seed =
          await _deviceKeyStore.loadOrCreateBoxSeed(CryptoService.boxSeedBytes);
      final initialSequence =
          await _deviceKeyStore.loadSequence(pairing.sessionId);
      _crypto = await CryptoService.create(
        seed: seed,
        initialSequence: initialSequence,
      );
      await _crypto!.setPeerPublicKey(pairing.publicKey);
    } else {
      await _crypto!.setPeerPublicKey(pairing.publicKey);
    }

    final uri = await _relayUri(pairing);
    debugPrint('CodexNomad relay connect: $uri');
    _events.add(RelayEvent('connecting', {'url': uri.toString()}));
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    channel.stream.listen(
      _handleRaw,
      onError: (dynamic error) {
        if (!identical(_channel, channel)) return;
        debugPrint('CodexNomad relay error: $error');
        _events.add(RelayEvent('disconnect', {'error': '$error'}));
      },
      onDone: () {
        if (!identical(_channel, channel)) return;
        debugPrint('CodexNomad relay closed');
        _events.add(
            const RelayEvent('disconnect', {'error': 'Relay socket closed'}));
      },
      cancelOnError: false,
    );

    final mobilePublicKey = _crypto!.publicKey;
    _sendPlain({
      'type': 'mobile_hello',
      'sid': pairing.sessionId,
      'role': 'mobile',
      'public_key': mobilePublicKey,
      'device_id': _deviceIdForPublicKey(mobilePublicKey),
      'device_name': 'Codex Nomad phone',
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
    final env = await crypto.seal(
      sessionId: pairing.sessionId,
      type: type,
      data: data,
    );
    await _deviceKeyStore.saveSequence(pairing.sessionId, crypto.sequence);
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
    unawaited(_handleRawAsync(raw));
  }

  Future<void> _handleRawAsync(dynamic raw) async {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = decoded['type'] as String? ?? '';
      debugPrint('CodexNomad relay frame: $type');
      if (type == 'daemon_ready') {
        final key = decoded['public_key'] as String?;
        if (key != null && key.isNotEmpty) {
          await _crypto?.setPeerPublicKey(key);
        }
        _events.add(RelayEvent('session_ready', {
          'device_id': decoded['device_id'],
        }));
        return;
      }
      if (type == 'pairing_expired') {
        _events.add(const RelayEvent('pairing_expired', {
          'message':
              'Pairing expired. Start a new local session and scan again.',
        }));
        return;
      }
      if (type == 'device_identity_required') {
        _events.add(const RelayEvent('error', {
          'message': 'This app build is missing a trusted phone identity.',
        }));
        return;
      }
      if (type == 'device_authorization_failed') {
        _events.add(const RelayEvent('error', {
          'message': 'The machine could not save this phone as trusted.',
        }));
        return;
      }
      if (type != 'ciphertext') {
        _events.add(RelayEvent(type, decoded));
        return;
      }
      final payload = decoded['payload'];
      if (payload is! Map) return;
      final message = await _crypto!.open(payload.cast<String, dynamic>());
      _events.add(RelayEvent(message.type, message.data));
    } catch (error, stack) {
      debugPrint('CodexNomad relay frame handling failed: $error\n$stack');
      _events.add(RelayEvent('error', {'message': '$error'}));
    }
  }

  Future<void> close() async {
    await _closeSocket();
    _crypto?.dispose();
    _crypto = null;
    _pairing = null;
  }

  Future<void> _closeSocket() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  String _deviceIdForPublicKey(String publicKey) {
    final prefixLength = publicKey.length < 22 ? publicKey.length : 22;
    return 'mobile_${publicKey.substring(0, prefixLength)}';
  }
}
