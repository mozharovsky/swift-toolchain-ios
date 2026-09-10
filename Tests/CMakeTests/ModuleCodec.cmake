file(READ "${TOOLCHAIN_SOURCE_DIR}/Toolchain.lock.json" inputs)
string(JSON version GET "${inputs}" swiftVersion)
file(MAKE_DIRECTORY "${TOOLCHAIN_TEST_ROOT}")
set(probe "${TOOLCHAIN_TEST_ROOT}/probe.cmake")
file(WRITE "${probe}"
  "include(\"${TOOLCHAIN_SOURCE_DIR}/CMake/ModuleCodec.cmake\")\n"
  "toolchain_module_codec_swift(selected)\n"
  "file(WRITE \"\${TOOLCHAIN_RESULT}\" \"\${selected}\")\n")

# Version-only fixtures check compiler selection without starting a Swift build.
function(write_swift root version)
  file(MAKE_DIRECTORY "${root}/bin")
  file(WRITE "${root}/bin/swift" "#!/bin/sh\nprintf '%s\\n' 'Swift version ${version}'\n")
  file(CHMOD "${root}/bin/swift" PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
endfunction()

# A conflicting PATH entry must not change the declared bootstrap selection.
function(check_bootstrap name root expected_error)
  set(result "${TOOLCHAIN_TEST_ROOT}/${name}.txt")
  execute_process(COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=${TOOLCHAIN_TEST_ROOT}/decoy/bin:$ENV{PATH}" "${CMAKE_COMMAND}"
    "-DTOOLCHAIN_BOOTSTRAP_ROOT=${root}" "-DTOOLCHAIN_RESULT=${result}" -P "${probe}"
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT expected_error STREQUAL "")
    if(status EQUAL 0 OR NOT "${output}${error}" MATCHES "${expected_error}")
      message(FATAL_ERROR "The ${name} bootstrap did not report its expected validation failure.")
    endif()
  else()
    if(NOT status EQUAL 0)
      message(FATAL_ERROR "The pinned bootstrap failed validation. ${output}${error}")
    endif()
    file(READ "${result}" selected)
    if(NOT selected STREQUAL "${root}/bin/swift")
      message(FATAL_ERROR "The module codec selected Swift outside its declared bootstrap.")
    endif()
  endif()
endfunction()

write_swift("${TOOLCHAIN_TEST_ROOT}/pinned" "${version}")
write_swift("${TOOLCHAIN_TEST_ROOT}/older" "0.0.0")
write_swift("${TOOLCHAIN_TEST_ROOT}/decoy" "0.0.0")
check_bootstrap(pinned "${TOOLCHAIN_TEST_ROOT}/pinned" "")
check_bootstrap(missing "${TOOLCHAIN_TEST_ROOT}/missing" "pinned Swift toolchain")
check_bootstrap(mismatch "${TOOLCHAIN_TEST_ROOT}/older" "bootstrap must match Swift")
