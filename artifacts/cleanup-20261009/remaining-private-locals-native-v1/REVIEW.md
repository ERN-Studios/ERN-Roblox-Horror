# Remaining LE-34 and LE-32 private locals

Read-only native observation at `2026-10-10T00:06:54Z` used Studio
`1b603e69-7ae1-4572-b210-d5bf05c684ff`, Edit, place `131311258779917`,
universe `10559217407`. Eight Sources/editors matched the current mirror and
manifest, including identities, classes, parents, recorded properties, attributes
and tags. No native writes, objects or mode switches were performed. The exact
read code and bounded metadata/hash output are `read-source.luau` and
`observation.json`. This is a point-in-time observation; Root must recheck during
any native probe or installation.

## Proposed next batch: RoomDressing only

Status: **gennemført med native før-/efterport; lokal commit-ID afventer Root**. This is one ModuleScript,
`ServerScriptService/Level 3 Systems/Level 3 Worn Party Room Dressing.ModuleScript.lua`,
native `ServerScriptService.Level 3 Systems.Level 3 Worn Party Room Dressing`,
identity `1_42745`, parent `1_15620`. Before is 18,304 bytes, SHA256
`4424920501f4fafa63788f1fb70a3263e23d75e31741d68a37bd6f55b48f511a`.
The exact old scoped candidate is 18,179 bytes, SHA256
`89fc2abec94362a1759d572346513092c72d718a780b3da679712ced0df6b53b`.
Only the five substitutions already saved in `../additional-locals` are proposed:

- Remove private `safeRect.reservePerimeter`, use the existing `WALL_INSET`, and
  remove the two literal-false arguments. The only two callers are `Dress.Plan`
  and the `Dress.Apply` fallback placement. This local is not exported. Both
  callers always select the existing constant branch; no initializer, Instance,
  event, require or visible-object call is removed.
- Construct the breaker position at its existing final `V(.98,2.15,.42)` and
  remove its immediate overwrite. `V` is `Vector3.new`, an immutable value
  constructor. Its discarded +6.70 value is overwritten before the first read
  in `carrier`; the breaker, carrier, prompt, nav exclusion and placement calls
  remain. Claw and arcade offsets remain unchanged.

Risk is low and the gain is 125 source bytes and one discarded value
construction/constant branch. No measured performance gain is claimed.

The current real caller is `Level 3 Worn Party Visual Adapter` (Source SHA256
`0b5d4034c3a9016f6e4405024d713244ad936cf97988f13e03296ed016b39035`,
native identity `1_42746`, same parent). Its `Dressing.Apply` path, `helper.Place`,
participant/generation checks, noise and sound callbacks remain. The adapter's
active Level6BlenderKit and Level6 Kit Metadata dependencies, asset clones,
colliders, meshes and proxy/nav data are retained. The pure helpers neither emit
nor consume a remote or modify player data. The complete actual RoomDressing
module is loaded inside a local engine boundary, so all its public functions,
static initialization, Plan and Apply bodies are exercised without requiring the
authoritative live module.

Authoring references remain in `tools/level3_worn_party/prepare_studio_install.py`,
`install_studio.luau`, `reconcile_prompt_visibility.luau` and its RoomDressing/
VisualAdapter payloads; `tools/level6_build/room_dressing.luau` and the separate
native Level 6 Room Dressing are outside this batch. Identical helper text is not
evidence to retire those packages. No authoring package, asset or tool is removed.

The apparent copies are intentionally distinct. `tools/level3_worn_party/README.md`
explicitly retires the historical installer as a Studio deployment baseline. Its
19,427-byte/766976 payload differs from the current 18,304-byte/442492 module. The
frozen first-install manifest marks the Room target `create=true`; the exact
installer's full preflight requires that target to be absent before any write.
The current target exists. The real package builder also presently rejects a
missing `artifacts/level3-rebuild-20260930/native-backup/scripts.json` before
payload/listener setup. The actual historical preflight block, run offline against
a current-existing-target boundary, rejects before any source access/write (one
case/two checks plus O0/O1 compiles). Editing this historical payload would break
its pinned reconstruction/snapshot contract. `prepare` refuses to replace the
historical manifest/code, and `serve` requires the recorded snapshot.

The Level 6 authoring payload is 18,364 bytes/SHA256 a5a16e313fe93686666ef9de3eed498b95b381c20f43b1b34a67855ce656455f,
byte-identical to the separate Level 6 Room Dressing mirror. Its installer EXTRAS
targets only that separate Level 6 module, not Room3. There are 62 differing lines
between the Level3/Level6 modules. The active Level3 adapter requires Level6
kit/bake/metadata, never the Level6 Room Dressing module. There is no active exact
Source authoring duplicate to update with this 125-byte native transform. Both
distinct/historical packages remain unchanged, with exact hashes and bounded
read-only/offline proof in `authoring-closure.json`.

### Concrete gates

