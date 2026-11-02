import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shared_ledger_mobile_core/src/offline_store.dart';
import 'package:shared_ledger_mobile_core/src/sync_coordinator.dart';

class FakeSyncServer implements SyncTransport {
  final Map<String, OfflineOperation> operations = {};
  final Map<String, List<SyncEvent>> feeds = {};
  final Map<String, int> sequences = {};
  int submissions = 0;
  bool timeoutAfterNextCommit = false;
  bool failNextPull = false;

  @override
  Future<SyncAcceptance> submitOperation(OfflineOperation operation) async {
    submissions++;
    final existing = operations[operation.operationId];
    if (existing != null) {
      return SyncAcceptance(
        outcome: 'already_processed',
        businessState: 'awaiting_counterparty',
        serverVersion: 1,
        serverSequence: feeds[operation.relationshipId]!
            .firstWhere((event) => event.operationId == operation.operationId)
            .serverSequence,
      );
    }

    operations[operation.operationId] = operation;
    final sequence = (sequences[operation.relationshipId] ?? 0) + 1;
    sequences[operation.relationshipId] = sequence;
    feeds.putIfAbsent(operation.relationshipId, () => []).add(
      SyncEvent(
        relationshipId: operation.relationshipId,
        serverSequence: sequence,
        eventId: '43000000-0000-0000-0000-${sequence.toString().padLeft(12, '0')}',
        operationId: operation.operationId,
        eventType: 'operation.created',
        payload: {
          'operationId': operation.operationId,
          'operationType': operation.operationType,
          'businessState': 'awaiting_counterparty',
          'serverVersion': 1,
          'payload': operation.payload,
        },
        createdAt: operation.clientCreatedAt,
      ),
    );

    if (timeoutAfterNextCommit) {
      timeoutAfterNextCommit = false;
      throw const SocketException('response timed out after server commit');
    }

    return SyncAcceptance(
      outcome: 'accepted',
      businessState: 'awaiting_counterparty',
      serverVersion: 1,
      serverSequence: sequence,
    );
  }

  @override
  Future<SyncEventPage> pullEvents({
    required String relationshipId,
    required Map<int,int> cursors,
    required int limit,
  }) async {
    if (failNextPull) {
      failNextPull = false;
      throw const SocketException('network unavailable');
    }
    final all = (feeds[relationshipId] ?? [])
        .where((event) => event.serverSequence > (cursors[event.syncShard] ?? 0))
        .toList()
      ..sort((a, b) => a.serverSequence.compareTo(b.serverSequence));
    final hasMore = all.length > limit;
    final events = all.take(limit).toList();
    return SyncEventPage(
      events: events,
      nextCursor: Map<int,int>.from(cursors)..[0] = events.where((e) => e.syncShard == 0).isEmpty ? (cursors[0] ?? 0) : events.where((e) => e.syncShard == 0).last.serverSequence,
      hasMore: hasMore,
    );
  }

  void approve(String relationshipId, String operationId) {
    final sequence = (sequences[relationshipId] ?? 0) + 1;
    sequences[relationshipId] = sequence;
    feeds[relationshipId]!.add(
      SyncEvent(
        relationshipId: relationshipId,
        serverSequence: sequence,
        eventId: '44000000-0000-0000-0000-${sequence.toString().padLeft(12, '0')}',
        operationId: operationId,
        eventType: 'operation.state_changed',
        payload: {
          'operationId': operationId,
          'businessState': 'approved',
          'serverVersion': 2,
        },
        createdAt: DateTime.utc(2026, 11, 2, 0, 1),
      ),
    );
  }


}


class AuthRequiredTransport implements SyncTransport {
  @override
  Future<SyncAcceptance> submitOperation(OfflineOperation operation) async {
    throw const SyncAuthenticationRequired();
  }

  @override
  Future<SyncEventPage> pullEvents({
    required String relationshipId,
    required int after,
    required int limit,
  }) async {
    return SyncEventPage(events: const [], nextCursor: cursors, hasMore: false);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  Future<OfflineStore> openStore(Directory directory, String filename) {
    return OfflineStore.openForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/$filename',
    );
  }

