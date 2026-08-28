#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
target="${1:?Docker target is required}"
tag="${2:?image tag is required}"

source "$root/scripts/dependency-proxy-env.sh"
exec docker build \
  --add-host host.docker.internal:host-gateway \
  --build-arg "DEPENDENCY_DOCKER_REGISTRY=${DEPENDENCY_DOCKER_REGISTRY:-docker.io}" \
  --build-arg "DEPENDENCY_APT_UBUNTU_ARCHIVE_URL=${DEPENDENCY_APT_UBUNTU_ARCHIVE_URL:-}" \
  --build-arg "DEPENDENCY_APT_UBUNTU_SECURITY_URL=${DEPENDENCY_APT_UBUNTU_SECURITY_URL:-}" \
  --build-arg "DEPENDENCY_APT_UBUNTU_PORTS_URL=${DEPENDENCY_APT_UBUNTU_PORTS_URL:-}" \
  --build-arg "DEPENDENCY_CONAN_REMOTE_URL=${DEPENDENCY_CONAN_REMOTE_URL:-}" \
  --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL:-https://pypi.org/simple}" \
  --build-arg "PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST:-}" \
  --target "$target" \
  --tag "$tag" \
  "$root"
