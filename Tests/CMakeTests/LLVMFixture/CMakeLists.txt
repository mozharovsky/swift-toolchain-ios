cmake_minimum_required(VERSION 3.27)
project(LLVM LANGUAGES CXX)

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/Empty.cpp" "int fixture() { return 0; }\n")
add_library(LLVMSupport STATIC "${CMAKE_CURRENT_BINARY_DIR}/Empty.cpp")

# The producer hook must attach its adapter after LLVM has created its support target.
function(verify_metadata_attachment)
  get_target_property(sources LLVMSupport SOURCES)
  get_target_property(definitions LLVMSupport COMPILE_DEFINITIONS)
  get_target_property(libraries LLVMSupport LINK_LIBRARIES)
  if(NOT sources MATCHES "AppleFileSystemMetadata.cpp"
      OR NOT "SWIFT_TOOLCHAIN_APPLE_FILE_METADATA=1" IN_LIST definitions
      OR NOT libraries MATCHES "CoreFoundation")
    message(FATAL_ERROR "The LLVM metadata adapter is missing a source, definition, or dependency.")
  endif()
endfunction()

cmake_language(DEFER CALL verify_metadata_attachment)
