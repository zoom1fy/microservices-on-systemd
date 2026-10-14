#!/bin/bash
set -eu

ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)"

for _ in $(seq 1 30); do
    pg_isready -q && break
    sleep 1
done
if ! pg_isready -q; then
    echo "postgresql is not ready" >&2
    exit 1
fi

if [ "$(psql -tAc "SELECT 1 FROM pg_database WHERE datname='demo'")" != "1" ]; then
    psql -v ON_ERROR_STOP=1 -f "$ROOT/db/init.sql"
    echo "database demo initialized"
else
    echo "database demo already exists, skipping"
fi
