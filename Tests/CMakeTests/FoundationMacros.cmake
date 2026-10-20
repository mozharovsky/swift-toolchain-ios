include("${TOOLCHAIN_SOURCE_DIR}/CMake/FoundationMacros.cmake")
if(LIST_ONLY)
  set(TOOLCHAIN_FOUNDATION_SOURCE "${CASE_ROOT}")
  toolchain_foundation_macro_sources(sources)
  message(STATUS "sources=${sources}")
  return()
endif()
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef identity)
set(root "${TOOLCHAIN_TEST_ROOT}/${identity}")
set(macros "${root}/Sources/FoundationMacros")
file(MAKE_DIRECTORY "${macros}")

# A missing inventory stops macro preparation, so each case runs in another CMake process.
function(expect_sources expected_success expected_text)
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${TOOLCHAIN_SOURCE_DIR}"
    "-DCASE_ROOT=${root}" -DLIST_ONLY=ON -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(expected_success)
    if(NOT status EQUAL 0 OR NOT output MATCHES "${expected_text}")
      message(FATAL_ERROR "The Foundation macro inventory is wrong. ${output} ${error}")
    endif()
  elseif(status EQUAL 0 OR NOT error MATCHES "${expected_text}")
    message(FATAL_ERROR "An empty Foundation macro source returned ${status}. ${output} ${error}")
  endif()
endfunction()

expect_sources(FALSE "contains no Foundation macro sources")
file(WRITE "${macros}/PredicateMacro.swift" "struct PredicateMacro {}\n")
file(WRITE "${macros}/BundleMacro.swift" "struct BundleMacro {}\n")
file(WRITE "${macros}/CMakeLists.txt" "add_library(FoundationMacros)\n")
expect_sources(TRUE
  "sources=Source/FoundationMacros/BundleMacro.swift;Source/FoundationMacros/PredicateMacro.swift\n")
