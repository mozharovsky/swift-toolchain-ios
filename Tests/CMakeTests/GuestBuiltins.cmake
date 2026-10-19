include("${TOOLCHAIN_SOURCE_DIR}/CMake/GuestBuiltins.cmake")

# The compiler check accepts only a clang whose version line ends with the pinned revision.
set(revision 903b9faaae5c43ecc9b7e33f8db9c94c7429374a)
function(check_compiler version expected)
  toolchain_builtins_compiler_matches(actual "${version}" "${revision}")
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Unexpected compiler result ${actual} for ${version}.")
  endif()
endfunction()
check_compiler("Apple clang version 21.0.0 (https://github.com/swiftlang/llvm-project.git ${revision})\nTarget: arm64-apple-darwin27.0.0\n" TRUE)
check_compiler("clang version 21.0.0 (https://github.com/swiftlang/llvm-project.git ${revision})" TRUE)
check_compiler("Apple clang version 21.0.0 (https://github.com/swiftlang/llvm-project.git 903b9faa)" FALSE)
check_compiler("Apple clang version 21.0.0 (https://github.com/swiftlang/llvm-project.git a${revision})" FALSE)
check_compiler("Apple clang version 21.0.0 (clang-2100.0.123.102)\nInstalled from ${revision})" FALSE)
check_compiler("GNU C ${revision})" FALSE)
toolchain_builtins_compiler_matches(line_check "clang version 21.0.0 (x ${revision})\r\nTarget: wasm32" "${revision}")
if(NOT line_check_LINE STREQUAL "clang version 21.0.0 (x ${revision})")
  message(FATAL_ERROR "The compiler record must keep only the first version line.")
endif()

# Inventories follow llvm-nm's POSIX format, where members print as headers before their symbols.
set(members "a.c.o\nb.c.o\nempty.c.o\n")
set(symbols "\na.c.o:\n__a T 1 10\n__b U 0 0\n__stack_pointer U 0 0\nmemcmp U 0 0\n\nb.c.o:\n__b T 1 20\n__weak W 1 5\n__stack_pointer U 0 0\n")
function(expect_comparison replacement_members replacement_symbols expected_message)
  toolchain_compare_builtins(problem count "${members}" "${symbols}" "${replacement_members}"
    "${replacement_symbols}")
  if(expected_message STREQUAL "")
    if(NOT problem STREQUAL "" OR NOT count EQUAL 3)
      message(FATAL_ERROR "A matching replacement was rejected with ${count} symbols. ${problem}")
    endif()
  elseif(NOT problem MATCHES "${expected_message}")
    message(FATAL_ERROR "An invalid replacement returned '${problem}'.")
  endif()
endfunction()

expect_comparison("${members}" "${symbols}" "")
# Optimization may drop references, and member order does not change linker resolution.
expect_comparison("empty.c.o\nb.c.o\na.c.o\n" "\nb.c.o:\n__weak W 1 5\n__b T 1 9\n\na.c.o:\n__a T 1 4\nmemcmp U 0 0\n" "")
expect_comparison("a.c.o\nb.c.o\n" "${symbols}" "members")
expect_comparison("${members}" "\na.c.o:\n__a T 1 10\n\nb.c.o:\n__b T 1 20\n" "its binding")
expect_comparison("${members}" "\na.c.o:\n__a T 1 10\n\nb.c.o:\n__b T 1 20\n__weak T 1 5\n" "its binding")
expect_comparison("${members}" "\na.c.o:\n__a T 1 10\n__extra T 1 2\n\nb.c.o:\n__b T 1 20\n__weak W 1 5\n" "its binding")
expect_comparison("${members}" "\na.c.o:\n__a T 1 10\nmemset U 0 0\n\nb.c.o:\n__b T 1 20\n__weak W 1 5\n" "memset")

# Two empty inventories never count as a match.
toolchain_compare_builtins(problem count "" "" "" "")
if(problem STREQUAL "")
  message(FATAL_ERROR "An empty archive inventory must not match.")
endif()

set(TOOLCHAIN_llvm-project_REVISION "${revision}")
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef identity)
set(archive "${TOOLCHAIN_TEST_ROOT}/${identity}/libclang_rt.builtins-wasm32.a")
file(WRITE "${archive}" "archive bytes\n")
toolchain_guest_builtins_record(record "${archive}" "clang version 21.0.0 (\"quoted\" ${revision})"
  "${revision}${revision}" 218)
file(SHA256 "${archive}" checksum)
string(JSON recorded_path GET "${record}" path)
string(JSON recorded_compiler GET "${record}" compiler)
string(JSON recorded_checksum GET "${record}" sha256)
string(JSON recorded_count GET "${record}" definedSymbols)
string(JSON recorded_type GET "${record}" buildType)
if(NOT recorded_path STREQUAL TOOLCHAIN_GUEST_BUILTINS_PATH
    OR NOT recorded_compiler STREQUAL "clang version 21.0.0 (\"quoted\" ${revision})"
    OR NOT recorded_checksum STREQUAL checksum OR NOT recorded_count EQUAL 218
    OR NOT recorded_type STREQUAL "Release")
  message(FATAL_ERROR "The guest builtins record changed a provenance value. ${record}")
endif()
