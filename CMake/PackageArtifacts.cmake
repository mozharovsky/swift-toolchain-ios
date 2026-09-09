include("${CMAKE_CURRENT_LIST_DIR}/ArtifactInputs.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/ArtifactHelpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/VerifyNativeProfile.cmake")
find_program(TOOLCHAIN_ARCHIVE_TOOL NAMES ditto PATHS /usr/bin NO_DEFAULT_PATH REQUIRED)
if(NOT DEFINED TOOLCHAIN_ARTIFACT_OUTPUT OR NOT IS_ABSOLUTE "${TOOLCHAIN_ARTIFACT_OUTPUT}")
  message(FATAL_ERROR "Set TOOLCHAIN_ARTIFACT_OUTPUT to a new absolute ignored output directory.")
endif()
if(EXISTS "${TOOLCHAIN_ARTIFACT_OUTPUT}")
  message(FATAL_ERROR "Choose a new artifact output directory to preserve existing archives.")
endif()
if(NOT TOOLCHAIN_ARTIFACT_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  message(FATAL_ERROR "Set TOOLCHAIN_ARTIFACT_VERSION to three numeric release components.")
endif()
if(NOT EXISTS "${TOOLCHAIN_MACRO_OUTPUT}/libSwiftInProcPluginServer.dylib")
  message(FATAL_ERROR "Run BuildMacros.cmake before packaging compiler artifacts.")
endif()
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/MainActorMacroEntry.patch" macro_patch)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/BundledMacroLibraries.patch" bundled_macro_patch)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.cpp" adapter)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.h" adapter_header)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/CMake/BuildMacros.cmake" recipe)
string(SHA256 macro_identity
  "${TOOLCHAIN_NATIVE_RECEIPT_SHA256}${macro_patch}${bundled_macro_patch}${adapter}${adapter_header}${recipe}")
set(macro_files lib_CompilerSwiftLibraryPluginProvider.dylib libSwiftInProcPluginServer.dylib
  libObservationMacros.dylib libSwiftMacros.dylib)
toolchain_verify_cache("${TOOLCHAIN_MACRO_OUTPUT}/MacroArtifacts.json"
  "${TOOLCHAIN_MACRO_OUTPUT}" "${macro_identity}" ${macro_files})
set(TOOLCHAIN_PACKAGE_WORK "${TOOLCHAIN_ARTIFACT_OUTPUT}/Work")
file(MAKE_DIRECTORY "${TOOLCHAIN_ARTIFACT_OUTPUT}/Frameworks"
  "${TOOLCHAIN_ARTIFACT_OUTPUT}/XCFrameworks" "${TOOLCHAIN_ARTIFACT_OUTPUT}/Archives"
  "${TOOLCHAIN_PACKAGE_WORK}")
set(libraries "")
foreach(input IN LISTS native_files)
  if(input MATCHES "^lib/swift/host/compiler/.*\.dylib$")
    list(APPEND libraries "${TOOLCHAIN_SWIFT_BUILD}/${input}")
  endif()
endforeach()
list(SORT libraries)
list(PREPEND libraries "${TOOLCHAIN_SWIFT_BUILD}/lib/libSwiftCompilerBridge.dylib")
foreach(name _CompilerSwiftLibraryPluginProvider SwiftInProcPluginServer ObservationMacros SwiftMacros)
  list(APPEND libraries "${TOOLCHAIN_MACRO_OUTPUT}/lib${name}.dylib")
endforeach()
set(names "")
set(changes "")
foreach(library IN LISTS libraries)
  toolchain_inspect_library("${library}")
  get_filename_component(filename "${library}" NAME)
  string(REGEX REPLACE "^lib(.*)\\.dylib$" "\\1" name "${filename}")
  toolchain_validate_name("${name}")
  if(name IN_LIST names)
    message(FATAL_ERROR "Native artifact names must be unique.")
  endif()
  list(APPEND names "${name}")
  list(APPEND changes -change "@rpath/${filename}" "@rpath/${name}.framework/${name}")
  set(framework "${TOOLCHAIN_ARTIFACT_OUTPUT}/Frameworks/${name}.framework")
  file(MAKE_DIRECTORY "${framework}")
  file(COPY_FILE "${library}" "${framework}/${name}")
  toolchain_framework_plist("${framework}" "${name}")
endforeach()
foreach(name IN LISTS names)
  set(binary "${TOOLCHAIN_ARTIFACT_OUTPUT}/Frameworks/${name}.framework/${name}")
  execute_process(COMMAND xcrun install_name_tool -id "@rpath/${name}.framework/${name}"
    ${changes} "${binary}" COMMAND_ERROR_IS_FATAL ANY)
endforeach()
toolchain_framework_module("${TOOLCHAIN_ARTIFACT_OUTPUT}/Frameworks/SwiftCompilerBridge.framework"
  SwiftCompilerBridge "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/CompilerBridge/SwiftCompilerBridge.h")
file(COPY_FILE
  "${TOOLCHAIN_REPOSITORY_ROOT}/Resources/SwiftCompilerBridge/PrivacyInfo.xcprivacy"
  "${TOOLCHAIN_ARTIFACT_OUTPUT}/Frameworks/SwiftCompilerBridge.framework/PrivacyInfo.xcprivacy")
include("${CMAKE_CURRENT_LIST_DIR}/PrepareSDK.cmake")
list(APPEND names SwiftCompilerSDK)
include("${CMAKE_CURRENT_LIST_DIR}/PrepareMacroSDK.cmake")

