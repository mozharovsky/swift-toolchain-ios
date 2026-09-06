cmake_minimum_required(VERSION 3.27)
project(ConfigurationInputFixture NONE)
include(ExternalProject)
include("${TOOLCHAIN_SOURCE_DIR}/CMake/ConfigurationInputs.cmake")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/empty")
ExternalProject_Add(example
  SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/empty"
  DOWNLOAD_COMMAND ""
  UPDATE_COMMAND ""
  CONFIGURE_COMMAND "${CMAKE_COMMAND}"
    "-DCONFIGURE_LOG=${CMAKE_CURRENT_BINARY_DIR}/configure.log"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/RecordConfigure.cmake"
  BUILD_COMMAND ""
  INSTALL_COMMAND ""
  STEP_TARGETS configure
  EXCLUDE_FROM_ALL TRUE)
toolchain_watch_configuration(example
  "${CMAKE_CURRENT_SOURCE_DIR}/Profile.cmake"
  "${CMAKE_CURRENT_SOURCE_DIR}/Common.cmake"
  "${CMAKE_CURRENT_SOURCE_DIR}/Toolchain.lock.json")
