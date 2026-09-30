# Metadata writers use JSON string escaping rather than concatenate untrusted path syntax.
function(toolchain_json_string output value)
  string(REPLACE "\\" "\\\\" escaped "${value}")
  string(REPLACE "\"" "\\\"" escaped "${escaped}")
  string(REPLACE "\n" "\\n" escaped "${escaped}")
  string(REPLACE "\r" "\\r" escaped "${escaped}")
  string(REPLACE "\t" "\\t" escaped "${escaped}")
  set(${output} "\"${escaped}\"" PARENT_SCOPE)
endfunction()

# Xcode's platform selection metadata must agree with the independently inspected executables.
function(toolchain_inspect_xcframework directory name)
  execute_process(COMMAND plutil -convert json -o - "${directory}/Info.plist"
    OUTPUT_VARIABLE metadata COMMAND_ERROR_IS_FATAL ANY)
  string(JSON count LENGTH "${metadata}" AvailableLibraries)
  if(NOT count EQUAL 2)
    message(FATAL_ERROR "The XCFramework must contain exactly device and simulator libraries.")
  endif()
  set(seen "")
  foreach(index RANGE 1)
    string(JSON slice GET "${metadata}" AvailableLibraries ${index} LibraryIdentifier)
    string(JSON library GET "${metadata}" AvailableLibraries ${index} LibraryPath)
    string(JSON platform GET "${metadata}" AvailableLibraries ${index} SupportedPlatform)
    string(JSON arch_count LENGTH "${metadata}" AvailableLibraries ${index} SupportedArchitectures)
    string(JSON arch GET "${metadata}" AvailableLibraries ${index} SupportedArchitectures 0)
    string(JSON variant ERROR_VARIABLE variant_error
      GET "${metadata}" AvailableLibraries ${index} SupportedPlatformVariant)
    if(slice IN_LIST seen OR NOT library STREQUAL "${name}.framework"
        OR NOT platform STREQUAL "ios" OR NOT arch_count EQUAL 1 OR NOT arch STREQUAL "arm64")
      message(FATAL_ERROR "The XCFramework platform inventory is incompatible.")
    endif()
    list(APPEND seen "${slice}")
    if(slice STREQUAL "ios-arm64")
      if(NOT variant_error)
        message(FATAL_ERROR "The device slice must not declare a platform variant.")
      endif()
    elseif(slice STREQUAL "ios-arm64-simulator")
      if(variant_error OR NOT variant STREQUAL "simulator")
        message(FATAL_ERROR "The simulator slice must declare its platform variant.")
      endif()
    else()
      message(FATAL_ERROR "The XCFramework contains an unsupported library identifier.")
    endif()
  endforeach()
endfunction()

# Framework identities remain valid for SwiftPM, load commands, and generated module maps.
function(toolchain_validate_name name)
  if(NOT name MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
    message(FATAL_ERROR "Artifact names must contain only identifier characters.")
  endif()
endfunction()

# A framework records its deployment floor independently of the guest SDK target.
function(toolchain_framework_plist framework name)
  toolchain_validate_name("${name}")
  string(REGEX REPLACE "[^A-Za-z0-9]" "" identifier "${name}")
  file(WRITE "${framework}/Info.plist"
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\n"
    "<key>CFBundleExecutable</key><string>${name}</string>\n"
    "<key>CFBundleIdentifier</key><string>org.swift.toolchain.ios.${identifier}</string>\n"
    "<key>CFBundlePackageType</key><string>FMWK</string>\n"
    "<key>CFBundleVersion</key><string>1</string>\n"
    "<key>CFBundleShortVersionString</key><string>${TOOLCHAIN_ARTIFACT_VERSION}</string>\n"
    "<key>CFBundleSupportedPlatforms</key><array><string>${TOOLCHAIN_BUNDLE_PLATFORM}</string></array>\n"
    "<key>MinimumOSVersion</key><string>${TOOLCHAIN_DEPLOYMENT_TARGET}</string>\n</dict></plist>\n")
endfunction()

# Native modules need a clang module map only when consumers import their C or Objective-C API.
function(toolchain_framework_module framework name header)
  file(MAKE_DIRECTORY "${framework}/Headers" "${framework}/Modules")
  file(COPY_FILE "${header}" "${framework}/Headers/${name}.h")
  file(WRITE "${framework}/Modules/module.modulemap"
    "framework module ${name} {\n  umbrella header \"${name}.h\"\n  export *\n}\n")
endfunction()

# Platform inspection rejects libraries built for another native environment before repackaging.
function(toolchain_inspect_library binary)
  execute_process(COMMAND xcrun lipo -archs "${binary}"
    OUTPUT_VARIABLE architecture OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND xcrun vtool -show-build "${binary}"
    OUTPUT_VARIABLE platform COMMAND_ERROR_IS_FATAL ANY)
  string(REPLACE "." "\\." deployment_pattern "${TOOLCHAIN_DEPLOYMENT_TARGET}")
  if(NOT architecture STREQUAL "arm64" OR NOT platform MATCHES "platform ${TOOLCHAIN_MACHO_PLATFORM}[\r\n]"
      OR NOT platform MATCHES "minos ${deployment_pattern}[\r\n]")
    message(FATAL_ERROR "The native input must target the selected arm64 iOS platform at the declared deployment floor.")
  endif()
endfunction()
