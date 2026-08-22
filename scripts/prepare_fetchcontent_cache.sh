#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <cmake build directory>" >&2
  exit 2
fi

build_dir="$1"
cache_dir="/var/cache/cmake-fetchcontent"
archive_cache="${cache_dir}/http_archives"
archive_link="${build_dir}/http_archives"

mkdir -p "${build_dir}" "${archive_cache}"

if [[ -L "${archive_link}" ]]; then
  if [[ "$(readlink "${archive_link}")" != "${archive_cache}" ]]; then
    echo "unexpected FetchContent archive link: ${archive_link}" >&2
    exit 1
  fi
elif [[ -e "${archive_link}" ]]; then
  echo "FetchContent archive path is not a symlink: ${archive_link}" >&2
  exit 1
else
  ln -s "${archive_cache}" "${archive_link}"
fi

echo "[progress] FetchContent archives: ${archive_link} -> ${archive_cache}"
