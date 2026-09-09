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
set(syntax_modules "")
foreach(input IN LISTS native_files)
  if(input MATCHES "\\.swiftmodule$")
    list(APPEND syntax_modules "${TOOLCHAIN_SWIFT_BUILD}/${input}")
  endif()
endforeach()
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
  -I "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/NativeProfile"
  -D SWIFT_TOOLCHAIN_RESTRICTED_NATIVE
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
configure_file(
  "${TOOLCHAIN_SYNTAX_SOURCE}/Sources/SwiftLibraryPluginProvider/LibraryPluginProvider.swift"
  "${TOOLCHAIN_MACRO_OUTPUT}/Source/LibraryPluginProvider.swift" COPYONLY)
execute_process(COMMAND patch -p1 --forward --input
  "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/BundledMacroLibraries.patch"
  WORKING_DIRECTORY "${TOOLCHAIN_MACRO_OUTPUT}/Source" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND xcrun --sdk iphoneos clang++ -std=c++17 -O2 -fvisibility=hidden
  -target "${TOOLCHAIN_COMPILER_HOST}" -isysroot "${sdk}"
  "-ffile-prefix-map=${TOOLCHAIN_REPOSITORY_ROOT}=/toolchain/producer"
  -c "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.cpp"
  -o "${TOOLCHAIN_MACRO_OUTPUT}/MacroEntry.o" COMMAND_ERROR_IS_FATAL ANY)

foreach(name SwiftLibraryPluginProvider SwiftInProcPluginServer ObservationMacros SwiftMacros)
  set(link_name "${name}")
  set(extra_links "")
  if(name STREQUAL "SwiftLibraryPluginProvider")
    set(link_name _CompilerSwiftLibraryPluginProvider)
  endif()
  if(name STREQUAL "SwiftLibraryPluginProvider")
    set(sources "${TOOLCHAIN_MACRO_OUTPUT}/Source/LibraryPluginProvider.swift")
    set(extra_links -L "${TOOLCHAIN_SWIFT_BUILD}/lib" -lSwiftCompilerBridge)
  elseif(name STREQUAL "SwiftInProcPluginServer")
    set(sources "${TOOLCHAIN_MACRO_OUTPUT}/Source/InProcPluginServer.swift"
      "${TOOLCHAIN_MACRO_OUTPUT}/MacroEntry.o")
  else()
    file(GLOB sources "${TOOLCHAIN_SWIFT_SOURCE}/lib/Macros/Sources/${name}/*.swift")
  endif()
  execute_process(COMMAND "${compiler}" ${common}
    -module-name "${name}" -module-link-name "${link_name}" -Xfrontend -module-abi-name -Xfrontend "${link_name}"
    -emit-module-path "${TOOLCHAIN_MACRO_OUTPUT}/${name}.swiftmodule"
    -Xlinker -install_name -Xlinker "@rpath/lib${link_name}.dylib"
    -o "${TOOLCHAIN_MACRO_OUTPUT}/lib${link_name}.dylib" ${sources} ${extra_links}
    COMMAND_ERROR_IS_FATAL ANY)
endforeach()
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/MainActorMacroEntry.patch" macro_patch)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Patches/BundledMacroLibraries.patch" bundled_macro_patch)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.cpp" adapter)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/Sources/MacroBridge/MacroEntry.h" adapter_header)
file(SHA256 "${TOOLCHAIN_REPOSITORY_ROOT}/CMake/BuildMacros.cmake" recipe)
string(SHA256 macro_identity
  "${TOOLCHAIN_NATIVE_RECEIPT_SHA256}${macro_patch}${bundled_macro_patch}${adapter}${adapter_header}${recipe}")
set(macro_files lib_CompilerSwiftLibraryPluginProvider.dylib libSwiftInProcPluginServer.dylib
  libObservationMacros.dylib libSwiftMacros.dylib)
toolchain_record_cache("${TOOLCHAIN_MACRO_OUTPUT}/MacroArtifacts.json"
  "${TOOLCHAIN_MACRO_OUTPUT}" "${macro_identity}" ${macro_files})
message(STATUS "Built macro libraries against the existing compiler support ABI.")
