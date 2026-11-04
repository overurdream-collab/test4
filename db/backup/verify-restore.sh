#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required (source database)}"

RESTORE_DB="${RESTORE_DB:-${PGDATABASE}_restore}"
FINGERPRINT_SQL="db/backup/table_fingerprint.sql"

DUMP_FILE="$(mktemp)"
SOURCE_FP="$(mktemp)"
RESTORE_FP="$(mktemp)"

cleanup() {
    rm -f "$DUMP_FILE" "$SOURCE_FP" "$RESTORE_FP"
}
trap cleanup EXIT

export PGHOST PGPORT PGUSER PGPASSWORD

echo "Dumping source database ${PGDATABASE}..."
pg_dump --no-owner --no-acl -d "$PGDATABASE" -f "$DUMP_FILE"

echo "Recreating restore database ${RESTORE_DB}..."
psql -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS \"${RESTORE_DB}\";"
psql -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE \"${RESTORE_DB}\";"

echo "Restoring into ${RESTORE_DB}..."
grep -v '^SET transaction_timeout = 0;' "$DUMP_FILE" | psql -v ON_ERROR_STOP=1 -d "$RESTORE_DB"

echo "Fingerprinting source and restored databases..."
psql -v ON_ERROR_STOP=1 -d "$PGDATABASE" -f "$FINGERPRINT_SQL" > "$SOURCE_FP"
psql -v ON_ERROR_STOP=1 -d "$RESTORE_DB" -f "$FINGERPRINT_SQL" > "$RESTORE_FP"

if ! diff -u "$SOURCE_FP" "$RESTORE_FP"; then
    echo "ERROR: backup/restore fingerprint mismatch for ${PGDATABASE} -> ${RESTORE_DB}" >&2
    exit 1
fi

echo "OK: full restore verified — ${PGDATABASE} and ${RESTORE_DB} fingerprints match."
