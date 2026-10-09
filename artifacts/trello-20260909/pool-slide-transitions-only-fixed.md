# PoolSlide: corrected transitions-only probe

Prepared 10 September 2026. Probe artifact only; no production source, original clip, asset ID, Studio setting, or publication changed by this subtask.

## Why the previous transition report is invalid

`pool-slide-dense-v2-full.json` contains valid independent solo phase sweeps (993 poses across four clips) and passing non-Root channel checks. Its **transition grid is invalid**: maximum requested-versus-observed weight error was 1. For example, Idle→Walk reported destination weight 1 even at alpha 0, and source weight 0.0625 at alpha 1. Do not interpret transition penetration or the combined `sampledSkin.minY`/`minimumSkinPlaneGap` as actual gameplay defects.

Parent separately tested the native lifecycle: `Play(0,0,0)` produced stopped/0/0; a subsequent `AdjustWeight(.5,0)` stayed stopped/0/0. Explicit Stop followed by `Play(0,.5,0)` produced playing/.5/.5. This proves the probe's zero-weight startup was unsuitable. It does not prove a production adapter defect.

## New file and gates

Run `pool-slide-transitions-only-fixed.luau` only in an already-running normal Play server with `TEMP_PoolSlideContactCopiesV2_20260910` present. Parent owns execution. It reuses the reviewed complete mesh/bind reconstruction on a disposable scale-6 clone. It repeats **no solo phase sweep or channel-preservation sweep**.

- The same 72 directed transition cases ×17 alpha samples preserve current production Idle/Movement/Action priorities, .12-second entry to Attack, .16-second other fades, and local reviewed speed references Walk10.82/Run27.6.
- Every sample explicitly stops all probe tracks, waits, then starts each positive contribution with `Play(0,expectedWeight,0)` and seeks. A zero contribution stays stopped.
- Before skin reconstruction, require correct IsPlaying, WeightTarget, active WeightCurrent and phase (≤.002 tolerance), and no unrelated playing track on this disposable Animator. Positive active weights remain strictly checked. A mismatch records diagnostics and aborts **before measuring the invalid pose**. The entire grid remains invalid until all 1,224 samples pass.
- A stopped zero-weight endpoint additionally requires native equality with the remaining animation alone: one disposable reference rig per clip, each of which has only ever played that one track at full weight. Compare every Bone.Transform, including Root, with ≤.001 stud and ≤.001 radian tolerances. All 144 grid endpoints must pass before the grid is valid. Reference rigs are removed by cleanup. This verifies lack of visible bone contribution instead of assuming it from IsPlaying alone.
- Three additional actual native fades cover Idle→Walk, Walk→Run, Run→Attack at the existing priorities and fade durations. They use the production Stop(fade)/Play(fade,1,rate) sequence. Each Heartbeat captures only current states and20 bone transforms; all15,091-vertex calculations happen after capture, avoiding artificial skin-calculation stalls during the fade itself.
- Live fade validation requires monotonic complementary weights, correct targets, a playing/advancing destination, two observed interior blend frames, and a stopped source/full destination by the end. A failed or undersampled case records states without claiming valid skin measurements. Stop(fade) may set source IsPlaying false while its remaining weight still fades; that source is intentionally accepted during a live fade.

Frozen grids characterize actual engine blend geometry under verified weights. Three live fades check ordinary scheduling, but do not certify all phase combinations, renderer pixels, multiplayer replication, terrain navigation, or a target FPS. Existing independently valid dense clip measurements must be combined with **valid** new transition extrema before accepting envelope dimensions. Skin floor gap and foot-group gaps are both retained; weighted foot groups are not a substitute for the full-skin minimum.

## Report handling

Full result: Folder `ServerStorage.TrelloPoolSlideTransitionsFixedFull`, StringValue children `000001`, `000002`, etc., each≤40,000 characters. Concatenate child values in name order, then parse JSON. Folder attributes include total characters and chunk count. An existing report is never overwritten. In-memory fallback: `_G.TrelloPoolSlideTransitionsFixedResult` is assigned before report creation.

Compact return strips sample arrays but preserves diagnostics, case extrema, validity and source-scale/clone-cleanup checks. `ok` describes probe execution; use `transitions.valid` and `realtime.valid` to assess those two measurement sections. `certified` remains false. Partial valid samples in an aborted run do not make the complete transition grid valid.

## Observed stopped-weight cache and subsequent patch

The first native execution of this repaired probe stopped before measuring sample 17 (Idle→Walk, alpha1). Requested source0/destination1; source was IsPlaying=false, WeightTarget=0, TimePosition=.15000000596, but WeightCurrent retained .0625. Destination was playing at Current=Target=1, phase=.1478743106. The previous 16 samples passed. This is direct evidence that a stopped track can retain a stale raw current in this engine state; it is not evidence that the cached value still contributes to the bones.

The follow-up patch retains raw currents in every state and reports `maxInactiveRawWeight`, but excludes a correctly stopped zero-target track from the **active** weight-error calculation. It does not accept that exception on state alone: every zero endpoint must also pass the single-track reference comparison above before skin calculation. A nonzero positive-track weight error, an unexpectedly playing zero track, a nonzero zero-track target, or a mismatched endpoint pose still fails closed. No production adapter priority or behavior has been changed. Actual live Stop(fade) checks remain separate because an outgoing track can contribute during its fade after IsPlaying becomes false.

Compilation: Luau 0.737 passed, including the endpoint-reference revision. Parent owns its native execution; critic has been asked for an independent bounded review. The temporary supported Mesh/Image API setting must be restored to its prior OFF state before publication, as already tracked by parent.

API reference: [Roblox AnimationTrack documentation](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack) describes Play, Stop, weights and seeking; its sample starts a nonplaying track before adjusting it. The exact zero-weight failure above is direct native evidence from this session.
