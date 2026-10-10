# Foundation continuation: candidate review, 2026-10-10

This review and its candidate files were prepared without native Studio/MCP
calls, production writes, manifest/index writes or commits. Studio authority
and concurrent work stay with the root task. No old audit hypothesis is taken
as current proof. The original nine protected inputs stayed byte-identical
during the first baseline diagnostic; later root reconciliation is separate.

## Priorities

| Priority / finding | Exact scope and smallest change | Evidence / dependencies | Risk and gain | Before/after gate / current status |
|---|---|---|---|---|
| 1 / T01–T02 follow-up | The 15 `RemoteEvent` rows in `studio-sync-manifest.json` lack `properties.Archivable` and tags. Capture and register only fresh native remote metadata; do not run full sync or touch Source rows. | Current 227-row manifest SHA `bd211a5a7fdf2491603e5e9d2e3e168e43cd45bb2b3b53872cbfcca3f06f64ad` has 15 remotes, all with no properties/tags. S13's existing strict `read_native_record` already implements the required getter and remote schema. The manifest snapshot is historical after root's concurrent reconciliation starts. | Low downstream metadata risk; closes a recorded-property coverage gap. No runtime or measured performance change. | Fresh stable identities/classes/segments/props/attrs/tags for all 15 remotes, Edit place/universe brackets, mirror marker bytes unchanged, Source/editor scripts unchanged; scoped manifest diff with concurrent fields preserved. **afventer test** — root owns native reads and reconcile. |
| 2 / T06 extension, new current installer safety evidence | `tools/install_new_scripts.py:lua_lookup/lua_update/main`: metadata registration and compare-and-swap. Existing matched sources currently lose recorded metadata. Existing `--overwrite` ignores a changed callback baseline. The proposed change uses strict fresh S13 reads and full metadata checks inside `UpdateSourceAsync`, never copied stale properties. | Five current baseline cases run real `main()` and actual generated lookup/update Luau. Exact-source registration drops `segments`, `properties`, `attributes`, `tags`, `sourceEditorMatches`; the callback interleaving overwrites a foreign Source. Default differing Source and class mismatch correctly refuse. `installer-baseline.json` records the distinction. | Low gameplay impact because this is a manually invoked authoring tool; medium authoring correctness risk. Prevents concurrent source loss and false metadata parity. No FPS/CPU/memory claim. | V2: 14 actual-main cases/89 Python checks, 96 actual generated-Luau CAS/create cases/297 checks, O0/O1 compile PASS. Real native authoring/SES engine gate and root peer review remain separate. **afventer test/review** — candidate only. |
| 3 / T19 | Current runtime graph pollution by dated code. | Graphify graph absence cannot certify deletion; current/native rg/source confirmation is necessary. | Relevant analysis benefit; graph maintenance is broader and lower priority than verified source safety. | Fresh scoped graph and current-source queries, no archived asset deletion. **beholdes / afventer test**; not implemented here. |

T06's original Unicode defect is **already fixed** in B01b. The proposed
installer changes address separate current safety defects; they do not repeat
the old JSON/Unicode fix. B01/S12/S13, B17, S07/S08/S10 and X05 are left alone.

## Concrete candidate

`install_new_scripts.candidate-v2.py` retains the CLI, supported script classes,
Unicode literal helper and source/manifest newline representation. It changes:

- Presence lookup checks Edit/place/universe and duplicate sibling names.
  Existing source/identity/class/properties/attrs/tags facts come from the
  existing strict metadata-plus-chunk reader.
- The overwrite payload compares the complete fresh native record before SES
  and **again inside its callback**, then checks the callback's raw Source hash.
  Source/editor conflict, replaced/renamed/retagged/reparented target, property,
  class, place or mode drift refuse before a Source write.
- Registration obtains a fresh final native record and checks stable non-source
  metadata. It records fresh properties, attributes, tags, segments and editor
  agreement, instead of replacing a row with source-only fields or preserving
  stale values. Targeted queued/conflicted rows refuse before client creation;
  unrelated queued rows remain exact.
