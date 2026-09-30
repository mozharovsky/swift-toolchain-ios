cmake_minimum_required(VERSION 3.27)
project(ToolchainSourcePreparation NONE)
include(ExternalProject)

# ExternalProject owns extraction and successful patch stamps in one graph shared by all plans.
set(patch_command "")
if(TOOLCHAIN_SOURCE_NAME STREQUAL "swift")
  set(patch_command "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
    "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/DisableImmediateExecution.patch"
    COMMAND "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
    "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/RestrictedSwiftNativeProfile.patch")
elseif(TOOLCHAIN_SOURCE_NAME STREQUAL "llvm-project")
  set(patch_command "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
    "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/AppleFileSystemMetadata.patch"
    COMMAND "${TOOLCHAIN_PATCH}" -p1 --forward --fuzz=0 --input
    "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/RestrictedLLVMNativeProfile.patch")
endif()
ExternalProject_Add(prepare-source
  SOURCE_DIR "${TOOLCHAIN_SOURCE_DIRECTORY}"
  DOWNLOAD_DIR "${TOOLCHAIN_DOWNLOAD_DIRECTORY}"
  DOWNLOAD_NAME "${TOOLCHAIN_SOURCE_NAME}-${TOOLCHAIN_SOURCE_REVISION}.tar.gz"
  URL "${TOOLCHAIN_SOURCE_URL}"
  URL_HASH "SHA256=${TOOLCHAIN_SOURCE_SHA256}"
  DOWNLOAD_EXTRACT_TIMESTAMP FALSE
  TLS_VERIFY TRUE
  TIMEOUT 300
  INACTIVITY_TIMEOUT 30
  UPDATE_COMMAND ""
  PATCH_COMMAND ${patch_command}
  CONFIGURE_COMMAND ""
  BUILD_COMMAND ""
  INSTALL_COMMAND "")
