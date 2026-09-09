/// An accumulator whose local symbol is removed before serial fixture calls.
static unsigned toolchain_fixture_total;

/// Retains a local call target whose symbol is removed during packaging tests.
static unsigned toolchain_fixture_double(unsigned value) {
  return value * 2;
}

/// Exercises local code and data through an exported entry point for serial loader calls.
unsigned toolchain_symbol_fixture(unsigned value) {
  toolchain_fixture_total += toolchain_fixture_double(value);
  return toolchain_fixture_total;
}
