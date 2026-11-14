include("${CMAKE_CURRENT_LIST_DIR}/ArtifactHelpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/PayloadCodec.cmake")
if(NOT EXISTS "${TOOLCHAIN_SDK_ARCHIVE}")
  message(FATAL_ERROR "Provide the checksum-pinned SDK archive before packaging.")
endif()
string(JSON expected GET "${TOOLCHAIN_INPUTS}" sdk sha256)
file(SHA256 "${TOOLCHAIN_SDK_ARCHIVE}" actual)
if(NOT actual STREQUAL expected)
  message(FATAL_ERROR "The SDK archive checksum does not match Toolchain.lock.json.")
endif()
string(JSON sdk_version GET "${TOOLCHAIN_INPUTS}" sdk version)
set(extraction "${TOOLCHAIN_PACKAGE_WORK}/SDKArchive")
file(MAKE_DIRECTORY "${extraction}")
file(ARCHIVE_EXTRACT INPUT "${TOOLCHAIN_SDK_ARCHIVE}" DESTINATION "${extraction}")
set(sdk_source "${extraction}/${sdk_version}.artifactbundle/${sdk_version}/${TOOLCHAIN_PROGRAM_TARGET}")
if(NOT EXISTS "${sdk_source}/swift-sdk.json")
  message(FATAL_ERROR "The SDK archive lacks its declared target metadata.")
endif()
file(READ "${sdk_source}/swift-sdk.json" sdk_metadata)
string(JSON sdk_path GET "${sdk_metadata}" targetTriples "${TOOLCHAIN_PROGRAM_TARGET}" sdkRootPath)
string(JSON resources_path GET "${sdk_metadata}" targetTriples "${TOOLCHAIN_PROGRAM_TARGET}" swiftStaticResourcesPath)
if(NOT sdk_path STREQUAL "WASI.sdk" OR NOT resources_path STREQUAL "swift.xctoolchain/usr/lib/swift_static")
  message(FATAL_ERROR "The SDK payload layout needs a reviewed packaging update.")
endif()
set(framework "${TOOLCHAIN_FRAMEWORK_ROOT}/SwiftCompilerSDK.framework")
set(payload "${framework}/Payload")
file(MAKE_DIRECTORY "${framework}/Headers" "${payload}/swift.xctoolchain/usr/lib")
file(COPY "${sdk_source}/WASI.sdk" DESTINATION "${payload}" PATTERN ".DS_Store" EXCLUDE)
# Devices never run the SDK's host configuration scripts, and app distribution rejects standalone
# executables in an application bundle.
file(REMOVE_RECURSE "${payload}/WASI.sdk/bin")
file(COPY "${sdk_source}/${resources_path}" DESTINATION "${payload}/swift.xctoolchain/usr/lib"
  PATTERN ".DS_Store" EXCLUDE)
include("${CMAKE_CURRENT_LIST_DIR}/GuestBuiltins.cmake")
if(NOT DEFINED TOOLCHAIN_GUEST_BUILTINS)
  message(FATAL_ERROR "Build the guest builtins before preparing the SDK.")
endif()
toolchain_install_guest_builtins(TOOLCHAIN_REPLACED_BUILTINS_SHA256 TOOLCHAIN_GUEST_BUILTIN_SYMBOLS
  "${payload}" "${TOOLCHAIN_GUEST_BUILTINS}")
include("${CMAKE_CURRENT_LIST_DIR}/GuestFoundation.cmake")
if(NOT DEFINED TOOLCHAIN_GUEST_FOUNDATION_MEMBERS)
  message(FATAL_ERROR "Build the guest Foundation objects before preparing the SDK.")
endif()
toolchain_install_guest_foundation(TOOLCHAIN_REPLACED_FOUNDATION_SHA256 "${payload}"
  "${TOOLCHAIN_GUEST_FOUNDATION_OBJECTS}" "${TOOLCHAIN_GUEST_FOUNDATION_MEMBERS}")
file(SHA256 "${payload}/${TOOLCHAIN_GUEST_FOUNDATION_PATH}" TOOLCHAIN_GUEST_FOUNDATION_SHA256)
file(WRITE "${payload}/Compatibility.json"
  "{\n  \"schemaVersion\": 1,\n  \"swiftVersion\": \"${TOOLCHAIN_SWIFT_VERSION}\",\n"
  "  \"compilerCommit\": \"${TOOLCHAIN_swift_REVISION}\",\n"
  "  \"target\": \"${TOOLCHAIN_PROGRAM_TARGET}\",\n  \"revision\": \"${sdk_version}\"\n}\n")

toolchain_prepare_payload_codec(payload_codec)
toolchain_encode_payload(encoded_files "${payload}" "${payload_codec}")
include("${CMAKE_CURRENT_LIST_DIR}/PrepareNotices.cmake")
toolchain_find_static_archives(archives "${payload}")
if(archives)
  list(JOIN archives ", " archives)
  message(FATAL_ERROR "The SDK payload still contains static archives: ${archives}.")
endif()
file(GLOB_RECURSE payload_files LIST_DIRECTORIES FALSE "${payload}/*")
list(SORT payload_files)
set(identity_input "")
foreach(file IN LISTS payload_files)
  file(RELATIVE_PATH path "${payload}" "${file}")
  file(SHA256 "${file}" checksum)
  string(APPEND identity_input "${path} ${checksum}\n")
endforeach()
string(SHA256 identity "${identity_input}")
file(WRITE "${payload}/Materialization.json"
  "{\"schemaVersion\":3,\"encoding\":\"lzfse\",\"identity\":\"${identity}\","
  "\"encodedFiles\":${encoded_files}}\n")
configure_file("${CMAKE_CURRENT_LIST_DIR}/Templates/SDKBundle.h.in"
  "${TOOLCHAIN_PACKAGE_WORK}/SwiftCompilerSDK.h" @ONLY)
configure_file("${CMAKE_CURRENT_LIST_DIR}/Templates/SDKBundle.m.in"
  "${TOOLCHAIN_PACKAGE_WORK}/SDKBundle.m" @ONLY)
execute_process(COMMAND xcrun --sdk "${TOOLCHAIN_APPLE_SDK}" --show-sdk-path
  OUTPUT_VARIABLE sdk OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND xcrun --sdk "${TOOLCHAIN_APPLE_SDK}" clang -target "${TOOLCHAIN_COMPILER_HOST}"
  -isysroot "${sdk}" -fobjc-arc -dynamiclib -framework Foundation
  "-I${TOOLCHAIN_PACKAGE_WORK}" "${TOOLCHAIN_PACKAGE_WORK}/SDKBundle.m"
  -install_name "@rpath/SwiftCompilerSDK.framework/SwiftCompilerSDK"
  -o "${framework}/SwiftCompilerSDK" COMMAND_ERROR_IS_FATAL ANY)
toolchain_framework_module("${framework}" SwiftCompilerSDK "${TOOLCHAIN_PACKAGE_WORK}/SwiftCompilerSDK.h")
toolchain_framework_plist("${framework}" SwiftCompilerSDK)
string(JSON encoded_count LENGTH "${encoded_files}")
message(STATUS "Prepared the verified WASM SDK and ${encoded_count} encoded payload files.")
