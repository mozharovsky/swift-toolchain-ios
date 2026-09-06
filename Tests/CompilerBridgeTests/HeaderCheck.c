#include "SwiftCompilerBridge.h"

_Static_assert(sizeof(((SwiftCompilerResult *)0)->exitCode) == 4, "Status must remain 32-bit.");
_Static_assert(sizeof(((SwiftCompilerResult *)0)->canRunAgain) == 4, "Reuse must remain 32-bit.");

/// The C++ test calls through a C translation unit to verify header and linkage compatibility.
uint32_t compiler_header_version(void) {
  return swift_compiler_abi_version();
}
