include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/ArtifactHelpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/SwiftRelease.cmake")

# Guest programs link FoundationEssentials from this SDK archive.
set(TOOLCHAIN_GUEST_FOUNDATION_PATH
  "swift.xctoolchain/usr/lib/swift_static/wasi/libFoundationEssentials.a")
# The rebuild compiles this module directory of the pinned swift-foundation source.
set(TOOLCHAIN_GUEST_FOUNDATION_SOURCE "Sources/FoundationEssentials")
# This patch applies to the module sources with paths relative to the swift-foundation root.
set(TOOLCHAIN_GUEST_FOUNDATION_PATCH "LocaleEnvironment.patch")

# swift-foundation's CMake project lists the module's sources across nested directories. Statements
# are read in file order, so the result follows the order in which CMake adds the sources.
function(toolchain_guest_foundation_sources output directory)
  file(READ "${directory}/CMakeLists.txt" text)
  # An escaped space belongs to a file name, so it must survive the split into tokens.
  string(REPLACE "\\ " "%20" text "${text}")
  string(REGEX MATCHALL
    "(add_library|target_sources)\\(FoundationEssentials[^)]*\\)|add_subdirectory\\([^)]*\\)"
    statements "${text}")
  set(sources "")
  foreach(statement IN LISTS statements)
    if(statement MATCHES "^add_subdirectory\\(([^)]*)\\)$")
      string(STRIP "${CMAKE_MATCH_1}" child)
      toolchain_guest_foundation_sources(child_sources "${directory}/${child}")
      list(APPEND sources ${child_sources})
    else()
      string(REGEX MATCHALL "[^ \t\r\n()]+\\.swift" files "${statement}")
      foreach(file IN LISTS files)
        string(REPLACE "%20" " " file "${file}")
        list(APPEND sources "${directory}/${file}")
      endforeach()
    endif()
  endforeach()
  set(${output} "${sources}" PARENT_SCOPE)
endfunction()

# CMake names each object after its source file and replaces spaces, and the SDK archive keeps
# those names for its members.
function(toolchain_guest_foundation_member output source)
  get_filename_component(name "${source}" NAME)
  string(REPLACE " " "_" name "${name}")
  set(${output} "${name}.obj" PARENT_SCOPE)
endfunction()

# These options follow swift-foundation's CMake project as Swift's WASI SDK build configures it, a
# static Release build with whole-module optimization. An unpatched rebuild with them reproduces
# the SDK's objects, which packaging checks before it replaces any member.
function(toolchain_guest_foundation_options output sdk)
  set(options -target wasm32-unknown-wasip1 -sdk "${sdk}/WASI.sdk"
    -resource-dir "${sdk}/swift.xctoolchain/usr/lib/swift_static"
    -O -wmo -c -parse-as-library -static -module-name FoundationEssentials
    -package-name SwiftFoundation -Xfrontend -Xcc -Xfrontend -D_GNU_SOURCE)
  foreach(feature VariadicGenerics Lifetimes AddressableTypes BuiltinModule AccessLevelOnImport
      StrictConcurrency)
    list(APPEND options -Xfrontend -enable-experimental-feature -Xfrontend "${feature}")
  endforeach()
  foreach(feature InferSendableFromCaptures MemberImportVisibility)
    list(APPEND options -Xfrontend -enable-upcoming-feature -Xfrontend "${feature}")
  endforeach()
  foreach(version 6.0.2 6.1 6.2 6.3 6.4)
    list(APPEND options -Xfrontend -enable-experimental-feature -Xfrontend
      "AvailabilityMacro=FoundationPreview ${version}:macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26")
  endforeach()
  foreach(emulation GETPID SIGNAL MMAN)
    list(APPEND options -Xcc "-D_WASI_EMULATED_${emulation}")
  endforeach()
  foreach(library wasi-emulated-getpid wasi-emulated-signal wasi-emulated-mman _FoundationCShims
      _FoundationCollections swiftSynchronization)
    list(APPEND options -Xfrontend -public-autolink-library -Xfrontend "${library}")
  endforeach()
  set(${output} "${options}" PARENT_SCOPE)
