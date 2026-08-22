#pragma once

#include <utility>

#include <agrpc/grpc_context.hpp>
#include <agrpc/grpc_executor.hpp>
#include <agrpc/run.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/bind_executor.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/executor_work_guard.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/asio/ip/address.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/redirect_error.hpp>
#include <boost/asio/signal_set.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/http.hpp>
#include <grpcpp/server_builder.h>

#include <atomic>
#include <charconv>
#include <chrono>
#include <cctype>
#include <csignal>
#include <cstdlib>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace native_example {

inline void ConfigureGrpcRuntimeDefaults() noexcept {
#if defined(__unix__) || defined(__APPLE__)
  if (std::getenv("GRPC_EXPERIMENTS") == nullptr) {
    static_cast<void>(::setenv(
        "GRPC_EXPERIMENTS",
        "-event_engine_client,-event_engine_listener", 0));
  }
#endif
}

struct CooperativeRunTraits final {
  static constexpr std::chrono::microseconds MAX_LATENCY{50};

  static bool poll(boost::asio::io_context& context) {
    constexpr std::size_t kBatchSize = 8;
    std::size_t processed{};
    while (processed < kBatchSize && context.poll_one() != 0) ++processed;
    return processed != 0;
  }

  template <typename Rep, typename Period>
  static bool run_for(boost::asio::io_context& context,
                      std::chrono::duration<Rep, Period> duration) {
    return context.run_one_for(duration) != 0;
  }

  static bool is_stopped(boost::asio::io_context& context) {
    return context.stopped();
  }
};

inline std::string Env(std::string_view name, std::string fallback) {
  const auto key = std::string{name};
  const char* value = std::getenv(key.c_str());
  return value && *value ? std::string{value} : std::move(fallback);
}

inline bool EnvFlag(std::string_view name, bool fallback = false) {
  auto value = Env(name, fallback ? "true" : "false");
  for (auto& character : value) {
    character = static_cast<char>(
        std::tolower(static_cast<unsigned char>(character)));
  }
  if (value == "1" || value == "true" || value == "yes" || value == "on")
    return true;
  if (value == "0" || value == "false" || value == "no" || value == "off")
    return false;
  throw std::runtime_error(std::string{name} + " must be a boolean");
}

inline std::size_t PositiveSize(std::string_view name, std::size_t fallback) {
  const auto raw = Env(name, std::to_string(fallback));
  std::size_t value{};
  const auto [end, error] =
      std::from_chars(raw.data(), raw.data() + raw.size(), value);
  if (error != std::errc{} || end != raw.data() + raw.size() || value == 0)
    throw std::runtime_error(std::string{name} + " must be a positive integer");
  return value;
}

inline std::chrono::milliseconds ParseDuration(
    std::string_view name, std::chrono::milliseconds fallback) {
  const auto fallback_value = std::to_string(fallback.count()) + "ms";
  auto value = Env(name, fallback_value);
  double multiplier = 1000.0;
  if (value.ends_with("ms")) {
    multiplier = 1.0;
    value.resize(value.size() - 2);
  } else if (value.ends_with('s')) {
    value.pop_back();
  } else if (value.ends_with('m')) {
    multiplier = 60000.0;
    value.pop_back();
  }
  std::size_t consumed{};
  const auto amount = std::stod(value, &consumed);
  if (consumed != value.size() || amount < 0)
    throw std::runtime_error(std::string{name} + " must be a non-negative duration");
  return std::chrono::milliseconds{static_cast<std::int64_t>(amount * multiplier)};
}

class Runtime final {
 public:
  Runtime(std::size_t workers,
          std::unique_ptr<grpc::ServerCompletionQueue> server_queue = {})
      : workers_count_(workers),
        io_context_(static_cast<int>(workers)),
        grpc_context_(server_queue
                          ? std::make_unique<agrpc::GrpcContext>(
                                std::move(server_queue), workers)
                          : std::make_unique<agrpc::GrpcContext>(workers)),
        io_work_(boost::asio::make_work_guard(io_context_)),
        grpc_work_(boost::asio::make_work_guard(*grpc_context_)) {
    if (workers == 0) throw std::invalid_argument("workers must be positive");
  }

  Runtime(const Runtime&) = delete;
  Runtime& operator=(const Runtime&) = delete;
  ~Runtime() { Stop(); Join(); }

  void Start() {
    bool expected{};
    if (!running_.compare_exchange_strong(expected, true))
      throw std::logic_error("runtime already started");
    threads_.reserve(workers_count_);
    for (std::size_t index = 0; index < workers_count_; ++index) {
      threads_.emplace_back([this] {
        agrpc::run_completion_queue<CooperativeRunTraits>(
            *grpc_context_, io_context_,
            [this] { return stopping_.load(std::memory_order_acquire); });
      });
    }
  }

  void Stop() noexcept {
    if (stopping_.exchange(true, std::memory_order_acq_rel)) return;
    io_work_.reset();
    grpc_work_.reset();
    grpc_context_->stop();
    io_context_.stop();
  }

  void Join() noexcept {
    for (auto& thread : threads_)
      if (thread.joinable()) thread.join();
    threads_.clear();
  }

