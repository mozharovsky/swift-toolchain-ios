include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/ArtifactHelpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/SwiftRelease.cmake")

# Packaging and verification use the declared bootstrap release for their maintenance executable.
function(toolchain_payload_codec_swift output)
  get_filename_component(repository "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
  set(compiler "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swift")
  if(NOT IS_ABSOLUTE "${TOOLCHAIN_BOOTSTRAP_ROOT}" OR NOT EXISTS "${compiler}")
    message(FATAL_ERROR "Set TOOLCHAIN_BOOTSTRAP_ROOT to the pinned Swift toolchain usr directory.")
  endif()
  file(READ "${repository}/Toolchain.lock.json" inputs)
  string(JSON expected_version GET "${inputs}" swiftVersion)
  execute_process(COMMAND "${compiler}" --version OUTPUT_VARIABLE version
    COMMAND_ERROR_IS_FATAL ANY)
  toolchain_matches_swift_release(bootstrap_matches "${version}" "${expected_version}")
  if(NOT bootstrap_matches)
    message(FATAL_ERROR "The payload codec bootstrap must match Swift ${expected_version}.")
  endif()
  set(${output} "${compiler}" PARENT_SCOPE)
endfunction()

# The maintenance executable supplies Apple's codec without rebuilding native compiler libraries.
function(toolchain_prepare_payload_codec output)
  get_filename_component(repository "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
  toolchain_payload_codec_swift(compiler)
  execute_process(COMMAND "${compiler}" build --package-path "${repository}"
    --configuration release --product toolchain --jobs 4 COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND "${compiler}" build --package-path "${repository}"
    --configuration release --show-bin-path OUTPUT_VARIABLE directory
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  set(${output} "${directory}/toolchain" PARENT_SCOPE)
endfunction()

# Consumers find each encoded file beside the path it restores, so the name keeps its directory.
function(toolchain_encoded_payload_path output path)
  if(NOT path MATCHES "^(.*[^/])\\.(swiftmodule|a)$")
    message(FATAL_ERROR "The payload encodes only serialized modules and static archives, not ${path}.")
  endif()
  set(${output} "${CMAKE_MATCH_1}.compilerdata" PARENT_SCOPE)
endfunction()

# Xcode strips serialized native-module filenames, and app distribution rejects static archives in
# an application bundle whatever their members contain. Packaging therefore replaces both kinds
# with LZFSE files and returns the records that Materialization.json lists as encodedFiles.
function(toolchain_encode_payload output payload codec)
  file(GLOB_RECURSE inputs LIST_DIRECTORIES FALSE "${payload}/*.swiftmodule" "${payload}/*.a")
  list(SORT inputs)
  set(records "[]")
  set(index 0)
  set(claimed "")
  foreach(input IN LISTS inputs)
    file(RELATIVE_PATH path "${payload}" "${input}")
    toolchain_encoded_payload_path(encoded "${path}")
    # Case-insensitive volumes would let one encoded file replace another with a different case.
    string(TOLOWER "${encoded}" key)
    if(key IN_LIST claimed OR EXISTS "${payload}/${encoded}")
      message(FATAL_ERROR "Another payload file already uses ${encoded}, the encoded path of ${path}.")
    endif()
    list(APPEND claimed "${key}")
    file(SHA256 "${input}" checksum)
    file(SIZE "${input}" decoded_bytes)
    execute_process(COMMAND "${codec}" payload-codec compress "${input}" "${payload}/${encoded}"
      COMMAND_ERROR_IS_FATAL ANY)
    file(REMOVE "${input}")
    toolchain_json_string(path_json "${path}")
    toolchain_json_string(encoded_json "${encoded}")
    string(JSON record SET "{}" path "${path_json}")
    string(JSON record SET "${record}" encodedPath "${encoded_json}")
    string(JSON record SET "${record}" sha256 "\"${checksum}\"")
    string(JSON record SET "${record}" decodedByteCount "${decoded_bytes}")
    string(JSON records SET "${records}" ${index} "${record}")
    math(EXPR index "${index} + 1")
  endforeach()
  set(${output} "${records}" PARENT_SCOPE)
endfunction()

# App distribution does not document whether it detects a static archive by name or by content, so
# packaging and verification reject both an .a name and the ar signature of regular or thin archives.
function(toolchain_find_static_archives output directory)
  file(GLOB_RECURSE files LIST_DIRECTORIES FALSE "${directory}/*")
  list(SORT files)
  set(archives "")
  foreach(file IN LISTS files)
    file(READ "${file}" signature LIMIT 8 HEX)
    if(file MATCHES "\\.[Aa]$" OR signature STREQUAL "213c617263683e0a"
        OR signature STREQUAL "213c7468696e3e0a")
      file(RELATIVE_PATH path "${directory}" "${file}")
      list(APPEND archives "${path}")
    endif()
  endforeach()
  set(${output} "${archives}" PARENT_SCOPE)
endfunction()
