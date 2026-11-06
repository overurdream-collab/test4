import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_models.dart';

class QatLinkApi {
  QatLinkApi({
    required Uri baseUri,
    http.Client? client,
    AuthSession? initialSession,
    this.requestTimeout = const Duration(seconds: 25),
    Future<void> Function(AuthSession session)? onSessionChanged,
  }) : baseUri = _normalizeBase(baseUri),
       session = initialSession,
       _client = client ?? http.Client(),
       _onSessionChanged = onSessionChanged {
    if (this.baseUri.scheme != 'https' && this.baseUri.scheme != 'http') {
      throw ArgumentError.value(
        baseUri,
        'baseUri',
        'Only HTTP(S) is supported',
      );
    }
  }

  final Uri baseUri;
  final Duration requestTimeout;
  final http.Client _client;
  final Future<void> Function(AuthSession session)? _onSessionChanged;

  AuthSession? session;

  static Uri _normalizeBase(Uri value) {
    final path = value.path.endsWith('/')
        ? value.path.substring(0, value.path.length - 1)
        : value.path;
    return value.replace(path: path);
  }

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final suffix = segments.map(Uri.encodeComponent).join('/');
    return baseUri.replace(
      path: '${baseUri.path}/$suffix',
      queryParameters: query,
    );
  }

  Future<Map<String, Object?>> _request({
    required String method,
    required List<String> segments,
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
    Map<String, String>? extraHeaders,
    bool allowRefresh = true,
  }) async {
    final headers = <String, String>{
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      ...?extraHeaders,
    };
    if (authenticated) {
      final token = session?.accessToken;
      if (token == null || token.isEmpty) {
        throw const ApiException(401, 'authentication_required');
      }
      headers['authorization'] = 'Bearer $token';
    }

    final request = http.Request(method, _uri(segments, query));
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    final streamed = await _client.send(request).timeout(requestTimeout);
    final response = await http.Response.fromStream(
      streamed,
    ).timeout(requestTimeout);
    Map<String, Object?> decoded = const {};
    if (response.body.trim().isNotEmpty) {
      try {
        final value = jsonDecode(response.body);
        if (value is Map) decoded = Map<String, Object?>.from(value);
      } on FormatException {
        decoded = const {};
      }
    }

    if (response.statusCode == 401 && authenticated && allowRefresh) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        return _request(
          method: method,
          segments: segments,
          query: query,
          body: body,
          authenticated: authenticated,
          extraHeaders: extraHeaders,
          allowRefresh: false,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code =
          decoded['error']?.toString() ?? 'http_${response.statusCode}';
      throw ApiException(response.statusCode, code);
    }
    return decoded;
  }

  Future<bool> _refreshTokens() async {
    final current = session;
    if (current == null || current.refreshToken.isEmpty) return false;
    try {
      final response = await _request(
        method: 'POST',
        segments: ['v1', 'auth', 'refresh'],
        body: {'refreshToken': current.refreshToken},
        authenticated: false,
        allowRefresh: false,
      );
      final next = current.copyWith(
        accessToken: response['accessToken']! as String,
        refreshToken: response['refreshToken']! as String,
        accessExpiresAt: DateTime.parse(response['expiresAt']! as String),
        refreshExpiresAt: DateTime.parse(
          response['refreshExpiresAt']! as String,
        ),
      );
      session = next;
      await _onSessionChanged?.call(next);
      return true;
    } on Object {
      session = null;
      return false;
    }
  }

  Future<void> requestOtp(String phoneE164) async {
    await _request(
      method: 'POST',
      segments: ['v1', 'auth', 'otp', 'request'],
      body: {'phoneE164': phoneE164},
      authenticated: false,
    );
  }

  Future<AuthSession> verifyOtp({
    required String phoneE164,
    required String code,
    required String deviceId,
    required String deviceLabel,
    required String platform,
  }) async {
    final response = await _request(
      method: 'POST',
      segments: ['v1', 'auth', 'otp', 'verify'],
      body: {
        'phoneE164': phoneE164,
        'code': code,
        'deviceId': deviceId,
        'deviceLabel': deviceLabel,
        'platform': platform,
      },
      authenticated: false,
    );
    final user = _map(response['user']);
    final session = AuthSession(
      accessToken: response['accessToken']! as String,
      refreshToken: response['refreshToken']! as String,
      userId: user['id']! as String,
      phoneE164: user['phoneE164']! as String,
      deviceId: response['deviceId']! as String,
      accessExpiresAt: DateTime.parse(response['expiresAt']! as String),
      refreshExpiresAt: DateTime.parse(response['refreshExpiresAt']! as String),
    );
    this.session = session;
    await _onSessionChanged?.call(session);
    return session;
  }

  Future<RemoteUser> me() async {
    final response = await _request(method: 'GET', segments: ['v1', 'me']);
    final user = _map(response['user']);
    return RemoteUser(
      id: user['id']! as String,
      phoneE164: user['phoneE164']! as String,
      deviceId: response['deviceId']! as String,
      displayName: user['displayName'] as String?,
      locale: user['locale'] as String? ?? 'ar',
    );
  }

  Future<void> updateProfile(String displayName) async {
    await _request(
      method: 'PATCH',
      segments: ['v1', 'me'],
      body: {'displayName': displayName},
    );
  }

  Future<void> logout() async {
    try {
      await _request(
        method: 'POST',
        segments: ['v1', 'auth', 'logout'],
        body: const {},
      );
    } finally {
      session = null;
    }
  }

  Future<List<RemoteRelationship>> relationships() async {
    final response = await _request(
      method: 'GET',
      segments: ['v1', 'relationships'],
    );
    return _list(response['relationships']).map((raw) {
      final item = _map(raw);
      final other = item['otherParty'];
      return RemoteRelationship(
        relationshipId: item['relationshipId']! as String,
        relationshipType: item['relationshipType'] as String?,
        status: item['status']! as String,
        currentCycleId: item['currentCycleId']! as String,
        myRole: item['myRole']! as String,
        otherParty: other is Map
            ? RemoteParty(
                userId: _map(other)['userId']! as String,
                role: _map(other)['role'] as String? ?? '',
                displayName: _map(other)['displayName'] as String?,
                phoneE164: _map(other)['phoneE164'] as String?,
              )
            : null,
      );
    }).toList();
  }

  Future<RemoteAccountCycles> accountCycles(String relationshipId) async {
    final response = await _request(
      method: 'GET',
      segments: ['v1', 'relationships', relationshipId, 'account-cycles'],
    );
    return RemoteAccountCycles(
      currentCycleId: response['currentCycleId']! as String,
      cycles: _list(response['cycles'])
          .map((raw) {
            final item = _map(raw);
            return RemoteCycle(
              cycleId: item['cycleId']! as String,
              cycleNumber: _int(item['cycleNumber']),
              title: item['title'] as String? ?? '',
              status: item['status'] as String? ?? 'active',
              startedAt: _date(item['startedAt']),
              endedAt: _date(item['endedAt']),
              balances: _list(item['balances'])
                  .map((balanceRaw) {
                    final balance = _map(balanceRaw);
                    return RemoteBalance(
                      ownerUserId: balance['ownerUserId']! as String,
                      currency: balance['currency']! as String,
                      receivableMinor: _int(balance['receivableMinor']),
                      payableMinor: _int(balance['payableMinor']),
                      partyBalanceMinor: _int(balance['partyBalanceMinor']),
                      unappliedPaymentAssetMinor: _int(
                        balance['unappliedPaymentAssetMinor'],
                      ),
                      unappliedPaymentLiabilityMinor: _int(
                        balance['unappliedPaymentLiabilityMinor'],
                      ),
                    );
                  })
                  .toList(growable: false),
            );
          })
          .toList(growable: false),
    );
  }

  Future<List<RemoteOperation>> operations(String relationshipId) async {
    final output = <RemoteOperation>[];
    var after = 0;
    for (var page = 0; page < 100; page++) {
      final response = await _request(
        method: 'GET',
        segments: ['v1', 'relationships', relationshipId, 'operations'],
        query: {'after': '$after', 'limit': '200'},
      );
      final raw = _list(response['operations']);
      for (final value in raw) {
        final item = _map(value);
        final decision = item['decision'];
        output.add(
          RemoteOperation(
            operationId: item['operationId']! as String,
            actorUserId: item['actorUserId']! as String,
            operationType: item['operationType']! as String,
            businessState: item['businessState']! as String,
            baseVersion: _int(item['baseVersion']),
            serverVersion: _int(item['serverVersion']),
            serverSequence: _int(item['serverSequence']),
            payload: _map(item['payload']),
            clientCreatedAt: _date(item['clientCreatedAt']),
            serverCreatedAt: _date(item['serverCreatedAt']),
            decision: decision is Map
                ? RemoteDecision(
                    decision: _map(decision)['decision']! as String,
                    reason: _map(decision)['reason'] as String?,
                    actorUserId: _map(decision)['actorUserId'] as String?,
                    decidedAt: _date(_map(decision)['decidedAt']),
                  )
                : null,
          ),
        );
      }
      after = _int(response['nextCursor']);
      if (response['hasMore'] != true) break;
    }
    return output;
  }

  Future<RemoteOperationResult> submitOperation({
    required String relationshipId,
    required String operationId,
    required String operationType,
    required Map<String, Object?> payload,
    int baseVersion = 0,
    DateTime? clientCreatedAt,
  }) async {
    final response = await _request(
      method: 'POST',
      segments: ['v1', 'relationships', relationshipId, 'operations'],
      body: {
        'operationId': operationId,
        'operationType': operationType,
        'schemaVersion': 1,
        'baseVersion': baseVersion,
        'payload': payload,
        'clientCreatedAt': (clientCreatedAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      },
    );
    return RemoteOperationResult(
      outcome: response['outcome']! as String,
      operationId: response['operationId']! as String,
      businessState: response['businessState']! as String,
      serverVersion: _int(response['serverVersion']),
      serverSequence: _int(response['serverSequence']),
    );
  }

  Future<void> decideOperation({
    required String relationshipId,
    required String operationId,
    required String decision,
    required int expectedVersion,
    String? reason,
    required String idempotencyKey,
  }) async {
    await _request(
      method: 'POST',
      segments: [
        'v1',
        'relationships',
        relationshipId,
        'operations',
        operationId,
        'decision',
      ],
      extraHeaders: {'idempotency-key': idempotencyKey},
      body: {
        'decision': decision,
        'expectedVersion': expectedVersion,
        'reason': ?reason,
      },
    );
  }

  Future<RemoteSettlementRequest?> pendingSettlement(
    String relationshipId,
  ) async {
    final response = await _request(
      method: 'GET',
      segments: [
        'v1',
        'relationships',
        relationshipId,
        'settlement-reset-requests',
        'pending',
      ],
    );
    final request = response['request'];
    if (request is! Map) return null;
    final item = _map(request);
    return RemoteSettlementRequest(
      requestId: item['requestId']! as String,
      requestedByUserId: item['requestedByUserId']! as String,
      requestedAt: _date(item['requestedAt']),
    );
  }

  Future<String> requestSettlement({
    required String relationshipId,
    required String idempotencyKey,
  }) async {
    final response = await _request(
      method: 'POST',
      segments: [
        'v1',
        'relationships',
        relationshipId,
        'settlement-reset-requests',
      ],
      extraHeaders: {'idempotency-key': idempotencyKey},
      body: const {},
    );
    return response['requestId']! as String;
  }

  Future<void> decideSettlement({
    required String relationshipId,
    required String requestId,
    required String decision,
    String? reason,
    required String idempotencyKey,
  }) async {
    await _request(
      method: 'POST',
      segments: [
        'v1',
        'relationships',
        relationshipId,
        'settlement-reset-requests',
        requestId,
        'decision',
      ],
      extraHeaders: {'idempotency-key': idempotencyKey},
      body: {'decision': decision, 'reason': ?reason},
    );
  }

  Future<List<RemoteDevice>> devices() async {
    final response = await _request(method: 'GET', segments: ['v1', 'devices']);
    return _list(response['devices']).map((raw) {
      final item = _map(raw);
      return RemoteDevice(
        id: item['id']! as String,
        label: item['label'] as String? ?? '',
        platform: item['platform'] as String? ?? '',
        status: item['status'] as String? ?? '',
        isCurrent: item['isCurrent'] == true,
        registeredAt: _date(item['registeredAt']),
        lastSeenAt: _date(item['lastSeenAt']),
      );
    }).toList();
  }

  Future<void> revokeDevice(String deviceId) async {
    await _request(
      method: 'POST',
      segments: ['v1', 'devices', deviceId, 'revoke'],
      body: const {},
    );
  }

  Future<List<RemoteInvitation>> invitations() async {
    final response = await _request(
      method: 'GET',
      segments: ['v1', 'relationship-invitations'],
    );
    return _list(response['invitations']).map((raw) {
      final item = _map(raw);
      final inviter = _map(item['inviter']);
      return RemoteInvitation(
        invitationId: item['invitationId']! as String,
        relationshipId: item['relationshipId']! as String,
        relationshipType: item['relationshipType']! as String,
        inviterUserId: inviter['userId']! as String,
        inviterDisplayName: inviter['displayName'] as String?,
        inviteePhoneE164: inviter['phoneE164'] as String? ?? '',
        inviterRole: inviter['role'] as String? ?? '',
        inviteeRole: item['myRole'] as String? ?? '',
        status: 'pending',
        expiresAt: _date(item['expiresAt']),
      );
    }).toList();
  }

  Future<String> decideInvitation({
    required String invitationId,
    required String decision,
    String? reason,
    required String idempotencyKey,
  }) async {
    final response = await _request(
      method: 'POST',
      segments: ['v1', 'relationship-invitations', invitationId, 'decision'],
      extraHeaders: {'idempotency-key': idempotencyKey},
      body: {'decision': decision, 'reason': ?reason},
    );
    return response['status']! as String;
  }

  Future<CreatedInvitation> inviteRelationship({
    required String inviteePhoneE164,
    required String relationshipType,
    required String myRole,
    required String idempotencyKey,
  }) async {
    final response = await _request(
      method: 'POST',
      segments: ['v1', 'relationships'],
      extraHeaders: {'idempotency-key': idempotencyKey},
      body: {
        'inviteePhoneE164': inviteePhoneE164,
        'relationshipType': relationshipType,
        'myRole': myRole,
      },
    );
    return CreatedInvitation(
      invitationId: response['invitationId']! as String,
      relationshipId: response['relationshipId']! as String,
      status: response['status']! as String,
      expiresAt: _date(response['expiresAt']),
    );
  }

  void close() => _client.close();
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('Expected a JSON object');
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _date(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

String normalizePhoneE164(String input) {
  var value = input.replaceAll(RegExp(r'[^0-9+]'), '');
  if (value.startsWith('00')) value = value.substring(2);
  if (!value.startsWith('+')) {
    if (value.startsWith('967')) {
      value = '+$value';
    } else if (value.startsWith('0')) {
      value = '+967${value.substring(1)}';
    } else {
      value = '+967$value';
    }
  }
  return value;
}
