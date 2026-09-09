#include <cstdio>
#include <cstdlib>
#include <dlfcn.h>

/// Loads the library named by TOOLCHAIN_TEST_LIBRARY and checks its exported entry point.
int main() {
  const char *fixturePath = std::getenv("TOOLCHAIN_TEST_LIBRARY");
  if (fixturePath == nullptr || fixturePath[0] == '\0') {
    std::fprintf(stderr, "Set TOOLCHAIN_TEST_LIBRARY to the fixture library path.\n");
    return 1;
  }
  void *library = dlopen(fixturePath, RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) {
    std::fprintf(stderr, "The fixture library could not be loaded. %s\n", fixturePath);
    return 1;
  }
  const auto symbol = dlsym(library, "toolchain_symbol_fixture");
  int failures = 0;
  if (symbol == nullptr) {
    std::fprintf(stderr, "The fixture's exported entry point is missing. %s\n", fixturePath);
    failures += 1;
  } else {
    using FixtureFunction = unsigned (*)(unsigned);
    const auto fixture = reinterpret_cast<FixtureFunction>(symbol);
    if (fixture(3) != 6 || fixture(4) != 14) {
      std::fprintf(stderr, "The fixture's local code and data must remain usable.\n");
      failures += 1;
    }
  }
  if (dlclose(library) != 0) {
    std::fprintf(stderr, "The fixture library could not be closed. %s\n", fixturePath);
    failures += 1;
  }
  return failures == 0 ? 0 : 1;
}
