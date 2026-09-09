include("${TOOLCHAIN_SOURCE_DIR}/CMake/StripNativeSymbols.cmake")
file(MAKE_DIRECTORY "${TOOLCHAIN_TEST_ROOT}")
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef suffix)
set(binary "${TOOLCHAIN_TEST_ROOT}/fixture-${suffix}.dylib")
file(COPY_FILE "${TOOLCHAIN_TEST_LIBRARY}" "${binary}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "TOOLCHAIN_TEST_LIBRARY=${binary}"
  "${TOOLCHAIN_TEST_LOADER}" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND xcrun nm -a -j "${binary}" OUTPUT_VARIABLE symbols_before
  COMMAND_ERROR_IS_FATAL ANY)
foreach(symbol _toolchain_fixture_total _toolchain_fixture_double)
  if(NOT symbols_before MATCHES "${symbol}([\r\n]|$)")
    message(FATAL_ERROR "The fixture must retain local symbols before stripping. ${symbol}")
  endif()
endforeach()
toolchain_strip_native_symbols("${binary}")
execute_process(COMMAND xcrun nm -a -j "${binary}" OUTPUT_VARIABLE symbols_after
  COMMAND_ERROR_IS_FATAL ANY)
foreach(symbol _toolchain_fixture_total _toolchain_fixture_double)
  if(symbols_after MATCHES "${symbol}([\r\n]|$)")
    message(FATAL_ERROR "The fixture still contains a removed local symbol. ${symbol}")
  endif()
endforeach()
# Embedding applications sign rewritten Mach-O images before loading them.
execute_process(COMMAND /usr/bin/codesign --force --sign - "${binary}" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "TOOLCHAIN_TEST_LIBRARY=${binary}"
  "${TOOLCHAIN_TEST_LOADER}" COMMAND_ERROR_IS_FATAL ANY)
file(REMOVE "${binary}")
