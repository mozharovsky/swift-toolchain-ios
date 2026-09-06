cmake_minimum_required(VERSION 3.27)
project(Swift LANGUAGES CXX)

if(TARGET SwiftCompilerBridge)
  message(FATAL_ERROR "The bridge must wait until the frontend targets exist.")
endif()
set(TOOLCHAIN_BUILD_ROOT "${CMAKE_CURRENT_BINARY_DIR}/native")
set(TOOLCHAIN_SOURCE_ROOT "${CMAKE_CURRENT_BINARY_DIR}/sources")
include("${TOOLCHAIN_SOURCE_DIR}/CMake/Inputs.cmake")
set(LLD_DIR "${TOOLCHAIN_BUILD_ROOT}/llvm-ios/lib/cmake/lld" CACHE PATH
  "The configure-only fixture supplies target declarations without compiler libraries." FORCE)
file(MAKE_DIRECTORY "${LLD_DIR}" "${TOOLCHAIN_SWIFT_SOURCE}/lib/DriverTool"
  "${TOOLCHAIN_LLVM_SOURCE}/lld/include")
file(WRITE "${TOOLCHAIN_SWIFT_SOURCE}/lib/DriverTool/autolink_extract_main.cpp" "")
file(WRITE "${LLD_DIR}/LLDConfig.cmake" [=[
add_library(lldWasm INTERFACE IMPORTED)
add_library(lldCommon INTERFACE IMPORTED)
]=])
add_library(swiftFrontendTool INTERFACE)

# The fixture exercises target creation only and never compiles the backend against these stand-ins.
function(add_swift_host_library name)
  add_library(${name} ${ARGN})
endfunction()

# The real hook must attach existing absolute sources after the frontend contract becomes available.
function(check_bridge_configuration)
  if(NOT TARGET SwiftCompilerBridge)
    message(FATAL_ERROR "The deferred hook did not create the bridge target.")
  endif()
  get_target_property(bridge_sources SwiftCompilerBridge SOURCES)
  if(NOT bridge_sources)
    message(FATAL_ERROR "The included bridge recipe did not attach source files.")
  endif()
  foreach(source IN LISTS bridge_sources)
    if(NOT IS_ABSOLUTE "${source}" OR NOT EXISTS "${source}")
      message(FATAL_ERROR "The included bridge recipe must resolve its own source paths.")
    endif()
  endforeach()
endfunction()

# The hook must rediscover inputs after initial cache variables leave scope.
unset(TOOLCHAIN_SWIFT_SOURCE)
unset(TOOLCHAIN_LLVM_SOURCE)
cmake_language(DEFER CALL check_bridge_configuration)
