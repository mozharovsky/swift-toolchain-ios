# Compiler bridge

`Sources/CompilerBridge/SwiftCompilerBridge.h` declares C ABI version 1. An embedding application
checks `swift_compiler_abi_version()` before calling the frontend, object reader, or WebAssembly
linker. The real backend uses Swift's `performFrontend`, `autolink_extract_main`, and `lldMain`.
It does not implement a replacement Swift parser or interpreter.

## Ownership and execution

Argument arrays and their strings are borrowed until the synchronous operation returns. The caller
provides valid readable pointers and a trusted compilation recipe. Pointer-shape validation does not
make arbitrary arguments safe to expose to project code.

Every returned diagnostic allocation belongs to the caller. Release it once with
`swift_compiler_release`, including empty messages. `messageLength` excludes the terminating NUL and
preserves embedded NUL bytes. A null pointer can be released safely. Allocation failure returns no
message and marks the process's compiler session nonreusable.

All three operations share one mutex because the upstream libraries retain global state. Separate
threads may call the bridge, but their compiler operations execute in sequence. Consumers must not
bypass that sequence by calling Swift or LLD directly at the same time.

A nonzero exit code can be an ordinary source or argument error. `canRunAgain` distinguishes a
reusable failure from an invalidated native session. Once LLD reports a nonreusable result, later
frontend, linker, and object-reader calls fail before entering the backend. There is no reset API.

Fatal compiler failures can still terminate the process. The C++ boundary does not promise exception,
assertion, signal, or out-of-memory recovery. Frontend diagnostics are captured after compiler setup.
Early setup errors and detailed object-reader errors may also use standard error.

## Contract tests

The small CMake target links the real C ABI wrapper to an explicitly named test backend. It checks
C header linkage, argument validation, owned messages with embedded NUL bytes, ordinary error
recovery, shared serialization, and sticky invalidation. `TOOLCHAIN_ENABLE_SANITIZERS` defaults to
`OFF`. Setting it to `ON` instruments only the host test executable with ASan and UBSan.
`mise run native-check` enables this option. The test backend does not compile or interpret Swift.
Its results are not compiler execution or physical-device evidence.

The production Swift target links `NativeBackend.cpp`. The test backend is never part of that target.
