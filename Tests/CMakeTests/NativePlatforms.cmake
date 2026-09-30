set(TOOLCHAIN_SOURCE_ROOT "${TOOLCHAIN_TEST_ROOT}/sources")
set(TOOLCHAIN_ARTIFACT_VERSION 0.1.0)
if(DEFINED TEST_XCFRAMEWORK)
  include("${TOOLCHAIN_SOURCE_DIR}/CMake/ArtifactHelpers.cmake")
  toolchain_inspect_xcframework("${TEST_XCFRAMEWORK}" Fixture)
  return()
endif()
if(DEFINED TEST_REJECT_LIBRARY)
  set(TOOLCHAIN_PLATFORM "${TEST_PLATFORM}")
  include("${TOOLCHAIN_SOURCE_DIR}/CMake/Inputs.cmake")
  include("${TOOLCHAIN_SOURCE_DIR}/CMake/ArtifactHelpers.cmake")
  toolchain_inspect_library("${TEST_REJECT_LIBRARY}")
  return()
endif()

foreach(platform device simulator)
  set(TOOLCHAIN_PLATFORM "${platform}")
  include("${TOOLCHAIN_SOURCE_DIR}/CMake/Inputs.cmake")
  include("${TOOLCHAIN_SOURCE_DIR}/CMake/CacheManifest.cmake")
  toolchain_native_identity(${platform}_identity)
  set(framework "${TOOLCHAIN_TEST_ROOT}/${TOOLCHAIN_SLICE}/Fixture.framework")
  file(MAKE_DIRECTORY "${framework}")
  toolchain_framework_plist("${framework}" Fixture)
  file(READ "${framework}/Info.plist" plist)
  if(NOT plist MATCHES "<string>${TOOLCHAIN_BUNDLE_PLATFORM}</string>")
    message(FATAL_ERROR "The framework bundle platform does not match its native environment.")
  endif()
  execute_process(COMMAND xcrun --sdk "${TOOLCHAIN_APPLE_SDK}" clang
    -target "${TOOLCHAIN_COMPILER_HOST}" -dynamiclib
    "${TOOLCHAIN_SOURCE_DIR}/Tests/ArtifactPackagingTests/LocalSymbols.c"
    -o "${framework}/Fixture" COMMAND_ERROR_IS_FATAL ANY)
  toolchain_inspect_library("${framework}/Fixture")
  if(platform STREQUAL "device")
    set(other simulator)
  else()
    set(other device)
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DTOOLCHAIN_SOURCE_DIR=${TOOLCHAIN_SOURCE_DIR}" "-DTOOLCHAIN_TEST_ROOT=${TOOLCHAIN_TEST_ROOT}"
    "-DTEST_PLATFORM=${other}" "-DTEST_REJECT_LIBRARY=${framework}/Fixture"
    -P "${CMAKE_CURRENT_LIST_FILE}" RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(status EQUAL 0 OR NOT error MATCHES "selected arm64 iOS platform")
    message(FATAL_ERROR "Platform inspection accepted a library from another environment. ${output} ${error}")
  endif()
endforeach()
if(device_identity STREQUAL simulator_identity)
  message(FATAL_ERROR "Device and simulator native receipts must have distinct input identities.")
endif()
set(xcframework "${TOOLCHAIN_TEST_ROOT}/Fixture.xcframework")
file(REMOVE_RECURSE "${xcframework}")
execute_process(COMMAND xcodebuild -create-xcframework
  -framework "${TOOLCHAIN_TEST_ROOT}/ios-arm64/Fixture.framework"
  -framework "${TOOLCHAIN_TEST_ROOT}/ios-arm64-simulator/Fixture.framework"
  -output "${xcframework}" COMMAND_ERROR_IS_FATAL ANY)
toolchain_inspect_xcframework("${xcframework}" Fixture)
execute_process(COMMAND plutil -convert json -o - "${xcframework}/Info.plist"
  OUTPUT_VARIABLE metadata COMMAND_ERROR_IS_FATAL ANY)
string(JSON metadata SET "${metadata}" AvailableLibraries 1 SupportedPlatform "\"macos\"")
file(WRITE "${TOOLCHAIN_TEST_ROOT}/invalid.json" "${metadata}")
file(MAKE_DIRECTORY "${TOOLCHAIN_TEST_ROOT}/Invalid.xcframework")
execute_process(COMMAND plutil -convert xml1
  -o "${TOOLCHAIN_TEST_ROOT}/Invalid.xcframework/Info.plist" "${TOOLCHAIN_TEST_ROOT}/invalid.json"
  COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DTOOLCHAIN_SOURCE_DIR=${TOOLCHAIN_SOURCE_DIR}"
  "-DTEST_XCFRAMEWORK=${TOOLCHAIN_TEST_ROOT}/Invalid.xcframework"
  -P "${CMAKE_CURRENT_LIST_FILE}" RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(status EQUAL 0 OR NOT error MATCHES "platform inventory is incompatible")
  message(FATAL_ERROR "XCFramework inspection accepted mislabeled native platforms. ${output} ${error}")
endif()
