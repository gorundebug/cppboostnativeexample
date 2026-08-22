#include "common.hpp"

#include <agrpc/register_awaitable_rpc_handler.hpp>
#include <agrpc/server_rpc.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/this_coro.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <grpcpp/server.h>

#include <chrono>
#include <atomic>
#include <iostream>
#include <memory>
#include <unordered_map>

#include <proto/inventoryserviceapi.grpc.pb.h>

namespace native_example {

class Inventory final {
 public:
  explicit Inventory(std::chrono::milliseconds delay) : delay_(delay) {}

  boost::asio::awaitable<processorderitem::ProcessOrderItemResponse> Process(
      const processorderitem::ProcessOrderItemRequest& request) {
    if (delay_ > std::chrono::milliseconds::zero()) {
      boost::asio::steady_timer timer(co_await boost::asio::this_coro::executor,
                                      delay_);
      co_await timer.async_wait(boost::asio::use_awaitable);
    }

    auto iterator = stock_.find(request.sku());
    auto available = iterator == stock_.end()
                         ? 0
                         : iterator->second->load(std::memory_order_relaxed);
    bool reserved = false;
    while (iterator != stock_.end() && request.quantity() > 0 &&
           available >= request.quantity()) {
      if (iterator->second->compare_exchange_weak(
              available, available - request.quantity(),
              std::memory_order_relaxed, std::memory_order_relaxed)) {
        reserved = true;
        break;
      }
    }

    processorderitem::ProcessOrderItemResponse response;
    response.set_available_qty(reserved ? request.quantity() : available);
    response.set_reserved(reserved);
    response.set_status(reserved ? "CONFIRMED" : "OUT_OF_STOCK");
    co_return response;
  }

 private:
  std::chrono::milliseconds delay_;
  std::unordered_map<std::string, std::shared_ptr<std::atomic<int>>> stock_{
      {"SKU-001", std::make_shared<std::atomic<int>>(100)},
      {"SKU-002", std::make_shared<std::atomic<int>>(50)},
      {"SKU-003", std::make_shared<std::atomic<int>>(25)}};
};

}  // namespace native_example

int main() {
  try {
    native_example::ConfigureGrpcRuntimeDefaults();
    using Service = inventoryserviceapi::InventoryServiceApi;
    using RPC = agrpc::ServerRPC<&Service::AsyncService::RequestProcessOrderItem>;

    const auto workers =
        native_example::PositiveSize("NATIVE_WORKER_THREADS", 2);
    native_example::Inventory inventory(native_example::ParseDuration(
        "INVENTORY_SERVICE_RESPONSE_DELAY", std::chrono::milliseconds{0}));

    Service::AsyncService async_service;
    grpc::ServerBuilder builder;
    builder.AddListeningPort("0.0.0.0:9202", grpc::InsecureServerCredentials());
    builder.RegisterService(&async_service);
    auto completion_queue = builder.AddCompletionQueue();
    auto server = builder.BuildAndStart();
    if (!server) throw std::runtime_error("failed to start inventory gRPC server");

    native_example::Runtime runtime(workers, std::move(completion_queue));
    agrpc::register_awaitable_rpc_handler<RPC>(
        runtime.grpc_context(), async_service,
        [&inventory](RPC& rpc, RPC::Request& request)
            -> boost::asio::awaitable<void> {
          auto response = co_await inventory.Process(request);
          (void)co_await rpc.finish(response, grpc::Status::OK,
                                    boost::asio::use_awaitable);
        },
        boost::asio::bind_executor(runtime.io_context().get_executor(),
                                   boost::asio::detached));

    native_example::HttpServer http(
        runtime.io_context(), 9092, native_example::OperationalReply);
    http.Start();
    runtime.StopOnSignals([&] {
      http.Stop();
      server->Shutdown();
    });
    runtime.Start();
    std::cout << "inventoryservice workers=" << runtime.workers() << '\n';
    runtime.Join();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "inventoryservice: " << error.what() << '\n';
    return 1;
  }
}
