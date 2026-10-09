# Preserve switch choices through later GameManager releases

This artifact composes the independently reviewed **switch**, **longer Level 3 slide**, **full lobby circle**, **PLAYER ESP**, and **developer free respawn** changes. It does not install or publish them together. Each feature still needs root's separate native acceptance and mouse publication.

The source authority is the frozen reviewed before/after files and their exact SHA256 values. `prepare_composition.py` reuses the existing `game-manager-queue-slide-merge-prepared/prepare_merges.py` unique-context application/inverse functions without running that script's main routine. Every input is checked and copied to immutable `inputs/` here. No old source proposal, standalone validation or production file is rewritten.

The five intended release stages are:

| Stage | Exact GM input | Exact GM output (shortened) |
| --- | --- | --- |
| Switch choices | `3615b6a3…5d58` | `3d1b0599…d7db` |
| Then longer L3 slide | previous output | `757e2673…4439` |
| Then lobby circle | previous output | `efcd566d…6aa0` |
| Then PLAYER ESP | previous output | `f0f2cbf5…78cf` |
| Then DEV free respawn | previous output | `80fe5354…2fdb` |

`merge-proof.json` records every full input/output hash, path and source region count. These are **compare-and-swap prerequisites for root's later install**: compare the actual Studio/disk source with that stage's exact input before applying its output. If it differs, stop and recompose against the reviewed new checkpoint. Do not install the old `f006…` or `eba…` GM files, because they lack the new editable-selection feature. This package is read-only with respect to runtime and is not itself an installation command.

All **60 full application orders that place ESP before DEV** produce exactly the same final bytes and all reverse applications recover the entire original `3615…` source. The ESP-before-DEV constraint is real in the reviewed DEV context: its narrow insertion surrounds ESP's existing server branch. The check does not pretend that applying that dependency backward is supported. The fixed five-stage path has an exact inverse to its immediate prior stage as well.

The switch's other two files live under `companions/`: RoundUI **a851f631…b7f3** includes the accepted compact single-column correction, and UIRegression **f2b4699c…3ae4** includes only the new CompletionContract expectations. They remain unchanged through these later GM-only deltas. Other feature-owned files—L3 World Builder, DevCheats, Store—are not installed or recopied by this package. Use their reviewed feature proposals at the corresponding stage; the separate square-button package already preserves ESP/copy/DEV Store changes.

## Actual composed-source verification

The exact final GM SHA is **`80fe53548ebda3c95f43c559dca9b07733d2c2dd42eb579233d722c3aa712fdb`**. All existing relevant hosts were executed against it:

- Switch: **76 server + 32 client + 19 CompletionContract**, three negative controls, four whole-file compiles.
- Longer slide: **433 GM + 7,787 geometry + 61,269 aperture checks**, two negative controls, two compiles.
- Lobby circle: **257 checks**, three negative controls, two compiles.
- PLAYER ESP: **67 checks**, two negative controls; the original host receives the exact composed server callback and identical rate-limit block. Its unchanged client/UI fixtures are retained. DEV's additional branch is exercised by its own suite.
- Developer free respawn: **184 checks**, five negative controls, four compiles, using its original host and actual composed GM. A small authorized `--gm-source` adapter redirects only the tested GM read/compile and writes `validation-merged.json`; all existing planned-source proofs, Store/Dev inputs, negative controls and standalone `validation.json` remain intact. It records actual tested GM versus original planned baseline separately.

The five intermediate GM stages also compile individually. `reports/` freezes each derived result with provenance; `validation.json` records their hashes. No native physics, real multiplayer transfer, developer respawn or publication is claimed by these tests. The source merge preserves already reviewed behavior; each later feature's actual gameplay acceptance remains its own checkpoint.

Reproduce by running `prepare_composition.py`, the existing feature commands with the final GM path as their source override, `test_esp_composition.py`, then `collect_validation.py`. The relevant override flags are `test_switch.py --gm-source … --ui-source companions/…/RoundUI…`, `test_slide.py --gm-source …`, `test_circle.py --source …`, and `test_respawn.py --gm-source …`. All override reports are separate from their standalone reviewed checkpoints.

Independent composition review is **9/10** in `independent-review.md`. The critic independently replayed all 60 supported orders and their inverses, compiled the five GM stages, and verified the companion files and five exact-source reports. No code blocker remains. Separate native acceptance and publication are still required. The switch feature itself was already reviewed **7→9/10** after the final-presence fence fixed the critic's deferred-disconnect finding.
