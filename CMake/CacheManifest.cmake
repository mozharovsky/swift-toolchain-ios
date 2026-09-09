include("${CMAKE_CURRENT_LIST_DIR}/ArtifactHelpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/CompilerSupportModules.cmake")

# Input hashes describe the producer code whose outputs a later packaging run can consume.
function(toolchain_native_identity output)
  set(paths Toolchain.lock.json Patches/DisableImmediateExecution.patch
    Patches/AppleFileSystemMetadata.patch CMake/IncludeAppleFileSystemMetadata.cmake
    Patches/RestrictedSwiftNativeProfile.patch Patches/RestrictedLLVMNativeProfile.patch
    CMake/Profiles/RestrictedNative.cmake
    Sources/NativeProfile/BundledPluginPolicy.cpp Sources/NativeProfile/BundledPluginPolicy.h
    Sources/NativeProfile/SwiftToolchainPluginPolicy.h Sources/NativeProfile/module.modulemap
    Sources/AppleFileSystemMetadata/AppleFileSystemMetadata.cpp
    Sources/AppleFileSystemMetadata/AppleFileSystemMetadata.h
    CMake/Profiles/Common.cmake CMake/Profiles/HostTools.cmake CMake/Profiles/LLVM-IOS.cmake
    CMake/Profiles/CmarkIOS.cmake CMake/Profiles/SwiftIOS.cmake CMake/NativeLibraries.cmake
    CMake/IncludeBridge.cmake CMake/CompilerSupportModules.cmake Sources/CompilerBridge/CMakeLists.txt
    Sources/CompilerBridge/SwiftCompilerBridge.cpp Sources/CompilerBridge/SwiftCompilerBridge.h
    Sources/CompilerBridge/NativeBackend.cpp Sources/CompilerBridge/CompilerBackend.h)
  set(identity "")
  foreach(path IN LISTS paths)
    file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/${path}" checksum)
    string(APPEND identity "${path} ${checksum}\n")
  endforeach()
  string(SHA256 checksum "${identity}")
  set(${output} "${checksum}" PARENT_SCOPE)
endfunction()

# File inventories reject extra cache entries instead of silently adopting a substituted library.
function(toolchain_native_files output root)
  set(files "lib/libSwiftCompilerBridge.dylib")
  foreach(module IN LISTS TOOLCHAIN_COMPILER_SUPPORT_MODULES)
    list(APPEND files "lib/swift/host/compiler/lib_Compiler${module}.dylib"
      "_deps/compilerswiftsyntax-build/Sources/${module}/${module}.swiftmodule")
  endforeach()
  list(SORT files)
  set(${output} "${files}" PARENT_SCOPE)
endfunction()

# Only a completed producer operation records the exact bytes available to artifact preparation.
function(toolchain_record_cache receipt root identity)
  set(records "[]")
  set(index 0)
  foreach(path IN LISTS ARGN)
    if(IS_ABSOLUTE "${path}" OR path MATCHES "(^|/)\\.\\.(/|$)" OR IS_SYMLINK "${root}/${path}")
      message(FATAL_ERROR "Cache records require owned regular files within the build directory.")
    endif()
    file(SHA256 "${root}/${path}" checksum)
    file(SIZE "${root}/${path}" bytes)
    toolchain_json_string(path_json "${path}")
    string(JSON record SET "{}" path "${path_json}")
    string(JSON record SET "${record}" sha256 "\"${checksum}\"")
    string(JSON record SET "${record}" bytes "${bytes}")
    string(JSON records SET "${records}" ${index} "${record}")
    math(EXPR index "${index} + 1")
  endforeach()
  file(WRITE "${receipt}.tmp" "{\"schemaVersion\":1,\"identity\":\"${identity}\",\"files\":${records}}\n")
  file(RENAME "${receipt}.tmp" "${receipt}")
endfunction()

# Packaging must fail before copying stale, missing, additional, or modified cache inputs.
function(toolchain_verify_cache receipt root identity)
  if(NOT EXISTS "${receipt}")
    message(FATAL_ERROR "The producer cache manifest is missing. Rebuild the owning producer target.")
  endif()
  file(READ "${receipt}" manifest)
  string(JSON schema GET "${manifest}" schemaVersion)
  string(JSON recorded_identity GET "${manifest}" identity)
  if(NOT schema EQUAL 1 OR NOT recorded_identity STREQUAL identity)
    message(FATAL_ERROR "The producer cache input identity is stale.")
  endif()
  string(JSON count LENGTH "${manifest}" files)
  set(expected ${ARGN})
  list(LENGTH expected expected_count)
  if(NOT count EQUAL expected_count OR count EQUAL 0)
    message(FATAL_ERROR "The producer cache file inventory differs from its manifest.")
  endif()
  math(EXPR last "${count} - 1")
  set(seen "")
  foreach(index RANGE ${last})
    string(JSON path GET "${manifest}" files ${index} path)
    if(NOT path IN_LIST expected OR path IN_LIST seen OR IS_SYMLINK "${root}/${path}")
      message(FATAL_ERROR "The producer cache contains an unexpected file identity.")
    endif()
    list(APPEND seen "${path}")
    if(NOT EXISTS "${root}/${path}")
      message(FATAL_ERROR "A producer cache file is missing.")
    endif()
    string(JSON recorded_hash GET "${manifest}" files ${index} sha256)
    string(JSON recorded_bytes GET "${manifest}" files ${index} bytes)
    file(SHA256 "${root}/${path}" hash)
    file(SIZE "${root}/${path}" bytes)
    if(NOT recorded_hash STREQUAL hash OR NOT recorded_bytes EQUAL bytes)
      message(FATAL_ERROR "A producer cache file failed its integrity check.")
    endif()
  endforeach()
endfunction()