`room-proposal-v2/proposal.json` is the final offline proposal. Each actual-source
runner passes **752 assertions**, paired **1,504**, with another identical **1,504**
on runner reentry. The complete traces/graphs/properties/attributes/placements/
reports/noise signatures match. Cases include 336 seeded service/non-service
room-width/blocked-envelope decisions per version, all three service variants,
invalid dimensions, protected-space fallback, missing assets, all five prompts,
breaker final position/invisible carrier flags, validated interaction, duplicate
busy requests, delayed reset, stale generation, disabled participant workflow,
repeated owner cleanup, task cancellation and connection cleanup.

Two additional actual-cleanup failure cases reproduce the baseline behavior:
connection `Disconnect` or owner `Destroy` throws after `alive=false`; subsequent
`Cleanup` is a no-op and leaves the owner present. Before and candidate produce
the same fault and connection state. This is an existing lifecycle limitation,
not repaired or newly caused by the proposal. Separate harness cleanup restores
the fixture fault hook and independently disconnects/destroys only its synthetic
owned boundary tables. It does not claim a live production cleanup retry passed.

Two semantic mutants (wrong wall inset and breaker height) fail the unchanged
contract. Eighteen O0/O1 gates compile both full sources, all four actual-source
payloads, both native inputs and the actual extracted ownership fixture. Eight
ownership scenarios/20 assertions reject foreign preclaim/shared state/token/
connection table/nonempty connections/phase and mode changes, preserving foreign
metadata. The initial offline v1 evidence is retained; its compile-input labels
collided and omitted native-before from that compile list. V2 fixes only the
labeling and compiles all 18 distinct inputs; native-before/installed code bytes
are identical across those offline versions. Root then ran the exact frozen
native-before input at `2026-10-10T00:19:14Z`: 752 assertions per version,
1,504 paired and 1,504 reentry, identical behavior hashes, both semantic mutants
rejected, four fresh ModuleScripts created/destroyed, zero remaining, all 212
originals unchanged and exact owned lease released. The immutable receipt is
`room-native-before-result.json` (SHA256 bd37f31aad9b496e38b60044f8c52c091df116dd6b8c417f51d73b8a934a7d1f).

Root-only native proposal uses the hardened S11 late no-yield lease claim, exact
state/token/empty-connections/phase ownership, fresh unparented
`Instance.new("ModuleScript")` staging with exact empty Source/editor checks,
four independently cleaned probes, and authoritative Source/editor/identity/
class/properties/attributes/tags checks throughout and after either outcome.
Fresh native census is 212; a concurrent census or closure change rejects.
After the yielding full census, the complete original guard repeats. No borrowed
runtime state, original Source/Parent/attribute edits, live requires or mode
switches occur. Full Source/payloads stay in the input; output is bounded receipt
metadata/hashes. The lease is released only when exact ownership still holds.

Frozen preparer:
`tools/cleanup_20261009/prepare_room_private_locals_probe.py`, SHA256
`c789f036a9c2a074f3e2a9cec9828594a8ce73b6e98545291c20495906743a86`.
Template `room_private_locals_probe.luau` SHA256
`3346ba8f387d9d1a3e6203ff742e49f32298e2bacd8fd645f57a953d42d121e1`.
Native-before input SHA256
`20f87d2e14e182df26ba678eb2a863e1004dcb375c2fb854c2083d6998faa319`;
native-installed input SHA256
`7f9093bcdcc0bac74f865ac57f324d67176b947538a48faa7e2e78f302f7493d`.

The reviewed/root-executed before gate is:

```powershell
python -B tools/cleanup_20261009/prepare_room_private_locals_probe.py --execute before --receipt artifacts/cleanup-20261009/remaining-private-locals-native-v1/room-native-before-result.json
```

Installation remains a separate Root-reviewed scoped CAS/export/manifest task;
this preparer cannot install production Source. `apply_room_private_locals_cleanup.py`
and `room_private_locals_source_cas.luau` are the frozen proposal. The native
callback reads the exact current module/Source/editor/identity/metadata and all
212 originals, then applies five unique nonempty literal anchors; its removed
assignment uses a unique comment context to make rollback unambiguous. No bulk
repository body is supplied. Forward result must equal the reviewed 89fc2a hash;
reverse-order rollback must equal exact 442492. The actual extracted native
transform passes five forward/reverse/missing/duplicate/SHA cases/eight checks
and two O0/O1 compiles. Six generated native operations pass 12 compile gates.

The actual-wrapper fake-boundary port passes 16 cases/109 assertions, including
Play/prewrite rejection, malformed/truncated/oversized replies, short page,
catalog drift, chunk failure, commit-then-error, unknown/foreign native Source,
foreign local Source/target manifest fields/other metadata, replay and console
failure. All filesystem/CAS/rollback/projected-row code runs against owned
temporary files; native/MCP/console/git boundaries are fake. Private checkpoints
save exact native Source/editor, local source/manifest and a distinct HEAD-only
manifest projection. Recovery queries the actual native outcome before acting;
only a freshly guarded exact owned candidate is reversed. Unknown/foreign state
is preserved and documented. Local recovery restores only exact owned source or
the target row's two Source fields and retains concurrent metadata/other rows.
Filesystem compare-before-atomic-replace is point-in-time, not an OS-level
compare-exchange or continuous external-change certificate.