  template <typename Callback>
  void StopOnSignals(Callback callback) {
    signals_ = std::make_unique<boost::asio::signal_set>(io_context_, SIGINT, SIGTERM);
    signals_->async_wait(
        [this, callback = std::move(callback)](
            const boost::system::error_code& error, int) mutable {
          if (error) return;
          callback();
          Stop();
        });
  }

  boost::asio::io_context& io_context() noexcept { return io_context_; }
  agrpc::GrpcContext& grpc_context() noexcept { return *grpc_context_; }
  std::size_t workers() const noexcept { return workers_count_; }

 private:
  std::size_t workers_count_;
  boost::asio::io_context io_context_;
  std::unique_ptr<agrpc::GrpcContext> grpc_context_;
  boost::asio::executor_work_guard<boost::asio::io_context::executor_type> io_work_;
  boost::asio::executor_work_guard<agrpc::GrpcContext::executor_type> grpc_work_;
  std::atomic<bool> running_{};
  std::atomic<bool> stopping_{};
  std::unique_ptr<boost::asio::signal_set> signals_;
  std::vector<std::thread> threads_;
};

struct HttpReply final {
  unsigned status{200};
  std::string body;
  std::string content_type{"application/json"};
};

using HttpRequest = boost::beast::http::request<boost::beast::http::string_body>;
using HttpHandler =
    std::function<boost::asio::awaitable<HttpReply>(HttpRequest)>;

class HttpServer final {
 public:
  HttpServer(boost::asio::io_context& context, std::uint16_t port,
             HttpHandler handler)
      : acceptor_(context), handler_(std::move(handler)) {
    const boost::asio::ip::tcp::endpoint endpoint{
        boost::asio::ip::make_address("0.0.0.0"), port};
    acceptor_.open(endpoint.protocol());
    acceptor_.set_option(boost::asio::socket_base::reuse_address(true));
    acceptor_.bind(endpoint);
    acceptor_.listen(boost::asio::socket_base::max_listen_connections);
  }

  void Start() {
    boost::asio::co_spawn(acceptor_.get_executor(), AcceptLoop(),
                          boost::asio::detached);
  }

  void Stop() noexcept {
    boost::system::error_code ignored;
    acceptor_.cancel(ignored);
    acceptor_.close(ignored);
  }

 private:
  class Session final : public std::enable_shared_from_this<Session> {
   public:
    Session(boost::asio::ip::tcp::socket socket, HttpHandler handler)
        : stream_(std::move(socket)), handler_(std::move(handler)) {}

    void Start() {
      boost::asio::co_spawn(
          stream_.get_executor(), Run(),
          [self = shared_from_this()](std::exception_ptr) {});
    }

   private:
    boost::asio::awaitable<void> Run() {
      boost::beast::flat_buffer buffer;
      for (;;) {
        stream_.expires_after(std::chrono::seconds{30});
        HttpRequest request;
        boost::system::error_code error;
        co_await boost::beast::http::async_read(
            stream_, buffer, request,
            boost::asio::redirect_error(boost::asio::use_awaitable, error));
        if (error) break;

        const auto version = request.version();
        const auto keep_alive = request.keep_alive();
        auto reply = co_await handler_(std::move(request));
        boost::beast::http::response<boost::beast::http::string_body> response{
            static_cast<boost::beast::http::status>(reply.status), version};
        response.set(boost::beast::http::field::server, "cppboostnativeexample");
        response.set(boost::beast::http::field::content_type, reply.content_type);
        response.keep_alive(keep_alive);
        response.body() = std::move(reply.body);
        response.prepare_payload();
        co_await boost::beast::http::async_write(
            stream_, response,
            boost::asio::redirect_error(boost::asio::use_awaitable, error));
        if (error || !keep_alive) break;
      }
      boost::system::error_code ignored;
      stream_.socket().shutdown(boost::asio::ip::tcp::socket::shutdown_send,
                                ignored);
    }

    boost::beast::tcp_stream stream_;
    HttpHandler handler_;
  };

  boost::asio::awaitable<void> AcceptLoop() {
    for (;;) {
      boost::system::error_code error;
      boost::asio::ip::tcp::socket socket(acceptor_.get_executor());
      co_await acceptor_.async_accept(
          socket,
          boost::asio::redirect_error(boost::asio::use_awaitable, error));
      if (error == boost::asio::error::operation_aborted || !acceptor_.is_open())
        break;
      if (error) continue;
      std::make_shared<Session>(std::move(socket), handler_)->Start();
    }
  }

  boost::asio::ip::tcp::acceptor acceptor_;
  HttpHandler handler_;
};

inline boost::asio::awaitable<HttpReply> OperationalReply(HttpRequest request) {
  const auto target = std::string_view{request.target().data(), request.target().size()};
  if (target == "/status" || target == "/status/data")
    co_return HttpReply{200, R"({"status":"ok"})"};
  if (target == "/metrics")
    co_return HttpReply{200, "# No ServiceLib runtime metrics in the native baseline.\n",
                        "text/plain; version=0.0.4; charset=utf-8"};
  co_return HttpReply{404, "not found\n", "text/plain; charset=utf-8"};
}

}  // namespace native_example
