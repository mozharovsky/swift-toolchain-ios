# Compiler bridge

`Sources/CompilerBridge/SwiftCompilerBridge.h` declares C ABI version 3. An embedding application
checks `swift_compiler_abi_version()` before calling the frontend, object reader, WebAssembly
linker, completion, or annotation. The real backend uses Swift's `performFrontend`,
`autolink_extract_main`, and `lldMain`. Completion uses Swift's IDE inspection instance, and
annotation type-checks with a compiler instance and Swift's source entity walker. It does not
implement a replacement Swift parser or interpreter.

Version 2 adds semantic completion, and version 3 adds semantic annotation. The earlier operations
and their result layout are unchanged.

The bridge links Swift's compiler implementation modules and initializes them once before entering
the frontend. This registers the AST and SIL classes, analyses, and optimization passes that the
upstream driver normally initializes. Frontend entry alone does not perform that registration.

## Ownership and execution

Argument arrays and their strings are borrowed until the synchronous operation returns. The caller
provides valid readable pointers and a trusted compilation recipe. Pointer-shape validation does not
make arbitrary arguments safe to expose to project code.

Every returned diagnostic allocation belongs to the caller. Release it once with
`swift_compiler_release`, including empty messages. `messageLength` excludes the terminating NUL and
preserves embedded NUL bytes. A null pointer can be released safely. Allocation failure returns no
message and marks the process's compiler session nonreusable.

Every compiler operation shares one mutex because the upstream libraries retain global state. This
includes completion, its reset, and annotation. Separate threads may call the bridge, but their
compiler operations execute in sequence. Consumers must not bypass that sequence by calling Swift
or LLD directly at the same time. When bundled macros are enabled, submit compiler work from a
worker queue and keep the main queue available. Macro callbacks synchronously enter the upstream server on its
required main actor. Blocking the main queue while waiting for another compiler call can prevent
those callbacks from completing.

A nonzero exit code can be an ordinary source or argument error. `canRunAgain` distinguishes a
reusable failure from an invalidated native session. Once LLD reports a nonreusable result, later
frontend, linker, object-reader, completion, and annotation calls fail before entering the backend.
No API restores a nonreusable session. `swift_compiler_reset_completion` only drops completion caches.

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

## Completion

`swift_compiler_complete` lists the completions at a cursor for an editor. Its request names the
same trusted frontend arguments that a compile of the project uses, the input path that a borrowed
source buffer replaces, and the cursor as a UTF-8 byte offset on a character boundary. The bridge
rejects an offset inside a multibyte character. Identifier characters before the cursor become the
filter text, and completion runs at the start of that identifier, as in SourceKit-LSP.

The backend keeps one `IDEInspectionInstance` and one module result cache for the process, as
SourceKit does for a service. A request with the same arguments, path, and cache directory reuses
the type-checked context when the edit and the cursor stay inside one function or accessor body.
Any other request rebuilds the context. A request that names a cache directory keeps the
context-free results of each imported module on disk across launches. A different directory starts
a new context, and `swift_compiler_reset_completion` drops the context and the cache in memory.

Completion takes the same operation lock as the other entry points. A compile therefore delays a
completion, and a completion delays a compile. `swift_compiler_cancel_completion` takes the
caller's request identifier from any thread. It stops a running request at the compiler's next
cancellation check, or a waiting request as soon as it takes the lock. The bridge remembers the
most recent 64 identifiers cancelled before their request ran. Identifiers must stay unique for the
process so a later request is not cancelled by mistake.

Macro expansion during completion uses the same main-queue route as compilation, so a client
calls completion from a worker. A compiler crash during completion ends the process, as a crash
during compilation does.

### Result document

Every completion result carries an owned JSON document with `"schema": 1` and a `status` of
`success`, `failure`, or `cancelled`. The exit code is zero for success,
`SWIFT_COMPILER_COMPLETION_CANCELLED` for cancellation, and one for failure. A failure carries an
`error` string.

A successful document also carries these fields.

- `completionKind` names the syntactic position, such as `dotExpr`, `stmtOrExpr`, `callArg`, or
  `type`.
