include("${TOOLCHAIN_SOURCE_DIR}/CMake/GuestFoundation.cmake")

string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef identity)
set(root "${TOOLCHAIN_TEST_ROOT}/${identity}")

# Sources follow statement order across nested directories, and other targets' sources stay out.
file(WRITE "${root}/Module/CMakeLists.txt" "add_library(FoundationEssentials
  First.swift
  Collection\\ Defaults.swift)
add_subdirectory(Locale)
target_sources(FoundationEssentials PRIVATE Last.swift)
target_sources(FoundationMacros PRIVATE Macro.swift)
")
file(WRITE "${root}/Module/Locale/CMakeLists.txt"
  "target_sources(FoundationEssentials PRIVATE\n  Locale.swift\n  Locale_Cache.swift)\n")
toolchain_guest_foundation_sources(sources "${root}/Module")
set(expected "${root}/Module/First.swift" "${root}/Module/Collection Defaults.swift"
  "${root}/Module/Locale/Locale.swift" "${root}/Module/Locale/Locale_Cache.swift"
  "${root}/Module/Last.swift")
if(NOT sources STREQUAL expected)
  message(FATAL_ERROR "Unexpected guest Foundation sources ${sources}.")
endif()

# Archive members keep the file name and replace its spaces.
toolchain_guest_foundation_member(member "${root}/Module/Collection Defaults.swift")
if(NOT member STREQUAL "Collection_Defaults.swift.obj")
  message(FATAL_ERROR "Unexpected guest Foundation member ${member}.")
endif()

set(TOOLCHAIN_REPOSITORY_ROOT "${TOOLCHAIN_SOURCE_DIR}")
set(TOOLCHAIN_swift-foundation_REVISION 3b9d8f42b7923a7c1ae9ce20f3b05d1facac334e)
toolchain_guest_foundation_record(record "${identity}${identity}"
  "Swift version 6.4 (\"quoted\" swift-6.4-RELEASE)" "${identity}"
  "Locale.swift.obj;Locale_Cache.swift.obj")
file(SHA256 "${TOOLCHAIN_SOURCE_DIR}/Patches/${TOOLCHAIN_GUEST_FOUNDATION_PATCH}" patch)
string(JSON recorded_path GET "${record}" path)
string(JSON recorded_revision GET "${record}" revision)
string(JSON recorded_patch GET "${record}" patchSHA256)
string(JSON recorded_compiler GET "${record}" compiler)
string(JSON recorded_count LENGTH "${record}" members)
string(JSON recorded_member GET "${record}" members 1)
string(JSON recorded_replaced GET "${record}" replacedSHA256)
string(JSON recorded_checksum GET "${record}" sha256)
if(NOT recorded_path STREQUAL TOOLCHAIN_GUEST_FOUNDATION_PATH
    OR NOT recorded_revision STREQUAL TOOLCHAIN_swift-foundation_REVISION
    OR NOT recorded_patch STREQUAL patch
    OR NOT recorded_compiler STREQUAL "Swift version 6.4 (\"quoted\" swift-6.4-RELEASE)"
    OR NOT recorded_count EQUAL 2 OR NOT recorded_member STREQUAL "Locale_Cache.swift.obj"
    OR NOT recorded_replaced STREQUAL identity
    OR NOT recorded_checksum STREQUAL "${identity}${identity}")
  message(FATAL_ERROR "The guest Foundation record changed a provenance value. ${record}")
endif()
