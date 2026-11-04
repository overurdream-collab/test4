import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_ledger_mobile_core/src/offline_store.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const _relationshipId = '13000000-0000-0000-0000-000000000001';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  late Directory databaseDirectory;
  late String databasePath;

  setUp(() async {
    expect(
      Platform.isAndroid,
      isTrue,
      reason:
          'v1 target is Android; other platforms are documented as deferred.',
    );
    databaseDirectory = Directory(await sqlcipher.getDatabasesPath());
    await databaseDirectory.create(recursive: true);
    databasePath =
        '${databaseDirectory.path}/sqlcipher-contract-${DateTime.now().microsecondsSinceEpoch}.db';
    await storage.delete(key: offlineStoreDatabaseKeyName);
  });

  tearDown(() async {
    await storage.delete(key: offlineStoreDatabaseKeyName);
    for (final path in _databaseFiles(databasePath)) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  });

  testWidgets(
    'SQLCipher encrypts payloads at rest and survives reopen',
    (tester) async {
      final marker =
          'PLAINTEXT_MARKER_${DateTime.now().microsecondsSinceEpoch}';
      const operationId = '33000000-0000-0000-0000-000000000101';

      var store = await OfflineStore.openEncrypted(
        path: databasePath,
        secureStorage: storage,
      );
      await store.enqueueOperation(
        operationId: operationId,
        relationshipId: _relationshipId,
        operationType: 'credit_charge',
        payload: {'currency': 'YER', 'amountMinor': 1500, 'marker': marker},
        baseServerVersion: 0,
        clientCreatedAt: DateTime.utc(2026, 11, 2),
      );
      await store.close();

      final files = _databaseFiles(
        databasePath,
      ).where((path) => File(path).existsSync()).toList();
      expect(files, isNotEmpty, reason: 'Expected SQLCipher database files.');

      final sqliteHeader = utf8.encode('SQLite format 3\u0000');
      for (final path in files) {
        final bytes = await File(path).readAsBytes();
        expect(
          _contains(bytes, utf8.encode(marker)),
          isFalse,
          reason: 'Plaintext marker leaked into $path.',
        );
        if (path == databasePath) {
          expect(bytes.length, greaterThanOrEqualTo(sqliteHeader.length));
          expect(
            bytes.sublist(0, sqliteHeader.length),
            isNot(equals(sqliteHeader)),
            reason: 'Database header is not encrypted.',
          );
        }
      }

      final key = await storage.read(key: offlineStoreDatabaseKeyName);
      expect(key, isNotNull);
      expect(key!.length, greaterThanOrEqualTo(40));
      expect(await storage.read(key: offlineStoreDatabaseKeyName), key);

      store = await OfflineStore.openEncrypted(
        path: databasePath,
        secureStorage: storage,
      );
      final operation = await store.getOperation(operationId);
      expect(operation, isNotNull);
      expect(operation!.payload['marker'], marker);
      await store.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'wrong key fails explicitly and does not erase ciphertext',
    (tester) async {
      const operationId = '33000000-0000-0000-0000-000000000102';
      const marker = 'WRONG_KEY_SURVIVAL_MARKER';

      var store = await OfflineStore.openEncrypted(
        path: databasePath,
        secureStorage: storage,
      );
      await store.enqueueOperation(
        operationId: operationId,
        relationshipId: _relationshipId,
        operationType: 'credit_charge',
        payload: {'currency': 'YER', 'amountMinor': 500, 'marker': marker},
        baseServerVersion: 0,
      );
      await store.close();

      final originalKey = await storage.read(key: offlineStoreDatabaseKeyName);
      expect(originalKey, isNotNull);

      expect(await File(databasePath).exists(), isTrue);
      final mainDatabaseSizeBefore = await File(databasePath).length();

      var wrongKey = _validDifferentKey();
      while (wrongKey == originalKey) {
        wrongKey = _validDifferentKey();
      }
      await storage.write(key: offlineStoreDatabaseKeyName, value: wrongKey);

      await expectLater(
        OfflineStore.openEncrypted(path: databasePath, secureStorage: storage),
        throwsA(anything),
      );

      expect(
        await File(databasePath).exists(),
        isTrue,
        reason: 'Wrong key must not delete the database.',
      );
      expect(
        await File(databasePath).length(),
        mainDatabaseSizeBefore,
        reason: 'Wrong key must not rewrite the database.',
      );

      await storage.write(key: offlineStoreDatabaseKeyName, value: originalKey);
      store = await OfflineStore.openEncrypted(
        path: databasePath,
        secureStorage: storage,
      );
      final operation = await store.getOperation(operationId);
      expect(operation, isNotNull);
      expect(operation!.payload['marker'], marker);
      await store.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'missing key refuses to open existing database without creating a replacement key',
    (tester) async {
      const operationId = '33000000-0000-0000-0000-000000000103';
      const marker = 'MISSING_KEY_PRESERVATION_MARKER';

      var store = await OfflineStore.openEncrypted(
        path: databasePath,
        secureStorage: storage,
      );
      await store.enqueueOperation(
        operationId: operationId,
        relationshipId: _relationshipId,
        operationType: 'credit_charge',
        payload: {'currency': 'YER', 'amountMinor': 700, 'marker': marker},
        baseServerVersion: 0,
      );
      await store.close();

      final originalKey = await storage.read(key: offlineStoreDatabaseKeyName);
      expect(originalKey, isNotNull);
      final originalBytes = await File(databasePath).readAsBytes();

      await storage.delete(key: offlineStoreDatabaseKeyName);

      await expectLater(
        OfflineStore.openEncrypted(path: databasePath, secureStorage: storage),
        throwsA(isA<StateError>()),
      );

      expect(
        await storage.read(key: offlineStoreDatabaseKeyName),
        isNull,
        reason: 'Missing key must not be replaced automatically.',
      );
      expect(
        await File(databasePath).readAsBytes(),
        originalBytes,
        reason:
            'Existing database must not be rewritten when the key is missing.',
      );

      await storage.write(key: offlineStoreDatabaseKeyName, value: originalKey);
      store = await OfflineStore.openEncrypted(
        path: databasePath,
        secureStorage: storage,
      );
      final recovered = await store.getOperation(operationId);
      expect(recovered, isNotNull);
      expect(recovered!.payload['marker'], marker);
      final pending = await store.pendingOperations(
        relationshipId: _relationshipId,
      );
      expect(pending, isNotEmpty);
      await store.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'short invalid key is rejected before creating a database',
    (tester) async {
      await storage.write(key: offlineStoreDatabaseKeyName, value: 'too-short');

      await expectLater(
        OfflineStore.openEncrypted(path: databasePath, secureStorage: storage),
        throwsA(isA<StateError>()),
      );
      expect(await File(databasePath).exists(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

List<String> _databaseFiles(String path) => [
  path,
  '$path-wal',
  '$path-shm',
  '$path-journal',
];

String _validDifferentKey() {
  final bytes = List<int>.generate(32, (index) => (index * 7 + 11) % 256);
  return base64UrlEncode(bytes);
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) {
    return true;
  }
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}
