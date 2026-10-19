include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/ArtifactHelpers.cmake")

# The SDK's clang driver links this archive into every wasm32 WASI Preview 1 program.
set(TOOLCHAIN_GUEST_BUILTINS_PATH
  "swift.xctoolchain/usr/lib/swift_static/clang/lib/wasip1/libclang_rt.builtins-wasm32.a")
# The rebuild compiles the CMake project in this llvm-project directory with this build type.
set(TOOLCHAIN_GUEST_BUILTINS_SOURCE compiler-rt)
set(TOOLCHAIN_GUEST_BUILTINS_BUILD_TYPE Release)

# The bootstrap clang must come from the pinned LLVM revision, so the rebuilt archive uses the same
# sources and code generator as the archive it replaces.
function(toolchain_builtins_compiler_matches output version revision)
  string(REGEX REPLACE "\r?\n.*" "" first_line "${version}")
  string(LENGTH " ${revision})" suffix_length)
  string(LENGTH "${first_line}" line_length)
  set(matches FALSE)
  if(revision MATCHES "^[a-f0-9]+$" AND line_length GREATER suffix_length
      AND first_line MATCHES "^(Apple )?clang version [0-9]")
    math(EXPR suffix_offset "${line_length} - ${suffix_length}")
    string(SUBSTRING "${first_line}" ${suffix_offset} -1 suffix)
    if(suffix STREQUAL " ${revision})")
      set(matches TRUE)
    endif()
  endif()
  set(${output} "${matches}" PARENT_SCOPE)
  set(${output}_LINE "${first_line}" PARENT_SCOPE)
endfunction()

# Sorted inventories make two archives comparable regardless of member order.
function(toolchain_parse_builtins_symbols defined external text)
  string(REPLACE "\n" ";" lines "${text}")
  set(defined_symbols "")
  set(defined_names "")
  set(references "")
  foreach(line IN LISTS lines)
    if(line MATCHES "^([^ :]+) ([A-Za-z]) ")
      # A nested MATCHES test would overwrite the captured groups.
      set(name "${CMAKE_MATCH_1}")
      set(type "${CMAKE_MATCH_2}")
      if(type MATCHES "^[Uvw]$")
        list(APPEND references "${name}")
      else()
        list(APPEND defined_symbols "${name} ${type}")
        list(APPEND defined_names "${name}")
      endif()
    endif()
  endforeach()
  list(REMOVE_DUPLICATES references)
  if(defined_names)
    list(REMOVE_ITEM references ${defined_names})
  endif()
  list(SORT defined_symbols)
  list(SORT references)
  set(${defined} "${defined_symbols}" PARENT_SCOPE)
  set(${external} "${references}" PARENT_SCOPE)
endfunction()

# A replacement must keep every member and global definition with its binding, so the linker
# resolves the same builtins. It may drop external references but must not add new ones.
function(toolchain_compare_builtins problem count original_members original_symbols
    replacement_members replacement_symbols)
  string(REPLACE "\n" ";" old_members "${original_members}")
  string(REPLACE "\n" ";" new_members "${replacement_members}")
  list(REMOVE_ITEM old_members "")
  list(REMOVE_ITEM new_members "")
  list(SORT old_members)
  list(SORT new_members)
  toolchain_parse_builtins_symbols(old_defined old_external "${original_symbols}")
  toolchain_parse_builtins_symbols(new_defined new_external "${replacement_symbols}")
  set(result "")
  set(added_references "${new_external}")
  if(old_external)
    list(REMOVE_ITEM added_references ${old_external})
  endif()
  if(NOT old_members OR NOT old_members STREQUAL new_members)
    set(result "The rebuilt guest builtins must contain the SDK archive's members.")
  elseif(NOT old_defined OR NOT old_defined STREQUAL new_defined)
    set(result "The rebuilt guest builtins must keep each SDK symbol and its binding.")
  elseif(added_references)
    list(JOIN added_references ", " names)
    set(result "The rebuilt guest builtins reference symbols the SDK archive does not: ${names}.")
  endif()
  list(LENGTH new_defined defined_count)
  set(${problem} "${result}" PARENT_SCOPE)
  set(${count} "${defined_count}" PARENT_SCOPE)
endfunction()

