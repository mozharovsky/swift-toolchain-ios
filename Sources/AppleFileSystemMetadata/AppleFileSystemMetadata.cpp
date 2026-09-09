#include "AppleFileSystemMetadata.h"
#include <CoreFoundation/CoreFoundation.h>
#include <cerrno>
#include <climits>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>

int swift_toolchain_is_local_path(const char *path, bool *result) {
  if (path == nullptr || result == nullptr) {
    return EINVAL;
  }
  struct stat status;
  if (::stat(path, &status) != 0) {
    return errno;
  }
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      kCFAllocatorDefault, reinterpret_cast<const UInt8 *>(path), std::strlen(path),
      S_ISDIR(status.st_mode));
  if (url == nullptr) {
    return EINVAL;
  }
  CFTypeRef value = nullptr;
  const bool copied = CFURLCopyResourcePropertyForKey(url, kCFURLVolumeIsLocalKey, &value, nullptr);
  CFRelease(url);
  if (!copied || value == nullptr) {
    if (value != nullptr) {
      CFRelease(value);
    }
    return EIO;
  }
  if (CFGetTypeID(value) != CFBooleanGetTypeID()) {
    CFRelease(value);
    return EIO;
  }
  *result = CFBooleanGetValue(static_cast<CFBooleanRef>(value));
  CFRelease(value);
  return 0;
}

int swift_toolchain_is_local_fd(int descriptor, bool *result) {
  if (result == nullptr) {
    return EINVAL;
  }
  char path[PATH_MAX];
  if (fcntl(descriptor, F_GETPATH, path) != 0) {
    return errno;
  }
  return swift_toolchain_is_local_path(path, result);
}
