import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const _databaseKeyName = 'shared_ledger_sqlcipher_key_v1';
const _supportedOperationTypes = {
  'credit_charge',
  'payment',
  'allocation',
  'supply',
};

class OfflineOperation {
  const OfflineOperation({
    required this.operationId,
    required this.relationshipId,
    required this.operationType,
    required this.payload,
    required this.transportState,
    required this.baseServerVersion,
    required this.clientCreatedAt,
    this.businessState,
    this.serverVersion,
    this.serverSequence,
    this.syncShard = 0,
    this.attempts = 0,
  });

  final String operationId;
  final String relationshipId;
  final String operationType;
  final Map<String, Object?> payload;
  final String transportState;
  final int baseServerVersion;
  final DateTime clientCreatedAt;
  final String? businessState;
  final int? serverVersion;
  final int? serverSequence;
  final int syncShard;
  final int attempts;

  factory OfflineOperation.fromRow(Map<String, Object?> row) {
    return OfflineOperation(
      operationId: row['operation_id']! as String,
      relationshipId: row['relationship_id']! as String,
      operationType: row['operation_type']! as String,
      payload: Map<String, Object?>.from(
        jsonDecode(row['payload_json']! as String) as Map,
      ),
      transportState: row['transport_state']! as String,
      baseServerVersion: row['base_server_version']! as int,
      clientCreatedAt: DateTime.parse(row['client_created_at']! as String),
      businessState: row['business_state'] as String?,
      serverVersion: row['server_version'] as int?,
      serverSequence: row['server_sequence'] as int?,
      syncShard: row['sync_shard'] as int? ?? 0,
      attempts: row['attempts']! as int,
    );
  }
}

class SyncEvent {
  const SyncEvent({
    required this.relationshipId,
    required this.serverSequence,
    this.syncShard = 0,
    required this.eventId,
    required this.operationId,
    required this.eventType,
    required this.payload,
    required this.createdAt,
  });

  final String relationshipId;
  final int serverSequence;
  final int syncShard;
  final String eventId;
  final String operationId;
  final String eventType;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

class OfflineStore {
  OfflineStore._(this._database);

  final Database _database;

