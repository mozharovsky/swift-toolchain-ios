set(TOOLCHAIN_PLATFORM device)
include("${CMAKE_CURRENT_LIST_DIR}/ArtifactInputs.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/ArtifactHelpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/StripNativeSymbols.cmake")
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
if(NOT DEFINED TOOLCHAIN_SIMULATOR_MACRO_OUTPUT)
  message(FATAL_ERROR "Provide TOOLCHAIN_SIMULATOR_MACRO_OUTPUT alongside device macro inputs.")
endif()
set(device_macro_output "${TOOLCHAIN_MACRO_OUTPUT}")
file(MAKE_DIRECTORY "${TOOLCHAIN_ARTIFACT_OUTPUT}/XCFrameworks"
  "${TOOLCHAIN_ARTIFACT_OUTPUT}/Archives")

# Each platform verifies its own native receipt before its libraries enter an XCFramework.
function(toolchain_prepare_platform platform macro_output)
  set(TOOLCHAIN_PLATFORM "${platform}")
  set(TOOLCHAIN_MACRO_OUTPUT "${macro_output}")
  include("${CMAKE_CURRENT_LIST_DIR}/PrepareNativeFrameworks.cmake")
  set(${platform}_names "${names}" PARENT_SCOPE)
endfunction()
toolchain_prepare_platform(device "${device_macro_output}")
toolchain_prepare_platform(simulator "${TOOLCHAIN_SIMULATOR_MACRO_OUTPUT}")
if(NOT device_names STREQUAL simulator_names)
  message(FATAL_ERROR "Device and simulator framework inventories must match.")
endif()
set(names "${device_names}")
set(macro_sdk "${TOOLCHAIN_ARTIFACT_OUTPUT}/Development/MacroBuildSupport")
set(macro_sdk_archive "${TOOLCHAIN_ARTIFACT_OUTPUT}/Archives/MacroBuildSupport.zip")
execute_process(COMMAND "${TOOLCHAIN_ARCHIVE_TOOL}" -c -k --keepParent --norsrc "${macro_sdk}" "${macro_sdk_archive}"
  COMMAND_ERROR_IS_FATAL ANY)
file(SHA256 "${macro_sdk_archive}" macro_sdk_checksum)
file(SIZE "${macro_sdk_archive}" macro_sdk_bytes)
set(macro_sdk_record "{\"archive\":\"MacroBuildSupport.zip\",\"checksum\":\"${macro_sdk_checksum}\",\"archiveBytes\":${macro_sdk_bytes}}")

set(artifacts "[]")
set(index 0)
set(package_targets "")
set(product_targets "")
foreach(name IN LISTS names)
  set(framework_arguments "")
  set(slices "[]")
  set(slice_index 0)
  foreach(slice ios-arm64 ios-arm64-simulator)
    set(framework "${TOOLCHAIN_ARTIFACT_OUTPUT}/Frameworks/${slice}/${name}.framework")
    toolchain_strip_native_symbols("${framework}/${name}")
    toolchain_verify_native_profile("${framework}/${name}")
    file(SHA256 "${framework}/${name}" binary_checksum)
    file(SIZE "${framework}/${name}" binary_bytes)
    set(host "${TOOLCHAIN_COMPILER_HOST}")
    if(slice STREQUAL "ios-arm64-simulator")
      string(APPEND host "-simulator")
    endif()
    set(slice_record "{\"identifier\":\"${slice}\",\"compilerHost\":\"${host}\",\"binaryChecksum\":\"${binary_checksum}\",\"binaryBytes\":${binary_bytes}}")
    string(JSON slices SET "${slices}" ${slice_index} "${slice_record}")
    math(EXPR slice_index "${slice_index} + 1")
    list(APPEND framework_arguments -framework "${framework}")
  endforeach()
  set(xcframework "${TOOLCHAIN_ARTIFACT_OUTPUT}/XCFrameworks/${name}.xcframework")
  execute_process(COMMAND xcodebuild -create-xcframework ${framework_arguments}
    -output "${xcframework}" COMMAND_ERROR_IS_FATAL ANY)
  set(archive "${TOOLCHAIN_ARTIFACT_OUTPUT}/Archives/${name}.zip")
  execute_process(COMMAND "${TOOLCHAIN_ARCHIVE_TOOL}" -c -k --keepParent --norsrc "${xcframework}" "${archive}"
    COMMAND_ERROR_IS_FATAL ANY)
  file(SHA256 "${archive}" checksum)
  file(SIZE "${archive}" bytes)
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
  string(JSON record SET "${record}" slices "${slices}")
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
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/BundledMacroLibraries.patch" bundled_macro_patch)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Licenses/SDKNotices.json" notices_checksum)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.cpp" adapter_checksum)
file(SHA256 "${TOOLCHAIN_LOCK_FILE}" lock_checksum)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/MainActorMacroEntry.patch" macro_patch_checksum)
file(WRITE "${TOOLCHAIN_ARTIFACT_OUTPUT}/ArtifactManifest.json"
  "{\n  \"schemaVersion\": 2,\n  \"version\": \"${TOOLCHAIN_ARTIFACT_VERSION}\",\n"
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
