ARG DEPENDENCY_DOCKER_REGISTRY=docker.io
FROM ${DEPENDENCY_DOCKER_REGISTRY}/library/ubuntu:24.04 AS build-base
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG DEPENDENCY_APT_UBUNTU_ARCHIVE_URL=
ARG DEPENDENCY_APT_UBUNTU_SECURITY_URL=
ARG DEPENDENCY_APT_UBUNTU_PORTS_URL=
ARG DEPENDENCY_CONAN_REMOTE_URL=
ARG PIP_INDEX_URL=https://pypi.org/simple
ARG PIP_TRUSTED_HOST=
ENV DEPENDENCY_CONAN_REMOTE_URL=${DEPENDENCY_CONAN_REMOTE_URL}
RUN if [ -n "$DEPENDENCY_APT_UBUNTU_ARCHIVE_URL$DEPENDENCY_APT_UBUNTU_SECURITY_URL$DEPENDENCY_APT_UBUNTU_PORTS_URL" ]; then \
      find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|$DEPENDENCY_APT_UBUNTU_ARCHIVE_URL|g" \
        -e "s|http://security.ubuntu.com/ubuntu|$DEPENDENCY_APT_UBUNTU_SECURITY_URL|g" \
        -e "s|http://ports.ubuntu.com/ubuntu-ports|$DEPENDENCY_APT_UBUNTU_PORTS_URL|g" {} +; \
    fi
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=servicegen-apt-lists-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=servicegen-apt-cache-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    apt-get update \
    && apt-get install --yes --no-install-recommends \
      build-essential ca-certificates ccache cmake ninja-build pkg-config \
      python3 python3-venv
COPY conan/dependencies_generated.py /tmp/dependencies_generated.py
RUN CONAN_VERSION="$(python3 /tmp/dependencies_generated.py conan)" \
    && python3 -m venv /opt/conan \
    && PIP_TRUSTED_HOST="$PIP_TRUSTED_HOST" \
       /opt/conan/bin/pip install --no-cache-dir --index-url "$PIP_INDEX_URL" \
       "conan==$CONAN_VERSION" \
    && rm -f /tmp/dependencies_generated.py
ENV PATH=/opt/conan/bin:$PATH
ENV CONAN_HOME=/conan
WORKDIR /workspace
COPY conanfile.py ./
COPY conan ./conan
COPY scripts/conan-cache-guard.sh scripts/conan-configure-remotes.sh \
     scripts/conan-export-recipes.sh scripts/conan-install.sh \
     scripts/run_with_progress.sh ./scripts/

FROM build-base AS release-dependencies
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    ./scripts/run_with_progress.sh "Conan Release install" \
      ./scripts/conan-install.sh Release /workspace/build/conan-release

FROM release-dependencies AS release-build
COPY CMakeLists.txt ./
COPY proto ./proto
COPY scripts ./scripts
COPY src ./src
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    conan_toolchain="$(cat build/conan-release/toolchain.path)" \
    && ./scripts/run_with_progress.sh "Release configure" \
      cmake -S . -B build-release -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$conan_toolchain" \
        -DBUILD_TESTING=OFF \
    && ./scripts/run_with_progress.sh "Release build" \
      cmake --build build-release \
        --target inventoryservice orderservice inventoryservice_cq --parallel

FROM build-base AS debug-dependencies
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    ./scripts/run_with_progress.sh "Conan Debug install" \
      ./scripts/conan-install.sh Debug /workspace/build/conan-debug

FROM debug-dependencies AS test
COPY CMakeLists.txt ./
COPY proto ./proto
COPY scripts ./scripts
COPY src ./src
COPY tests ./tests
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    conan_toolchain="$(cat build/conan-debug/toolchain.path)" \
    && ./scripts/run_with_progress.sh "Debug configure" \
      cmake -S . -B build-debug -G Ninja \
        -DCMAKE_BUILD_TYPE=Debug \
        -DCMAKE_TOOLCHAIN_FILE="$conan_toolchain" \
        -DBUILD_TESTING=ON \
    && ./scripts/run_with_progress.sh "Debug build" \
      cmake --build build-debug --parallel \
    && ctest --test-dir build-debug --output-on-failure

