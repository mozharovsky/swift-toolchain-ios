function(swift_toolchain_add_bridge)
  add_subdirectory("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../Sources/CompilerBridge"
    "${CMAKE_BINARY_DIR}/compiler-bridge")
endfunction()

# Swift declares its frontend targets after project() returns.
cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL swift_toolchain_add_bridge)
