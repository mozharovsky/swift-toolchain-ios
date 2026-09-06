foreach(required TOOLCHAIN_BUILD_ROOT TOOLCHAIN_SOURCE_ROOT TOOLCHAIN_NINJA)
  if(NOT DEFINED ${required} OR NOT IS_ABSOLUTE "${${required}}")
    message(FATAL_ERROR "Set ${required} to an absolute path before loading this profile.")
  endif()
endforeach()
include("${CMAKE_CURRENT_LIST_DIR}/../Inputs.cmake")
execute_process(COMMAND xcrun --find clang OUTPUT_VARIABLE TOOLCHAIN_CLANG
  OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND xcrun --find clang++ OUTPUT_VARIABLE TOOLCHAIN_CLANGXX
  OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)

# Prefix maps keep compiler-generated paths independent of a maintainer's checkout location.
set(TOOLCHAIN_PREFIX_MAPS
  "\"-ffile-prefix-map=${TOOLCHAIN_SOURCE_ROOT}=/toolchain/sources\" \"-ffile-prefix-map=${TOOLCHAIN_BUILD_ROOT}=/toolchain/build\" \"-ffile-prefix-map=${TOOLCHAIN_REPOSITORY_ROOT}=/toolchain/producer\"")
set(CMAKE_C_FLAGS "${TOOLCHAIN_PREFIX_MAPS}" CACHE STRING "Stable native source paths." FORCE)
set(CMAKE_CXX_FLAGS "${TOOLCHAIN_PREFIX_MAPS}" CACHE STRING "Stable native source paths." FORCE)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON CACHE BOOL "The producer retains exact compile commands." FORCE)