Capture replies are 20 rows with a 20,000-byte limit, stable complete native
catalog/target summary across pages; actual Source reader uses isolated 64-line
chunks with an 8,000-byte reply limit. A complete original guard/census repeats
after the last chunk, inside the no-yield Source callback and after staging/
installed replay. The only repository updates are the verified native Source
export and target manifest `sha256`/`bytes`; HEAD-only projection preserves the
pre-existing owner RoundUI working change. Fresh installed replay and distinct
final 212-source parity/console checks remain mandatory. The proposed install
can run only after the successful exact native-before receipt already recorded.

Frozen wrapper SHA256 `c748944a3bcf02dc808ceee2bd168ef567fd2a40e1111ca20c1f8e71872eac8f`,
native CAS template `db9aa76b38fbc0f7b69850048427b6ae29cf103b77047a998d245625ccac9ae2`,
test `13ff99fa886a6f0380a25f42ad79d789bab151b61cd99abfad7dc88de4272bb9`.
Final offline-wrapper proof `room-source-proposal-v1/offline-wrapper-tests-final.json`
SHA256 `9a4da0e890c9ad3bdcabc32239324818350c56da9cf26968dd4243f8ab90165c`.
Independent clients peer reviewed both probe and installer closures successfully;
native installation was initially pending at that review stage.

```powershell
python -B tools/cleanup_20261009/apply_room_private_locals_cleanup.py --apply
```

Native-installed replay, final mirror/manifest/native metadata parity and console
comparison remain required.
These local-helper authoring contracts are not real-kit/gameplay, multiplayer,
streaming, respawn, teleport, navigation or performance certificates.

### Actual installed outcome

Root executed the frozen installer successfully, completed at
`2026-10-10T00:22:49.183233+00:00`, HEAD `8fb44faf48aa9623bbee75277d2570b53e0950e0`
unchanged during the batch. The result in `room-source-install-v1/result.json`
reports exactly 125 removed bytes and native/mirror Source SHA256 89fc2a.
Installed replay again passes 752/752, 1,504 paired and 1,504 reentry, both negative
controls rejected, four fresh modules created/destroyed, zero remaining, all 212
originals unchanged and exact owned lease released. Before/candidate behavior
hashes are identical `81cddf6665793174aca5b3eddfca40483c3c31348fab6caa951e8d40e1eea980`.

The complete before/final 212 rows show exactly one changed identity `1_42745`
and only its `sha256`/`bytes`. All identities, classes, parents, properties,
attributes and tags are unchanged; immediate-after/final rows agree. Working
manifest Source fields and native-exported mirror match. The separate private
HEAD manifest projection retains the owner's pre-existing working-only RoundUI
change. Console strings match exactly, including existing console entries; no
empty-console or unrelated error-resolution claim is made. No rollback was
needed. Root owns the local commit/staging; its commit ID is pending at this
update. This cleanup batch did not publish or push anything.

Curated public before/after/final metadata, representative executed CAS/capture/
final-guard code and `bounded-transport-and-parity-proof.json` are in the actual
install folder. Static exact-before 64-line alignment has seven chunks, maximum
3,128 bytes; actual wire response caps were independently enforced by the
executed wrapper. The largest saved pretty-printed metadata page is 15,108 bytes;
this is disk JSON size, not an invented measured wire size. Final metadata is an
exact assembly of actual snapshot3 pages with their private page hashes and
native first/last read timestamps. No full native Source/editor is copied into
this public receipt folder. Exact rollback originals/manifest projections/full
private page sets remain under `.git/mongotv-cleanup-20261009/room-source-install-v1`;
before/candidate full sources already exist in the old additional-locals archive.

The native/source contract boundaries and known existing cleanup-failure
limitation above continue to apply; this success does not certify live assets,
multiplayer/streaming/respawn/teleport/navigation or measured performance. No
production Source, manifest, probe, mode, staging, commit, publication or push was
changed by this reviewer/preparer; all actual native/production work was Root's.

## Usher: still pending

The exact native/mirror before SHA256 `9af1a745968b95928355707aeaf81bf36b2e9495bdc589918b72bca10d6ba7e3`
is unchanged. The old 86-byte candidate in `../usher-locals` removes only private
`targetReason`, `nextThinkAt` and `stunUntil` declarations/write-only assignments.
The actual local `reason`, ThinkSeconds timing, `stunCooldownUntil`, beamer,
targeting, navigation and capture calls remain. No side-effectful initializer is
removed, but the old actual-source section contract does not yet exercise all
failed Stop/cleanup/retry boundaries. A fresh native proposal will be considered
only after those same-flow/failure contracts and full private-state closure are
reviewed. No live navigation/capture, multiplayer, streaming or active round pass
is inferred from source inspection or synthetic scenarios.

Root owns all native execution/installation, production mirrors/manifest and
staging/commits. This agent has only prepared new artifacts/tools; no production
Source, manifest, existing proposal, Studio state, staging, publication or push
was changed.