set(artifacts "[]")
set(index 0)
set(package_targets "")
set(product_targets "")
foreach(name IN LISTS names)
  set(framework "${TOOLCHAIN_ARTIFACT_OUTPUT}/Frameworks/${name}.framework")
  toolchain_verify_native_profile("${framework}/${name}")
  set(xcframework "${TOOLCHAIN_ARTIFACT_OUTPUT}/XCFrameworks/${name}.xcframework")
  execute_process(COMMAND xcodebuild -create-xcframework -framework "${framework}"
    -output "${xcframework}" COMMAND_ERROR_IS_FATAL ANY)
  set(archive "${TOOLCHAIN_ARTIFACT_OUTPUT}/Archives/${name}.zip")
  execute_process(COMMAND "${TOOLCHAIN_ARCHIVE_TOOL}" -c -k --keepParent --norsrc "${xcframework}" "${archive}"
    COMMAND_ERROR_IS_FATAL ANY)
  file(SHA256 "${archive}" checksum)
  file(SIZE "${archive}" bytes)
  file(SHA256 "${framework}/${name}" binary_checksum)
  file(SIZE "${framework}/${name}" binary_bytes)
  set(record "{}")
  foreach(field name archive)
    if(field STREQUAL "name")
      set(value "${name}")
    else()
      set(value "${name}.zip")
    endif()
    toolchain_json_string(json_value "${value}")
    string(JSON record SET "${record}" "${field}" "${json_value}")
  endforeach()
  string(JSON record SET "${record}" checksum "\"${checksum}\"")
  string(JSON record SET "${record}" archiveBytes "${bytes}")
  string(JSON record SET "${record}" binaryChecksum "\"${binary_checksum}\"")
  string(JSON record SET "${record}" binaryBytes "${binary_bytes}")
  string(JSON artifacts SET "${artifacts}" ${index} "${record}")
  math(EXPR index "${index} + 1")
  string(APPEND package_targets "        .binaryTarget(name: \"${name}\", path: \"XCFrameworks/${name}.xcframework\"),\n")
  string(APPEND product_targets "\"${name}\", ")
endforeach()
execute_process(COMMAND git -C "${TOOLCHAIN_REPOSITORY_ROOT}" rev-parse HEAD
  OUTPUT_VARIABLE producer_revision OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND git -C "${TOOLCHAIN_REPOSITORY_ROOT}" status --porcelain --untracked-files=normal
  OUTPUT_VARIABLE producer_changes COMMAND_ERROR_IS_FATAL ANY)
set(producer_dirty false)
if(NOT producer_changes STREQUAL "")
  set(producer_dirty true)
endif()
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Licenses/SDKNotices.json" notices_checksum)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.cpp" adapter_checksum)
file(SHA256 "${TOOLCHAIN_LOCK_FILE}" lock_checksum)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/MainActorMacroEntry.patch" macro_patch_checksum)
file(WRITE "${TOOLCHAIN_ARTIFACT_OUTPUT}/ArtifactManifest.json"
  "{\n  \"schemaVersion\": 1,\n  \"version\": \"${TOOLCHAIN_ARTIFACT_VERSION}\",\n"
  "  \"bridgeABI\": 1,\n  \"compilerHost\": \"${TOOLCHAIN_COMPILER_HOST}\",\n"
  "  \"programTarget\": \"${TOOLCHAIN_PROGRAM_TARGET}\",\n"
  "  \"configurationSHA256\": \"${lock_checksum}\",\n"
  "  \"frontendPatchSHA256\": \"${TOOLCHAIN_PATCH_SHA256}\",\n"
  "  \"filesystemMetadataPatchSHA256\": \"${TOOLCHAIN_METADATA_PATCH_SHA256}\",\n"
  "  \"restrictedSwiftPatchSHA256\": \"${TOOLCHAIN_RESTRICTED_SWIFT_PATCH_SHA256}\",\n"
  "  \"restrictedLLVMPatchSHA256\": \"${TOOLCHAIN_RESTRICTED_LLVM_PATCH_SHA256}\",\n"
  "  \"bundledMacroPatchSHA256\": \"${bundled_macro_patch}\",\n"
  "  \"macroPatchSHA256\": \"${macro_patch_checksum}\",\n"
  "  \"producerRevision\": \"${producer_revision}\",\n"
  "  \"producerHasUncommittedChanges\": ${producer_dirty},\n"
  "  \"noticesSHA256\": \"${notices_checksum}\",\n"
  "  \"macroAdapterSHA256\": \"${adapter_checksum}\",\n"
  "  \"macroBuildSupport\": ${macro_sdk_record},\n  \"inputs\": ${TOOLCHAIN_INPUTS},\n  \"artifacts\": ${artifacts}\n}\n")
file(WRITE "${TOOLCHAIN_ARTIFACT_OUTPUT}/Package.swift"
  "// swift-tools-version: 6.3\nimport PackageDescription\n\n"
  "let package = Package(name: \"SwiftCompilerArtifacts\", platforms: [.iOS(.v18)],\n"
  "    products: [.library(name: \"SwiftCompilerArtifacts\", targets: [${product_targets}])],\n"
  "    targets: [\n${package_targets}    ])\n")
message(STATUS "Prepared ${index} checksum-addressed consumer archives.")
