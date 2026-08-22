#!/usr/bin/env bash
set -euo pipefail

build_dir="${1:?build directory is required}"
sanitizer="${2:?sanitizer name is required}"

case "$sanitizer" in
  asan)
    export ASAN_OPTIONS="detect_leaks=1:halt_on_error=1"
    export UBSAN_OPTIONS="halt_on_error=1"
    ;;
  tsan)
    export TSAN_OPTIONS="halt_on_error=1"
    ;;
  *)
    echo "unsupported sanitizer: $sanitizer" >&2
    exit 2
    ;;
esac

inventory_pid=""
order_pid=""
cleanup() {
  if [[ -n "$order_pid" ]]; then
    kill -TERM "$order_pid" 2>/dev/null || true
    wait "$order_pid" 2>/dev/null || true
  fi
  if [[ -n "$inventory_pid" ]]; then
    kill -TERM "$inventory_pid" 2>/dev/null || true
    wait "$inventory_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

NATIVE_WORKER_THREADS=2 \
  "./${build_dir}/inventoryservice" &
inventory_pid="$!"

NATIVE_WORKER_THREADS=2 \
INVENTORY_SERVICE_API_ADDRESS=dns:///127.0.0.1:9202 \
  "./${build_dir}/orderservice" &
order_pid="$!"

ready=0
for _ in $(seq 1 100); do
  if python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:9091/status/data", timeout=0.2)' \
      >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$inventory_pid" 2>/dev/null || \
     ! kill -0 "$order_pid" 2>/dev/null; then
    echo "sanitized service exited before readiness" >&2
    exit 1
  fi
  sleep 0.1
done
if [[ "$ready" -ne 1 ]]; then
  echo "sanitized services did not become ready" >&2
  exit 1
fi

python3 tests/integration_test.py

kill -TERM "$order_pid"
wait "$order_pid"
order_pid=""
kill -TERM "$inventory_pid"
wait "$inventory_pid"
inventory_pid=""