  test('two offline devices retry idempotently and converge after reconnect', () async {
    final directory = await Directory.systemTemp.createTemp('ledger-sync-two-clients-');
    final deviceA = await openStore(directory, 'a.db');
    final deviceB = await openStore(directory, 'b.db');
    final server = FakeSyncServer();
    final syncA = SyncCoordinator(
      store: deviceA,
      transport: server,
      retryBaseDelay: Duration.zero,
    );
    final syncB = SyncCoordinator(
      store: deviceB,
      transport: server,
      retryBaseDelay: Duration.zero,
    );

    const relationship = '13000000-0000-0000-0000-000000000001';
    const operation = '33000000-0000-0000-0000-000000000020';

    await deviceA.enqueueOperation(
      operationId: operation,
      relationshipId: relationship,
      operationType: 'credit_charge',
      payload: {
        'creditorUserId': '23000000-0000-0000-0000-000000000001',
        'debtorUserId': '23000000-0000-0000-0000-000000000002',
        'currency': 'YER',
        'amountMinor': 2500,
      },
      baseServerVersion: 0,
    );

    // Both devices are offline: device B cannot see A's local operation.
    final offlineB = await syncB.syncRelationship(relationship);
    expect(offlineB.finalCursor, 0);
    expect(await deviceB.getOperation(operation), isNull);

    // Server commits A's operation, but the response and event pull both time out.
    server.timeoutAfterNextCommit = true;
    server.failNextPull = true;
    await expectLater(syncA.syncRelationship(relationship), throwsA(isA<SocketException>()));
    expect((await deviceA.pendingOperations(relationshipId: relationship)), hasLength(1));
    expect(server.operations, hasLength(1));

    // Device B reconnects and receives the committed operation event.
    await syncB.syncRelationship(relationship);
    expect((await deviceB.getOperation(operation))?.businessState,
        'awaiting_counterparty');

    // A retries the exact same operation ID. Server returns the original result,
    // not a second financial operation or event.
    final retried = await syncA.syncRelationship(relationship);
    expect(retried.accepted, 1);
    expect(server.submissions, 2);
    expect(server.operations, hasLength(1));
    expect(server.feeds[relationship], hasLength(1));
    expect(await deviceA.pendingOperations(relationshipId: relationship), isEmpty);

    // Counterparty decision arrives as the next ordered event on both clients.
    server.approve(relationship, operation);
    await syncA.syncRelationship(relationship);
    await syncB.syncRelationship(relationship);
    expect((await deviceA.getOperation(operation))?.businessState, 'approved');
    expect((await deviceB.getOperation(operation))?.businessState, 'approved');
    expect(await deviceA.syncCursor(relationship), 2);
    expect(await deviceB.syncCursor(relationship), 2);

    await deviceA.close();
    await deviceB.close();
    await directory.delete(recursive: true);
  });

  test('authentication expiry keeps the operation queued for re-login', () async {
    final directory = await Directory.systemTemp.createTemp('ledger-auth-deferred-');
    final store = await openStore(directory, 'device.db');
    const relationship = '13000000-0000-0000-0000-000000000001';
    const operation = '33000000-0000-0000-0000-000000000030';
    await store.enqueueOperation(
      operationId: operation,
      relationshipId: relationship,
      operationType: 'credit_charge',
      payload: {'currency': 'YER', 'amountMinor': 50},
      baseServerVersion: 0,
    );

    final coordinator = SyncCoordinator(
      store: store,
      transport: AuthRequiredTransport(),
      retryBaseDelay: Duration.zero,
    );
    final result = await coordinator.syncRelationship(relationship);
    expect(result.retryable, 1);
    expect((await store.pendingOperations(relationshipId: relationship)), hasLength(1));
    expect((await store.getOperation(operation))?.transportState, 'queued');

    await store.close();
    await directory.delete(recursive: true);
  });

}
