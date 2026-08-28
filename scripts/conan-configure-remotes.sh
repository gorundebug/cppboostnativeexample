#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DEPENDENCY_CONAN_REMOTE_URL:-}" ]]; then
  conan remote remove conancenter >/dev/null 2>&1 || true
  conan remote remove servicegen-nexus >/dev/null 2>&1 || true
  if conan remote list | grep -q '^dependency-proxy:'; then
    conan remote update dependency-proxy --url "$DEPENDENCY_CONAN_REMOTE_URL" --insecure
  else
    conan remote add dependency-proxy "$DEPENDENCY_CONAN_REMOTE_URL" --insecure
  fi
  exit 0
fi

conan remote remove servicegen-nexus >/dev/null 2>&1 || true
conan remote remove dependency-proxy >/dev/null 2>&1 || true
if conan remote list | grep -q '^conancenter:'; then
  conan remote update conancenter --url https://center2.conan.io
else
  conan remote add conancenter https://center2.conan.io
fi
