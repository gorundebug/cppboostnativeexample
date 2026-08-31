#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version=$(python3 "$root/conan/dependencies_generated.py" grpc)
conan export "$root/conan/recipes/grpc" \
  --version "$version" --user gorundebug --channel boost
