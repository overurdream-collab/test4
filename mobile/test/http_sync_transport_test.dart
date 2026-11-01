import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ledger_mobile_core/src/http_sync_transport.dart';
import 'package:shared_ledger_mobile_core/src/offline_store.dart';
import 'package:shared_ledger_mobile_core/src/sync_coordinator.dart';

void main() {
  test('HTTP transport sends authenticated operation and parses event cursor', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <HttpRequest>[];
    final bodies = <Map<String, Object?>>[];
    final serverSubscription = server.listen((request) async {
      requests.add(request);
      final text = await utf8.decoder.bind(request).join();
      if (text.isNotEmpty) bodies.add(Map<String, Object?>.from(jsonDecode(text) as Map));

      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST') {
        request.response.write(jsonEncode({
          'outcome': 'accepted',
          'operationId': '33000000-0000-0000-0000-000000000001',
          'businessState': 'awaiting_counterparty',
          'serverVersion': 1,
          'serverSequence': 1,
          'serverCreatedAt': '2026-11-02T00:00:00.000Z',
        }));
      } else {
        request.response.write(jsonEncode({
          'events': [{
            'serverSequence': 1,
            'eventId': '43000000-0000-0000-0000-000000000001',
            'operationId': '33000000-0000-0000-0000-000000000001',
            'eventType': 'operation.created',
            'payload': {
              'operationId': '33000000-0000-0000-0000-000000000001',
              'operationType': 'credit_charge',
              'businessState': 'awaiting_counterparty',
              'serverVersion': 1,
              'payload': {'currency': 'YER', 'amountMinor': 100},
            },
            'createdAt': '2026-11-02T00:00:00.000Z',
          }],
          'nextCursor': 1,
          'hasMore': false,
        }));
      }
      await request.response.close();
    });

    final transport = HttpSyncTransport(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessTokenProvider: () async => 'test-token',
    );
    final operation = OfflineOperation(
      operationId: '33000000-0000-0000-0000-000000000001',
      relationshipId: '13000000-0000-0000-0000-000000000001',
      operationType: 'credit_charge',
      payload: {'currency': 'YER', 'amountMinor': 100},
      transportState: 'sending',
      baseServerVersion: 0,
      clientCreatedAt: DateTime.utc(2026, 11, 2),
      attempts: 1,
    );

    final accepted = await transport.submitOperation(operation);
    expect(accepted.outcome, 'accepted');
    expect(requests.first.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-token');
    expect(bodies.first['operationId'], operation.operationId);
    expect(bodies.first.containsKey('actorUserId'), false);

    final page = await transport.pullEvents(
      relationshipId: operation.relationshipId,
      after: 0,
      limit: 10,
    );
    expect(page.events, hasLength(1));
    expect(page.events.single.serverSequence, 1);
    expect(page.nextCursor, 1);
    expect(page.hasMore, false);

    transport.close();
    await serverSubscription.cancel();
    await server.close(force: true);
  });

  test('HTTP 409 becomes a non-retryable sync conflict', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.statusCode = HttpStatus.conflict;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"error":"conflict"}');
      await request.response.close();
    });
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessTokenProvider: () async => 'test-token',
    );

    final operation = OfflineOperation(
      operationId: '33000000-0000-0000-0000-000000000002',
      relationshipId: '13000000-0000-0000-0000-000000000001',
      operationType: 'credit_charge',
      payload: {'currency': 'YER', 'amountMinor': 100},
      transportState: 'sending',
      baseServerVersion: 0,
      clientCreatedAt: DateTime.utc(2026, 11, 2),
    );
    await expectLater(
      transport.submitOperation(operation),
      throwsA(isA<SyncConflictException>()),
    );

    transport.close();
    await subscription.cancel();
    await server.close(force: true);
  });
}
