#include "AppleFileSystemMetadata.h"
#include <CoreFoundation/CoreFoundation.h>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <sys/attr.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

/// The descriptor query returns only the supported-attribute mask and volume mount flags.
struct VolumeMountFlags {
  /// The kernel reports the number of bytes written so truncated metadata can be rejected.
  std::uint32_t length;
  /// The returned mask distinguishes an unsupported flag query from a nonlocal volume.
  attribute_set_t returned;
  /// LLVM's mapping policy consumes MNT_LOCAL without requesting volume capacity.
  std::uint32_t flags;
};

} // namespace

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
  struct attrlist attributes = {};
  attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
  attributes.commonattr = ATTR_CMN_RETURNED_ATTRS;
  attributes.volattr = ATTR_VOL_INFO | ATTR_VOL_MOUNTFLAGS;
  VolumeMountFlags value = {};
  if (fgetattrlist(descriptor, &attributes, &value, sizeof(value), 0) != 0) {
    return errno;
  }
  if (value.length != sizeof(value) || (value.returned.volattr & ATTR_VOL_MOUNTFLAGS) == 0) {
    return EIO;
  }
  *result = (value.flags & MNT_LOCAL) != 0;
  return 0;
}