FROM build-base AS asan-dependencies
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    ./scripts/run_with_progress.sh "Conan ASan/UBSan install" \
      ./scripts/conan-install.sh RelWithDebInfo /workspace/build/conan-asan \
        -s:h compiler.sanitizer=Address \
        -c:h 'tools.build:cflags=["-fsanitize=address,undefined","-fno-omit-frame-pointer"]' \
        -c:h 'tools.build:cxxflags=["-fsanitize=address,undefined","-fno-omit-frame-pointer"]' \
        -c:h 'tools.build:exelinkflags=["-fsanitize=address,undefined"]' \
        -c:h 'tools.build:sharedlinkflags=["-fsanitize=address,undefined"]'

FROM asan-dependencies AS asan-test
COPY CMakeLists.txt ./
COPY proto ./proto
COPY scripts ./scripts
COPY src ./src
COPY tests ./tests
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    conan_toolchain="$(cat build/conan-asan/toolchain.path)" \
    && ./scripts/run_with_progress.sh "ASan/UBSan configure" \
      cmake -S . -B build-asan -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_TOOLCHAIN_FILE="$conan_toolchain" \
        -DBUILD_TESTING=ON \
        -DCPPBOOSTNATIVE_ASAN=ON \
        -DCPPBOOSTNATIVE_UBSAN=ON \
    && ./scripts/run_with_progress.sh "ASan/UBSan build" \
      cmake --build build-asan --parallel \
    && ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
       UBSAN_OPTIONS=halt_on_error=1 \
       ctest --test-dir build-asan --output-on-failure \
    && ./scripts/sanitizer_integration.sh build-asan asan

FROM build-base AS tsan-dependencies
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    ./scripts/run_with_progress.sh "Conan TSan install" \
      ./scripts/conan-install.sh RelWithDebInfo /workspace/build/conan-tsan \
        -s:h compiler.sanitizer=Thread \
        -c:h 'tools.build:cflags=["-fsanitize=thread","-fno-omit-frame-pointer"]' \
        -c:h 'tools.build:cxxflags=["-fsanitize=thread","-fno-omit-frame-pointer"]' \
        -c:h 'tools.build:exelinkflags=["-fsanitize=thread"]' \
        -c:h 'tools.build:sharedlinkflags=["-fsanitize=thread"]'

FROM tsan-dependencies AS tsan-test
COPY CMakeLists.txt ./
COPY proto ./proto
COPY scripts ./scripts
COPY src ./src
COPY tests ./tests
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    conan_toolchain="$(cat build/conan-tsan/toolchain.path)" \
    && ./scripts/run_with_progress.sh "TSan configure" \
      cmake -S . -B build-tsan -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_TOOLCHAIN_FILE="$conan_toolchain" \
        -DBUILD_TESTING=ON \
        -DCPPBOOSTNATIVE_TSAN=ON \
    && ./scripts/run_with_progress.sh "TSan build" \
      cmake --build build-tsan --parallel \
    && TSAN_OPTIONS=halt_on_error=1 \
       ctest --test-dir build-tsan --output-on-failure \
    && ./scripts/sanitizer_integration.sh build-tsan tsan

FROM ${DEPENDENCY_DOCKER_REGISTRY}/library/ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG DEPENDENCY_APT_UBUNTU_ARCHIVE_URL=
ARG DEPENDENCY_APT_UBUNTU_SECURITY_URL=
ARG DEPENDENCY_APT_UBUNTU_PORTS_URL=
RUN if [ -n "$DEPENDENCY_APT_UBUNTU_ARCHIVE_URL$DEPENDENCY_APT_UBUNTU_SECURITY_URL$DEPENDENCY_APT_UBUNTU_PORTS_URL" ]; then \
      find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|$DEPENDENCY_APT_UBUNTU_ARCHIVE_URL|g" \
        -e "s|http://security.ubuntu.com/ubuntu|$DEPENDENCY_APT_UBUNTU_SECURITY_URL|g" \
        -e "s|http://ports.ubuntu.com/ubuntu-ports|$DEPENDENCY_APT_UBUNTU_PORTS_URL|g" {} +; \
    fi
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=servicegen-apt-lists-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=servicegen-apt-cache-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates

FROM runtime AS inventoryservice
COPY --from=release-build /workspace/build-release/inventoryservice /usr/local/bin/inventoryservice
ENTRYPOINT ["/usr/local/bin/inventoryservice"]

FROM runtime AS orderservice
COPY --from=release-build /workspace/build-release/orderservice /usr/local/bin/orderservice
ENTRYPOINT ["/usr/local/bin/orderservice"]

FROM runtime AS inventoryservice-cq
COPY --from=release-build /workspace/build-release/inventoryservice_cq /usr/local/bin/inventoryservice_cq
ENTRYPOINT ["/usr/local/bin/inventoryservice_cq"]
