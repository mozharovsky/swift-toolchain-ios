#ifndef SWIFT_TOOLCHAIN_APPLE_FILE_SYSTEM_METADATA_H
#define SWIFT_TOOLCHAIN_APPLE_FILE_SYSTEM_METADATA_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Reads volume locality for LLVM without requesting filesystem capacity statistics.
/// The path is a readable, null-terminated filesystem path. The output is set only on success.
/// Returns zero on success or a POSIX error code. Null arguments return EINVAL.
int swift_toolchain_is_local_path(const char *path, bool *result);

/// Reads volume locality for LLVM's open-file mapping policy without taking ownership of the file.
/// The descriptor must remain open during the call. The output is set only on success.
/// Returns zero on success or a POSIX error code when the descriptor or its path cannot be read.
int swift_toolchain_is_local_fd(int descriptor, bool *result);

#ifdef __cplusplus
}
#endif

#endif