- `reusedContext` reports whether the cached type-checked context served the request.
- `filterText`, `replacementOffset`, and `replacementLength` describe the identifier prefix that an
  inserted item replaces, in UTF-8 bytes.
- `totalResults`, `matchedResults`, and `hiddenResults` count the compiler's results, those that
  matched the filter, and those left out of an unfiltered list.
- `items` lists at most the requested number of ranked results.
- `diagnostics` lists the first error messages of the type check, and `timingsMs` reports the setup,
  completion, and ranking time.

Each item carries `name`, `description`, `kind`, `type`, `sourceText`, `typeRelation`, `context`,
`module`, `brief`, and `notRecommended`. `sourceText` uses Xcode's placeholder syntax, such as
`<#T##label: Int##Int#>`. Ranking follows SourceKit's result groups, fuzzy matching, and semantic
context without popularity data. An unfiltered list leaves out results that are not recommended or
have an invalid type, and a filtered list ranks them last.

## Annotation

`swift_compiler_annotate` lists the named references in a source file for an editor that colors
them. Its request names the same trusted frontend arguments that a compile of the project uses,
the input path that a borrowed source buffer replaces, and a request identifier. The other inputs
are parsed as secondary files, and only the primary input's function bodies are type-checked.

Every request builds a new compiler instance with the shared macro plugin registry and drops it
before returning. The cost therefore follows the size of the input and does not depend on earlier
requests. Annotation takes the operation lock and the macro rules of completion, and
`swift_compiler_cancel_completion` stops it the same way. Completions and annotations share one
identifier space. A cancelled type check leaves expressions unsolved, so the bridge returns the
cancelled status instead of partial references.

The backend follows SourceKit's semantic annotator. It reports references to declarations and
leaves out implicit references, `self`, unavailable declarations, and the `nil` literal that a
pattern turns into `Optional.none`. A reference to an initializer through its type's name reports
the type. References inside macro expansions and references whose text does not start like an
identifier, such as operators and subscript brackets, are left out. Declarations themselves are not
references, so an editor colors declaration names from syntax.

### Annotation document

Every annotation result carries an owned JSON document with `"schema": 1` and a `status` of
`success`, `failure`, or `cancelled`. The exit code is zero for success,
`SWIFT_COMPILER_COMPLETION_CANCELLED` for cancellation, and one for failure. A failure carries an
`error` string. Source errors still produce a successful document.

A successful document also carries these fields.

- `module` names the main module of the frontend arguments.
- `references` lists the references in source order of the walk. Each carries `offset` and
  `length` in UTF-8 bytes, the referenced declaration's `kind` with the completion item kind
  names, its `module`, and `project`, which is true for declarations of the main module.
- `diagnostics` lists at most 100 errors and warnings. Each carries `severity`, `message`, and
  the UTF-8 `offset` of its location when the location falls in the primary input.
- `timingsMs` reports the setup, type-check, and walk time.

The module comparison decides `project`, because an embedding application can supply its SDK
modules through ordinary import paths, where the compiler treats them as user modules.

## Contract tests

The small CMake target links the real C ABI wrapper to an explicitly named test backend. It checks
C header linkage, argument validation, owned messages with embedded NUL bytes, ordinary error
recovery, shared serialization, and sticky invalidation. Its completion checks cover request
validation, cancellation before and during a run, the reset, and the poisoned session. Its
annotation checks cover request validation, forwarding, cancellation shared with completion, and
the poisoned session.
`TOOLCHAIN_ENABLE_SANITIZERS` defaults to `OFF`. Setting it to `ON` instruments the bridge and bundled-plugin host tests with ASan and UBSan.
`mise run native-check` enables this option. The test backend does not compile or interpret Swift.
Its results are not compiler execution or physical-device evidence.

The bundled-plugin tests exercise canonical paths and owned return buffers. They also change an
alias after validation and verify that the returned path still opens the original bundled file.
Separate upstream profile tests compile the patched process and memory implementations against
matching host LLVM support archives. Those tests execute on the build machine and do not establish
execution of the complete compiler on iPhone.

The production Swift target links `NativeBackend.cpp`, `CompletionBackend.cpp`,
`AnnotationBackend.cpp`, and `SemanticSupport.cpp`. The test backend is never part of that target.
