# S11: ONE private PuzzleManager field from LE-34

Status: offline proposal ready; **native before/after contract and installation pending**.
No authoritative Source, manifest, native probe, mode switch, staging or commit
was performed by this subagent. The three native sources were read without edits.

The smallest eligible change removes only `latchMode = true` from the private
`session` initializer in
`ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua:1373`.
It removes 18 bytes. Existing immutable before/candidate sources are referenced
from `../additional-locals/`; they were not rewritten or duplicated.
The exact whole-source hashes remain `6cde618088f7aff94385e7348c830f07b597b011bb64640def7395b7a53b2ad7`
and `40fce9298d29bfca01e20c0307591b545dfb125b2b66a9ab7e2d4092f6b85d8c`.

## Fresh baseline and closure

At 2026-10-09T23:26:48Z, the correct Studio GUID, place131311258779917 and
universe10559217407 were in Edit. PuzzleManager, RoomDressing and Usher matched
their exact saved before Sources and editor Sources, classes, recorded properties,
attributes and tags. See `observation.json` and the exact read-only
`read-source.luau`. PuzzleManager still has Enabled=true, Disabled=false and
RunContext.Legacy; its identity is `1_408347`, parent `1_15621`.
TeamObjectives was also read freshly; its complete Source/editor matched
`4e5f91990b1d2cddcca1310ef877f709cf308ef450d43ff48b4399b0d1cd40b2`.
Current mirrors and current manifest agree with these native sources.

There is precisely one production `latchMode` occurrence: this boolean literal.
No reader, dynamic indexing/reflection or session export was found in the complete
current script. The private session crosses only the script's private helper and
callback closure. Nil-between-rounds state, participant roster, character records,
fuses, inventory, circuits, boxes, relays, levers, escaped state, connections,
folder destruction, generation/stale-callback checks and all active calls remain.
No initializer call or other side effect is removed.

The only other active development reference is the synthetic session field in
`tools/tests/test_level1_team_prompts.py:139`; it is never read. That historical
fixture stays unchanged. All actual current prompt-handler bodies and
TeamObjectives.Announce are extracted verbatim. No TeamObjectives module
initializer, analytics call to the live service, real remote, live player,
Workspace attribute, game folder or gameplay callback is invoked by the proposal.
Engine/player/remote/analytics/world/clock interfaces are local test boundaries.

Risk is low: an unread private literal field. Expected gain is 18 fewer source
bytes and removal of misleading state; there is no measured performance claim.

## Meaningful ports

`latch-only/proposal.json` records 47 assertions before and 47 after, then the
same 94 assertions on runner reentry. Business event traces and resulting
cleanup state are identical. These include the existing actual 21-check
fuse/box/lever/team contract plus actual `clearPuzzle` coverage: disconnect
failure continuing to later connections, owned folder cleanup, stale fuse
callback rejection, duplicate pickup rejection, empty-session cleanup,
fresh-session reentry, observable folder error and cleanup retry. An inactive
session initializer mutant fails the unchanged objective contract.

Four full-script before/candidate O0/O1 compiles, six actual contract-module
O0/O1 compiles and four generated native-before/installed O0/O1 compiles pass:
14 compile invocations in total. These are combined with behavioral ports;
compile success alone is not the removal evidence.

The root-run native runner stages only fresh `Instance.new("ModuleScript")`
objects with exact empty Source/editor baselines. It never clones a
LuaSourceContainer, requires a live script/module or writes an original Source.
It captures all currently authoritative LuaSourceContainers (expected212),
Source/editor, identities/Parent/classes/properties/attributes/tags, checks the
two exact dependency baselines, and guards them during each SES staging callback
and after both success and failure. All three unparented test modules are owned
independently; cleanup attempts each even after a failure and refuses to destroy
a reparented, modified or foreign object. The shared lease is released only
while still owned; foreign shared state is preserved.

No native probe has run yet. Original guards are point-in-time reads, including
a repeat after the yielding final census. They are not a continuous epoch,
full native asset or gameplay certificate.

## Root execution and scoped installation

Root must review the frozen helpers and generated inputs first. In the unchanged
authoritative Edit baseline, run:

```powershell
python -B tools/cleanup_20261009/prepare_latch_mode_probe.py --execute before --receipt artifacts/cleanup-20261009/pending-locals-native-v1/native-before-result.json
```

Require `pass=true`, the 47/47 paired checks plus reentry, the semantic negative,
all212 originals unchanged, all three probes destroyed, zero remaining probes,
no cleanup/transport error and release of the owned lease. If any necessary port
fails or Edit becomes unavailable, keep the field and preserve the failure.

Only after that port, root may use its existing scoped native CAS installation
process against the freshly reread PuzzleManager Source/editor and identity.
The change allowlist is the single 18-byte initializer substitution. Preserve
properties, attributes, native script class and RunContext. Export this one
verified native Source and update only its manifest Source hash/size. The
RoomDressing and Usher sources must remain untouched. No public publication or
GitHub push is included.

After installation and mirror/manifest reconciliation, run:

```powershell
python -B tools/cleanup_20261009/prepare_latch_mode_probe.py --execute installed --receipt artifacts/cleanup-20261009/pending-locals-native-v1/native-installed-result.json
```

This separately checks exact installed candidate Source/editor and reruns the
same immutable before/candidate business/lifecycle contract. It does not overwrite
the proposal or before receipt. Root must inspect diff/console and final scoped
parity before committing. A new regression requires root's exact batch rollback;
the probe itself never restores or overwrites concurrently edited originals.

RoomDressing's safeRect/breaker locals and Usher's three unused state locals are
still native-baseline-valid proposals, **not implemented**. Their existing
1477/21 and59 offline contracts remain scoped evidence. They need their own
fresh native isolation/after port and original guards; this one field port does
not certify those files. Real gameplay, multiplayer, streaming, respawn,
reserved-server teleport, real-asset navigation and performance remain untested
by this private-field contract. CORE025/037 and the five S04 roots remain pending
their separately documented integration gates.
