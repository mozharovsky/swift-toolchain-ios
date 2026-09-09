#include "AppleFileSystemMetadata.h"
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <sys/mount.h>
#include <unistd.h>

namespace {

/// The test process aggregates contract failures so its temporary file is always removed.
int check(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    return 1;
  }
  return 0;
}

} // namespace

int main() {
  char path[] = "/tmp/swift-toolchain-metadata.XXXXXX";
  const int descriptor = mkstemp(path);
  if (descriptor < 0) {
    return check(false, "Create the temporary metadata fixture.");
  }
  int failures = 0;
  struct statfs status;
  const bool described = statfs(path, &status) == 0;
  failures += check(described, "Read the reference volume locality.");
  const bool expected = described && (status.f_flags & MNT_LOCAL) != 0;
  bool result = false;
  failures += check(swift_toolchain_is_local_path(path, &result) == 0 && result == expected,
                    "Path locality must match the reference volume.");
  result = false;
  failures += check(swift_toolchain_is_local_fd(descriptor, &result) == 0 && result == expected,
                    "Descriptor locality must match the reference volume.");
  failures += check(swift_toolchain_is_local_path(nullptr, &result) == EINVAL,
                    "A missing path must report EINVAL.");
  failures += check(swift_toolchain_is_local_path(path, nullptr) == EINVAL,
                    "A missing output must report EINVAL.");
  failures += check(swift_toolchain_is_local_fd(descriptor, nullptr) == EINVAL,
                    "A descriptor needs valid output storage.");
  close(descriptor);
  result = true;
  failures += check(swift_toolchain_is_local_fd(descriptor, &result) == EBADF && result,
                    "A closed descriptor must leave the output unchanged.");
  unlink(path);
  result = true;
  failures += check(swift_toolchain_is_local_path(path, &result) == ENOENT && result,
                    "A removed file must leave the output unchanged.");
  return failures == 0 ? 0 : 1;
}
