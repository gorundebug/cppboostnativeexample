# Native C++ Boost example

Hand-written baseline for the order-processing benchmark using Boost.Beast and
asio-grpc directly. It does not include or link `cppboostservicelib`.

The HTTP payloads, protobuf contracts, inventory state, sequential item
processing, request timeout and soft-deadline rules match `cppnativeexample`.

Explicit dependency versions come from ServiceGen's canonical
`dependencies.yaml`; Conan 2 resolves them through checked-in platform
lockfiles.

```sh
make docker-build
make docker-up
make docker-down
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

The sanitizer gates give every host dependency a distinct Conan package ID and
instrument gRPC/Abseil and asio-grpc together with the real Order and Inventory
services. They run the native unit test and then a live HTTP-to-gRPC scenario.
Builds deliberately use unrestricted `--parallel` scheduling.

```sh
make docker-test
make docker-asan
make docker-tsan
```

The ASan target uses `RelWithDebInfo`, also enables UBSan and leak detection,
and is verification-only rather than a production image. TSan is a separate,
mutually exclusive build. Regenerate lockfiles only after an intentional
dependency update with `make conan-lock`.
