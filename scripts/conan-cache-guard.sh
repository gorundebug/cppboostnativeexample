#!/usr/bin/env bash

# Serialize every mutation of a shared Conan home across build containers.
# Finished recipes, sources, packages and transient build state remain cached.
# Cache repair is an explicit operation and is never part of a normal build.
dependency_conan_cache_guard() {
  local script=${1:?script path is required}
  shift

  if [[ "${DEPENDENCY_CONAN_CACHE_LOCK_HELD:-0}" == "1" ]]; then
    return
  fi

  local conan_home=${CONAN_HOME:-${HOME:?HOME is required}/.conan2}
  mkdir -p "$conan_home"
  if ! command -v flock >/dev/null 2>&1; then
    echo "flock is required to use the shared Conan cache safely" >&2
    return 1
  fi

  exec flock "$conan_home/.dependency-cache.lock" \
    env DEPENDENCY_CONAN_CACHE_LOCK_HELD=1 "$script" "$@"
}
