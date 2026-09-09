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
bypass that sequence by calling Swift or LLD directly at the same time. When bundled macros are
enabled, submit compiler work from a worker queue and keep the main queue available. Macro callbacks
synchronously enter the upstream server on its required main actor. Blocking the main queue while
waiting for another compiler call can prevent those callbacks from completing.

A nonzero exit code can be an ordinary source or argument error. `canRunAgain` distinguishes a
reusable failure from an invalidated native session. Once LLD reports a nonreusable result, later
frontend, linker, and object-reader calls fail before entering the backend. There is no reset API.

Fatal compiler failures can still terminate the process. The C++ boundary does not promise exception,
assertion, signal, or out-of-memory recovery. Frontend diagnostics are captured after compiler setup.
Early setup errors and detailed object-reader errors may also use standard error.

## Native profile

The iOS recipes select a restricted native profile. LLVM and Swift process entry points return
failures before spawning or replacing a process. Executable plugins and plugin search options
produce frontend diagnostics. LLVM rejects additional library loads while retaining symbol lookup
through its existing process handle.

LLVM mapped-memory allocation and protection reject `MF_EXEC` with an operation-not-permitted
error. Readable and writable data mappings retain their normal behavior. Instruction-cache
invalidation is a no-op in this profile. Bundled framework images still use the platform loader.

Macro selection uses explicit `-load-plugin-library` arguments or `-load-resolved-plugin`
arguments with an empty executable-server field. Both use `-in-process-plugin-server-path`.
Each library or in-process server path must resolve to a regular file at
`Name.framework/Name` directly inside the main bundle's private frameworks directory.
Executable plugins, external plugin servers, and plugin search directories are unavailable.
Applications keep additional macro implementations in that same bundled framework layout.

The compiler and library-plugin provider share a path validator in `SwiftCompilerBridge`.
It returns an owned canonical path, which the loader opens. A mutable alias therefore cannot
redirect that later open outside the bundle. The embedding application preserves its bundled
files throughout compiler use, and the loader validates the library format. The validator reads
bundle metadata without acquiring the compiler operation mutex, so main-actor macro callbacks
can use it while the frontend is running.

The native profile constrains these compiler entry points. Consumers still supply a trusted
recipe and enforce their own source, filesystem, and resource limits. The profile does not add
crash recovery or certify an application for distribution.

## Contract tests

The small CMake target links the real C ABI wrapper to an explicitly named test backend. It checks
C header linkage, argument validation, owned messages with embedded NUL bytes, ordinary error
recovery, shared serialization, and sticky invalidation. `TOOLCHAIN_ENABLE_SANITIZERS` defaults to
`OFF`. Setting it to `ON` instruments the bridge and bundled-plugin host tests with ASan and UBSan.
`mise run native-check` enables this option. The test backend does not compile or interpret Swift.
Its results are not compiler execution or physical-device evidence.

The bundled-plugin tests exercise canonical paths and owned return buffers. They also change an
alias after validation and verify that the returned path still opens the original bundled file.
Separate upstream profile tests compile the patched process and memory implementations against
matching host LLVM support archives. Those tests execute on the build machine and do not establish
execution of the complete compiler on iPhone.

The production Swift target links `NativeBackend.cpp`. The test backend is never part of that target.
