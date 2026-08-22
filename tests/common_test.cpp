#include "common.hpp"

#include <cassert>
#include <chrono>
#include <cstdlib>

int main() {
  using namespace std::chrono_literals;
  setenv("NATIVE_TEST_DURATION", "1.5s", 1);
  setenv("NATIVE_TEST_SIZE", "7", 1);
  assert(native_example::ParseDuration("NATIVE_TEST_DURATION", 0ms) == 1500ms);
  assert(native_example::PositiveSize("NATIVE_TEST_SIZE", 1) == 7);
  setenv("NATIVE_TEST_FLAG", "YeS", 1);
  assert(native_example::EnvFlag("NATIVE_TEST_FLAG"));
  setenv("NATIVE_TEST_FLAG", "off", 1);
  assert(!native_example::EnvFlag("NATIVE_TEST_FLAG", true));
  return 0;
}
