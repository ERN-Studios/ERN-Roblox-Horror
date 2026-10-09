Level 6 effects preload eligibility
=================================

The enabled Level 6 Playground Client explicitly fetched six chase, rage and
kill effects at startup, even while its player remained in the lobby. The
scoped change defers that loop until `Level6PlaygroundPreview` is true and
`Level5VoidRound` is not true. The latter marker matters because Level 5 uses
the shared preview marker too.

A single coroutine owns the loop. Eligibility is checked before each engine
request. Leaving during a request lets that request drain, then pauses the
remaining effects. Reentry resumes the saved cursor without repeating finished
fetches or overlapping an earlier request. Actual failure callbacks still mark
the same refused effect; `oneShot` retains its existing fallback behavior.
The patch preserves the previous caught engine-error behavior. Voice timeout
or setup failure releases the owner so a later entry can try again.

Fresh Studio source/editor baseline: Level 6 Playground Client SHA-256
`6e57bb0e05008fbe459afe6607fb732c6e2224beb88cbfa516d1ce5ab7b808e5`.
Candidate SHA-256:
`a812142882845810749b6c985a1bca22a4de37b6035f1c61741df9949a122396`.
The source delta is limited to this preload loop and its two eligibility hooks.
Sound templates, HUD construction, playback, music and map lifetimes are not
changed by this patch.

Portable verification after verified native installation and export:

```powershell
python artifacts/lazy-levels-20261009/test_level6_deferred_audio.py --mutations --luau <path-to-luau.exe>
```

The default test reads the canonical mirror. An optional `--candidate` selects
the generated local candidate before promotion. It extracts the exact selected
preload block, its hooks and `oneShot` consumer into a coroutine fixture; it
does not manually reproduce their implementation. 81 checks and nine mutation
rejections passed. The full candidate also compiles with the Luau compiler.

These are offline ownership and eligibility checks. They do not establish
native gameplay, renderer performance or zero engine cache activity. Native
verification should preserve the installed source hash, check normal Level 5
and Level 6 entry/Continue, and confirm actual refused-effect fallback behavior
without forcing readiness or acknowledgements. Shared replicated templates and
the engine's existing asset cache remain outside this explicit preload defer.
