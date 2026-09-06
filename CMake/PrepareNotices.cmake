set(notices "${payload}/Notices")
file(MAKE_DIRECTORY "${notices}/Native")
file(COPY "${TOOLCHAIN_REPOSITORY_ROOT}/LICENSE" "${TOOLCHAIN_REPOSITORY_ROOT}/NOTICE"
  DESTINATION "${notices}")
set(native_notices
  "swift|LICENSE.txt|Swift.txt"
  "swift-syntax|LICENSE.txt|SwiftSyntax.txt"
  "swift-cmark|COPYING|Cmark.txt"
  "string-processing|LICENSE.txt|StringProcessing.txt"
  "llvm-project|llvm/LICENSE.TXT|LLVM.txt"
  "llvm-project|clang/LICENSE.TXT|Clang.txt"
  "llvm-project|lld/LICENSE.TXT|LLD.txt"
  "llvm-project|libcxx/LICENSE.TXT|LibCXX.txt"
  "llvm-project|libcxxabi/LICENSE.TXT|LibCXXABI.txt"
  "llvm-project|compiler-rt/LICENSE.TXT|CompilerRT.txt"
  "llvm-project|llvm/lib/Support/BLAKE3/LICENSE|BLAKE3.txt"
  "llvm-project|llvm/include/llvm/Support/LICENSE.TXT|LLVMSupport.txt")
set(records "[]")
set(index 0)
foreach(entry IN LISTS native_notices)
  string(REPLACE "|" ";" fields "${entry}")
  list(GET fields 0 component)
  list(GET fields 1 source_path)
  list(GET fields 2 filename)
  set(source "${TOOLCHAIN_${component}_SOURCE}/${source_path}")
  file(COPY_FILE "${source}" "${notices}/Native/${filename}")
  file(SHA256 "${source}" checksum)
  set(record "{}")
  string(JSON record SET "${record}" component "\"${component}\"")
  string(JSON record SET "${record}" revision "\"${TOOLCHAIN_${component}_REVISION}\"")
  string(JSON record SET "${record}" path "\"Native/${filename}\"")
  string(JSON record SET "${record}" sha256 "\"${checksum}\"")
  string(JSON records SET "${records}" ${index} "${record}")
  math(EXPR index "${index} + 1")
endforeach()
file(READ "${TOOLCHAIN_REPOSITORY_ROOT}/Licenses/SDKNotices.json" sdk_notices)
string(JSON notice_sdk GET "${sdk_notices}" sdkVersion)
if(NOT notice_sdk STREQUAL sdk_version)
  message(FATAL_ERROR "The SDK notices must match the selected SDK release.")
endif()
string(JSON count LENGTH "${sdk_notices}" sources)
math(EXPR last "${count} - 1")
foreach(number RANGE ${last})
  string(JSON path GET "${sdk_notices}" sources ${number} path)
  string(JSON expected GET "${sdk_notices}" sources ${number} sha256)
  if(NOT path MATCHES "^TargetLibraries/" OR path MATCHES "(^|/)\\.\\.(/|$)")
    message(FATAL_ERROR "SDK notice paths must stay inside the notice source directory.")
  endif()
  set(source "${TOOLCHAIN_REPOSITORY_ROOT}/Licenses/${path}")
  file(SHA256 "${source}" actual)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "A pinned SDK notice changed without updating its identity.")
  endif()
  get_filename_component(parent "${notices}/${path}" DIRECTORY)
  file(MAKE_DIRECTORY "${parent}")
  file(COPY_FILE "${source}" "${notices}/${path}")
endforeach()
file(WRITE "${notices}/NativeSources.json" "{\"schemaVersion\":1,\"sources\":${records}}\n")
file(WRITE "${notices}/SDKSources.json" "${sdk_notices}")
