#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build_type="${1:-Release}"
output_dir="${2:-$root/build/conan-${build_type,,}}"
profile="${CPPBOOSTNATIVE_CONAN_PROFILE:-}"

if [[ -z "$profile" ]]; then
  case "$(uname -s):$(uname -m)" in
    Linux:aarch64|Linux:arm64)
      profile="$root/conan/profiles/linux-gcc-armv8"
      ;;
    Linux:x86_64)
      profile="$root/conan/profiles/linux-gcc-x86_64"
      ;;
    Darwin:arm64)
      profile="$root/conan/profiles/macos-apple-clang-armv8"
      ;;
    *)
      echo "unsupported Conan host: $(uname -s) $(uname -m)" >&2
      exit 1
      ;;
  esac
fi

"$root/scripts/conan-configure-remotes.sh"
conan_home="$(conan config home)"
install -m 0644 "$root/conan/settings_user.yml" \
  "$conan_home/settings_user.yml"
source_download_cache="${CPPBOOSTNATIVE_CONAN_SOURCE_CACHE:-$conan_home/source-download-cache}"
mkdir -p "$source_download_cache"

lockfile="${CPPBOOSTNATIVE_CONAN_LOCKFILE:-$root/conan/locks/$(basename "$profile").lock}"
lock_args=()
if [[ "$lockfile" != "none" ]]; then
  if [[ ! -f "$lockfile" ]]; then
    echo "Conan lockfile is missing: $lockfile; run scripts/conan-lock.sh" >&2
    exit 2
  fi
  lock_args=(--lockfile "$lockfile")
fi

conan install "$root" \
  --profile:host "$profile" \
  --profile:build "$profile" \
  -s:h "build_type=$build_type" \
  -s:b "build_type=$build_type" \
  --build=missing \
  -cc "core.sources:download_cache=$source_download_cache" \
  -c "tools.cmake.cmaketoolchain:user_presets=" \
  "${lock_args[@]}" \
  --output-folder="$output_dir" \
  "${@:3}"

mapfile -t toolchains < <(find "$output_dir" -type f \
  -name conan_toolchain.cmake -print)
if [[ "${#toolchains[@]}" -ne 1 ]]; then
  echo "expected exactly one Conan toolchain below $output_dir, found ${#toolchains[@]}" >&2
  exit 2
fi
printf '%s\n' "${toolchains[0]}" >"$output_dir/toolchain.path"
