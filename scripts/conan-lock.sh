#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$root/scripts/conan-cache-guard.sh"
dependency_conan_cache_guard "$0" "$@"
mkdir -p "$root/conan/locks"
"$root/scripts/conan-configure-remotes.sh"
"$root/scripts/conan-export-recipes.sh"

for profile in "$root"/conan/profiles/*; do
  [[ -f "$profile" ]] || continue
  conan lock create "$root" \
    --profile:host "$profile" \
    --profile:build "$profile" \
    -s:h build_type=Release \
    -s:b build_type=Release \
    -o:h "openssl/*:no_engine=False" \
    -o:b "openssl/*:no_engine=False" \
    --lockfile-out "$root/conan/locks/$(basename "$profile").lock"
done
