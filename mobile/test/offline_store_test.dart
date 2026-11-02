import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shared_ledger_mobile_core/src/offline_store.dart';

import 'offline_store_contract.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  runOfflineStoreContractTests(
    openStore: (path) => OfflineStore.openForTesting(
      factory: databaseFactoryFfi,
      path: path,
    ),
  );
}