# Archive inspection uses the bootstrap release's LLVM tools, which read wasm32 objects.
function(toolchain_read_builtins members symbols archive)
  set(tools "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin")
  if(NOT IS_ABSOLUTE "${TOOLCHAIN_BOOTSTRAP_ROOT}" OR NOT EXISTS "${tools}/llvm-nm")
    message(FATAL_ERROR "Set TOOLCHAIN_BOOTSTRAP_ROOT to the pinned Swift toolchain usr directory.")
  endif()
  execute_process(COMMAND "${tools}/llvm-ar" t "${archive}" OUTPUT_VARIABLE member_text
    COMMAND_ERROR_IS_FATAL ANY)
  # Members without symbols print a notice on standard error, which carries no inventory.
  execute_process(COMMAND "${tools}/llvm-nm" -g -P "${archive}" OUTPUT_VARIABLE symbol_text
    ERROR_QUIET COMMAND_ERROR_IS_FATAL ANY)
  set(${members} "${member_text}" PARENT_SCOPE)
  set(${symbols} "${symbol_text}" PARENT_SCOPE)
endfunction()

# Swift's WASI build configures these builtins without CMAKE_BUILD_TYPE, so the SDK ships them
# unoptimized. This build keeps the upstream WASI options and adds the release build type and a
# source prefix map that keeps machine paths out of the archive's abort messages.
function(toolchain_build_guest_builtins archive compiler work)
  set(tools "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin")
  if(NOT IS_ABSOLUTE "${TOOLCHAIN_BOOTSTRAP_ROOT}" OR NOT EXISTS "${tools}/clang")
    message(FATAL_ERROR "Set TOOLCHAIN_BOOTSTRAP_ROOT to the pinned Swift toolchain usr directory.")
  endif()
  execute_process(COMMAND "${tools}/clang" --version OUTPUT_VARIABLE version
    COMMAND_ERROR_IS_FATAL ANY)
  toolchain_builtins_compiler_matches(matches "${version}" "${TOOLCHAIN_llvm-project_REVISION}")
  if(NOT matches)
    message(FATAL_ERROR "The bootstrap clang must come from the pinned llvm-project revision.")
  endif()
  # The manifest names the upstream revision, which stays accurate only while no patch edits
  # compiler-rt.
  foreach(patch AppleFileSystemMetadata RestrictedLLVMNativeProfile WebAssemblyMultiDefStackify)
    file(STRINGS "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/${patch}.patch" patched_builtins
      REGEX "^\\+\\+\\+ b/${TOOLCHAIN_GUEST_BUILTINS_SOURCE}/")
    if(patched_builtins)
      message(FATAL_ERROR "The guest builtins rebuild requires unpatched compiler-rt sources.")
    endif()
  endforeach()
  find_program(TOOLCHAIN_NINJA NAMES ninja REQUIRED)
  file(REMOVE_RECURSE "${work}")
  # Upstream compiles the builtins before wasi-libc exists, so its sysroot is empty as well.
  file(MAKE_DIRECTORY "${work}/sysroot")
  execute_process(COMMAND "${CMAKE_COMMAND}"
      -S "${TOOLCHAIN_LLVM_SOURCE}/${TOOLCHAIN_GUEST_BUILTINS_SOURCE}"
      -B "${work}/build" -G Ninja "-DCMAKE_MAKE_PROGRAM=${TOOLCHAIN_NINJA}"
      "-DCMAKE_BUILD_TYPE=${TOOLCHAIN_GUEST_BUILTINS_BUILD_TYPE}"
      "-DCMAKE_C_FLAGS=-ffile-prefix-map=${TOOLCHAIN_LLVM_SOURCE}=llvm-project"
      -DCMAKE_CXX_FLAGS=-fno-exceptions
      "-DCMAKE_SYSROOT=${work}/sysroot" -DCMAKE_STAGING_PREFIX=/
      -DCMAKE_SYSTEM_NAME=WASI -DCMAKE_SYSTEM_PROCESSOR=wasm32 -DUNIX=TRUE
      "-DCMAKE_AR=${tools}/llvm-ar" "-DCMAKE_RANLIB=${tools}/llvm-ranlib"
      "-DCMAKE_C_COMPILER=${tools}/clang" "-DCMAKE_CXX_COMPILER=${tools}/clang++"
      -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 -DCMAKE_CXX_COMPILER_TARGET=wasm32-wasip1
      -DCMAKE_C_COMPILER_WORKS=TRUE -DCMAKE_CXX_COMPILER_WORKS=TRUE
      -DCOMPILER_RT_DEFAULT_TARGET_ARCH=wasm32 -DCOMPILER_RT_DEFAULT_TARGET_ONLY=TRUE
      -DCOMPILER_RT_BAREMETAL_BUILD=TRUE -DCOMPILER_RT_BUILD_BUILTINS=TRUE
      -DCOMPILER_RT_BUILD_PROFILE=FALSE -DCOMPILER_RT_BUILD_CRT=FALSE
      -DCOMPILER_RT_BUILD_XRAY=FALSE -DCOMPILER_RT_INCLUDE_TESTS=FALSE
      -DCOMPILER_RT_HAS_FPIC_FLAG=FALSE -DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=FALSE
      -DCOMPILER_RT_OS_DIR=wasip1
    OUTPUT_FILE "${work}/configure.log" ERROR_FILE "${work}/configure.log"
    RESULT_VARIABLE status)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "Configuring the guest builtins failed. Read ${work}/configure.log.")
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}" --build "${work}/build" --parallel 4
      --target clang_rt.builtins-wasm32
    OUTPUT_FILE "${work}/build.log" ERROR_FILE "${work}/build.log" RESULT_VARIABLE status)
  set(output "${work}/build/lib/wasip1/libclang_rt.builtins-wasm32.a")
  if(NOT status EQUAL 0 OR NOT EXISTS "${output}")
    message(FATAL_ERROR "Building the guest builtins failed. Read ${work}/build.log.")
  endif()
  set(${archive} "${output}" PARENT_SCOPE)
  set(${compiler} "${matches_LINE}" PARENT_SCOPE)
