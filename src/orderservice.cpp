#include "common.hpp"

#include <agrpc/client_rpc.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/json.hpp>
#include <grpcpp/create_channel.h>

#include <array>
#include <chrono>
#include <cmath>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <vector>

#include <proto/inventoryserviceapi.grpc.pb.h>

namespace native_example {

struct RequestItem final {
  std::string item_id;
  std::string sku;
  int quantity{};
  double unit_price{};
};

struct ItemResult final {
  RequestItem item;
  int available_qty{};
  bool reserved{};
  std::string status;
  std::string error;
};

inline std::string RequestId() {
  thread_local std::mt19937_64 generator{std::random_device{}()};
  std::array<std::uint64_t, 2> values{generator(), generator()};
  std::ostringstream output;
  output << std::hex << std::setfill('0') << std::setw(16) << values[0]
         << std::setw(16) << values[1];
  return output.str();
}

inline std::string Timestamp() {
  const auto now = std::chrono::system_clock::now();
  const auto seconds = std::chrono::system_clock::to_time_t(now);
  std::tm utc{};
  gmtime_r(&seconds, &utc);
  std::ostringstream output;
  output << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
  return output.str();
}

inline boost::json::value MakeResponse(
    std::string_view order_id, std::string_view status, double total,
    const std::vector<ItemResult>& results) {
  boost::json::object response{
      {"order_id", order_id},
      {"status", status},
      {"total_amount", total},
      {"processed_at", Timestamp()},
  };
  boost::json::array confirmed;
  confirmed.reserve(results.size());
  for (const auto& result : results) {
    boost::json::object item{
        {"item_id", result.item.item_id},
        {"sku", result.item.sku},
        {"available_qty", result.available_qty},
        {"reserved", result.reserved},
        {"status", result.status},
    };
    if (!result.error.empty()) item["error"] = result.error;
    confirmed.push_back(std::move(item));
  }
  if (!confirmed.empty()) {
    response["confirmed_items"] = std::move(confirmed);
  }
  return response;
}

class OrderHandler final {
 public:
  using Service = inventoryserviceapi::InventoryServiceApi;
  using RPC = agrpc::ClientRPC<&Service::Stub::PrepareAsyncProcessOrderItem>;

  OrderHandler(agrpc::GrpcContext& grpc_context,
               std::vector<std::unique_ptr<Service::Stub>> clients,
               std::chrono::milliseconds timeout,
               std::chrono::milliseconds soft_margin,
               bool diagnostic_bypass_grpc = false)
      : grpc_context_(grpc_context),
        clients_(std::move(clients)),
        timeout_(timeout),
        soft_margin_(soft_margin),
        diagnostic_bypass_grpc_(diagnostic_bypass_grpc) {
    if (soft_margin_ > timeout_)
      throw std::runtime_error("soft deadline margin exceeds timeout");
  }

