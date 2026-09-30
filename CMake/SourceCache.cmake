# A shared preparation graph keeps first-time native plans from replacing prepared source trees.
function(toolchain_add_source name)
  set(preparation "${TOOLCHAIN_CACHE_ROOT}/source-projects/${TOOLCHAIN_${name}_IDENTITY}")
  add_custom_target(source-${name}
    COMMAND "${CMAKE_COMMAND}" -S "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/SourcePreparation"
      -B "${preparation}" -G "${CMAKE_GENERATOR}"
      "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DTOOLCHAIN_REPOSITORY_ROOT=${TOOLCHAIN_REPOSITORY_ROOT}"
      "-DTOOLCHAIN_PATCH=${TOOLCHAIN_PATCH}"
      "-DTOOLCHAIN_SOURCE_NAME=${name}"
      "-DTOOLCHAIN_SOURCE_DIRECTORY=${TOOLCHAIN_${name}_SOURCE}"
      "-DTOOLCHAIN_SOURCE_URL=${TOOLCHAIN_${name}_URL}"
      "-DTOOLCHAIN_SOURCE_SHA256=${TOOLCHAIN_${name}_SHA256}"
      "-DTOOLCHAIN_SOURCE_REVISION=${TOOLCHAIN_${name}_REVISION}"
      "-DTOOLCHAIN_DOWNLOAD_DIRECTORY=${TOOLCHAIN_CACHE_ROOT}/downloads"
    COMMAND "${CMAKE_COMMAND}" --build "${preparation}" --target prepare-source
    VERBATIM)
endfunction()
