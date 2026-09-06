string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef run_identity)
set(test_root "${TOOLCHAIN_TEST_ROOT}/${run_identity}")
set(source "${test_root}/source")
set(build "${test_root}/build")
file(MAKE_DIRECTORY "${source}")
file(COPY "${TOOLCHAIN_SOURCE_DIR}/Tests/CMakeTests/Fixture/" DESTINATION "${source}")
set(input_files Profile.cmake Common.cmake Toolchain.lock.json)
foreach(input IN LISTS input_files)
  file(WRITE "${source}/${input}" "initial\n")
endforeach()

# A failed configure or build must retain its output in the CTest failure report.
function(run_checked)
  execute_process(COMMAND ${ARGN} RESULT_VARIABLE status
    OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "Fixture command failed with ${status}.\n${output}\n${error}")
  endif()
endfunction()

# Repeated builds must preserve the configure count until an input file changes.
function(expect_configure_count expected)
  run_checked("${CMAKE_COMMAND}" --build "${build}" --target example-configure --parallel 4)
  file(STRINGS "${build}/configure.log" runs)
  list(LENGTH runs count)
  if(NOT count EQUAL expected)
    message(FATAL_ERROR "Expected ${expected} configure executions, received ${count}.")
  endif()
endfunction()

run_checked("${CMAKE_COMMAND}" -S "${source}" -B "${build}"
  -G "${TOOLCHAIN_TEST_GENERATOR}"
  "-DCMAKE_MAKE_PROGRAM=${TOOLCHAIN_TEST_MAKE_PROGRAM}"
  "-DTOOLCHAIN_SOURCE_DIR=${TOOLCHAIN_SOURCE_DIR}")
expect_configure_count(1)
expect_configure_count(1)
set(expected 1)
foreach(input IN LISTS input_files)
  # Makefile generators compare timestamps at whole-second resolution.
  run_checked("${CMAKE_COMMAND}" -E sleep 1.1)
  file(APPEND "${source}/${input}" "changed\n")
  math(EXPR expected "${expected} + 1")
  expect_configure_count(${expected})
  expect_configure_count(${expected})
endforeach()
