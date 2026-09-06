# Swift declares its frontend targets after project() returns, and deferred calls cannot add directories.
function(swift_toolchain_add_bridge)
  # Initial cache files do not retain these ordinary variables in the later project scope.
  include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Inputs.cmake")
  include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../Sources/CompilerBridge/CMakeLists.txt")
endfunction()

cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL swift_toolchain_add_bridge)
