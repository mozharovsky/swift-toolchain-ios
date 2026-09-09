include("${TOOLCHAIN_SOURCE_DIR}/CMake/VerifyNativeProfile.cmake")
if(DEFINED TEST_LIBRARY)
  toolchain_verify_native_profile("${TEST_LIBRARY}")
  return()
endif()
if(DEFINED TEST_IMPORT)
  toolchain_validate_native_imports("Compiler.framework/Compiler" "${TEST_IMPORT}")
  return()
endif()

toolchain_validate_native_imports("Compiler.framework/Compiler"
  "_mmap\n_mprotect\n_dlopen\n_swift_toolchain_copy_bundled_plugin_path\n_forked_value\n")
foreach(symbol _fork _vfork _execv _execve _execvp _execvpe _execl _execle _execlp
    _posix_spawn _posix_spawnp _posix_spawnattr_init _posix_spawn_file_actions_addopen
    _popen _system _sys_icache_invalidate _pthread_jit_write_protect_np "_popen$UNIX2003")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${TOOLCHAIN_SOURCE_DIR}"
    "-DTEST_IMPORT=${symbol}" -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(status EQUAL 0 OR NOT error MATCHES "native compiler profile rejects")
    message(FATAL_ERROR "A disallowed native import was accepted. ${symbol} ${output} ${error}")
  endif()
endforeach()

if(DEFINED TEST_ALLOWED_LIBRARY AND DEFINED TEST_FORBIDDEN_LIBRARY)
  toolchain_verify_native_profile("${TEST_ALLOWED_LIBRARY}")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DTOOLCHAIN_SOURCE_DIR=${TOOLCHAIN_SOURCE_DIR}"
    "-DTEST_LIBRARY=${TEST_FORBIDDEN_LIBRARY}" -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(status EQUAL 0 OR NOT error MATCHES "native compiler profile rejects _system")
    message(FATAL_ERROR "A forbidden import in a native library was accepted. ${output} ${error}")
  endif()
endif()
