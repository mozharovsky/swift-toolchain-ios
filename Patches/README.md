# Compiler patches

`DisableImmediateExecution.patch` applies to Swift commit
`b8189d766d86ad7fc8106787d6ce9e402f38dd72`. It makes immediate native execution an optional frontend
build dependency. The iOS profile disables that option while retaining parsing, type checking,
optimization, object emission, and macro infrastructure.

The upstream default remains enabled. A disabled build reports a compiler diagnostic for immediate
execution. This patch does not establish that every unused process or dynamic-loading path has been
removed from the resulting library. Those paths need a separate artifact audit.

The producer applies contextual hunks without fuzz to the checksum-pinned source archive after
extraction. A changed patch receives a
different source identity so it cannot silently reuse an earlier patched tree. Swift's license and
Runtime Library Exception are retained in `Licenses/Swift.txt`.

`MainActorMacroEntry.patch` renames the C entry of the same pinned Swift source. The producer applies
it only to a copied macro-server file in the macro build directory. The native adapter exports the
original name and invokes the upstream handler on its required main actor. Compiler sources and
compiler output identities remain independent of this macro-only patch.

`AppleFileSystemMetadata.patch` applies to LLVM commit
`903b9faaae5c43ecc9b7e33f8db9c94c7429374a`. The iOS profile attaches a small adapter that reads
path locality through CoreFoundation resource metadata. Descriptor queries request only volume
mount flags and remain valid after unlinking the file. Other LLVM platforms retain their existing
implementation. Disk-capacity queries remain in LLVM's cache-pruning path.

The adapter is covered by native contract tests and linked only when the profile selects it.
Its source, configuration hook, and patch participate in the native cache identity. A changed
filesystem profile cannot reuse the earlier native receipt. LLVM's license and exception are
retained in `Licenses/LLVM.txt`.

`RestrictedLLVMNativeProfile.patch` applies to the same pinned LLVM revision. The iOS profile
defines `SWIFT_TOOLCHAIN_RESTRICTED_NATIVE`, which selects local failures for process execution
and waiting. Mapped-memory allocation and protection reject executable flags, and instruction-cache
invalidation becomes a no-op. LLVM can inspect its existing process handle but cannot open
additional libraries through its generic loader. Host tool builds retain their normal profile.

`RestrictedSwiftNativeProfile.patch` applies to the pinned Swift revision. It rejects process
entry points and executable plugins before resources are created. The frontend accepts explicit
bundled library paths for its macro implementations and in-process server. Resolved-plugin
arguments retain their module names and require an empty executable-server field. Other plugin
search forms produce diagnostics. The dynamic loader uses the canonical path returned by the
producer's shared bundled-plugin validator.

`BundledMacroLibraries.patch` applies to SwiftSyntax commit
`050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf`. Macro preparation applies it to a copied
`LibraryPluginProvider.swift` file. The provider calls the same validator through a private C module
and opens its returned canonical path. This keeps plugin messages subject to the compiler's path
policy. The provider also handles an absent loader-error string without a forced unwrap.

Both native restriction patches participate in source and native-cache identities. The bundled
macro patch participates in the macro cache identity. Archive validation checks the resulting
native imports independently of these source records. Runtime profile tests use the patched
upstream implementations, and bundled-path tests cover symlink redirection and return ownership.
