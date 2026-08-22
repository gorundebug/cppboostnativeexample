#!/usr/bin/env bash

set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <operation name> <command> [args...]" >&2
  exit 2
fi

operation="$1"
shift

echo "[progress] ${operation}: started"
"$@" &
command_pid=$!

(
  while kill -0 "${command_pid}" 2>/dev/null; do
    sleep 15
    if kill -0 "${command_pid}" 2>/dev/null; then
      echo "[progress] ${operation}: still running"
    fi
  done
) &
heartbeat_pid=$!

cleanup() {
  kill "${heartbeat_pid}" 2>/dev/null || true
  wait "${heartbeat_pid}" 2>/dev/null || true
}

forward_signal() {
  kill -TERM "${command_pid}" 2>/dev/null || true
}

trap forward_signal INT TERM
trap cleanup EXIT

wait "${command_pid}"
status=$?

if [[ ${status} -eq 0 ]]; then
  echo "[progress] ${operation}: completed"
else
  echo "[progress] ${operation}: failed with exit code ${status}" >&2
fi

exit "${status}"
