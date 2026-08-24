#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SERVICEGEN_CONAN_REMOTE_URL:-}" ]]; then
  conan remote remove conancenter >/dev/null 2>&1 || true
  conan remote add servicegen-nexus "$SERVICEGEN_CONAN_REMOTE_URL" \
    --force --insecure
  exit 0
fi

conan remote remove servicegen-nexus >/dev/null 2>&1 || true
conan remote add conancenter https://center2.conan.io --force
