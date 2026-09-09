# LLVM creates LLVMSupport after project() returns, so the source attachment runs at directory end.
function(toolchain_add_apple_file_metadata)
  if(NOT TARGET LLVMSupport)
    message(FATAL_ERROR "The Apple filesystem adapter requires LLVM's support target.")
  endif()
  get_filename_component(producer "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
  target_sources(LLVMSupport PRIVATE
    "${producer}/Sources/AppleFileSystemMetadata/AppleFileSystemMetadata.cpp")
  target_include_directories(LLVMSupport PRIVATE "${producer}/Sources/AppleFileSystemMetadata")
  target_compile_definitions(LLVMSupport PRIVATE SWIFT_TOOLCHAIN_APPLE_FILE_METADATA=1)
  target_link_libraries(LLVMSupport PUBLIC "-framework CoreFoundation")
endfunction()

cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL toolchain_add_apple_file_metadata)
