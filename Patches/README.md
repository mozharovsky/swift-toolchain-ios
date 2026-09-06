# Compiler patches

`DisableImmediateExecution.patch` applies to Swift commit
`cd8d8ad0019e4e291906b311e0d25d7039cddc9c`. It makes immediate native execution an optional frontend
build dependency. The iOS profile disables that option while retaining parsing, type checking,
optimization, object emission, and macro infrastructure.

The upstream default remains enabled. A disabled build reports a compiler diagnostic for immediate
execution. This patch does not establish that every unused process or dynamic-loading path has been
removed from the resulting library. Those paths need a separate artifact audit.

The producer applies exact line hunks to the checksum-pinned source archive after extraction. A changed patch receives a
different source identity so it cannot silently reuse an earlier patched tree. Swift's license and
Runtime Library Exception are retained in `Licenses/Swift.txt`.

`MainActorMacroEntry.patch` renames the C entry of the same pinned Swift source. The producer applies
it only to a copied macro-server file in the macro build directory. The native adapter exports the
original name and invokes the upstream handler on its required main actor. Compiler sources and
compiler output identities remain independent of this macro-only patch.
