#include "BundledPluginPolicy.h"
#include "SwiftToolchainPluginPolicy.h"
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <system_error>

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#endif

std::string swift_toolchain::bundledFrameworkExecutablePath(const char *frameworkDirectory,
                                                            const char *path) {
  if (frameworkDirectory == nullptr || path == nullptr || frameworkDirectory[0] == '\0' ||
      path[0] == '\0') {
    return {};
  }
  std::error_code error;
  const auto root = std::filesystem::canonical(frameworkDirectory, error);
  if (error) {
    return {};
  }
  const auto executable = std::filesystem::canonical(path, error);
  if (error || !std::filesystem::is_regular_file(executable, error) || error) {
    return {};
  }
  const auto framework = executable.parent_path();
  if (framework.parent_path() != root || framework.extension() != ".framework" ||
      framework.stem().empty() || executable.filename() != framework.stem()) {
    return {};
  }
  return executable.string();
}

char *swift_toolchain_copy_bundled_plugin_path(const char *path) {
#if defined(__APPLE__)
  const auto bundle = CFBundleGetMainBundle();
  if (bundle == nullptr) {
    return nullptr;
  }
  const auto url = CFBundleCopyPrivateFrameworksURL(bundle);
  if (url == nullptr) {
    return nullptr;
  }
  UInt8 directory[PATH_MAX];
  const bool represented =
      CFURLGetFileSystemRepresentation(url, true, directory, sizeof(directory));
  CFRelease(url);
  if (!represented) {
    return nullptr;
  }
  const auto executable = swift_toolchain::bundledFrameworkExecutablePath(
      reinterpret_cast<const char *>(directory), path);
  if (executable.empty()) {
    return nullptr;
  }
  auto *copy = static_cast<char *>(std::malloc(executable.size() + 1));
  if (copy != nullptr) {
    std::memcpy(copy, executable.c_str(), executable.size() + 1);
  }
  return copy;
#else
  (void)path;
  return nullptr;
#endif
}
