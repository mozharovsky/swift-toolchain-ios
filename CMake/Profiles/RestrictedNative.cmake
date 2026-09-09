# Native callers share these restrictions regardless of which frontend arguments select a path.
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DSWIFT_TOOLCHAIN_RESTRICTED_NATIVE=1"
  CACHE STRING "The iOS profile rejects subprocesses and executable LLVM memory requests." FORCE)
set(CMAKE_CXX_FLAGS
  "${CMAKE_CXX_FLAGS} -DSWIFT_TOOLCHAIN_RESTRICTED_NATIVE=1 \"-I${TOOLCHAIN_REPOSITORY_ROOT}/Sources/NativeProfile\""
  CACHE STRING "Native compiler libraries share the bundled-plugin policy." FORCE)
