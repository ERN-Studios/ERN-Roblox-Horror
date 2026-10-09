# Final ESP proposal after logos and revised Continue

Artifact only. Root requested composition against the actual published-logo Store and the already reviewed revised-Continue GameManager proposal. **Continue is not yet installed in the preparation checkpoint.** No production, Studio, UI, manifest or Trello mutation was performed.

| File | Actual runtime at preparation | Required baseline before ESP installation | Merged proposal |
|---|---|---|---|
| DevCheats | `39072aee…` | Same | `f16d6fc3…5aeb` |
| Store | `749afb83…` — Entity Shield + new logos | Same | `1ca6514e…d6bbb` |
| GameManager | `4d0ee8f3…` — v1849 spawn checkpoint | `3615b6a3…` — reviewed old-UI/auto-continue + visible choices | `35758568…56c3f` |

Full hashes and paths are in `manifest.json`. `runtime-before/` preserves the actual runtime checkpoint; `baseline/` preserves the intended installation baseline. GameManager's latter file is the reviewed Continue proposal and is independently copied to `inputs/Continue-GameManager.lua`. These are deliberately different. Root must publish/verify Continue first and then match the actual GameManager to the planned baseline before applying ESP. Applying this complete GameManager to the current v1849 checkpoint would also install Continue prematurely and is outside this installation step.

The original ESP generator/test runner/manifest are frozen in `inputs/`; the original proposal and earlier installation-merge remain unchanged. The generator has only two adapter seams: this folder's root depth and reading from the preserved planned baselines. All original ESP source replacements are unchanged. The test runner has only root depth and an explicit hash-checkpoint adapter. It runs all original behavior tests and refuses runtime bytes outside the exact recorded, planned or installed hashes. Recognizing those hashes supports preparation/retesting; it is not installation authorization.

`merge-proof.json` verifies every original ESP change payload is identical in the new composition. It then removes each original ESP insertion/replacement from every complete new proposal and requires the result to equal the planned baseline **byte for byte**. Thus GameManager retains precisely the reviewed Continue behavior, and Store retains Shield/new logos. The Store also matches the independently prepared `section-logo-rework-prepared/after-shield-and-esp.lua` exactly. No Config/product-icon field or RoundUI is touched; any separate camera fix to RoundUI remains outside ESP.

Validation: **67 original actual-source checks**, both targeted negative controls and **three complete compilations** pass against these actual merged files. Both original runtime and original proposal files remain unchanged. The Continue source-preservation proof is the meaningful integration check; this task does not repeat or claim the separately pending native Continue acceptance.

```powershell
python artifacts/trello-20260909/player-esp-prepared/final-install-proposal/prepare_final.py
python artifacts/trello-20260909/player-esp-prepared/final-install-proposal/test_final.py
```

The generator deliberately refuses after the preparation runtime advances; do not rerun it to overwrite immutable inputs. The test supports only explicitly recorded exact checkpoints. If a later feature changes GameManager or Store beyond these hashes, rebase the same narrow ESP deltas and re-review that composition.

This is not a native or release pass. Root still verifies the actual DEV row and marker behavior, keeps multiplayer/streaming limitations honest, compiles/audits after installation and mouse-publishes ESP separately. The independent reviewer reran67 checks, both negatives and all three complete compiles, independently inverted all original ESP payloads and verified the checkpoint adapters. This final composition received **9/10 with no merge blocker**; see `independent-review.md` and `independent-validation.json`. The author assigns no independent score.
