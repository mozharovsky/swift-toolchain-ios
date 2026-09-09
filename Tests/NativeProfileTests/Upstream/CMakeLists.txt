cmake_minimum_required(VERSION 3.27)
project(UpstreamNativeProfileTests LANGUAGES C CXX)

foreach(input TOOLCHAIN_LLVM_SOURCE TOOLCHAIN_SWIFT_SOURCE)
  if(NOT IS_ABSOLUTE "${${input}}" OR NOT IS_DIRECTORY "${${input}}")
    message(FATAL_ERROR "Set ${input} to the verified, patched upstream source directory.")
  endif()
endforeach()
find_package(LLVM REQUIRED CONFIG)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
enable_testing()

# Matching host support archives provide unchanged dependencies for the patched implementation files.
add_executable(UpstreamNativeProfileTests
  "${CMAKE_CURRENT_LIST_DIR}/../UpstreamNativeProfileTests.cpp"
  "${TOOLCHAIN_LLVM_SOURCE}/llvm/lib/Support/Program.cpp"
  "${TOOLCHAIN_LLVM_SOURCE}/llvm/lib/Support/Memory.cpp"
  "${TOOLCHAIN_LLVM_SOURCE}/llvm/lib/Support/DynamicLibrary.cpp"
  "${TOOLCHAIN_SWIFT_SOURCE}/lib/Basic/Program.cpp")
target_include_directories(UpstreamNativeProfileTests SYSTEM PRIVATE
  ${LLVM_INCLUDE_DIRS} "${TOOLCHAIN_LLVM_SOURCE}/llvm/include" "${TOOLCHAIN_SWIFT_SOURCE}/include")
target_compile_definitions(UpstreamNativeProfileTests PRIVATE SWIFT_TOOLCHAIN_RESTRICTED_NATIVE=1)
if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(UpstreamNativeProfileTests PRIVATE -fno-rtti)
endif()
if(NOT LLVM_ENABLE_EH)
  target_compile_options(UpstreamNativeProfileTests PRIVATE -fno-exceptions)
endif()
separate_arguments(llvm_definitions NATIVE_COMMAND "${LLVM_DEFINITIONS}")
target_compile_options(UpstreamNativeProfileTests PRIVATE ${llvm_definitions} -Wall -Werror)
set_source_files_properties("${CMAKE_CURRENT_LIST_DIR}/../UpstreamNativeProfileTests.cpp"
  PROPERTIES COMPILE_OPTIONS "-Wextra;-Wpedantic")
target_link_libraries(UpstreamNativeProfileTests PRIVATE LLVMSupport)
add_test(NAME UpstreamNativeProfile COMMAND UpstreamNativeProfileTests)
set_tests_properties(UpstreamNativeProfile PROPERTIES TIMEOUT 20)
