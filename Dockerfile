# syntax=docker/dockerfile:1
ARG SERVICEGEN_GRPC_SOURCE_STAGE=empty-source-cache
ARG SERVICEGEN_ASIO_GRPC_SOURCE_STAGE=empty-source-cache
FROM scratch AS empty-source-cache
FROM ${SERVICEGEN_GRPC_SOURCE_STAGE} AS grpc-source-context
FROM ${SERVICEGEN_ASIO_GRPC_SOURCE_STAGE} AS asio-grpc-source-context

FROM ubuntu:24.04 AS build
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=servicegen-apt-lists-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=servicegen-apt-cache-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    apt-get update \
    && apt-get install --yes --no-install-recommends \
      build-essential ca-certificates ccache cmake git libboost-json1.83-dev \
      libjemalloc-dev libssl-dev ninja-build pkg-config python3 zlib1g-dev
WORKDIR /workspace
COPY CMakeLists.txt ./
COPY proto ./proto
COPY src ./src
COPY scripts ./scripts
COPY tests ./tests
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=cppboostnative-fetchcontent-${TARGETARCH},target=/var/cache/cmake-fetchcontent,sharing=locked \
    --mount=type=cache,id=servicegen-grpc-v1.71.0-asio-grpc-v3.5.0-sources-${TARGETARCH},target=/var/cache/servicegen-cpp-sources,sharing=locked \
    --mount=type=bind,from=grpc-source-context,target=/servicegen-grpc-source,ro \
    --mount=type=bind,from=asio-grpc-source-context,target=/servicegen-asio-grpc-source,ro \
    grpc_source_arg="" \
    && asio_grpc_source_arg="" \
    && if [ -f /var/cache/servicegen-cpp-sources/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/servicegen-cpp-sources/grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/cmake-fetchcontent/grpc-src"; \
       fi \
    && if [ -f /var/cache/servicegen-cpp-sources/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/servicegen-cpp-sources/asio-grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/cmake-fetchcontent/asio-grpc-src"; \
       fi \
    && if [ -f /servicegen-grpc-source/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/servicegen-grpc-source"; \
       fi \
    && if [ -f /servicegen-asio-grpc-source/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/servicegen-asio-grpc-source"; \
       fi \
    && ./scripts/prepare_fetchcontent_cache.sh build \
    && ./scripts/run_with_progress.sh "Release configure" \
      cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DFETCHCONTENT_BASE_DIR=/var/cache/cmake-fetchcontent \
      -DFETCHCONTENT_UPDATES_DISCONNECTED=ON \
      ${grpc_source_arg} ${asio_grpc_source_arg} \
    && ./scripts/run_with_progress.sh "Release build" \
      cmake --build build --target inventoryservice orderservice inventoryservice_cq --parallel

FROM build AS test
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=cppboostnative-fetchcontent-${TARGETARCH},target=/var/cache/cmake-fetchcontent,sharing=locked \
    --mount=type=cache,id=servicegen-grpc-v1.71.0-asio-grpc-v3.5.0-sources-${TARGETARCH},target=/var/cache/servicegen-cpp-sources,sharing=locked \
    grpc_source_arg="" \
    && asio_grpc_source_arg="" \
    && if [ -f /var/cache/servicegen-cpp-sources/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/servicegen-cpp-sources/grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/cmake-fetchcontent/grpc-src"; \
       fi \
    && if [ -f /var/cache/servicegen-cpp-sources/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/servicegen-cpp-sources/asio-grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/cmake-fetchcontent/asio-grpc-src"; \
       fi \
    && ./scripts/prepare_fetchcontent_cache.sh build-test \
    && ./scripts/run_with_progress.sh "Debug test configure" \
      cmake -S . -B build-test -G Ninja \
      -DCMAKE_BUILD_TYPE=Debug \
      -DBUILD_TESTING=ON \
      -DFETCHCONTENT_BASE_DIR=/var/cache/cmake-fetchcontent \
      -DFETCHCONTENT_UPDATES_DISCONNECTED=ON \
      ${grpc_source_arg} ${asio_grpc_source_arg} \
    && ./scripts/run_with_progress.sh "Debug test build" \
      cmake --build build-test --parallel \
    && ctest --test-dir build-test --output-on-failure

FROM build AS asan-test
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=cppboostnative-fetchcontent-${TARGETARCH},target=/var/cache/cmake-fetchcontent,sharing=locked \
    --mount=type=cache,id=servicegen-grpc-v1.71.0-asio-grpc-v3.5.0-sources-${TARGETARCH},target=/var/cache/servicegen-cpp-sources,sharing=locked \
    grpc_source_arg="" \
    && asio_grpc_source_arg="" \
    && if [ -f /var/cache/servicegen-cpp-sources/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/servicegen-cpp-sources/grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/cmake-fetchcontent/grpc-src"; \
       fi \
    && if [ -f /var/cache/servicegen-cpp-sources/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/servicegen-cpp-sources/asio-grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/cmake-fetchcontent/asio-grpc-src"; \
       fi \
    && ./scripts/prepare_fetchcontent_cache.sh build-asan \
    && ./scripts/run_with_progress.sh "ASan/UBSan configure" \
      cmake -S . -B build-asan -G Ninja \
      -DCMAKE_BUILD_TYPE=Debug \
      -DBUILD_TESTING=ON \
      -DCPPBOOSTNATIVE_ASAN=ON \
      -DCPPBOOSTNATIVE_UBSAN=ON \
      -DFETCHCONTENT_BASE_DIR=/var/cache/cmake-fetchcontent \
      -DFETCHCONTENT_UPDATES_DISCONNECTED=ON \
      ${grpc_source_arg} ${asio_grpc_source_arg} \
    && ./scripts/run_with_progress.sh "ASan/UBSan build" \
      cmake --build build-asan \
      --target inventoryservice orderservice inventoryservice_cq \
               native_common_test --parallel \
    && ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
       UBSAN_OPTIONS=halt_on_error=1 \
       ctest --test-dir build-asan --output-on-failure \
    && ./scripts/sanitizer_integration.sh build-asan asan

FROM build AS tsan-test
RUN --mount=type=cache,id=cppboostnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=cppboostnative-fetchcontent-${TARGETARCH},target=/var/cache/cmake-fetchcontent,sharing=locked \
    --mount=type=cache,id=servicegen-grpc-v1.71.0-asio-grpc-v3.5.0-sources-${TARGETARCH},target=/var/cache/servicegen-cpp-sources,sharing=locked \
    grpc_source_arg="" \
    && asio_grpc_source_arg="" \
    && if [ -f /var/cache/servicegen-cpp-sources/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/servicegen-cpp-sources/grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/grpc-src/include/grpc/grpc.h ]; then \
         grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_GRPC=/var/cache/cmake-fetchcontent/grpc-src"; \
       fi \
    && if [ -f /var/cache/servicegen-cpp-sources/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/servicegen-cpp-sources/asio-grpc-src"; \
       elif [ -f /var/cache/cmake-fetchcontent/asio-grpc-src/src/agrpc/asio_grpc.hpp ]; then \
         asio_grpc_source_arg="-DFETCHCONTENT_SOURCE_DIR_ASIO-GRPC=/var/cache/cmake-fetchcontent/asio-grpc-src"; \
       fi \
    && ./scripts/prepare_fetchcontent_cache.sh build-tsan \
    && ./scripts/run_with_progress.sh "TSan configure" \
      cmake -S . -B build-tsan -G Ninja \
      -DCMAKE_BUILD_TYPE=Debug \
      -DBUILD_TESTING=ON \
      -DCPPBOOSTNATIVE_TSAN=ON \
      -DFETCHCONTENT_BASE_DIR=/var/cache/cmake-fetchcontent \
      -DFETCHCONTENT_UPDATES_DISCONNECTED=ON \
      ${grpc_source_arg} ${asio_grpc_source_arg} \
    && ./scripts/run_with_progress.sh "TSan build" \
      cmake --build build-tsan \
      --target inventoryservice orderservice inventoryservice_cq \
               native_common_test --parallel \
    && TSAN_OPTIONS=halt_on_error=1 \
       ctest --test-dir build-tsan --output-on-failure \
    && ./scripts/sanitizer_integration.sh build-tsan tsan

FROM ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=servicegen-apt-lists-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=servicegen-apt-cache-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    apt-get update \
    && apt-get install --yes --no-install-recommends \
      ca-certificates libboost-json1.83.0 libjemalloc2 libssl3t64 zlib1g
FROM runtime AS inventoryservice
COPY --from=build /workspace/build/inventoryservice /usr/local/bin/inventoryservice
ENTRYPOINT ["/usr/local/bin/inventoryservice"]

FROM runtime AS orderservice
COPY --from=build /workspace/build/orderservice /usr/local/bin/orderservice
ENTRYPOINT ["/usr/local/bin/orderservice"]

FROM runtime AS inventoryservice-cq
COPY --from=build /workspace/build/inventoryservice_cq /usr/local/bin/inventoryservice_cq
ENTRYPOINT ["/usr/local/bin/inventoryservice_cq"]
