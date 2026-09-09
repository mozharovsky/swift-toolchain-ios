# Remove local symbols in a temporary copy of a staged thin Mach-O library.
# Replacement requires unchanged global symbol names and a size that does not increase.
function(toolchain_strip_native_symbols binary)
  set(stripped "${binary}.stripped")
  if(EXISTS "${stripped}")
    message(FATAL_ERROR "The symbol-stripping output already exists. Use a fresh staging directory.")
  endif()
  execute_process(COMMAND xcrun nm -g -U -j "${binary}" OUTPUT_VARIABLE exports_before
    COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND xcrun nm -u -j "${binary}" OUTPUT_VARIABLE imports_before
    COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND xcrun strip -x -o "${stripped}" "${binary}"
    COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND xcrun nm -g -U -j "${stripped}" OUTPUT_VARIABLE exports_after
    COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND xcrun nm -u -j "${stripped}" OUTPUT_VARIABLE imports_after
    COMMAND_ERROR_IS_FATAL ANY)
  if(NOT exports_before STREQUAL exports_after OR NOT imports_before STREQUAL imports_after)
    message(FATAL_ERROR "Stripping changed a framework's global symbols. Inspect the staged copies.")
  endif()
  file(SIZE "${binary}" bytes_before)
  file(SIZE "${stripped}" bytes_after)
  if(bytes_after GREATER bytes_before)
    message(FATAL_ERROR "Stripping increased a framework's size. Inspect the staged copies.")
  endif()
  file(RENAME "${stripped}" "${binary}")
endfunction()
