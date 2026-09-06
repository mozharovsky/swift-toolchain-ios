if(NOT TARGET swiftFrontendTool OR NOT COMMAND add_swift_host_library)
  message(FATAL_ERROR "Configure this target through the pinned Swift compiler build.")
endif()

find_package(LLD CONFIG REQUIRED
  PATHS "${TOOLCHAIN_BUILD_ROOT}/llvm-ios/lib/cmake/lld" NO_DEFAULT_PATH)

add_swift_host_library(SwiftCompilerBridge SHARED
  SwiftCompilerBridge.cpp NativeBackend.cpp)
target_sources(SwiftCompilerBridge PRIVATE
  "${TOOLCHAIN_SWIFT_SOURCE}/lib/DriverTool/autolink_extract_main.cpp")
target_include_directories(SwiftCompilerBridge PRIVATE "${TOOLCHAIN_LLVM_SOURCE}/lld/include")
target_link_libraries(SwiftCompilerBridge PRIVATE swiftFrontendTool lldWasm lldCommon)
set_target_properties(SwiftCompilerBridge PROPERTIES
  CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)
