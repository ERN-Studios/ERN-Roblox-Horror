# S25b — remove unreachable retired bpy-exporter source

Prepared only; no production or native edit. Root authorized replacing the two
already-retired unsafe exporters with clear retirement stubs after the same
CLI/import contract passes. S25 was locally committed as `b2c16a6d`.

`tools/export_entity_keyframes.py` currently has 4,812 bytes and
`tools/export_entity_animations.py` has 3,389 bytes. Both currently refuse CLI and
import before bpy imports, export initialization or the private `safe_name`
definition. The new 501-byte stubs preserve the same message, CLI SystemExit and
import RuntimeError. They remove 7,199 bytes of unreachable definitions/imports
and export initializers. No previously callable helper is removed: neither
module can currently import successfully, and no live import/subprocess or
`safe_name` consumer was found. Historical `docs/AUDIT-2026-09-03.md` references
remain documentary and are not edited.

The exact pre-guard original sources remain pinned in S25's
`proposal-v1/before/tools/`; exact currently installed S25 guarded sources are
additionally archived here in `proposal-v1/before/tools/`. The two stubs have the
same source because their intentionally refused entry contracts are identical.
That source equality is not a statement about native asset equality.

Publisher and retargeted sampler source stay unchanged, including their seven
pure helper functions. Generic MCP/Blender tools and both shared builders remain.
All eight v10 input JSON files, eleven published-ID receipts, two shared builders
and the active EntityAnimation ID Source remain byte-identical. No native cache,
AnimationId, PublishedAssetId or asset object is removed by this local batch.

`prepare_and_verify.py` uses the actual frozen S25 CLI/import boundary harness.
The author receipt `actual-port-v1.json` passes:

- 16 real Python subprocess CLI cases: installed before and candidate stub,
  two files, four argument combinations, same exit status/message and no stdout.
- Four actual whole-source import cases: both versions of both files raise the
  same retirement error before optional/native boundaries.
- Four semantic negatives: removing import refusal returns a namespace instead
  of the required error; removing CLI refusal produces the wrong exception.
- Thirteen behavioral contracts from the retained publisher/sampler helpers,
  preserving the S25 contract rather than replacing those helpers.
- All four production tools, 21 retained inputs/receipts/builders and active
  runtime ID Source unchanged during replay; eight durable published IDs retained.

Independent prepared replay writes only a new receipt:

```powershell
python -B artifacts/cleanup-20261010/animation-workflow-stubs-v1/prepare_and_verify.py --receipt NEW_RECEIPT.json
```

After Root promotes the two exact candidates against the reviewed current byte
hashes, use `--verify-installed` to execute the actual installed stubs and the
archived S25 before contract. This does not rewrite the proposal or old receipts:

```powershell
python -B artifacts/cleanup-20261010/animation-workflow-stubs-v1/prepare_and_verify.py --verify-installed --receipt NEW_INSTALLED_RECEIPT.json
```

Root's remaining gates are independent review/replay, exact source-byte CAS,
installed replay and selective diff/commit. The prior current sources provide
rollback. The expected benefit is removal of documented unreachable authoring
source and clear retirement behavior. There is no gameplay, actual native cache,
archive/recovery/reference/deletion or measured performance pass. Studio mode,
Source and assets are not touched.
