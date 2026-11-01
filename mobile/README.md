# Mobile offline data core

This is a Flutter package, not a user interface or complete application.

## Local persistence

- Production opening uses sqflite_sqlcipher and SQLCipher 4.
- A random 256-bit database passphrase is generated once and stored using flutter_secure_storage.
- If secure storage cannot return the key, the database does not fall back to plaintext.
- Local operation and outbox rows are inserted in one SQLite transaction.
- Transport state is separate from approval/business state.
- The event applier enforces per-relationship ordered cursors and rejects gaps atomically.
- A retry always reuses the original operation ID and stored payload.

## Testing boundary

The automated unit tests use sqflite_common_ffi with ordinary SQLite to test repository logic, HTTP transport behavior, and two independent local database files against a fake server. They do not prove SQLCipher native encryption, Android Keystore behavior, or a full PostgreSQL-to-physical-device round trip. Those require an Android/iOS integration test on a real device or emulator.

## Dependency review before production

The current SQLCipher plugin is sqflite_sqlcipher 3.4.1 (SQLCipher 4.x). Its pub.dev publisher is listed as an unverified uploader. The package is MIT licensed, but this is not a substitute for source-code and release-artifact review. It supports Android, iOS, and macOS; its documentation also requires this Android release ProGuard rule:

    -keep class net.sqlcipher.** { *; }

The selected flutter_secure_storage release uses platform secure storage. The current 11.x release raises its Android minimum to API 24. This implies an Android 7.0+ baseline unless a different, reviewed version is selected.

Before a production build:
1. Review and pin the SQLCipher plugin source and native binaries.
2. Test opening with the correct key and failing with a wrong key on Android and iOS.
3. Verify database files, WAL, SHM, and temporary files are encrypted or appropriately protected.
4. Define backup/restore and key-recovery behavior; a database restored without its platform-held key must not be silently reset.
5. Verify Android backup exclusions and key accessibility after device reboot/app upgrade.

## Run

    flutter pub get
    dart format --set-exit-if-changed .
    flutter analyze
    flutter test

No screens, production authentication, server deployment, or paid service are included.
