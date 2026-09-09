#ifndef SWIFT_TOOLCHAIN_BUNDLED_PLUGIN_POLICY_H
#define SWIFT_TOOLCHAIN_BUNDLED_PLUGIN_POLICY_H

#include <string>

namespace swift_toolchain {

/// Resolves a regular file at an executable location in the owning application's framework
/// directory. Both arguments are readable null-terminated filesystem paths for this call. Canonical
/// paths must place the executable in a direct child framework whose basename matches the
/// executable. Returns the canonical path, or an empty string when the file or its owning layout is
/// invalid.
std::string bundledFrameworkExecutablePath(const char *frameworkDirectory, const char *path);

} // namespace swift_toolchain

#endif