endfunction()

# One compilation writes an object for every source and the module that importers would read.
# Each object embeds a hash that covers the source and object paths. Both builds therefore run in
# one directory with paths relative to it and move their results afterwards. The archive bytes then
# stay the same in every checkout.
function(toolchain_compile_guest_foundation destination compiler sdk sources work)
  set(output "${work}/Objects")
  file(MAKE_DIRECTORY "${output}")
  set(map "{}")
  set(relative_sources "")
  foreach(source IN LISTS sources)
    file(RELATIVE_PATH relative "${work}" "${source}")
    list(APPEND relative_sources "${relative}")
    toolchain_guest_foundation_member(member "${source}")
    toolchain_json_string(object "Objects/${member}")
    string(JSON map SET "${map}" "${relative}" "{\"object\":${object}}")
  endforeach()
  file(WRITE "${output}/OutputFileMap.json" "${map}")
  toolchain_guest_foundation_options(options "${sdk}")
  execute_process(COMMAND "${compiler}" ${options} -num-threads 4 -module-cache-path ModuleCache
      -emit-module -emit-module-path Objects/FoundationEssentials.swiftmodule
      -output-file-map Objects/OutputFileMap.json ${relative_sources}
    WORKING_DIRECTORY "${work}"
    OUTPUT_FILE "${output}/build.log" ERROR_FILE "${output}/build.log" RESULT_VARIABLE status)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "Building FoundationEssentials failed. Read ${output}/build.log.")
  endif()
  file(RENAME "${output}" "${destination}")
endfunction()

# Symbol tables include visibility and binding, which a member's size alone does not show.
function(toolchain_guest_foundation_symbols output directory members)
  execute_process(COMMAND "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/llvm-objdump" -t ${members}
    WORKING_DIRECTORY "${directory}" OUTPUT_FILE "${output}" COMMAND_ERROR_IS_FATAL ANY)
endfunction()

