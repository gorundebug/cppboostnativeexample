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
    # Instrument project targets. Conan dependencies remain pinned, tested
    # RelWithDebInfo binaries; whole-tree ASan is not portable across Abseil.
    add_compile_options(
      $<$<COMPILE_LANGUAGE:C,CXX>:-fsanitize=address>
      $<$<COMPILE_LANGUAGE:C,CXX>:-fno-omit-frame-pointer>)
    add_link_options(-fsanitize=address)
  endif()
  if(CPPBOOSTNATIVE_TSAN)
    # The Docker TSan profile also instruments the Conan graph so TSan sees
    # synchronization inside gRPC EventEngine instead of reporting false races.
    add_compile_options(
      $<$<COMPILE_LANGUAGE:C,CXX>:-fsanitize=thread>
      $<$<COMPILE_LANGUAGE:C,CXX>:-fno-omit-frame-pointer>)
    add_link_options(-fsanitize=thread)
  endif()
endif()

find_package(Boost CONFIG REQUIRED COMPONENTS json)
find_package(Protobuf CONFIG REQUIRED)
find_package(gRPC CONFIG REQUIRED)
find_package(asio-grpc CONFIG REQUIRED)
find_package(jemalloc CONFIG REQUIRED)
find_package(Threads REQUIRED)

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
  protobuf::libprotobuf gRPC::grpc++)

add_library(native_common INTERFACE)
target_include_directories(native_common INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(native_common INTERFACE
  asio-grpc::asio-grpc Boost::json Threads::Threads native_inventory_api)
if(CPPBOOSTNATIVE_UBSAN AND
   CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  # UBSan is applied to every project consumer through native_common.
  target_compile_options(native_common INTERFACE
    -fsanitize=undefined -fno-omit-frame-pointer)
  target_link_options(native_common INTERFACE -fsanitize=undefined)
endif()

foreach(service inventoryservice orderservice)
  add_executable(${service} "src/${service}.cpp")
  target_link_libraries(${service} PRIVATE jemalloc::jemalloc native_common)
  target_compile_options(${service} PRIVATE
    -Wall -Wextra -Wpedantic -g -fno-omit-frame-pointer)
  target_link_options(${service} PRIVATE -fno-omit-frame-pointer)
endforeach()

add_executable(inventoryservice_cq src/inventoryservice_cq.cpp)
target_link_libraries(inventoryservice_cq PRIVATE jemalloc::jemalloc native_common)
target_compile_options(inventoryservice_cq PRIVATE
  -Wall -Wextra -Wpedantic -g -fno-omit-frame-pointer)
target_link_options(inventoryservice_cq PRIVATE -fno-omit-frame-pointer)

include(CTest)
if(BUILD_TESTING)
  add_executable(native_common_test tests/common_test.cpp)
  target_link_libraries(native_common_test PRIVATE native_common)
  add_test(NAME native_common_test COMMAND native_common_test)
endif()