  /// Opens the production SQLCipher database. Key loss or secure-storage
  /// failure is fatal: this method never falls back to an unencrypted database.
  static Future<OfflineStore> openEncrypted({
    required String path,
    FlutterSecureStorage? secureStorage,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    final storage = secureStorage ?? const FlutterSecureStorage();
    var key = await storage.read(key: _databaseKeyName);
    if (key == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      key = base64UrlEncode(bytes);
      await storage.write(key: _databaseKeyName, value: key);
    }
    if (key.length < 40) {
      throw StateError('Stored local database key is invalid; refusing to open database.');
    }

    final database = await sqlcipher.openDatabase(
      path,
      password: key,
      version: 2,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return OfflineStore._(database);
  }

  /// Plain SQLite is available only for deterministic unit tests. Production
  /// code must call openEncrypted().
  static Future<OfflineStore> openForTesting({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return OfflineStore._(database);
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE local_operations (
        operation_id TEXT PRIMARY KEY,
        relationship_id TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        schema_version INTEGER NOT NULL CHECK (schema_version = 1),
        base_server_version INTEGER NOT NULL CHECK (base_server_version >= 0),
        payload_json TEXT NOT NULL,
        transport_state TEXT NOT NULL CHECK (
          transport_state IN ('queued','sending','synced','conflict','failed')
        ),
        business_state TEXT,
        server_version INTEGER,
        server_sequence INTEGER,
        sync_shard INTEGER NOT NULL DEFAULT 0 CHECK(sync_shard BETWEEN 0 AND 7),
        origin TEXT NOT NULL CHECK (origin IN ('local','remote')),
        client_created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
        last_error TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE outbox (
        operation_id TEXT PRIMARY KEY
          REFERENCES local_operations(operation_id) ON DELETE RESTRICT,
        queued_at TEXT NOT NULL,
        next_attempt_at TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE local_events (
        relationship_id TEXT NOT NULL,
        server_sequence INTEGER NOT NULL CHECK (server_sequence > 0),
        sync_shard INTEGER NOT NULL DEFAULT 0 CHECK(sync_shard BETWEEN 0 AND 7),
        event_id TEXT NOT NULL UNIQUE,
        operation_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        event_payload_json TEXT NOT NULL,
        received_at TEXT NOT NULL,
        PRIMARY KEY (relationship_id, server_sequence)
      )
    ''');
    await database.execute('''
      CREATE TABLE sync_cursors (
        relationship_id TEXT NOT NULL,
        sync_shard INTEGER NOT NULL DEFAULT 0 CHECK(sync_shard BETWEEN 0 AND 7),
        last_server_sequence INTEGER NOT NULL DEFAULT 0
          CHECK (last_server_sequence >= 0),
        PRIMARY KEY(relationship_id,sync_shard)
      )
    ''');
    await database.execute(
      'CREATE INDEX outbox_due_idx ON outbox(next_attempt_at, queued_at)',
    );
    await database.execute(
      'CREATE INDEX local_operations_relationship_idx '
      'ON local_operations(relationship_id, client_created_at)',
    );
  }

  static Future<void> _upgradeSchema(Database database, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await database.execute("ALTER TABLE local_operations ADD COLUMN sync_shard INTEGER NOT NULL DEFAULT 0");
      await database.execute("ALTER TABLE local_events ADD COLUMN sync_shard INTEGER NOT NULL DEFAULT 0");
      final operations = await database.query('local_operations', columns: ['operation_id']);
      for (final row in operations) {
        final id = (row['operation_id']! as String).replaceAll('-', '');
        final shard = int.parse(id.substring(id.length - 1), radix: 16) % 8;
        await database.update('local_operations', {'sync_shard': shard}, where: 'operation_id = ?', whereArgs: [row['operation_id']]);
      }
      final events = await database.query('local_events', columns: ['event_id','operation_id']);
      for (final row in events) {
        final id = (row['operation_id']! as String).replaceAll('-', '');
        final shard = int.parse(id.substring(id.length - 1), radix: 16) % 8;
        await database.update('local_events', {'sync_shard': shard}, where: 'event_id = ?', whereArgs: [row['event_id']]);
      }
      await database.execute('ALTER TABLE sync_cursors RENAME TO sync_cursors_v1');
      await database.execute('''
        CREATE TABLE sync_cursors (
          relationship_id TEXT NOT NULL,
          sync_shard INTEGER NOT NULL CHECK(sync_shard BETWEEN 0 AND 7),
          last_server_sequence INTEGER NOT NULL DEFAULT 0 CHECK(last_server_sequence >= 0),
          PRIMARY KEY(relationship_id,sync_shard)
        )
      ''');
      final oldCursors = await database.query('sync_cursors_v1');
      for (final row in oldCursors) {
        final relationshipId = row['relationship_id']! as String;
        final oldCursor = row['last_server_sequence']! as int;
        for (var shard = 0; shard < 8; shard++) {
          await database.insert('sync_cursors', {
            'relationship_id': relationshipId,
            'sync_shard': shard,
            'last_server_sequence': shard * 1000000000000 + oldCursor,
          });
        }
      }
      await database.execute('DROP TABLE sync_cursors_v1');
    }
  }

  static Object? _normalizeJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _normalizeJson(value[key]),
      };
    }
    if (value is List) {
      return value.map(_normalizeJson).toList();
    }
    return value;
  }

  static String _canonicalJson(Map<String, Object?> value) =>
      jsonEncode(_normalizeJson(value));

  Future<void> enqueueOperation({
    required String operationId,
    required String relationshipId,
    required String operationType,
    required Map<String, Object?> payload,
    required int baseServerVersion,
    DateTime? clientCreatedAt,
  }) async {
    if (!_supportedOperationTypes.contains(operationType)) {
      throw ArgumentError.value(operationType, 'operationType', 'Unsupported operation type');
    }
    if (baseServerVersion < 0) {
      throw ArgumentError.value(baseServerVersion, 'baseServerVersion');
    }
    final payloadJson = _canonicalJson(payload);
    final createdAt = (clientCreatedAt ?? DateTime.now()).toUtc().toIso8601String();
    await _database.transaction((transaction) async {
      final existing = await transaction.query(
        'local_operations',
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        final same = row['relationship_id'] == relationshipId &&
            row['operation_type'] == operationType &&
            row['payload_json'] == payloadJson &&
            row['base_server_version'] == baseServerVersion;
        if (!same) {
          throw StateError('operationId already exists with different local content');
        }
        return;
      }

      await transaction.insert('local_operations', {
        'operation_id': operationId,
        'relationship_id': relationshipId,
        'operation_type': operationType,
        'schema_version': 1,
        'base_server_version': baseServerVersion,
        'payload_json': payloadJson,
        'transport_state': 'queued',
        'origin': 'local',
        'client_created_at': createdAt,
        'attempts': 0,
      });
      await transaction.insert('outbox', {
        'operation_id': operationId,
        'queued_at': createdAt,
      });
    });
  }

  Future<List<OfflineOperation>> pendingOperations({
    String? relationshipId,
    int limit = 50,
    DateTime? now,
  }) async {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 200');
    }
    final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    final rows = await _database.rawQuery(
      '''
      SELECT operations.*
      FROM local_operations AS operations
      INNER JOIN outbox USING(operation_id)
      WHERE operations.transport_state IN ('queued','sending')
        AND (? IS NULL OR operations.relationship_id = ?)
        AND (outbox.next_attempt_at IS NULL OR outbox.next_attempt_at <= ?)
      ORDER BY outbox.queued_at, operations.operation_id
      LIMIT ?
      ''',
      [relationshipId, relationshipId, timestamp, limit],
    );
    return rows.map(OfflineOperation.fromRow).toList();
  }

  Future<void> markSending(String operationId) async {
    await _database.transaction((transaction) async {
      final changed = await transaction.rawUpdate(
        '''
        UPDATE local_operations
        SET transport_state='sending', attempts=attempts+1, last_error=NULL
        WHERE operation_id=? AND transport_state IN ('queued','sending')
        ''',
        [operationId],
      );
      if (changed != 1) throw StateError('Operation is not eligible for sending');
    });
  }

  Future<void> markRetryable(
    String operationId, {
    required String error,
    DateTime? retryAt,
  }) async {
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        'local_operations',
        {'transport_state': 'queued', 'last_error': error},
        where: 'operation_id = ? AND transport_state IN (?,?)',
        whereArgs: [operationId, 'sending', 'queued'],
      );
      if (changed != 1) throw StateError('Operation cannot be returned to the outbox');
      await transaction.update(
        'outbox',
        {'next_attempt_at': retryAt?.toUtc().toIso8601String()},
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    });
  }

  Future<void> markAccepted({
    required String operationId,
    required String businessState,
    required int serverVersion,
    required int serverSequence,
    int syncShard = 0,
  }) async {
    if (serverVersion < 1 || serverSequence < 1) {
      throw ArgumentError('Invalid canonical server version or sequence');
    }
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        'local_operations',
        {
          'transport_state': 'synced',
          'business_state': businessState,
          'server_version': serverVersion,
          'server_sequence': serverSequence,
          'sync_shard': syncShard,
          'last_error': null,
        },
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
      if (changed != 1) throw StateError('Accepted operation does not exist locally');
      await transaction.delete(
        'outbox',
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    });
  }

  Future<void> markConflict(String operationId, String reason) async {
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        'local_operations',
        {'transport_state': 'conflict', 'last_error': reason},
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
      if (changed != 1) throw StateError('Conflicted operation does not exist locally');
      await transaction.delete(
        'outbox',
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    });
  }

  Future<Map<int,int>> syncCursors(String relationshipId) async {
    final rows = await _database.query('sync_cursors',
      columns: ['sync_shard','last_server_sequence'],
      where: 'relationship_id = ?', whereArgs: [relationshipId]);
    final result = <int,int>{for (var shard=0; shard<8; shard++) shard: 0};
    for (final row in rows) result[row['sync_shard']! as int] = row['last_server_sequence']! as int;
    return result;
  }

  Future<int> syncCursor(String relationshipId) async {
    final values = await syncCursors(relationshipId);
    return values.values.fold<int>(0,(a,b)=>a>b?a:b);
  }

  Future<void> applyEvents(
    String relationshipId,
    List<SyncEvent> events, {
    Map<int,int>? nextCursor,
  }) async {
    await _database.transaction((transaction) async {
      final cursorRows = await transaction.query('sync_cursors',
        columns: ['sync_shard','last_server_sequence'],
        where: 'relationship_id = ?', whereArgs: [relationshipId]);
      final cursors = <int,int>{for (var shard=0; shard<8; shard++) shard: 0};
      for (final row in cursorRows) cursors[row['sync_shard']! as int] = row['last_server_sequence']! as int;

      for (final event in events) {
        if (event.relationshipId != relationshipId) throw StateError('Event belongs to a different relationship');
        if (event.syncShard < 0 || event.syncShard > 7) throw StateError('Invalid event shard');
        final cursor = cursors[event.syncShard] ?? 0;
        if (event.serverSequence <= cursor) continue;

        if (event.eventType == 'operation.created') {
          final operationPayload = Map<String,Object?>.from(event.payload['payload'] as Map? ?? const <String,Object?>{});
          final operationType = event.payload['operationType'] as String?;
          final businessState = event.payload['businessState'] as String?;
          final serverVersion = (event.payload['serverVersion'] as num?)?.toInt();
          if (operationType == null || businessState == null || serverVersion == null) throw StateError('Malformed operation.created event');
          await transaction.rawInsert('''
            INSERT INTO local_operations (
              operation_id,relationship_id,operation_type,schema_version,base_server_version,
              payload_json,transport_state,business_state,server_version,server_sequence,sync_shard,
              origin,client_created_at,attempts
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,0)
            ON CONFLICT(operation_id) DO UPDATE SET
              transport_state='synced',business_state=excluded.business_state,
              server_version=excluded.server_version,server_sequence=excluded.server_sequence,
              sync_shard=excluded.sync_shard
          ''',[
            event.operationId,relationshipId,operationType,1,0,_canonicalJson(operationPayload),
            'synced',businessState,serverVersion,event.serverSequence,event.syncShard,'remote',
            event.createdAt.toUtc().toIso8601String(),
          ]);
          await transaction.delete('outbox',where:'operation_id = ?',whereArgs:[event.operationId]);
        } else if (event.eventType == 'operation.state_changed') {
          final businessState = event.payload['businessState'] as String?;
          final serverVersion = (event.payload['serverVersion'] as num?)?.toInt();
          if (businessState == null || serverVersion == null) throw StateError('Malformed operation.state_changed event');
          final changed = await transaction.update('local_operations',{
            'business_state':businessState,'server_version':serverVersion,
            'server_sequence':event.serverSequence,'sync_shard':event.syncShard,'transport_state':'synced',
          },where:'operation_id = ? AND relationship_id = ?',whereArgs:[event.operationId,relationshipId]);
          if (changed != 1) throw StateError('State event arrived before its operation.created event');
        } else {
          throw StateError('Unsupported sync event type: ${event.eventType}');
        }

        await transaction.insert('local_events',{
          'relationship_id':relationshipId,'server_sequence':event.serverSequence,
          'sync_shard':event.syncShard,'event_id':event.eventId,'operation_id':event.operationId,
          'event_type':event.eventType,'event_payload_json':_canonicalJson(event.payload),
          'received_at':DateTime.now().toUtc().toIso8601String(),
        });
        cursors[event.syncShard]=event.serverSequence;
        await transaction.insert('sync_cursors',{
          'relationship_id':relationshipId,'sync_shard':event.syncShard,
          'last_server_sequence':event.serverSequence,
        },conflictAlgorithm:ConflictAlgorithm.replace);
      }
      if (nextCursor != null) {
        for (var shard=0; shard<8; shard++) {
          final value=nextCursor[shard] ?? cursors[shard] ?? 0;
          if (value > (cursors[shard] ?? 0)) {
            cursors[shard]=value;
            await transaction.insert('sync_cursors',{
              'relationship_id':relationshipId,'sync_shard':shard,'last_server_sequence':value,
            },conflictAlgorithm:ConflictAlgorithm.replace);
          }
        }
      }
    });
  }

  Future<OfflineOperation?> getOperation(String operationId) async {
    final rows = await _database.query(
      'local_operations',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    return rows.isEmpty ? null : OfflineOperation.fromRow(rows.first);
  }

  Future<void> close() => _database.close();
}