# Swift's WASI SDK reads no locale from the environment, so Locale.current is always en_001. This
# build compiles FoundationEssentials from the pinned swift-foundation source twice, without and
# with the patch, in one source directory. Objects that the patch leaves unchanged are then
# byte-identical, and only the changed members replace the SDK's.
function(toolchain_build_guest_foundation members compiler work)
  set(swiftc "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swiftc")
  if(NOT IS_ABSOLUTE "${TOOLCHAIN_BOOTSTRAP_ROOT}" OR NOT EXISTS "${swiftc}")
    message(FATAL_ERROR "Set TOOLCHAIN_BOOTSTRAP_ROOT to the pinned Swift toolchain usr directory.")
  endif()
  execute_process(COMMAND "${swiftc}" --version OUTPUT_VARIABLE version COMMAND_ERROR_IS_FATAL ANY)
  toolchain_matches_swift_release(matches "${version}" "${TOOLCHAIN_SWIFT_VERSION}")
  if(NOT matches)
    message(FATAL_ERROR "The guest Foundation compiler must match Swift ${TOOLCHAIN_SWIFT_VERSION}.")
  endif()
  string(REGEX REPLACE "\r?\n.*" "" banner "${version}")
  string(JSON expected GET "${TOOLCHAIN_INPUTS}" sdk sha256)
  file(SHA256 "${TOOLCHAIN_SDK_ARCHIVE}" actual)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "The SDK archive checksum does not match Toolchain.lock.json.")
  endif()
  file(REMOVE_RECURSE "${work}")
  file(ARCHIVE_EXTRACT INPUT "${TOOLCHAIN_SDK_ARCHIVE}" DESTINATION "${work}/SDKArchive")
  string(JSON sdk_version GET "${TOOLCHAIN_INPUTS}" sdk version)
  set(sdk "${work}/SDKArchive/${sdk_version}.artifactbundle/${sdk_version}/${TOOLCHAIN_PROGRAM_TARGET}")
  set(archive "${sdk}/${TOOLCHAIN_GUEST_FOUNDATION_PATH}")
  if(NOT EXISTS "${archive}")
    message(FATAL_ERROR "The SDK archive lacks ${TOOLCHAIN_GUEST_FOUNDATION_PATH}.")
  endif()

  set(source "${work}/Source/${TOOLCHAIN_GUEST_FOUNDATION_SOURCE}")
  file(COPY "${TOOLCHAIN_FOUNDATION_SOURCE}/${TOOLCHAIN_GUEST_FOUNDATION_SOURCE}/"
    DESTINATION "${source}")
  toolchain_guest_foundation_sources(sources "${source}")
  set(names "")
  foreach(file IN LISTS sources)
    toolchain_guest_foundation_member(member "${file}")
    list(APPEND names "${member}")
  endforeach()
  set(unique_names "${names}")
  list(REMOVE_DUPLICATES unique_names)
  list(SORT unique_names)
  file(MAKE_DIRECTORY "${work}/Upstream")
  execute_process(COMMAND "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/llvm-ar" x "${archive}"
    WORKING_DIRECTORY "${work}/Upstream" COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/llvm-ar" t "${archive}"
    OUTPUT_VARIABLE upstream_text COMMAND_ERROR_IS_FATAL ANY)
  string(REGEX REPLACE "\n$" "" upstream_text "${upstream_text}")
  string(REPLACE "\n" ";" upstream_names "${upstream_text}")
  list(SORT upstream_names)
  list(LENGTH names count)
  list(LENGTH unique_names unique_count)
  if(NOT count EQUAL unique_count OR NOT unique_names STREQUAL upstream_names)
    message(FATAL_ERROR "The FoundationEssentials sources must match the SDK archive's members.")
  endif()

  toolchain_compile_guest_foundation("${work}/Original" "${swiftc}" "${sdk}" "${sources}" "${work}")
  toolchain_guest_foundation_symbols("${work}/Upstream.symbols" "${work}/Upstream" "${names}")
  toolchain_guest_foundation_symbols("${work}/Original.symbols" "${work}/Original" "${names}")
  file(SHA256 "${work}/Upstream.symbols" upstream_symbols)
  file(SHA256 "${work}/Original.symbols" original_symbols)
  set(reproduced TRUE)
  foreach(member IN LISTS names)
    file(SIZE "${work}/Upstream/${member}" upstream_size)
    file(SIZE "${work}/Original/${member}" original_size)
    if(NOT upstream_size EQUAL original_size)
      set(reproduced FALSE)
    endif()
  endforeach()
  if(NOT reproduced OR NOT upstream_symbols STREQUAL original_symbols)
    message(FATAL_ERROR "The unpatched rebuild must reproduce the SDK's FoundationEssentials objects.")
  endif()

  execute_process(COMMAND patch -p1 --forward --fuzz=0 --input
    "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/${TOOLCHAIN_GUEST_FOUNDATION_PATCH}"
    WORKING_DIRECTORY "${work}/Source" COMMAND_ERROR_IS_FATAL ANY)
  toolchain_compile_guest_foundation("${work}/Patched" "${swiftc}" "${sdk}" "${sources}" "${work}")
  # The SDK's module keeps describing the patched code only while the patch changes no interface.
  file(SHA256 "${work}/Original/FoundationEssentials.swiftmodule" original_module)
  file(SHA256 "${work}/Patched/FoundationEssentials.swiftmodule" patched_module)
  if(NOT original_module STREQUAL patched_module)
    message(FATAL_ERROR "The guest Foundation patch must not change the FoundationEssentials module.")
  endif()
  set(changed "")
  foreach(member IN LISTS names)
    file(SHA256 "${work}/Original/${member}" before)
    file(SHA256 "${work}/Patched/${member}" after)
    if(NOT before STREQUAL after)
      list(APPEND changed "${member}")
    endif()
  endforeach()
  if(NOT "Locale_Cache.swift.obj" IN_LIST changed)
    message(FATAL_ERROR "The guest Foundation patch must change the locale cache object.")
  endif()
  list(SORT changed)
  file(SHA256 "${archive}" upstream_archive)
  set(TOOLCHAIN_GUEST_FOUNDATION_OBJECTS "${work}/Patched" PARENT_SCOPE)
  set(TOOLCHAIN_GUEST_FOUNDATION_UPSTREAM_SHA256 "${upstream_archive}" PARENT_SCOPE)
  set(${members} "${changed}" PARENT_SCOPE)
  set(${compiler} "${banner}" PARENT_SCOPE)
