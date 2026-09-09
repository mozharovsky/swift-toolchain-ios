#ifndef SWIFT_TOOLCHAIN_PLUGIN_POLICY_H
#define SWIFT_TOOLCHAIN_PLUGIN_POLICY_H

#ifdef __cplusplus
extern "C" {
#endif

/// Copies the canonical plugin path that the compiler or macro server may open.
/// The caller provides a readable null-terminated path for this call. Both the path and the main
/// application's private frameworks directory are resolved through filesystem symlinks.
/// Returns null when resolution fails or the path is not a regular file at a framework's executable
/// location in that directory. The loader validates the library format. A successful result is
/// null-terminated and must be freed by the caller with free().
/// Loaders open this returned path so mutable aliases cannot redirect a later open outside the
/// bundle. The application must preserve its bundled files throughout compiler use.
__attribute__((visibility("default"))) char *
swift_toolchain_copy_bundled_plugin_path(const char *path);

#ifdef __cplusplus
}
#endif

#endif
