#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$root/conan/locks"
"$root/scripts/conan-configure-remotes.sh"

for profile in "$root"/conan/profiles/*; do
  [[ -f "$profile" ]] || continue
  conan lock create "$root" \
    --profile:host "$profile" \
    --profile:build "$profile" \
    -s:h build_type=Release \
    -s:b build_type=Release \
    --lockfile-out "$root/conan/locks/$(basename "$profile").lock"
done
