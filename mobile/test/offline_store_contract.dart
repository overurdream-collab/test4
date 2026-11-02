import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shared_ledger_mobile_core/src/offline_store.dart';

/// Opens a store at [path]. The production contract uses SQLCipher; unit tests
/// use an unencrypted FFI factory with the same schema and API.
typedef OfflineStoreContractOpener = Future<OfflineStore> Function(String path);

/// Reusable behavioral contract for [OfflineStore].
///
/// Run this against the plain in-process factory for fast tests and against the
/// real SQLCipher engine in device integration tests. Both engines must satisfy
/// the same behavior before a storage migration is accepted.
void runOfflineStoreContractTests({
  required OfflineStoreContractOpener openStore,
}) {
  group('OfflineStore contract', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ledger-contract-');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    Future<OfflineStore> open(String filename) =>
        openStore('${directory.path}/$filename');

    test('offline operation and outbox survive app close and reopen', () async {
      var store = await open('device-a.db');

      await store.enqueueOperation(
        operationId: '33000000-0000-0000-0000-000000000001',
        relationshipId: '13000000-0000-0000-0000-000000000001',
        operationType: 'credit_charge',
        payload: {'currency': 'YER', 'amountMinor': 1500},
        baseServerVersion: 0,
        clientCreatedAt: DateTime.utc(2026, 11, 2),
      );
      expect((await store.pendingOperations()).single.operationId,
          '33000000-0000-0000-0000-000000000001');
      await store.close();

      store = await open('device-a.db');
      final pending = await store.pendingOperations();
      expect(pending, hasLength(1));
      expect(pending.single.transportState, 'queued');
      expect(pending.single.payload['amountMinor'], 1500);
      await store.close();
    });

    test('same operation ID is idempotent locally; changed content is rejected', () async {
      final store = await open('local.db');
      const id = '33000000-0000-0000-0000-000000000002';
      const relationship = '13000000-0000-0000-0000-000000000001';

      Future<void> enqueue(int amount) => store.enqueueOperation(
            operationId: id,
            relationshipId: relationship,
            operationType: 'credit_charge',
            payload: {'amountMinor': amount, 'currency': 'YER'},
            baseServerVersion: 0,
          );

      await enqueue(1500);
      await enqueue(1500);
      await expectLater(enqueue(1600), throwsA(isA<StateError>()));
      expect(await store.pendingOperations(), hasLength(1));
      await store.close();
    });

    test('two independent local stores converge from ordered server events', () async {
      final deviceA = await open('device-a.db');
      final deviceB = await open('device-b.db');
      const relationship = '13000000-0000-0000-0000-000000000001';
      const operation = '33000000-0000-0000-0000-000000000003';

      await deviceA.enqueueOperation(
        operationId: operation,
        relationshipId: relationship,
        operationType: 'credit_charge',
        payload: {
          'creditorUserId': '23000000-0000-0000-0000-000000000001',
          'debtorUserId': '23000000-0000-0000-0000-000000000002',
          'currency': 'YER',
          'amountMinor': 1500,
        },
        baseServerVersion: 0,
      );
      expect(await deviceB.getOperation(operation), isNull);

      await deviceA.markSending(operation);
      await deviceA.markRetryable(operation, error: 'offline');
      final retry = (await deviceA.pendingOperations()).single;
      expect(retry.operationId, operation);
      expect(retry.attempts, 1);

      await deviceA.markAccepted(
        operationId: operation,
        businessState: 'awaiting_counterparty',
        serverVersion: 1,
        serverSequence: 1,
      );

      final created = SyncEvent(
        relationshipId: relationship,
        serverSequence: 1,
        eventId: '43000000-0000-0000-0000-000000000001',
        operationId: operation,
        eventType: 'operation.created',
        payload: {
          'operationId': operation,
          'operationType': 'credit_charge',
          'businessState': 'awaiting_counterparty',
          'serverVersion': 1,
          'payload': {
            'creditorUserId': '23000000-0000-0000-0000-000000000001',
            'debtorUserId': '23000000-0000-0000-0000-000000000002',
            'currency': 'YER',
            'amountMinor': 1500,
          },
        },
        createdAt: DateTime.utc(2026, 11, 2),
      );
      await deviceA.applyEvents(relationship, [created]);
      await deviceB.applyEvents(relationship, [created]);

      expect((await deviceB.getOperation(operation))?.businessState,
          'awaiting_counterparty');
      expect(await deviceA.syncCursor(relationship), 1);
      expect(await deviceB.syncCursor(relationship), 1);

      final approved = SyncEvent(
        relationshipId: relationship,
        serverSequence: 2,
        eventId: '43000000-0000-0000-0000-000000000002',
        operationId: operation,
        eventType: 'operation.state_changed',
        payload: {
          'operationId': operation,
          'businessState': 'approved',
          'serverVersion': 2,
        },
        createdAt: DateTime.utc(2026, 11, 2, 0, 1),
      );
      await deviceA.applyEvents(relationship, [approved]);
      await deviceB.applyEvents(relationship, [approved]);

      expect((await deviceA.getOperation(operation))?.businessState, 'approved');
      expect((await deviceB.getOperation(operation))?.businessState, 'approved');
      expect((await deviceB.getOperation(operation))?.serverVersion, 2);

      // Re-delivery of an already applied event is harmless.
      await deviceB.applyEvents(relationship, [created, approved]);
      expect(await deviceB.syncCursor(relationship), 2);

      await deviceA.close();
      await deviceB.close();
    });

    test('event gaps roll back the local event and cursor transaction', () async {
      final store = await open('device.db');
      const relationship = '13000000-0000-0000-0000-000000000001';

      final gap = SyncEvent(
        relationshipId: relationship,
        serverSequence: 2,
        eventId: '43000000-0000-0000-0000-000000000012',
        operationId: '33000000-0000-0000-0000-000000000012',
        eventType: 'operation.created',
        payload: {
          'operationId': '33000000-0000-0000-0000-000000000012',
          'operationType': 'credit_charge',
          'businessState': 'awaiting_counterparty',
          'serverVersion': 1,
          'payload': {'currency': 'YER', 'amountMinor': 10},
        },
        createdAt: DateTime.utc(2026, 11, 2),
      );

      await expectLater(
        store.applyEvents(relationship, [gap]),
        throwsA(isA<StateError>()),
      );
      expect(await store.syncCursor(relationship), 0);
      expect(await store.getOperation(gap.operationId), isNull);
      await store.close();
    });
  });
}
