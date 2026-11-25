#!/usr/bin/env bash
# Starts a throwaway backend on localhost and runs the app's sync/content
# integration tests against it. Usage: tools/run_server_integration.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
PORT="${QJ_TEST_PORT:-8799}"
export QJ_DB_PATH="$TMP/test.sqlite" QJ_PORT="$PORT" QJ_HOST=127.0.0.1
export QJ_TEST_ADMIN_EMAIL="admin@example.org"
export QJ_TEST_ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -d '/+=')"
cd "$ROOT/server"
node --no-warnings bin/seed.js >/dev/null
QJ_ADMIN_PASSWORD="$QJ_TEST_ADMIN_PASSWORD" node --no-warnings bin/create-admin.js "$QJ_TEST_ADMIN_EMAIL" >/dev/null
node --no-warnings bin/server.js > "$TMP/server.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 50); do curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break; sleep 0.2; done
cd "$ROOT/app"
QJ_TEST_SERVER="http://localhost:$PORT" flutter test integration_server_test/
