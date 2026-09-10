include_guard(GLOBAL)

# The maintenance executable supplies Apple's codec without rebuilding native compiler libraries.
function(toolchain_prepare_module_codec output)
  get_filename_component(repository "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
  find_program(TOOLCHAIN_MAINTENANCE_SWIFT NAMES swift REQUIRED)
  execute_process(COMMAND "${TOOLCHAIN_MAINTENANCE_SWIFT}" build --package-path "${repository}"
    --configuration release --product toolchain --jobs 4 COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND "${TOOLCHAIN_MAINTENANCE_SWIFT}" build --package-path "${repository}"
    --configuration release --show-bin-path OUTPUT_VARIABLE directory
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  set(${output} "${directory}/toolchain" PARENT_SCOPE)
endfunction()
