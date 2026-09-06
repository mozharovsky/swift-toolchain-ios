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
    add_executable(MacroCallbackThreadingTests
      Sources/MacroBridge/MacroEntry.cpp Tests/MacroBridgeTests/ThreadingTests.cpp)
    target_include_directories(MacroCallbackThreadingTests PRIVATE Sources/MacroBridge)
    target_compile_options(MacroCallbackThreadingTests PRIVATE -Wall -Wextra -Werror -Wpedantic)
    add_test(NAME MacroCallbackThreading COMMAND MacroCallbackThreadingTests)
    set_tests_properties(MacroCallbackThreading PROPERTIES TIMEOUT 20)
    find_program(TOOLCHAIN_XCRUN NAMES xcrun REQUIRED)
    file(GLOB_RECURSE native_sources CONFIGURE_DEPENDS
      "${CMAKE_SOURCE_DIR}/Sources/CompilerBridge/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/CompilerBridge/*.h"
      "${CMAKE_SOURCE_DIR}/Sources/MacroBridge/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/MacroBridge/*.h"
      "${CMAKE_SOURCE_DIR}/Tests/MacroBridgeTests/*.cpp"
      "${CMAKE_SOURCE_DIR}/Tests/CompilerBridgeTests/*.cpp"
      "${CMAKE_SOURCE_DIR}/Tests/CompilerBridgeTests/*.h"
      "${CMAKE_SOURCE_DIR}/Tests/CompilerBridgeTests/*.c")
    add_test(NAME NativeSourceFormatting
      COMMAND "${TOOLCHAIN_XCRUN}" clang-format --dry-run --Werror ${native_sources})
  endif()
  add_test(NAME CompilerConfigurationInputs
    COMMAND "${CMAKE_COMMAND}"
      "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DTOOLCHAIN_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/configuration-input-tests"
      "-DTOOLCHAIN_TEST_GENERATOR=${CMAKE_GENERATOR}"
      "-DTOOLCHAIN_TEST_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/ConfigurationInputs.cmake")
  add_test(NAME CompilerBridgeConfiguration
    COMMAND "${CMAKE_COMMAND}"
      -S "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/BridgeFixture"
      -B "${CMAKE_CURRENT_BINARY_DIR}/bridge-configure-fixture"
      -G "${CMAKE_GENERATOR}"
      "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DCMAKE_PROJECT_Swift_INCLUDE=${CMAKE_SOURCE_DIR}/CMake/IncludeBridge.cmake"
      "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}")
  add_test(NAME ArtifactMetadata
    COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/ArtifactMetadata.cmake")
  set_tests_properties(CompilerBridgeContract CompilerConfigurationInputs
    CompilerBridgeConfiguration PROPERTIES TIMEOUT 20)
endif()

if(TOOLCHAIN_ENABLE_COMPILER_BUILD)
  include(CMake/CompilerBuild.cmake)
endif()
