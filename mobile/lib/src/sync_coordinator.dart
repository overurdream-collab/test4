import 'dart:async';
import 'dart:math';

import 'offline_store.dart';

class SyncAcceptance {
  const SyncAcceptance({
    required this.outcome,
    required this.businessState,
    required this.serverVersion,
    required this.serverSequence,
  });

  final String outcome;
  final String businessState;
  final int serverVersion;
  final int serverSequence;
}

class SyncEventPage {
  const SyncEventPage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<SyncEvent> events;
  final int nextCursor;
  final bool hasMore;
}

abstract interface class SyncTransport {
  Future<SyncAcceptance> submitOperation(OfflineOperation operation);

  Future<SyncEventPage> pullEvents({
    required String relationshipId,
    required int after,
    required int limit,
  });
}

class SyncConflictException implements Exception {
  const SyncConflictException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SyncPermanentFailure implements Exception {
  const SyncPermanentFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class SyncSummary {
  const SyncSummary({
    required this.accepted,
    required this.retryable,
    required this.conflicted,
    required this.eventsApplied,
    required this.finalCursor,
  });

  final int accepted;
  final int retryable;
  final int conflicted;
  final int eventsApplied;
  final int finalCursor;
}

class SyncCoordinator {
  SyncCoordinator({
    required this.store,
    required this.transport,
    this.pageSize = 100,
    this.maxPages = 20,
  }) {
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    if (maxPages < 1 || maxPages > 100) {
      throw ArgumentError.value(maxPages, 'maxPages');
    }
  }

  final OfflineStore store;
  final SyncTransport transport;
  final int pageSize;
  final int maxPages;
  final Map<String, Future<SyncSummary>> _inFlight = {};

  Future<SyncSummary> syncRelationship(String relationshipId) {
    final existing = _inFlight[relationshipId];
    if (existing != null) return existing;

    final future = _run(relationshipId);
    _inFlight[relationshipId] = future;
    return future.whenComplete(() => _inFlight.remove(relationshipId));
  }

  Future<SyncSummary> _run(String relationshipId) async {
    var accepted = 0;
    var retryable = 0;
    var conflicted = 0;
    var eventsApplied = 0;

    final pending = await store.pendingOperations(
      relationshipId: relationshipId,
      limit: 200,
    );

    for (final operation in pending) {
      await store.markSending(operation.operationId);
      try {
        final response = await transport.submitOperation(operation);
        if (response.outcome != 'accepted' &&
            response.outcome != 'already_processed') {
          throw SyncPermanentFailure('Unexpected server outcome: ${response.outcome}');
        }
        await store.markAccepted(
          operationId: operation.operationId,
          businessState: response.businessState,
          serverVersion: response.serverVersion,
          serverSequence: response.serverSequence,
        );
        accepted++;
      } on SyncConflictException catch (error) {
        await store.markConflict(operation.operationId, error.message);
        conflicted++;
      } on SyncPermanentFailure catch (error) {
        await store.markConflict(operation.operationId, error.message);
        conflicted++;
      } catch (error) {
        final exponent = min(operation.attempts, 7);
        final delaySeconds = min(300, 2 * (1 << exponent));
        await store.markRetryable(
          operation.operationId,
          error: error.toString(),
          retryAt: DateTime.now().toUtc().add(Duration(seconds: delaySeconds)),
        );
        retryable++;
      }
    }

    var pages = 0;
    while (pages < maxPages) {
      final cursor = await store.syncCursor(relationshipId);
      final page = await transport.pullEvents(
        relationshipId: relationshipId,
        after: cursor,
        limit: pageSize,
      );
      if (page.events.isEmpty) {
        if (page.hasMore) {
          throw StateError('Server returned hasMore with an empty event page');
        }
        break;
      }
      final expectedNext = page.events.last.serverSequence;
      if (page.nextCursor != expectedNext) {
        throw StateError('Server nextCursor does not match the last returned event');
      }
      await store.applyEvents(relationshipId, page.events);
      eventsApplied += page.events.length;
      pages++;
      if (!page.hasMore) break;
    }

    return SyncSummary(
      accepted: accepted,
      retryable: retryable,
      conflicted: conflicted,
      eventsApplied: eventsApplied,
      finalCursor: await store.syncCursor(relationshipId),
    );
  }
}
