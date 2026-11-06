import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_models.dart';

const _sessionKey = 'qat_link_auth_session_v1';
const _deviceIdKey = 'qat_link_device_id_v1';

abstract interface class QatLinkSessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();

  Future<String> deviceId();
}

class SecureQatLinkSessionStore implements QatLinkSessionStore {
  SecureQatLinkSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AuthSession.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) {
    return _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);

  @override
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = generateUuidV4();
    await _storage.write(key: _deviceIdKey, value: created);
    return created;
  }
}

class MemoryQatLinkSessionStore implements QatLinkSessionStore {
  MemoryQatLinkSessionStore({AuthSession? session, String? deviceId})
    : _session = session,
      _deviceId = deviceId ?? generateUuidV4();

  AuthSession? _session;
  final String _deviceId;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;

  @override
  Future<String> deviceId() async => _deviceId;
}

String generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
