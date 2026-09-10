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
  add_executable(BundledPluginPolicyTests
    Sources/NativeProfile/BundledPluginPolicy.cpp
    Tests/NativeProfileTests/BundledPluginPolicyTests.cpp)
  target_include_directories(BundledPluginPolicyTests PRIVATE Sources/NativeProfile)
  target_compile_options(BundledPluginPolicyTests PRIVATE -Wall -Wextra -Werror -Wpedantic)
  if(TOOLCHAIN_ENABLE_SANITIZERS)
    target_compile_options(BundledPluginPolicyTests PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(BundledPluginPolicyTests PRIVATE -fsanitize=address,undefined)
  endif()
  if(APPLE)
    set_target_properties(BundledPluginPolicyTests PROPERTIES MACOSX_BUNDLE TRUE
      MACOSX_BUNDLE_GUI_IDENTIFIER org.swift.toolchain.native-profile-tests)
    target_link_libraries(BundledPluginPolicyTests PRIVATE "-framework CoreFoundation")
  endif()
  add_test(NAME BundledPluginPolicy COMMAND BundledPluginPolicyTests)
  set_tests_properties(BundledPluginPolicy PROPERTIES TIMEOUT 20)
  set(native_profile_library_arguments)
  if(APPLE)
    add_executable(AppleFileSystemMetadataTests
      Sources/AppleFileSystemMetadata/AppleFileSystemMetadata.cpp
      Tests/AppleFileSystemMetadataTests/ContractTests.cpp)
    target_include_directories(AppleFileSystemMetadataTests PRIVATE Sources/AppleFileSystemMetadata)
    target_compile_options(AppleFileSystemMetadataTests PRIVATE -Wall -Wextra -Werror -Wpedantic)
    target_link_libraries(AppleFileSystemMetadataTests PRIVATE "-framework CoreFoundation")
    add_test(NAME AppleFileSystemMetadata COMMAND AppleFileSystemMetadataTests)
    add_test(NAME LLVMFileSystemMetadataConfiguration
      COMMAND "${CMAKE_COMMAND}" -S "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/LLVMFixture"
        -B "${CMAKE_CURRENT_BINARY_DIR}/llvm-metadata-fixture"
        "-DCMAKE_PROJECT_LLVM_INCLUDE=${CMAKE_SOURCE_DIR}/CMake/IncludeAppleFileSystemMetadata.cmake")
    add_executable(MacroCallbackThreadingTests
      Sources/MacroBridge/MacroEntry.cpp Tests/MacroBridgeTests/ThreadingTests.cpp)
    target_include_directories(MacroCallbackThreadingTests PRIVATE Sources/MacroBridge)
    target_compile_options(MacroCallbackThreadingTests PRIVATE -Wall -Wextra -Werror -Wpedantic)
    add_test(NAME MacroCallbackThreading COMMAND MacroCallbackThreadingTests)
    set_tests_properties(MacroCallbackThreading PROPERTIES TIMEOUT 20)
    find_program(TOOLCHAIN_XCRUN NAMES xcrun REQUIRED)
    add_library(AllowedNativeImportFixture SHARED Tests/NativeProfileTests/ImportFixture.c)
    add_library(ForbiddenNativeImportFixture SHARED Tests/NativeProfileTests/ImportFixture.c)
    target_compile_definitions(ForbiddenNativeImportFixture PRIVATE TOOLCHAIN_TEST_FORBIDDEN_IMPORT=1)
    foreach(target AllowedNativeImportFixture ForbiddenNativeImportFixture)
      target_compile_options(${target} PRIVATE -Wall -Wextra -Werror -Wpedantic)
    endforeach()
    set(native_profile_library_arguments
      "-DTEST_ALLOWED_LIBRARY=$<TARGET_FILE:AllowedNativeImportFixture>"
      "-DTEST_FORBIDDEN_LIBRARY=$<TARGET_FILE:ForbiddenNativeImportFixture>")
    add_library(NativeSymbolFixture SHARED Tests/ArtifactPackagingTests/LocalSymbols.c)
    target_compile_options(NativeSymbolFixture PRIVATE -O0 -Wall -Wextra -Werror -Wpedantic)
    add_executable(StrippedLibraryTests Tests/ArtifactPackagingTests/LibraryLoadTests.cpp)
    target_compile_options(StrippedLibraryTests PRIVATE -Wall -Wextra -Werror -Wpedantic)
    add_test(NAME StripNativeSymbols COMMAND "${CMAKE_COMMAND}"
      "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DTOOLCHAIN_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/strip-symbol-tests"
      "-DTOOLCHAIN_TEST_LIBRARY=$<TARGET_FILE:NativeSymbolFixture>"
      "-DTOOLCHAIN_TEST_LOADER=$<TARGET_FILE:StrippedLibraryTests>"
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/StripNativeSymbols.cmake")
    set_tests_properties(StripNativeSymbols PROPERTIES TIMEOUT 20)
    file(GLOB_RECURSE native_sources CONFIGURE_DEPENDS
      "${CMAKE_SOURCE_DIR}/Sources/CompilerBridge/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/CompilerBridge/*.h"
      "${CMAKE_SOURCE_DIR}/Sources/MacroBridge/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/MacroBridge/*.h"
      "${CMAKE_SOURCE_DIR}/Sources/NativeProfile/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/NativeProfile/*.h"
      "${CMAKE_SOURCE_DIR}/Tests/NativeProfileTests/*.cpp"
      "${CMAKE_SOURCE_DIR}/Tests/NativeProfileTests/*.c"
      "${CMAKE_SOURCE_DIR}/Tests/ArtifactPackagingTests/*.c"
      "${CMAKE_SOURCE_DIR}/Tests/ArtifactPackagingTests/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/AppleFileSystemMetadata/*.cpp"
      "${CMAKE_SOURCE_DIR}/Sources/AppleFileSystemMetadata/*.h"
      "${CMAKE_SOURCE_DIR}/Tests/AppleFileSystemMetadataTests/*.cpp"
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
  add_test(NAME ModuleCodecToolchain
    COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DTOOLCHAIN_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/module-codec-tests"
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/ModuleCodec.cmake")
  set_tests_properties(ModuleCodecToolchain PROPERTIES TIMEOUT 20)
  add_test(NAME ProducerCacheManifest
    COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DTOOLCHAIN_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/cache-manifest-tests"
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/CacheManifest.cmake")
  add_test(NAME ArtifactNotices
    COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DTOOLCHAIN_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/notice-tests"
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/Notices.cmake")
  add_test(NAME ArtifactNoticeSource
    COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DTOOLCHAIN_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/notice-source-tests"
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/NoticeSource.cmake")
  add_test(NAME NativeProfileImports
    COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      ${native_profile_library_arguments}
      -P "${CMAKE_SOURCE_DIR}/Tests/CMakeTests/NativeProfile.cmake")
  set_tests_properties(CompilerBridgeContract CompilerConfigurationInputs
    CompilerBridgeConfiguration PROPERTIES TIMEOUT 20)
endif()

if(TOOLCHAIN_ENABLE_COMPILER_BUILD)
  include(CMake/CompilerBuild.cmake)
endif()
