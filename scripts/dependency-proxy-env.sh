#!/usr/bin/env bash

if [[ -n "${SERVICEGEN_DEPENDENCY_PROXY_DIR:-}" ]]; then
  proxy_host="${SERVICEGEN_DEPENDENCY_PROXY_DOCKER_HOST:-host.docker.internal}"
  proxy_port="${SERVICEGEN_DEPENDENCY_PROXY_PORT:-${SERVICEGEN_NEXUS_PORT:-18081}}"
  proxy_base="http://${proxy_host}:${proxy_port}/repository"

  export SERVICEGEN_CONAN_REMOTE_URL="${proxy_base}/conan-proxy"
  export PIP_INDEX_URL="${proxy_base}/pypi-proxy/simple"
  export PIP_TRUSTED_HOST="${proxy_host}"
  export SERVICEGEN_APT_UBUNTU_ARCHIVE_URL="${proxy_base}/apt-ubuntu-archive"
  export SERVICEGEN_APT_UBUNTU_SECURITY_URL="${proxy_base}/apt-ubuntu-security"
  export SERVICEGEN_APT_UBUNTU_PORTS_URL="${proxy_base}/apt-ubuntu-ports"
fi
