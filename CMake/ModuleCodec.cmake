include_guard(GLOBAL)

# Packaging and verification use the declared bootstrap release for their maintenance executable.
function(toolchain_module_codec_swift output)
  get_filename_component(repository "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
  set(compiler "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swift")
  if(NOT IS_ABSOLUTE "${TOOLCHAIN_BOOTSTRAP_ROOT}" OR NOT EXISTS "${compiler}")
    message(FATAL_ERROR "Set TOOLCHAIN_BOOTSTRAP_ROOT to the pinned Swift toolchain usr directory.")
  endif()
  file(READ "${repository}/Toolchain.lock.json" inputs)
  string(JSON expected_version GET "${inputs}" swiftVersion)
  execute_process(COMMAND "${compiler}" --version OUTPUT_VARIABLE version
    COMMAND_ERROR_IS_FATAL ANY)
  string(REPLACE "." "\\." version_pattern "${expected_version}")
  if(NOT version MATCHES "Swift version ${version_pattern}([ \n]|$)")
    message(FATAL_ERROR "The module codec bootstrap must match Swift ${expected_version}.")
  endif()
  set(${output} "${compiler}" PARENT_SCOPE)
endfunction()

# The maintenance executable supplies Apple's codec without rebuilding native compiler libraries.
function(toolchain_prepare_module_codec output)
  get_filename_component(repository "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
  toolchain_module_codec_swift(compiler)
  execute_process(COMMAND "${compiler}" build --package-path "${repository}"
    --configuration release --product toolchain --jobs 4 COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND "${compiler}" build --package-path "${repository}"
    --configuration release --show-bin-path OUTPUT_VARIABLE directory
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  set(${output} "${directory}/toolchain" PARENT_SCOPE)
endfunction()
