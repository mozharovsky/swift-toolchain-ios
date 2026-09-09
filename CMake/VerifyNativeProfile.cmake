# Packaging checks imported symbol names before any native library enters an archive.
function(toolchain_validate_native_imports library imports)
  string(REPLACE "\r" "" imports "${imports}")
  string(REPLACE "\n" ";" symbols "${imports}")
  set(forbidden
    "^_(fork|vfork|execv|execve|execvp|execvpe|execl|execle|execlp|posix_spawn|posix_spawnp|posix_spawnattr_[A-Za-z0-9_]+|posix_spawn_file_actions_[A-Za-z0-9_]+|popen|system|sys_icache_invalidate|pthread_jit_[A-Za-z0-9_]+)(\\$[A-Za-z0-9_]+)?$")
  foreach(symbol IN LISTS symbols)
    string(STRIP "${symbol}" symbol)
    if(symbol MATCHES "${forbidden}")
      message(FATAL_ERROR
        "The native compiler profile rejects ${symbol} in ${library}. Rebuild the restricted native artifacts.")
    endif()
  endforeach()
endfunction()

# Packaging and host fixtures request symbol names so tool formatting cannot bypass the policy.
function(toolchain_verify_native_profile library)
  execute_process(COMMAND xcrun nm -u -j "${library}" OUTPUT_VARIABLE imports
    ERROR_VARIABLE error RESULT_VARIABLE status)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "Could not inspect native imports in ${library}. ${error}")
  endif()
  toolchain_validate_native_imports("${library}" "${imports}")
endfunction()