  boost::asio::awaitable<HttpReply> operator()(HttpRequest request) {
    const auto target = std::string_view{request.target().data(), request.target().size()};
    if (target != "/v1/processorder")
      co_return co_await OperationalReply(std::move(request));
    if (request.method() != boost::beast::http::verb::post)
      co_return HttpReply{405, "method not allowed\n", "text/plain; charset=utf-8"};

    try {
      const auto document = boost::json::parse(request.body());
      const auto& root = document.as_object();
      const auto& raw_items = root.at("items").as_array();
      if (raw_items.empty())
        co_return Error(400, "items must not be empty");

      std::vector<RequestItem> items;
      items.reserve(raw_items.size());
      double original_total{};
      for (const auto& raw_value : raw_items) {
        const auto& raw = raw_value.as_object();
        RequestItem item;
        if (const auto* value = raw.if_contains("item_id"))
          item.item_id = value->as_string();
        else
          item.item_id = raw.at("itemId").as_string();
        item.sku = raw.at("sku").as_string();
        item.quantity = static_cast<int>(raw.at("quantity").as_int64());
        if (item.quantity <= 0)
          co_return Error(400, "all quantities must be positive");
        if (const auto* value = raw.if_contains("unit_price"))
          item.unit_price = value->is_double() ? value->as_double()
                                               : value->as_int64();
        if (const auto* value = raw.if_contains("unitPrice"))
          item.unit_price = value->is_double() ? value->as_double()
                                               : value->as_int64();
        original_total += item.unit_price * item.quantity;
        items.push_back(std::move(item));
      }

      std::string order_id;
      if (const auto value = request.find("X-Request-ID"); value != request.end())
        order_id = value->value();
      if (order_id.empty()) order_id = RequestId();

      const auto soft_deadline =
          std::chrono::system_clock::now() + timeout_ - soft_margin_;
      std::vector<ItemResult> results;
      results.reserve(items.size());
      for (auto& item : items) {
        if (std::chrono::system_clock::now() >= soft_deadline)
          co_return Json(MakeResponse(order_id, "TIMED_OUT", original_total, {}));

        // An explicit benchmark-only control path. The normal example always
        // executes the gRPC call; this branch preserves request parsing,
        // business response construction and JSON serialization so profiling
        // can measure exactly the incremental unary-gRPC cost.
        if (diagnostic_bypass_grpc_) {
          results.push_back(ItemResult{std::move(item), 0, false,
                                       "OUT_OF_STOCK", {}});
          continue;
        }

        processorderitem::ProcessOrderItemRequest grpc_request;
        grpc_request.set_order_id(order_id);
        grpc_request.set_item_id(item.item_id);
        grpc_request.set_sku(item.sku);
        grpc_request.set_quantity(item.quantity);
        processorderitem::ProcessOrderItemResponse grpc_response;
        grpc::ClientContext context;
        context.set_deadline(soft_deadline);
        const auto index = next_client_.fetch_add(1, std::memory_order_relaxed) %
                           clients_.size();
        auto status = co_await RPC::request(
            grpc_context_, *clients_[index], context, grpc_request,
            grpc_response, boost::asio::use_awaitable);
        if (!status.ok()) {
          if (status.error_code() == grpc::StatusCode::DEADLINE_EXCEEDED ||
              std::chrono::system_clock::now() >= soft_deadline)
            co_return Json(MakeResponse(order_id, "TIMED_OUT", original_total, {}));
          results.push_back(ItemResult{std::move(item), 0, false,
                                       "PROCESSING_ERROR", status.error_message()});
        } else {
          results.push_back(ItemResult{std::move(item), grpc_response.available_qty(),
                                       grpc_response.reserved(),
                                       grpc_response.status(), {}});
        }
      }

      bool all_reserved = true;
      double total{};
      for (const auto& result : results) {
        all_reserved = all_reserved && result.reserved;
        total += result.item.unit_price * result.item.quantity;
      }
      co_return Json(MakeResponse(order_id,
                                  all_reserved ? "CONFIRMED"
                                               : "PARTIALLY_CONFIRMED",
                                  total, results));
    } catch (const boost::json::system_error& error) {
      co_return Error(400, error.what());
    } catch (const std::out_of_range& error) {
      co_return Error(400, error.what());
    } catch (const std::invalid_argument& error) {
      co_return Error(400, error.what());
    } catch (const std::exception& error) {
      co_return Error(500, error.what());
    }
  }

 private:
  static HttpReply Json(boost::json::value value) {
    return HttpReply{200, boost::json::serialize(value)};
  }

  static HttpReply Error(unsigned status, std::string_view message) {
    return HttpReply{status, std::string{message} + "\n",
                     "text/plain; charset=utf-8"};
  }

  agrpc::GrpcContext& grpc_context_;
  std::vector<std::unique_ptr<Service::Stub>> clients_;
  std::chrono::milliseconds timeout_;
  std::chrono::milliseconds soft_margin_;
  bool diagnostic_bypass_grpc_{};
  std::atomic<std::size_t> next_client_{};
};

}  // namespace native_example

int main() {
  try {
    native_example::ConfigureGrpcRuntimeDefaults();
    const auto workers =
        native_example::PositiveSize("NATIVE_WORKER_THREADS", 2);
    const auto connection_count = native_example::PositiveSize(
        "INVENTORY_SERVICE_API_CONNECTIONS_COUNT", 1);
    const auto address = native_example::Env(
        "INVENTORY_SERVICE_API_ADDRESS", "dns:///inventoryservice:9202");
    const auto timeout = native_example::ParseDuration(
        "ORDER_SERVICE_REQUEST_TIMEOUT", std::chrono::seconds{5});
    const auto soft_margin = native_example::ParseDuration(
        "ORDER_SERVICE_SOFT_DEADLINE_MARGIN", std::chrono::seconds{1});
    const auto diagnostic_bypass_grpc =
        native_example::EnvFlag("NATIVE_DIAGNOSTIC_BYPASS_GRPC");

    native_example::Runtime runtime(workers);
    std::vector<std::unique_ptr<native_example::OrderHandler::Service::Stub>> clients;
    clients.reserve(connection_count);
    for (std::size_t index = 0; index < connection_count; ++index) {
      clients.push_back(native_example::OrderHandler::Service::NewStub(
          grpc::CreateChannel(address, grpc::InsecureChannelCredentials())));
    }
    auto handler = std::make_shared<native_example::OrderHandler>(
        runtime.grpc_context(), std::move(clients), timeout, soft_margin,
        diagnostic_bypass_grpc);
    native_example::HttpServer http(
        runtime.io_context(), 9091,
        [handler](native_example::HttpRequest request) {
          return (*handler)(std::move(request));
        });
    http.Start();
    runtime.StopOnSignals([&] { http.Stop(); });
    runtime.Start();
    std::cout << "orderservice workers=" << runtime.workers() << '\n';
    runtime.Join();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "orderservice: " << error.what() << '\n';
    return 1;
  }
}
