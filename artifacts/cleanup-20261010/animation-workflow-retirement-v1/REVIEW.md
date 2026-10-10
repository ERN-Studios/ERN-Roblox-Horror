# Retired Studio entity-animation authoring entrypoints — prepared only

The owner explicitly retired the old Studio animation workflows for
`MongoTVEntityAnimations` and `RBX_ANIMSAVES`, while preserving published gameplay
IDs, upload-cache metadata, regeneration inputs and shared Blender functions.
Root owns promotion and all native actions. This artifact does not remove either
native data forest and does not modify any production file.

Four exact tool sources are archived under `proposal-v1/before/tools/`. Candidate
copies under `proposal-v1/candidate/tools/` add entry guards:

| Tool | Retirement boundary | Preserved functions |
| --- | --- | --- |
| `publish_entity_animations.py` | CLI before optional/native imports; `publish_code` and `main` refuse before emitting Lua/client setup | `luau_table` |
| `export_entity_keyframes_retargeted.py` | CLI before optional/native imports; `studio_rest` and `main` refuse before reading Studio or invoking Blender | Six pure conversion/sampler helpers |
| `export_entity_keyframes.py` | CLI and import refuse before its top-level bpy export initializer | Exact original and `safe_name` source remain archived; unsafe importing workflow is retired |
| `export_entity_animations.py` | CLI and import refuse before its top-level bpy export initializer | Exact original and `safe_name` source remain archived; unsafe importing workflow is retired |

The current tools/runtime reference search found no production imports,
subprocess callers or supported direct consumers of these four workflow modules.
README lines 660–663 still describe the retired pipeline and require a scoped
documentation update at promotion. Deprecated tool docstrings cross-reference
the former replacement. Historical analysis/artifact references are records.
Shared `build_corrected_entity_actions.py`, `build_entity_kill_animation.py` and
generic MCP/Blender tools remain byte-identical. The 21 retained files comprise
eight current v10 JSON inputs, eleven published-ID receipts and two builders.
`proposal.json` and `regeneration-inputs-v1.json` pin every retained file.

No runtime Source is a candidate. Current `EntityAnimation` constructs its own
Animation objects with the eight published IDs. The current Level 1 Entity Motion
client uses `ReplicatedStorage.Level1EntityMotion.Clips`, and Level 3/6 manager and
Luna animations use their separate active assets. No runtime remotes, attributes,
entitlements, receipts, migrations, collision parts or animation fallbacks are
changed. The earlier dependency review records the precise runtime Sources.

`actual-ports-v3.json` is the final author receipt. The test executes full archived
and candidate Python sources at controlled optional/native service boundaries:

- 16 actual candidate CLI subprocesses (four argument combinations per tool)
  exit with the retirement message before optional/native imports.
- Full original CLI/import/direct-call routes reach their controlled Studio or
  Blender boundary; the candidate routes refuse before that boundary. There are
  32 CLI/import/direct-entry cases in total, including the 16 subprocesses.
- Thirteen independent pure-helper behaviors pass on both original and candidate
  imports: hierarchy nil/child behavior, matrix layout, Roblox rest basis,
  Blender-axis conversion, quaternion normalization/orientation and slerp/clamps,
  plus the retained sampler generator.
- The original publisher's actual generated Lua runs through official Luau 0.737
  with all eight real v10 JSON inputs and documented published-ID cache fixtures.
  Each returns its exact reused ID without `CreateAssetAsync` or Instance
  allocation. A missing-ID negative rejects reuse at the controlled destruction
  boundary before upload/allocation. These fixtures do not assert that all native
  cache entries presently match them.
- The four production tools, all 21 retained inputs/receipts/builders and current
  runtime ID Source remain byte-identical through the test.

The first author fixture failed because its own broad `ID` placeholder replacement
corrupted a Lua assertion label. `port-failure-v1/` retains the exact failed test
and explanation. The corrected fixture uses unique placeholders and retains the
actual boundary list instead of rebinding a captured list. `actual-ports-v2.json`
passes that corrected test. The final v3 receipt additionally supports installed
verification and records byte preservation of the active ID Source. Prior
receipts and failed sources remain unchanged.

Independent prepared replay (write a new receipt):

```powershell
python -B artifacts/cleanup-20261010/animation-workflow-retirement-v1/verify_guards.py --receipt NEW_RECEIPT.json
```

After Root promotes only the reviewed four exact candidate tool bytes, replay
against the real installed entrypoints using `--verify-installed`. This requires
all installed tool hashes to match the frozen candidate and runs the actual
installed CLI files, plus archived/candidate direct/helper/cache ports:

```powershell
python -B artifacts/cleanup-20261010/animation-workflow-retirement-v1/verify_guards.py --verify-installed --receipt NEW_INSTALLED_RECEIPT.json
```

Risks and limits: old command-line and unsafe import workflows intentionally stop;
the owner authorized that retirement. Pure conversion functions remain callable
from the two safely importable modules. No upload is performed. No native cache
inventory, giant-forest archive/reopen, protected-reference absence, recovery,
animation playback, gameplay, multiplayer, streaming or performance pass is
claimed. Current cache metadata and every non-script animation value must receive
their own full native archive/data/reference/absence/recovery proof before native
removal. No FPS, memory or runtime savings are measured by this batch.

Root's remaining local gates: independent review/replay, exact-current tool CAS
promotion with rollback bytes, scoped README reconciliation, installed port,
selective staged diff/commit and final authoritative parity. This is not permission
to remove native data or to publish the public game.