endfunction()

# Each SDK slice replaces the changed members in place. The archive keeps its member order and
# GNU format, and its other members stay byte-identical to the SDK's.
function(toolchain_install_guest_foundation replaced payload objects members)
  set(archive "${payload}/${TOOLCHAIN_GUEST_FOUNDATION_PATH}")
  if(NOT EXISTS "${archive}" OR NOT members)
    message(FATAL_ERROR "Build the guest Foundation objects and extract the SDK before replacing them.")
  endif()
  file(SHA256 "${archive}" original)
  if(NOT original STREQUAL TOOLCHAIN_GUEST_FOUNDATION_UPSTREAM_SHA256)
    message(FATAL_ERROR "The SDK slice holds another FoundationEssentials archive than the rebuild.")
  endif()
  set(tools "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin")
  execute_process(COMMAND "${tools}/llvm-ar" t "${archive}" OUTPUT_VARIABLE before
    COMMAND_ERROR_IS_FATAL ANY)
  set(files "")
  foreach(member IN LISTS members)
    list(APPEND files "${objects}/${member}")
  endforeach()
  execute_process(COMMAND "${tools}/llvm-ar" --format=gnu r "${archive}" ${files}
    COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND "${tools}/llvm-ar" t "${archive}" OUTPUT_VARIABLE after
    COMMAND_ERROR_IS_FATAL ANY)
  if(NOT before STREQUAL after)
    message(FATAL_ERROR "Replacing guest Foundation objects changed the archive's members.")
  endif()
  set(${replaced} "${original}" PARENT_SCOPE)
endfunction()

# The manifest record lets consumers trace the archive to its source, patch, and compiler and to
# the SDK archive it replaced without unpacking the SDK framework.
function(toolchain_guest_foundation_record output checksum compiler replaced members)
  file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/${TOOLCHAIN_GUEST_FOUNDATION_PATCH}" patch)
  toolchain_json_string(compiler_json "${compiler}")
  set(member_json "[]")
  set(index 0)
  foreach(member IN LISTS members)
    toolchain_json_string(name "${member}")
    string(JSON member_json SET "${member_json}" ${index} "${name}")
    math(EXPR index "${index} + 1")
  endforeach()
  set(record "{}")
  string(JSON record SET "${record}" path "\"${TOOLCHAIN_GUEST_FOUNDATION_PATH}\"")
  string(JSON record SET "${record}" component "\"swift-foundation\"")
  string(JSON record SET "${record}" revision "\"${TOOLCHAIN_swift-foundation_REVISION}\"")
  string(JSON record SET "${record}" sourcePath "\"${TOOLCHAIN_GUEST_FOUNDATION_SOURCE}\"")
  string(JSON record SET "${record}" patchSHA256 "\"${patch}\"")
  string(JSON record SET "${record}" compiler "${compiler_json}")
  string(JSON record SET "${record}" members "${member_json}")
  string(JSON record SET "${record}" replacedSHA256 "\"${replaced}\"")
  string(JSON record SET "${record}" sha256 "\"${checksum}\"")
  set(${output} "${record}" PARENT_SCOPE)
endfunction()
