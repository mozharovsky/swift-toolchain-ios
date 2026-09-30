file(REMOVE_RECURSE "${TOOLCHAIN_TEST_ROOT}")
file(MAKE_DIRECTORY "${TOOLCHAIN_TEST_ROOT}/archive" "${TOOLCHAIN_TEST_ROOT}/project")
file(WRITE "${TOOLCHAIN_TEST_ROOT}/archive/source.txt" "Pinned source fixture.\n")
execute_process(COMMAND "${CMAKE_COMMAND}" -E tar czf "${TOOLCHAIN_TEST_ROOT}/source.tar.gz"
  source.txt WORKING_DIRECTORY "${TOOLCHAIN_TEST_ROOT}/archive" COMMAND_ERROR_IS_FATAL ANY)
file(SHA256 "${TOOLCHAIN_TEST_ROOT}/source.tar.gz" checksum)
file(WRITE "${TOOLCHAIN_TEST_ROOT}/project/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.27)
project(SourceCacheFixture NONE)
set(TOOLCHAIN_CACHE_ROOT "${TEST_ROOT}/cache")
set(TOOLCHAIN_fixture_IDENTITY fixture-v1)
set(TOOLCHAIN_fixture_SOURCE "${TOOLCHAIN_CACHE_ROOT}/sources/fixture-v1")
set(TOOLCHAIN_fixture_REVISION v1)
set(TOOLCHAIN_fixture_URL "file://${TEST_ROOT}/source.tar.gz")
set(TOOLCHAIN_fixture_SHA256 "${TEST_CHECKSUM}")
include("${SOURCE_ROOT}/CMake/SourceCache.cmake")
toolchain_add_source(fixture)
]=])
foreach(plan device simulator)
  execute_process(COMMAND "${CMAKE_COMMAND}" -S "${TOOLCHAIN_TEST_ROOT}/project"
    -B "${TOOLCHAIN_TEST_ROOT}/${plan}" -G "${TOOLCHAIN_TEST_GENERATOR}"
    "-DCMAKE_MAKE_PROGRAM=${TOOLCHAIN_TEST_MAKE_PROGRAM}"
    "-DSOURCE_ROOT=${TOOLCHAIN_SOURCE_DIR}" "-DTEST_ROOT=${TOOLCHAIN_TEST_ROOT}"
    "-DTEST_CHECKSUM=${checksum}" COMMAND_ERROR_IS_FATAL ANY)
endforeach()
foreach(plan device simulator)
  execute_process(COMMAND "${CMAKE_COMMAND}" --build "${TOOLCHAIN_TEST_ROOT}/${plan}"
    --target source-fixture COMMAND_ERROR_IS_FATAL ANY)
endforeach()
foreach(plan device simulator device)
  execute_process(COMMAND "${CMAKE_COMMAND}" --build "${TOOLCHAIN_TEST_ROOT}/${plan}"
    --target source-fixture OUTPUT_VARIABLE output ERROR_VARIABLE error
    RESULT_VARIABLE status)
  if(NOT status EQUAL 0 OR output MATCHES "download step|patch step")
    message(FATAL_ERROR "Switching native plans repeated source preparation. ${output} ${error}")
  endif()
endforeach()
file(READ "${TOOLCHAIN_TEST_ROOT}/cache/sources/fixture-v1/source.txt" contents)
if(NOT contents STREQUAL "Pinned source fixture.\n")
  message(FATAL_ERROR "Sharing prepared sources changed their contents.")
endif()
