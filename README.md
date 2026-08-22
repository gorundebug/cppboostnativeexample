# Native C++ Boost example

Hand-written baseline for the order-processing benchmark using Boost.Beast and
asio-grpc directly. It does not include or link `cppboostservicelib`.

The HTTP payloads, protobuf contracts, inventory state, sequential item
processing, request timeout and soft-deadline rules match `cppnativeexample`.

```sh
docker compose up --build
```

Runtime settings use the same environment contract as the other native
examples:

- `NATIVE_WORKER_THREADS` (default `2`)
- `INVENTORY_SERVICE_RESPONSE_DELAY` (default `0s`)
- `INVENTORY_SERVICE_API_CONNECTIONS_COUNT` (default `1`)
- `ORDER_SERVICE_REQUEST_TIMEOUT` (default `5s`)
- `ORDER_SERVICE_SOFT_DEADLINE_MARGIN` (default `1s`)

Both binaries are built with Release optimization, debug information and frame pointers
so `perf`, GDB and LLDB can resolve native coroutine stacks.

The sanitizer gates build the pinned gRPC/Abseil and asio-grpc sources together
with the real Order and Inventory services, run the native unit test, then run a
live HTTP-to-gRPC integration scenario.  Builds deliberately use unrestricted
`--parallel` scheduling.

```sh
docker build --target asan-test \
  -t cppboostnativeexample-asan-test:latest .
docker build --target tsan-test \
  -t cppboostnativeexample-tsan-test:latest .
```

The ASan target also enables consumer-side UBSan and leak detection.  Pinned
gRPC is fully ASan-instrumented; UBSan remains consumer-side because gRPC
1.71's vendored Abseil does not compile as a whole-tree GCC UBSan build.
