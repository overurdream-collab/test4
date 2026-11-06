import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qat_link/src/data/api_models.dart';
import 'package:qat_link/src/data/qat_link_api.dart';

void main() {
  test('normalizes Yemeni phone numbers to E.164', () {
    expect(normalizePhoneE164('0770123456'), '+967770123456');
    expect(normalizePhoneE164('967770123456'), '+967770123456');
    expect(normalizePhoneE164('+967 770 123 456'), '+967770123456');
    expect(normalizePhoneE164('00967 770123456'), '+967770123456');
  });

  test(
    'verifyOtp stores the session and notifies the session listener',
    () async {
      late Map<String, Object?> sent;
      final api = QatLinkApi(
        baseUri: Uri.parse('https://api.qatlink.test'),
        onSessionChanged: (session) async {
          expect(session.accessToken, 'access-1');
        },
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, Object?>;
          return _json({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'expiresAt': '2026-11-05T12:00:00Z',
            'refreshExpiresAt': '2026-12-05T12:00:00Z',
            'user': {'id': 'user-1', 'phoneE164': '+967700000001'},
            'deviceId': 'device-1',
          });
        }),
      );

      final session = await api.verifyOtp(
        phoneE164: '+967700000001',
        code: '123456',
        deviceId: 'device-1',
        deviceLabel: 'Test device',
        platform: 'android',
      );

      expect(session.userId, 'user-1');
      expect(session.deviceId, 'device-1');
      expect(api.session?.refreshToken, 'refresh-1');
      expect(sent['code'], '123456');
    },
  );

  test('refreshes once after a 401 and retries the original request', () async {
    var meCalls = 0;
    var refreshCalls = 0;
    final api = QatLinkApi(
      baseUri: Uri.parse('https://api.qatlink.test'),
      initialSession: AuthSession(
        accessToken: 'expired',
        refreshToken: 'refresh-1',
        userId: 'user-1',
        phoneE164: '+967700000001',
        deviceId: 'device-1',
        accessExpiresAt: DateTime.utc(2026, 11, 5, 12),
        refreshExpiresAt: DateTime.utc(2026, 12, 5, 12),
      ),
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/refresh') {
          refreshCalls++;
          return _json({
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'expiresAt': '2026-11-05T12:00:00Z',
            'refreshExpiresAt': '2026-12-05T12:00:00Z',
          });
        }
        if (request.url.path == '/v1/me') {
          meCalls++;
          if (meCalls == 1) {
            return _json({'error': 'unauthorized'}, status: 401);
          }
          expect(request.headers['authorization'], 'Bearer access-2');
          return _json({
            'user': {
              'id': 'user-1',
              'phoneE164': '+967700000001',
              'displayName': 'أحمد',
              'locale': 'ar',
            },
            'deviceId': 'device-1',
          });
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final me = await api.me();

    expect(me.displayName, 'أحمد');
    expect(refreshCalls, 1);
    expect(meCalls, 2);
    expect(api.session?.accessToken, 'access-2');
  });

  test(
    'pages through relationship operations until hasMore is false',
    () async {
      final cursors = <String>[];
      final api = QatLinkApi(
        baseUri: Uri.parse('https://api.qatlink.test'),
        initialSession: AuthSession(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          userId: 'user-1',
          phoneE164: '+967700000001',
          deviceId: 'device-1',
          accessExpiresAt: DateTime.utc(2026, 11, 5, 12),
          refreshExpiresAt: DateTime.utc(2026, 12, 5, 12),
        ),
        client: MockClient((request) async {
          expect(request.url.path, '/v1/relationships/rel-1/operations');
          final after = request.url.queryParameters['after']!;
          cursors.add(after);
          if (after == '0') {
            return _json({
              'operations': [_operation(sequence: 1)],
              'nextCursor': 1,
              'hasMore': true,
            });
          }
          return _json({
            'operations': [_operation(sequence: 2)],
            'nextCursor': 2,
            'hasMore': false,
          });
        }),
      );

      final operations = await api.operations('rel-1');

      expect(cursors, ['0', '1']);
      expect(operations.map((item) => item.operationId), ['op-1', 'op-2']);
    },
  );
}

http.Response _json(Map<String, Object?> body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, Object?> _operation({required int sequence}) {
  return {
    'operationId': 'op-$sequence',
    'actorUserId': 'user-2',
    'operationType': 'credit_charge',
    'businessState': 'awaiting_counterparty',
    'baseVersion': 0,
    'serverVersion': 1,
    'serverSequence': sequence,
    'payload': {'amountMinor': '1200000', 'currency': 'YER'},
    'clientCreatedAt': '2026-11-05T10:00:00Z',
    'serverCreatedAt': '2026-11-05T10:00:01Z',
    'decision': null,
  };
}
