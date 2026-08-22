cmake_minimum_required(VERSION 3.24)
project(cppboostnativeexample LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(SERVICEGEN_USE_CCACHE "Use ccache when it is available" ON)
if(SERVICEGEN_USE_CCACHE AND NOT CMAKE_CXX_COMPILER_LAUNCHER)
  find_program(SERVICEGEN_CCACHE_PROGRAM ccache)
  if(SERVICEGEN_CCACHE_PROGRAM)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${SERVICEGEN_CCACHE_PROGRAM}")
    message(STATUS "C++ compiler cache: ${SERVICEGEN_CCACHE_PROGRAM}")
  endif()
endif()

option(CPPBOOSTNATIVE_ASAN "Enable AddressSanitizer" OFF)
option(CPPBOOSTNATIVE_UBSAN "Enable UndefinedBehaviorSanitizer" OFF)
option(CPPBOOSTNATIVE_TSAN "Enable ThreadSanitizer" OFF)
set(CPPBOOSTNATIVE_ASIO_RECYCLING_CACHE_SIZE "2" CACHE STRING
    "Per-thread Boost.Asio recycled operation blocks retained per allocator tag")
if(NOT CPPBOOSTNATIVE_ASIO_RECYCLING_CACHE_SIZE MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR
      "CPPBOOSTNATIVE_ASIO_RECYCLING_CACHE_SIZE must be a positive integer")
endif()
add_compile_definitions(
  BOOST_ASIO_RECYCLING_ALLOCATOR_CACHE_SIZE=${CPPBOOSTNATIVE_ASIO_RECYCLING_CACHE_SIZE})

set(_cppboostnative_exclusive_sanitizers 0)
foreach(_option CPPBOOSTNATIVE_ASAN CPPBOOSTNATIVE_TSAN)
  if(${_option})
    math(EXPR _cppboostnative_exclusive_sanitizers
         "${_cppboostnative_exclusive_sanitizers} + 1")
  endif()
endforeach()
if(_cppboostnative_exclusive_sanitizers GREATER 1)
  message(FATAL_ERROR "ASan and TSan cannot be enabled together")
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  if(CPPBOOSTNATIVE_ASAN)
    # Coroutine frames cross the gRPC/asio-grpc boundary, so ASan must see the
    # pinned transport dependencies as well as the native service sources.
    add_compile_options(
      $<$<COMPILE_LANGUAGE:C,CXX>:-fsanitize=address>
      $<$<COMPILE_LANGUAGE:C,CXX>:-fno-omit-frame-pointer>)
    add_link_options(-fsanitize=address)
  endif()
  if(CPPBOOSTNATIVE_TSAN)
    # Non-instrumented static gRPC/Abseil code hides EventEngine
    # synchronization from TSan and produces invalid publication reports.
    add_compile_options(
      $<$<COMPILE_LANGUAGE:C,CXX>:-fsanitize=thread>
      $<$<COMPILE_LANGUAGE:C,CXX>:-fno-omit-frame-pointer>)
    add_link_options(-fsanitize=thread)
  endif()
endif()

include(FetchContent)
set(FETCHCONTENT_QUIET OFF CACHE BOOL
    "Show dependency download/configuration progress" FORCE)
find_package(Boost 1.83 REQUIRED COMPONENTS json)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(JEMALLOC REQUIRED IMPORTED_TARGET jemalloc)

set(CPPBOOSTNATIVE_GRPC_VERSION "v1.71.0" CACHE STRING
    "Pinned gRPC version shared with cppboostservicelib")
set(CPPBOOSTNATIVE_ASIO_GRPC_VERSION "v3.5.0" CACHE STRING
    "Pinned asio-grpc version shared with cppboostservicelib")

set(gRPC_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(gRPC_BUILD_CODEGEN ON CACHE BOOL "" FORCE)
set(gRPC_INSTALL OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(protobuf_INSTALL OFF CACHE BOOL "" FORCE)
set(ABSL_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(CARES_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(CARES_INSTALL OFF CACHE BOOL "" FORCE)
set(RE2_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(gRPC_BUILD_GRPC_CSHARP_PLUGIN OFF CACHE BOOL "" FORCE)
set(gRPC_BUILD_GRPC_NODE_PLUGIN OFF CACHE BOOL "" FORCE)
set(gRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN OFF CACHE BOOL "" FORCE)
set(gRPC_BUILD_GRPC_PHP_PLUGIN OFF CACHE BOOL "" FORCE)
set(gRPC_BUILD_GRPC_PYTHON_PLUGIN OFF CACHE BOOL "" FORCE)
set(gRPC_BUILD_GRPC_RUBY_PLUGIN OFF CACHE BOOL "" FORCE)
set(gRPC_ABSL_PROVIDER module CACHE STRING "" FORCE)
set(gRPC_CARES_PROVIDER module CACHE STRING "" FORCE)
set(gRPC_PROTOBUF_PROVIDER module CACHE STRING "" FORCE)
set(gRPC_RE2_PROVIDER module CACHE STRING "" FORCE)
find_package(OpenSSL REQUIRED)
find_package(ZLIB REQUIRED)
set(gRPC_SSL_PROVIDER package CACHE STRING "" FORCE)
set(gRPC_ZLIB_PROVIDER package CACHE STRING "" FORCE)
FetchContent_Declare(grpc
  GIT_REPOSITORY https://github.com/grpc/grpc.git
  GIT_TAG "${CPPBOOSTNATIVE_GRPC_VERSION}"
  GIT_SHALLOW TRUE
  GIT_SUBMODULES
    third_party/abseil-cpp
    third_party/cares/cares
    third_party/protobuf
    third_party/re2
  GIT_SUBMODULES_RECURSE FALSE)

set(ASIO_GRPC_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ASIO_GRPC_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ASIO_GRPC_ENABLE_CMAKE_INSTALL_TEST OFF CACHE BOOL "" FORCE)
FetchContent_Declare(asio-grpc
  GIT_REPOSITORY https://github.com/Tradias/asio-grpc.git
  GIT_TAG "${CPPBOOSTNATIVE_ASIO_GRPC_VERSION}"
  GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(grpc asio-grpc)

if(TARGET grpc_cpp_plugin AND NOT TARGET gRPC::grpc_cpp_plugin)
  get_target_property(_cppboostnative_grpc_plugin_binary_dir grpc_cpp_plugin
                      BINARY_DIR)
  add_executable(gRPC::grpc_cpp_plugin IMPORTED GLOBAL)
  set_target_properties(gRPC::grpc_cpp_plugin PROPERTIES
    IMPORTED_LOCATION
      "${_cppboostnative_grpc_plugin_binary_dir}/grpc_cpp_plugin")
  add_dependencies(gRPC::grpc_cpp_plugin grpc_cpp_plugin)
  unset(_cppboostnative_grpc_plugin_binary_dir)
endif()
if(TARGET protoc AND NOT TARGET protobuf::protoc)
  add_executable(protobuf::protoc ALIAS protoc)
endif()

if(TARGET gRPC::grpc++)
  set(CPPBOOSTNATIVE_GRPCPP_TARGET gRPC::grpc++)
else()
  set(CPPBOOSTNATIVE_GRPCPP_TARGET grpc++)
endif()
if(TARGET protobuf::libprotobuf)
  set(CPPBOOSTNATIVE_PROTOBUF_TARGET protobuf::libprotobuf)
else()
  set(CPPBOOSTNATIVE_PROTOBUF_TARGET libprotobuf)
endif()

set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
asio_grpc_protobuf_generate(
  GENERATE_GRPC
  OUT_VAR NATIVE_PROTO_SOURCES
  OUT_DIR "${GENERATED_DIR}"
  IMPORT_DIRS "${CMAKE_CURRENT_SOURCE_DIR}"
  PROTOS
    "${CMAKE_CURRENT_SOURCE_DIR}/proto/inventoryserviceapi.proto"
    "${CMAKE_CURRENT_SOURCE_DIR}/proto/processorderitem.proto")
add_library(native_inventory_api STATIC ${NATIVE_PROTO_SOURCES})
target_include_directories(native_inventory_api PUBLIC "${GENERATED_DIR}")
target_link_libraries(native_inventory_api PUBLIC
  ${CPPBOOSTNATIVE_PROTOBUF_TARGET} ${CPPBOOSTNATIVE_GRPCPP_TARGET})

add_library(native_common INTERFACE)
target_include_directories(native_common INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(native_common INTERFACE
  asio-grpc::asio-grpc Boost::json Threads::Threads native_inventory_api)
if(CPPBOOSTNATIVE_UBSAN AND
   CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  # gRPC 1.71's vendored Abseil does not compile under whole-tree UBSan on
  # GCC. Instrument every native consumer while ASan covers coroutine frames
  # that cross the transport-library boundary.
  target_compile_options(native_common INTERFACE
    -fsanitize=undefined -fno-omit-frame-pointer)
  target_link_options(native_common INTERFACE -fsanitize=undefined)
endif()

foreach(service inventoryservice orderservice)
  add_executable(${service} "src/${service}.cpp")
  target_link_libraries(${service} PRIVATE PkgConfig::JEMALLOC native_common)
  target_compile_options(${service} PRIVATE
    -Wall -Wextra -Wpedantic -g -fno-omit-frame-pointer)
  target_link_options(${service} PRIVATE -fno-omit-frame-pointer)
endforeach()

add_executable(inventoryservice_cq src/inventoryservice_cq.cpp)
target_link_libraries(inventoryservice_cq PRIVATE PkgConfig::JEMALLOC native_common)
target_compile_options(inventoryservice_cq PRIVATE
  -Wall -Wextra -Wpedantic -g -fno-omit-frame-pointer)
target_link_options(inventoryservice_cq PRIVATE -fno-omit-frame-pointer)

include(CTest)
if(BUILD_TESTING)
  add_executable(native_common_test tests/common_test.cpp)
  target_link_libraries(native_common_test PRIVATE native_common)
  add_test(NAME native_common_test COMMAND native_common_test)
endif()
