# Native stages must rerun configuration after an input changes, including explicit step targets.
function(toolchain_watch_configuration name)
  ExternalProject_Add_Step(${name} configuration-inputs
    DEPENDEES patch
    DEPENDERS configure
    DEPENDS ${ARGN})
endfunction()