endfunction()

# Each SDK slice replaces its archive only after the rebuilt inventory matches the original.
function(toolchain_install_guest_builtins replaced count payload replacement)
  set(original "${payload}/${TOOLCHAIN_GUEST_BUILTINS_PATH}")
  if(NOT EXISTS "${original}" OR NOT EXISTS "${replacement}")
    message(FATAL_ERROR "Build the guest builtins and extract the SDK before replacing them.")
  endif()
  toolchain_read_builtins(original_members original_symbols "${original}")
  toolchain_read_builtins(replacement_members replacement_symbols "${replacement}")
  toolchain_compare_builtins(problem defined_count "${original_members}" "${original_symbols}"
    "${replacement_members}" "${replacement_symbols}")
  if(problem)
    message(FATAL_ERROR "${problem}")
  endif()
  file(SHA256 "${original}" original_checksum)
  file(COPY_FILE "${replacement}" "${original}")
  set(${replaced} "${original_checksum}" PARENT_SCOPE)
  set(${count} "${defined_count}" PARENT_SCOPE)
endfunction()

# The manifest record lets consumers trace the archive to its sources, compiler, and the SDK
# archive it replaced without unpacking the SDK framework.
function(toolchain_guest_builtins_record output archive compiler replaced count)
  file(SHA256 "${archive}" checksum)
  toolchain_json_string(compiler_json "${compiler}")
  set(record "{}")
  string(JSON record SET "${record}" path "\"${TOOLCHAIN_GUEST_BUILTINS_PATH}\"")
  string(JSON record SET "${record}" component "\"llvm-project\"")
  string(JSON record SET "${record}" revision "\"${TOOLCHAIN_llvm-project_REVISION}\"")
  string(JSON record SET "${record}" sourcePath "\"${TOOLCHAIN_GUEST_BUILTINS_SOURCE}\"")
  string(JSON record SET "${record}" buildType "\"${TOOLCHAIN_GUEST_BUILTINS_BUILD_TYPE}\"")
  string(JSON record SET "${record}" compiler "${compiler_json}")
  string(JSON record SET "${record}" replacedSHA256 "\"${replaced}\"")
  string(JSON record SET "${record}" sha256 "\"${checksum}\"")
  string(JSON record SET "${record}" definedSymbols "${count}")
  set(${output} "${record}" PARENT_SCOPE)
endfunction()
