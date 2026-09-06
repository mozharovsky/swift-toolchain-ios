cmake_minimum_required(VERSION 3.27)
project(SwiftToolchainIOS LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(TOOLCHAIN_ENABLE_COMPILER_BUILD "Create explicit upstream compiler build targets." OFF)
option(TOOLCHAIN_ENABLE_SANITIZERS "Instrument the small native contract tests." OFF)
include(CTest)

if(BUILD_TESTING)
  find_package(Threads REQUIRED)
  add_executable(CompilerBridgeContractTests
    Sources/CompilerBridge/SwiftCompilerBridge.cpp
    Tests/CompilerBridgeTests/ContractTests.cpp
    Tests/CompilerBridgeTests/TestBackend.cpp
    Tests/CompilerBridgeTests/HeaderCheck.c)
  target_include_directories(CompilerBridgeContractTests PRIVATE Sources/CompilerBridge)
  target_link_libraries(CompilerBridgeContractTests PRIVATE Threads::Threads)
  target_compile_options(CompilerBridgeContractTests PRIVATE -Wall -Wextra -Werror -Wpedantic)
  if(TOOLCHAIN_ENABLE_SANITIZERS)
    target_compile_options(CompilerBridgeContractTests PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(CompilerBridgeContractTests PRIVATE -fsanitize=address,undefined)
  endif()
  add_test(NAME CompilerBridgeContract COMMAND CompilerBridgeContractTests)
  if(APPLE)
    find_program(TOOLCHAIN_XCRUN NAMES xcrun REQUIRED)
    file(GLOB_RECURSE native_sources CONFIGURE_DEPENDS
      "${CMAKE_SOURCE_DIR}/Sources/CompilerBridge/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/CompilerBridge/*.h"
      "${CMAKE_SOURCE_DIR}/Tests/CompilerBridgeTests/*.cpp"
      "${CMAKE_SOURCE_DIR}/Tests/CompilerBridgeTests/*.h"
      "${CMAKE_SOURCE_DIR}/Tests/CompilerBridgeTests/*.c")
    add_test(NAME NativeSourceFormatting
      COMMAND "${TOOLCHAIN_XCRUN}" clang-format --dry-run --Werror ${native_sources})
  endif()
  set_tests_properties(CompilerBridgeContract PROPERTIES TIMEOUT 20)
endif()

if(TOOLCHAIN_ENABLE_COMPILER_BUILD)
  include(CMake/CompilerBuild.cmake)
endif()
