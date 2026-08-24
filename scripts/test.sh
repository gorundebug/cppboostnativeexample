#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

cleanup() {
  docker compose down --timeout 10 >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build --target test -t cppboostnativeexample-test:latest .
docker compose build
docker compose up --detach --no-build

ready=0
for attempt in $(seq 1 60); do
  if python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:9091/status/data", timeout=1)' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  docker compose logs --no-color
  exit 1
fi

python3 tests/integration_test.py
