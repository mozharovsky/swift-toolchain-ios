set(macro_sdk "${TOOLCHAIN_ARTIFACT_OUTPUT}/Development/MacroBuildSupport")
file(MAKE_DIRECTORY "${macro_sdk}/Modules" "${macro_sdk}/Libraries" "${macro_sdk}/Includes")
file(GLOB module_files "${TOOLCHAIN_SWIFT_BUILD}/_deps/compilerswiftsyntax-build/Sources/*/*.swiftmodule")
foreach(module IN LISTS module_files)
  file(COPY "${module}" DESTINATION "${macro_sdk}/Modules")
endforeach()
file(GLOB support_libraries "${TOOLCHAIN_COMPILER_LIBRARIES}/*.dylib")
file(COPY ${support_libraries} DESTINATION "${macro_sdk}/Libraries")
foreach(shim _SwiftSyntaxCShims _SwiftLibraryPluginProviderCShims)
  file(COPY "${TOOLCHAIN_SYNTAX_SOURCE}/Sources/${shim}/include/"
    DESTINATION "${macro_sdk}/Includes/${shim}")
endforeach()
file(COPY "${payload}/Notices" DESTINATION "${macro_sdk}")
file(WRITE "${macro_sdk}/Compatibility.json"
  "{\"schemaVersion\":1,\"swiftVersion\":\"${TOOLCHAIN_SWIFT_VERSION}\","
  "\"compilerHost\":\"${TOOLCHAIN_COMPILER_HOST}\",\"nativeReceiptSHA256\":\"${TOOLCHAIN_NATIVE_RECEIPT_SHA256}\"}\n")
set(macro_sdk_archive "${TOOLCHAIN_ARTIFACT_OUTPUT}/Archives/MacroBuildSupport.zip")
execute_process(COMMAND /usr/bin/ditto -c -k --keepParent --norsrc "${macro_sdk}" "${macro_sdk_archive}"
  COMMAND_ERROR_IS_FATAL ANY)
file(SHA256 "${macro_sdk_archive}" macro_sdk_checksum)
file(SIZE "${macro_sdk_archive}" macro_sdk_bytes)
set(macro_sdk_record "{\"archive\":\"MacroBuildSupport.zip\",\"checksum\":\"${macro_sdk_checksum}\",\"archiveBytes\":${macro_sdk_bytes}}")
