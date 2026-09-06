# Metadata writers use JSON string escaping rather than concatenate untrusted path syntax.
function(toolchain_json_string output value)
  string(REPLACE "\\" "\\\\" escaped "${value}")
  string(REPLACE "\"" "\\\"" escaped "${escaped}")
  string(REPLACE "\n" "\\n" escaped "${escaped}")
  string(REPLACE "\r" "\\r" escaped "${escaped}")
  string(REPLACE "\t" "\\t" escaped "${escaped}")
  set(${output} "\"${escaped}\"" PARENT_SCOPE)
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
    "<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>\n"
    "<key>MinimumOSVersion</key><string>${TOOLCHAIN_DEPLOYMENT_TARGET}</string>\n</dict></plist>\n")
endfunction()

# Native modules need a clang module map only when consumers import their C or Objective-C API.
function(toolchain_framework_module framework name header)
  file(MAKE_DIRECTORY "${framework}/Headers" "${framework}/Modules")
  file(COPY_FILE "${header}" "${framework}/Headers/${name}.h")
  file(WRITE "${framework}/Modules/module.modulemap"
    "framework module ${name} {\n  umbrella header \"${name}.h\"\n  export *\n}\n")
endfunction()

# Platform inspection rejects a same-architecture macOS or simulator library before repackaging.
function(toolchain_inspect_library binary)
  execute_process(COMMAND xcrun lipo -archs "${binary}"
    OUTPUT_VARIABLE architecture OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND xcrun vtool -show-build "${binary}"
    OUTPUT_VARIABLE platform COMMAND_ERROR_IS_FATAL ANY)
  string(REPLACE "." "\\." deployment_pattern "${TOOLCHAIN_DEPLOYMENT_TARGET}")
  if(NOT architecture STREQUAL "arm64" OR NOT platform MATCHES "platform IOS[\r\n]"
      OR NOT platform MATCHES "minos ${deployment_pattern}[\r\n]")
    message(FATAL_ERROR "The native input must target arm64 iOS at the declared deployment floor.")
  endif()
endfunction()
