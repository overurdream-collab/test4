import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qat_link/src/data/api_models.dart';
import 'package:qat_link/src/data/qat_link_api.dart';
import 'package:qat_link/src/data/session_store.dart';
import 'package:qat_link/src/models.dart';
import 'package:qat_link/src/state/app_state.dart';

void main() {
  test('remote login loads relationships, balances and operations', () async {
    final api = QatLinkApi(
      baseUri: Uri.parse('https://api.qatlink.test'),
      client: MockClient(_handler),
    );
    final state = AppState(
      seed: false,
      api: api,
      sessionStore: MemoryQatLinkSessionStore(deviceId: 'device-1'),
    );

    await state.verifyOtp(phone: '+967 700 000 001', code: '123456');

    expect(state.loggedIn, isTrue);
    expect(state.isRemote, isTrue);
    expect(state.user.name, 'أحمد الصبري');
    expect(state.contacts, hasLength(1));
    expect(state.contacts.single.name, 'أبو أحمد');
    expect(state.contacts.single.balanceMinor, 1200000);
    expect(state.contacts.single.pendingMinor, 1200000);
    expect(state.entries, hasLength(1));
    expect(state.merchantEntries, hasLength(1));

    final entry = state.entries.single;
    expect(entry.id, 'op-1');
    expect(entry.type, OperationType.charge);
    expect(entry.status, TxStatus.pending);
    expect(entry.createdByMe, isTrue);
    expect(entry.serverVersion, 1);
    expect(state.persona, AppPersona.merchant);
    expect(state.sessions.single.current, isTrue);
  });

  test('bootstrap restores a stored session before loading data', () async {
    final session = AuthSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      userId: 'user-1',
      phoneE164: '+967700000001',
      deviceId: 'device-1',
      accessExpiresAt: DateTime.utc(2026, 11, 5, 12),
      refreshExpiresAt: DateTime.utc(2026, 12, 5, 12),
    );
    final api = QatLinkApi(
      baseUri: Uri.parse('https://api.qatlink.test'),
      client: MockClient(_handler),
    );
    final state = AppState(
      seed: false,
      api: api,
      sessionStore: MemoryQatLinkSessionStore(
        session: session,
        deviceId: 'device-1',
      ),
    );

    await state.bootstrap();

    expect(state.loggedIn, isTrue);
    expect(state.bootstrapped, isTrue);
    expect(state.contacts.single.id, 'rel-1');
    expect(api.session?.userId, 'user-1');
  });

  test('remote logout clears loaded identity and relationship state', () async {
    final api = QatLinkApi(
      baseUri: Uri.parse('https://api.qatlink.test'),
      client: MockClient(_handler),
    );
    final state = AppState(
      seed: false,
      api: api,
      sessionStore: MemoryQatLinkSessionStore(deviceId: 'device-1'),
    );

    await state.verifyOtp(phone: '+967 700 000 001', code: '123456');
    expect(state.contacts, isNotEmpty);
    expect(state.activeRelationshipId, 'rel-1');

    await state.logout();

    expect(state.loggedIn, isFalse);
    expect(state.contacts, isEmpty);
    expect(state.entries, isEmpty);
    expect(state.sessions, isEmpty);
    expect(state.activeRelationshipId, isNull);
    expect(state.persona, AppPersona.merchant);
    expect(api.session, isNull);
  });
}

Future<http.Response> _handler(http.Request request) async {
  switch (request.url.path) {
    case '/v1/auth/otp/request':
      return _json({});
    case '/v1/auth/otp/verify':
      return _json({
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'expiresAt': '2026-11-05T12:00:00Z',
        'refreshExpiresAt': '2026-12-05T12:00:00Z',
        'user': {'id': 'user-1', 'phoneE164': '+967700000001'},
        'deviceId': 'device-1',
      });
    case '/v1/auth/logout':
      return _json({'status': 'logged_out'});
    case '/v1/me':
      return _json({
        'user': {
          'id': 'user-1',
          'phoneE164': '+967700000001',
          'displayName': 'أحمد الصبري',
          'locale': 'ar',
        },
        'deviceId': 'device-1',
      });
    case '/v1/relationships':
      return _json({
        'relationships': [
          {
            'relationshipId': 'rel-1',
            'relationshipType': 'merchant_customer',
            'status': 'active',
            'currentCycleId': 'cycle-1',
            'myRole': 'merchant',
            'otherParty': {
              'userId': 'user-2',
              'role': 'customer',
              'displayName': 'أبو أحمد',
              'phoneE164': '+967700000002',
            },
          },
        ],
      });
    case '/v1/devices':
      return _json({
        'devices': [
          {
            'id': 'device-1',
            'label': 'جهاز الاختبار',
            'platform': 'android',
            'status': 'active',
            'isCurrent': true,
            'registeredAt': '2026-11-05T08:00:00Z',
            'lastSeenAt': '2026-11-05T10:00:00Z',
          },
        ],
      });
    case '/v1/relationship-invitations':
      return _json({'invitations': []});
    case '/v1/relationships/rel-1/account-cycles':
      return _json({
        'currentCycleId': 'cycle-1',
        'balanceSemantics': 'separate_account_classes_minor_units',
        'cycles': [
          {
            'cycleId': 'cycle-1',
            'cycleNumber': 1,
            'title': 'الدورة الحالية',
            'status': 'active',
            'startedAt': '2026-11-05T08:00:00Z',
            'endedAt': null,
            'balances': [
              {
                'ownerUserId': 'user-1',
                'currency': 'YER',
                'receivableMinor': '1200000',
                'payableMinor': '0',
                'partyBalanceMinor': '1200000',
                'unappliedPaymentAssetMinor': '0',
                'unappliedPaymentLiabilityMinor': '0',
              },
            ],
          },
        ],
      });
    case '/v1/relationships/rel-1/operations':
      return _json({
        'operations': [
          {
            'operationId': 'op-1',
            'actorUserId': 'user-1',
            'operationType': 'credit_charge',
            'businessState': 'awaiting_counterparty',
            'baseVersion': 0,
            'serverVersion': 1,
            'serverSequence': 1,
            'payload': {
              'creditorUserId': 'user-1',
              'debtorUserId': 'user-2',
              'currency': 'YER',
              'amountMinor': '1200000',
              'productName': 'قات رطب',
            },
            'clientCreatedAt': '2026-11-05T10:00:00Z',
            'serverCreatedAt': '2026-11-05T10:00:01Z',
            'decision': null,
          },
        ],
        'nextCursor': 1,
        'hasMore': false,
      });
    case '/v1/relationships/rel-1/settlement-reset-requests/pending':
      return _json({'request': null});
    default:
      return _json({'error': 'not_found'}, status: 404);
  }
}

http.Response _json(Map<String, Object?> body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
