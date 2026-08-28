#!/usr/bin/env bash

# Serialize every mutation of a shared Conan home across build containers.
# Finished recipes, sources and packages remain cached; only transient build
# state from an interrupted Conan process is discarded by the new owner.
dependency_conan_cache_guard() {
  local script=${1:?script path is required}
  shift

  if [[ "${DEPENDENCY_CONAN_CACHE_LOCK_HELD:-0}" == "1" ]]; then
    conan cache clean "*" --build --temp >/dev/null
    return
  fi

  local conan_home
  conan_home=$(conan config home)
  mkdir -p "$conan_home"
  if ! command -v flock >/dev/null 2>&1; then
    echo "flock is required to use the shared Conan cache safely" >&2
    return 1
  fi

  exec flock "$conan_home/.dependency-cache.lock" \
    env DEPENDENCY_CONAN_CACHE_LOCK_HELD=1 "$script" "$@"
}
