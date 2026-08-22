#include "common.hpp"

#include <grpcpp/server.h>

#include <atomic>
#include <csignal>
#include <iostream>
#include <memory>
#include <pthread.h>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#include <vector>

#include <proto/inventoryserviceapi.grpc.pb.h>

namespace native_example::cq_diagnostic {

using Service = inventoryserviceapi::InventoryServiceApi;

class Inventory final {
 public:
  void Process(const processorderitem::ProcessOrderItemRequest& request,
               processorderitem::ProcessOrderItemResponse& response) {
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
    response.set_available_qty(reserved ? request.quantity() : available);
    response.set_reserved(reserved);
    response.set_status(reserved ? "CONFIRMED" : "OUT_OF_STOCK");
  }

 private:
  std::unordered_map<std::string, std::shared_ptr<std::atomic<int>>> stock_{
      {"SKU-001", std::make_shared<std::atomic<int>>(100)},
      {"SKU-002", std::make_shared<std::atomic<int>>(50)},
      {"SKU-003", std::make_shared<std::atomic<int>>(25)}};
};

class Call final {
 public:
  Call(Service::AsyncService& service, grpc::ServerCompletionQueue& queue,
       Inventory& inventory)
      : service_(service), queue_(queue), inventory_(inventory), responder_(&context_) {
    RequestNext();
  }

  void Proceed(bool ok) {
    if (state_ == State::kRequested) {
      if (!ok) {
        delete this;
        return;
      }
      new Call(service_, queue_, inventory_);
      inventory_.Process(request_, response_);
      state_ = State::kFinishing;
      responder_.Finish(response_, grpc::Status::OK, this);
      return;
    }
    delete this;
  }

 private:
  enum class State { kRequested, kFinishing };

  void RequestNext() {
    service_.RequestProcessOrderItem(&context_, &request_, &responder_, &queue_,
                                     &queue_, this);
  }

  Service::AsyncService& service_;
  grpc::ServerCompletionQueue& queue_;
  Inventory& inventory_;
  grpc::ServerContext context_;
  processorderitem::ProcessOrderItemRequest request_;
  processorderitem::ProcessOrderItemResponse response_;
  grpc::ServerAsyncResponseWriter<processorderitem::ProcessOrderItemResponse>
      responder_;
  State state_{State::kRequested};
};

}  // namespace native_example::cq_diagnostic

int main() {
  try {
    native_example::ConfigureGrpcRuntimeDefaults();
    const auto workers =
        native_example::PositiveSize("NATIVE_WORKER_THREADS", 2);

    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGINT);
    sigaddset(&signals, SIGTERM);
    if (pthread_sigmask(SIG_BLOCK, &signals, nullptr) != 0)
      throw std::runtime_error("failed to block shutdown signals");

    native_example::cq_diagnostic::Service::AsyncService service;
    grpc::ServerBuilder builder;
    builder.AddListeningPort("0.0.0.0:9202", grpc::InsecureServerCredentials());
    builder.RegisterService(&service);
    auto queue = builder.AddCompletionQueue();
    auto server = builder.BuildAndStart();
    if (!server) throw std::runtime_error("failed to start raw-CQ gRPC server");

    native_example::cq_diagnostic::Inventory inventory;
    new native_example::cq_diagnostic::Call(service, *queue, inventory);

    std::vector<std::thread> threads;
    threads.reserve(workers);
    for (std::size_t index = 0; index < workers; ++index) {
      threads.emplace_back([&queue] {
        void* tag{};
        bool ok{};
        while (queue->Next(&tag, &ok)) {
          static_cast<native_example::cq_diagnostic::Call*>(tag)->Proceed(ok);
        }
      });
    }

    std::cout << "inventoryservice-cq workers=" << workers << '\n';
    int signal{};
    static_cast<void>(sigwait(&signals, &signal));
    server->Shutdown();
    queue->Shutdown();
    for (auto& thread : threads) thread.join();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "inventoryservice-cq: " << error.what() << '\n';
    return 1;
  }
}
