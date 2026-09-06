include(ExternalProject)

if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" OR NOT CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "arm64")
  message(FATAL_ERROR "Native compiler production currently requires an Apple silicon Mac.")
endif()
set(TOOLCHAIN_CACHE_ROOT "${CMAKE_BINARY_DIR}/native" CACHE PATH "Ignored source and build storage.")
set(TOOLCHAIN_BOOTSTRAP_ROOT "" CACHE PATH "The Swift release toolchain's usr directory.")
set(TOOLCHAIN_BUILD_JOBS 4 CACHE STRING "Maximum jobs within the active native build stage.")
if(NOT TOOLCHAIN_BUILD_JOBS MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR "TOOLCHAIN_BUILD_JOBS must be a positive integer.")
endif()
if(NOT EXISTS "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swiftc")
  message(FATAL_ERROR "Set TOOLCHAIN_BOOTSTRAP_ROOT to the pinned Swift toolchain usr directory.")
endif()
find_program(TOOLCHAIN_NINJA NAMES ninja REQUIRED)
find_program(TOOLCHAIN_PATCH NAMES patch REQUIRED)
get_filename_component(TOOLCHAIN_CACHE_ROOT "${TOOLCHAIN_CACHE_ROOT}" ABSOLUTE)
set(TOOLCHAIN_SOURCE_ROOT "${TOOLCHAIN_CACHE_ROOT}/sources")
include("${CMAKE_CURRENT_LIST_DIR}/Inputs.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/NativeLibraries.cmake")
file(SHA256 "${TOOLCHAIN_LOCK_FILE}" lock_digest)
string(SHA256 input_digest "${lock_digest}${TOOLCHAIN_PATCH_SHA256}")
set(TOOLCHAIN_BUILD_ROOT "${TOOLCHAIN_CACHE_ROOT}/build/${input_digest}")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${TOOLCHAIN_LOCK_FILE}" "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/DisableImmediateExecution.patch")

execute_process(COMMAND "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swiftc" --version
  OUTPUT_VARIABLE bootstrap_version COMMAND_ERROR_IS_FATAL ANY)
string(REPLACE "." "\\." version_pattern "${TOOLCHAIN_SWIFT_VERSION}")
if(NOT bootstrap_version MATCHES "Swift version ${version_pattern}([ \n]|$)")
  message(FATAL_ERROR "The bootstrap compiler must match Swift ${TOOLCHAIN_SWIFT_VERSION}.")
endif()

set(source_targets "")
foreach(name IN LISTS TOOLCHAIN_SOURCE_NAMES)
  set(patch_command "")
  if(name STREQUAL "swift")
    set(patch_command "${TOOLCHAIN_PATCH}" -p1 --forward --input
      "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/DisableImmediateExecution.patch")
  endif()
  ExternalProject_Add(source-${name}
    PREFIX "${TOOLCHAIN_CACHE_ROOT}/projects/${TOOLCHAIN_${name}_IDENTITY}"
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
  list(APPEND source_targets source-${name})
endforeach()
add_custom_target(toolchain-sources DEPENDS ${source_targets})

function(toolchain_native_stage name source profile)
  set(stage_arguments
    "-DTOOLCHAIN_BUILD_ROOT:PATH=${TOOLCHAIN_BUILD_ROOT}"
    "-DTOOLCHAIN_SOURCE_ROOT:PATH=${TOOLCHAIN_SOURCE_ROOT}"
    "-DTOOLCHAIN_NINJA:FILEPATH=${TOOLCHAIN_NINJA}")
  if(name STREQUAL "swift-ios")
    list(APPEND stage_arguments
      "-DTOOLCHAIN_BOOTSTRAP_ROOT:PATH=${TOOLCHAIN_BOOTSTRAP_ROOT}"
      "-DCMAKE_PROJECT_Swift_INCLUDE:FILEPATH=${TOOLCHAIN_REPOSITORY_ROOT}/CMake/IncludeBridge.cmake")
  endif()
  ExternalProject_Add(${name}
    PREFIX "${TOOLCHAIN_BUILD_ROOT}/projects/${name}"
    SOURCE_DIR "${source}"
    BINARY_DIR "${TOOLCHAIN_BUILD_ROOT}/${name}"
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND ""
    CMAKE_GENERATOR Ninja
    CMAKE_ARGS ${stage_arguments}
      -C "${TOOLCHAIN_REPOSITORY_ROOT}/CMake/Profiles/${profile}.cmake"
    BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR>
      --parallel "${TOOLCHAIN_BUILD_JOBS}" --target ${ARGN}
    BUILD_ALWAYS TRUE
    INSTALL_COMMAND ""
    EXCLUDE_FROM_ALL TRUE)
  ExternalProject_Add_StepDependencies(${name} configure
    "${TOOLCHAIN_REPOSITORY_ROOT}/CMake/Profiles/${profile}.cmake"
    "${TOOLCHAIN_REPOSITORY_ROOT}/CMake/Profiles/Common.cmake"
    "${TOOLCHAIN_LOCK_FILE}")
endfunction()

toolchain_native_stage(host-tools "${TOOLCHAIN_LLVM_SOURCE}/llvm" HostTools llvm-tblgen clang-tblgen)
add_dependencies(host-tools source-llvm-project)
toolchain_native_stage(llvm-ios "${TOOLCHAIN_LLVM_SOURCE}/llvm" LLVM-IOS ${TOOLCHAIN_NATIVE_LIBRARIES})
add_dependencies(llvm-ios host-tools)
toolchain_native_stage(cmark-ios "${TOOLCHAIN_CMARK_SOURCE}" CmarkIOS cmark-gfm_static)
add_dependencies(cmark-ios source-swift-cmark llvm-ios)
toolchain_native_stage(swift-ios "${TOOLCHAIN_SWIFT_SOURCE}" SwiftIOS SwiftCompilerBridge)
add_dependencies(swift-ios source-swift source-swift-syntax source-string-processing cmark-ios)
add_custom_target(toolchain-compiler DEPENDS swift-ios)

message(STATUS "Compiler host ${TOOLCHAIN_COMPILER_HOST}. Program target ${TOOLCHAIN_PROGRAM_TARGET}.")
message(STATUS "Native build root ${TOOLCHAIN_BUILD_ROOT}")
message(STATUS "Compiler production is explicit. Build toolchain-compiler only with a resource budget.")
