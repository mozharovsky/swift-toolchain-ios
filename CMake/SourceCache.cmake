include(ExternalProject)

# Plans share source bytes while retaining their own Ninja step timestamps.
function(toolchain_add_source name)
  set(patch_command "")
  if(name STREQUAL "swift")
    set(patch_command "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
      "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/DisableImmediateExecution.patch"
      COMMAND "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
      "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/RestrictedSwiftNativeProfile.patch")
  elseif(name STREQUAL "llvm-project")
    set(patch_command "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
      "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/AppleFileSystemMetadata.patch"
      COMMAND "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
      "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/RestrictedLLVMNativeProfile.patch")
  endif()
  ExternalProject_Add(source-${name}
    PREFIX "${CMAKE_BINARY_DIR}/source-projects/${TOOLCHAIN_${name}_IDENTITY}"
    SOURCE_DIR "${TOOLCHAIN_${name}_SOURCE}"
    DOWNLOAD_DIR "${TOOLCHAIN_CACHE_ROOT}/downloads"
    DOWNLOAD_NAME "${name}-${TOOLCHAIN_${name}_REVISION}.tar.gz"
    URL "${TOOLCHAIN_${name}_URL}"
    URL_HASH "SHA256=${TOOLCHAIN_${name}_SHA256}"
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
    TLS_VERIFY TRUE
    TIMEOUT 300
    INACTIVITY_TIMEOUT 30
    UPDATE_COMMAND ""
    PATCH_COMMAND ${patch_command}
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
    EXCLUDE_FROM_ALL TRUE)
endfunction()
