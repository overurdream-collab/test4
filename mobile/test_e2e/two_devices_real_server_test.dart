import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shared_ledger_mobile_core/src/http_sync_transport.dart';
import 'package:shared_ledger_mobile_core/src/offline_store.dart';
import 'package:shared_ledger_mobile_core/src/sync_coordinator.dart';

String _required(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw StateError('Missing $key');
  }
  return value;
}

Future<void> _approve({
  required String approvalUrl,
  required String token,
  required String relationshipId,
  required String operationId,
  required String idempotencyKey,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(
        '$approvalUrl/v1/relationships/$relationshipId/'
        'operations/$operationId/decision',
      ),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set('idempotency-key', idempotencyKey)
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        'decision': 'approved',
        'expectedVersion': 1,
        'reason': 'two-device offline E2E approval',
      }),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, 200, reason: body);
  } finally {
    client.close(force: true);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'two offline stores converge with PostgreSQL through real HTTP',
    () async {
      final syncUrl = _required('E2E_SYNC_URL');
      final approvalUrl = _required('E2E_APPROVAL_URL');
      final sellerToken = _required('E2E_SELLER_TOKEN');
      final buyerToken = _required('E2E_BUYER_TOKEN');
      final relationshipId = _required('E2E_RELATIONSHIP_ID');
      final sellerUserId = _required('E2E_SELLER_USER_ID');
      final buyerUserId = _required('E2E_BUYER_USER_ID');
      final chargeId = _required('E2E_CHARGE_ID');
      final approvalId = _required('E2E_APPROVAL_ID');

      final directory = await Directory.systemTemp.createTemp(
        'ledger-two-device-real-',
      );
      final deviceAPath = '${directory.path}/device-a.db';
      final deviceBPath = '${directory.path}/device-b.db';
      late OfflineStore deviceA;
      late OfflineStore deviceB;
      HttpSyncTransport? offlineTransport;
      HttpSyncTransport? transportA;
      HttpSyncTransport? transportB;

      deviceA = await OfflineStore.openForTesting(
        factory: databaseFactoryFfi,
        path: deviceAPath,
      );
      deviceB = await OfflineStore.openForTesting(
        factory: databaseFactoryFfi,
        path: deviceBPath,
      );

      try {
        await deviceA.enqueueOperation(
          operationId: chargeId,
          relationshipId: relationshipId,
          operationType: 'credit_charge',
          payload: {
            'creditorUserId': sellerUserId,
            'debtorUserId': buyerUserId,
            'currency': 'YER',
            'amountMinor': 2500,
          },
          baseServerVersion: 0,
        );

        // Device A is offline. Its local outbox survives a failed sync and an
        // application restart without losing the exact operation ID.
        final offline = HttpSyncTransport(
          baseUri: Uri.parse('http://127.0.0.1:1'),
          accessTokenProvider: () async => sellerToken,
          requestTimeout: const Duration(seconds: 2),
        );
        offlineTransport = offline;
        final offlineSync = SyncCoordinator(
          store: deviceA,
          transport: offline,
          retryBaseDelay: Duration.zero,
        );
        await expectLater(
          offlineSync.syncRelationship(relationshipId),
          throwsA(isA<SocketException>()),
        );
        expect(
          await deviceA.pendingOperations(relationshipId: relationshipId),
          hasLength(1),
        );
        offlineTransport.close();
        offlineTransport = null;

        await deviceA.close();
        deviceA = await OfflineStore.openForTesting(
          factory: databaseFactoryFfi,
          path: deviceAPath,
        );
        expect(
          await deviceA.pendingOperations(relationshipId: relationshipId),
          hasLength(1),
        );

        final realTransportB = HttpSyncTransport(
          baseUri: Uri.parse(syncUrl),
          accessTokenProvider: () async => buyerToken,
        );
        transportB = realTransportB;
        final syncB = SyncCoordinator(
          store: deviceB,
          transport: realTransportB,
          retryBaseDelay: Duration.zero,
        );

        final beforeReconnect = await syncB.syncRelationship(relationshipId);
        expect(beforeReconnect.eventsApplied, 0);
        expect(beforeReconnect.finalCursor, 0);
        expect(await deviceB.getOperation(chargeId), isNull);

        final realTransportA = HttpSyncTransport(
          baseUri: Uri.parse(syncUrl),
          accessTokenProvider: () async => sellerToken,
        );
        transportA = realTransportA;
        final syncA = SyncCoordinator(
          store: deviceA,
          transport: realTransportA,
          retryBaseDelay: Duration.zero,
        );

        final reconnected = await syncA.syncRelationship(relationshipId);
        expect(reconnected.accepted, 1);
        expect(reconnected.eventsApplied, 1);
        expect(reconnected.finalCursor, 1);
        expect(
          await deviceA.pendingOperations(relationshipId: relationshipId),
          isEmpty,
        );
        expect(
          (await deviceA.getOperation(chargeId))?.businessState,
          'awaiting_counterparty',
        );
        expect(await deviceA.syncCursor(relationshipId), 1);

        final stored = await deviceA.getOperation(chargeId);
        expect(stored, isNotNull);
        final duplicate = await realTransportA.submitOperation(stored!);
        expect(duplicate.outcome, 'already_processed');

        final buyerSawOperation = await syncB.syncRelationship(relationshipId);
        expect(buyerSawOperation.eventsApplied, 1);
        expect(buyerSawOperation.finalCursor, 1);
        expect(
          (await deviceB.getOperation(chargeId))?.businessState,
          'awaiting_counterparty',
        );

        await _approve(
          approvalUrl: approvalUrl,
          token: buyerToken,
          relationshipId: relationshipId,
          operationId: chargeId,
          idempotencyKey: approvalId,
        );

        await syncA.syncRelationship(relationshipId);
        await syncB.syncRelationship(relationshipId);
        expect(
          (await deviceA.getOperation(chargeId))?.businessState,
          'approved',
        );
        expect(
          (await deviceB.getOperation(chargeId))?.businessState,
          'approved',
        );
        expect(await deviceA.syncCursor(relationshipId), 2);
        expect(await deviceB.syncCursor(relationshipId), 2);
      } finally {
        offlineTransport?.close();
        transportA?.close();
        transportB?.close();
        await deviceA.close();
        await deviceB.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
