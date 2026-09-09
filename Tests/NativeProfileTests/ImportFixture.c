#include <stdio.h>
#include <stdlib.h>

/// Retains an import in a library that verification inspects without executing.
int toolchain_native_import_fixture(const char *value) {
#if defined(TOOLCHAIN_TEST_FORBIDDEN_IMPORT)
  return system(value);
#else
  return puts(value);
#endif
}