- A concurrently changed manifest refuses registration and preserves the other
  actor's bytes. This is a check-before-write boundary, not a proven continuous
  filesystem transaction or multiprocess locking protocol.
- Missing targets use a newly created, owned empty LuaSourceContainer instead
  of `multi_edit`, which could race with somebody else's newly created target.
  New Script/LocalScript objects stay disabled while staged and recover their
  own original Enabled value only after landing. Empty Source/editor, class,
  debug ID, parent, properties, attrs and tags are checked inside the callback.
  Failures destroy only the precise object created by this attempt while its
  source/metadata still belongs to the attempt. Foreign changes cause retention
  for reconciliation; cleanup does not overwrite or destroy the raced original.

The create branch is needed to keep the same authoring workflow while closing
its concurrent-creation race. It is the largest part of this candidate and must
be reviewed separately. No candidate is installed in production by this agent.

## Dependency closure and integration requirements

Runtime callers, remotes and gameplay attributes: **none**. This is a manually
invoked developer command documented in
`docs/LEVEL4_HANDOFF_2026-09-23.md:165`. Its sources and manifest inputs may still
represent active gameplay and therefore must remain guarded.

The concrete closure is `install_new_scripts.py`, `sync_from_studio.py`
(`StudioMcpClient`, selection, strict getter/chunk bracket),
`push_repo_to_studio.py` (Unicode literals/native chunk protocol),
`studio_source_contract.py` (LF hashes/newline metadata), the sync manifest and
target mirror files. Existing generic installer tests and `fakestudio.py` are
the test consumers. The old four-file `install_trello_new_scripts.py` is a
separate preserved manual workflow; this candidate does not silently retire or
rewrite it. No initializer execution is introduced by the source-reading path.

Before promotion, root must:

1. Inspect fresh production bytes and scope; preserve rollback files. V2 was
   prepared from installer raw SHA
   `4e9e6177f602f6b1519e682b70e661cec13928aec7ce3e608365163b3285292f`.
2. Replace the two **candidate-location-only** ROOT/sys.path lines with the
   production file's normal paths. Their overlays are explicit in the copy.
3. Update the installer docstring: it currently still describes `multi_edit`.
4. Adapt `tools/tests/test_install_new_scripts.py`: `lua_update` now requires
   the freshly validated `baseline` argument. The old literal-only fake engine
   lacks the full metadata services needed for this stronger callback; do not
   remove the Unicode gate. The new fixture runs actual guarded Lua with
   Danish/emoji source but presently uses an ASCII path.
5. Add or run the missing Unicode-path, malformed presence response, missing
   parent, parent-replacement/create-race, final metadata/post-source conflict,
   large chunked source and error-path gates appropriate to promotion. These
   are not implied by the present PASS counts.
6. If invoking native create/install for verification, use only explicit owned
   temporary scripts and an exact fresh Source/editor/identity baseline.
   Preserve original native source/metadata guards before and after both
   success and failure. Never stop/switch a user's Play session.

No real installer, bot, HTTP upload, publish, client gameplay or multiplayer
scenario ran here. Actual-main tests use a fake MCP reader protocol; generated
native guard tests use a fake DataModel/SES and a lookup-table SHA boundary. They
exercise the real commands and callbacks, not real Roblox engine semantics.

## Failures and immutable evidence

The initial candidate test failed because its owned-create callback omitted an
explicit debug-ID comparison. V2 adds that guard. The prior candidate, prior
test source and failure receipt are preserved as
`install_new_scripts.candidate.py`, `failed-attempt-v1.test.py` and
`failed-attempt-v1.json`. That trial also exposed a compiler-log decoding issue:
disassembly can contain arbitrary bytes, so V2 collects compiler output as bytes
and checks its exit status. No production or native state changed in the failed
trial.

Successful V2 receipt: `candidate-tests-v2.json`. The exact generated Luau
fixture is `candidate-generated-guards.luau`; it includes controlled cleanup
and retained-foreign-edit paths. Runtime reset/reentry/multiplayer/streaming
certificates are unnecessary for these local helpers and are not claimed.
