include("${CMAKE_CURRENT_LIST_DIR}/ArtifactInputs.cmake")
if(NOT DEFINED TOOLCHAIN_MACRO_OUTPUT OR NOT IS_ABSOLUTE "${TOOLCHAIN_MACRO_OUTPUT}")
  message(FATAL_ERROR "Set TOOLCHAIN_MACRO_OUTPUT to an absolute ignored output directory.")
endif()
if(NOT EXISTS "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swiftc")
  message(FATAL_ERROR "Set TOOLCHAIN_BOOTSTRAP_ROOT to the matching Swift release usr directory.")
endif()
execute_process(COMMAND "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swiftc" --version
  OUTPUT_VARIABLE version COMMAND_ERROR_IS_FATAL ANY)
string(REPLACE "." "\\." version_pattern "${TOOLCHAIN_SWIFT_VERSION}")
if(NOT version MATCHES "Swift version ${version_pattern}([ \n]|$)")
  message(FATAL_ERROR "The macro bootstrap compiler must match Swift ${TOOLCHAIN_SWIFT_VERSION}.")
endif()
file(MAKE_DIRECTORY "${TOOLCHAIN_MACRO_OUTPUT}" "${TOOLCHAIN_MACRO_OUTPUT}/Source")
execute_process(COMMAND xcrun --sdk iphoneos --show-sdk-path
  OUTPUT_VARIABLE sdk OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
file(GLOB syntax_modules
  "${TOOLCHAIN_SWIFT_BUILD}/_deps/compilerswiftsyntax-build/Sources/*/*.swiftmodule")
if(NOT syntax_modules)
  message(FATAL_ERROR "The native compiler build contains no reusable SwiftSyntax modules.")
endif()
set(module_paths "")
foreach(module IN LISTS syntax_modules)
  get_filename_component(directory "${module}" DIRECTORY)
  list(APPEND module_paths -I "${directory}")
endforeach()
set(compiler "${TOOLCHAIN_BOOTSTRAP_ROOT}/bin/swiftc")
set(common -emit-library -emit-module -parse-as-library -O -whole-module-optimization
  -num-threads 1 -swift-version 6 -strict-concurrency=complete -warnings-as-errors
  -target "${TOOLCHAIN_COMPILER_HOST}" -sdk "${sdk}"
  -module-cache-path "${TOOLCHAIN_MACRO_OUTPUT}/ModuleCache"
  -file-prefix-map "${TOOLCHAIN_SOURCE_ROOT}=/toolchain/sources"
  -file-prefix-map "${TOOLCHAIN_MACRO_OUTPUT}=/toolchain/macros"
  -file-prefix-map "${TOOLCHAIN_REPOSITORY_ROOT}=/toolchain/producer"
  -L "${TOOLCHAIN_COMPILER_LIBRARIES}" -L "${TOOLCHAIN_MACRO_OUTPUT}"
  -I "${TOOLCHAIN_MACRO_OUTPUT}"
  -I "${TOOLCHAIN_SYNTAX_SOURCE}/Sources/_SwiftLibraryPluginProviderCShims/include"
  -I "${TOOLCHAIN_SYNTAX_SOURCE}/Sources/_SwiftSyntaxCShims/include" ${module_paths}
  -Xlinker -headerpad_max_install_names -Xlinker -rpath -Xlinker @loader_path)

# The adapter preserves the upstream actor boundary without rebuilding its implementation libraries.
configure_file(
  "${TOOLCHAIN_SWIFT_SOURCE}/tools/swift-plugin-server/Sources/SwiftInProcPluginServer/InProcPluginServer.swift"
  "${TOOLCHAIN_MACRO_OUTPUT}/Source/InProcPluginServer.swift" COPYONLY)
execute_process(COMMAND patch -p1 --forward --input
  "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/MainActorMacroEntry.patch"
  WORKING_DIRECTORY "${TOOLCHAIN_MACRO_OUTPUT}/Source" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND xcrun --sdk iphoneos clang++ -std=c++17 -O2 -fvisibility=hidden
  -target "${TOOLCHAIN_COMPILER_HOST}" -isysroot "${sdk}"
  "-ffile-prefix-map=${TOOLCHAIN_REPOSITORY_ROOT}=/toolchain/producer"
  -c "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.cpp"
  -o "${TOOLCHAIN_MACRO_OUTPUT}/MacroEntry.o" COMMAND_ERROR_IS_FATAL ANY)

foreach(name SwiftLibraryPluginProvider SwiftInProcPluginServer ObservationMacros SwiftMacros)
  if(name STREQUAL "SwiftLibraryPluginProvider")
    set(sources "${TOOLCHAIN_SYNTAX_SOURCE}/Sources/SwiftLibraryPluginProvider/LibraryPluginProvider.swift")
  elseif(name STREQUAL "SwiftInProcPluginServer")
    set(sources "${TOOLCHAIN_MACRO_OUTPUT}/Source/InProcPluginServer.swift"
      "${TOOLCHAIN_MACRO_OUTPUT}/MacroEntry.o")
  else()
    file(GLOB sources "${TOOLCHAIN_SWIFT_SOURCE}/lib/Macros/Sources/${name}/*.swift")
  endif()
  execute_process(COMMAND "${compiler}" ${common}
    -module-name "${name}" -module-link-name "${name}"
    -emit-module-path "${TOOLCHAIN_MACRO_OUTPUT}/${name}.swiftmodule"
    -Xlinker -install_name -Xlinker "@rpath/lib${name}.dylib"
    -o "${TOOLCHAIN_MACRO_OUTPUT}/lib${name}.dylib" ${sources}
    COMMAND_ERROR_IS_FATAL ANY)
endforeach()
message(STATUS "Built macro libraries against the existing compiler support ABI.")
