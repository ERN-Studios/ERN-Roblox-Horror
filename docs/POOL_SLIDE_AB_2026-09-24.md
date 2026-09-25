# Pool Slide Walk/Run isolated Studio A/B — 24 September 2026

This began as an isolated A/B test of the existing group-owned Walk/Run animation IDs against two new candidates on copies of the current 20-bone rig. The owner approved the Studio MCP test. After the A/B result, the scale-neutral pair was applied to the live Studio **Edit** template and tested in a solo Level 2 round. This is still **not a publication**.

The four candidate Animation assets were created through Open Cloud at expected price 0. Each create-operation receipt reports `state: Active` and `moderationState: Approved`:

| Variant | Walk | Run | Source/receipt |
| --- | ---: | ---: | --- |
| Previous v1 | `103719823156557` | `128800704640816` | Pre-change Studio template and native v2074 backup |
| Dropout-repaired v2 | `95711439274562` | `74954076089837` | [`candidates/animations`](../assets/models/pool_slide/candidates/animations) |
| Scale-neutral v2 | `100254982019982` | `80850407466977` | [`candidates/scale-neutral/animations`](../assets/models/pool_slide/candidates/scale-neutral/animations) |

In the isolated A/B, the verified template (`ServerStorage.Level2Assets.Level 2 Pool Slide Template`, `ScaleTo(6.6)`) was cloned three times at y=1000. The clones were anchored, noncolliding, nonqueryable, and away from gameplay. `ContentProvider:PreloadAsync` loaded each animation before `Animator` playback. Each clip was frozen at its authored keyframe times, with 20 `Bone.Transform` values and both foot-bone world positions sampled. No gameplay script or template property was edited during the A/B. The Play session was stopped and its temporary clones cleared. The [saved v2074 native backup](../artifacts/poolslide-20260924/README.md) preserves the original template before the later Edit change.

| Native measurement | Live v1 | Repaired v2 | Scale-neutral v2 |
| --- | ---: | ---: | ---: |
| Walk all-20-bone rest flashes | **31/64** | 0/64 | 0/64 |
| Run all-20-bone rest flashes | **19/39** | 0/39 | 0/39 |
| Walk left foot vertical second-difference sum | 173.99 | 2.72 | **2.44** |
| Run left foot vertical second-difference sum | 293.90 | 4.86 | **4.45** |
| Walk hip vertical second-difference sum | 112.22 | 2.67 | **2.22** |
| Run hip vertical second-difference sum | 172.03 | 3.23 | **2.69** |
| Walk lowest left foot-bone height relative to pivot | −5.806 | −5.806 | **−5.721** |

The rest left foot-bone height is −5.709 relative to the pivot. The scale-neutral Walk therefore dips ~0.012 stud below that **bone reference**, versus ~0.097 for the raw repaired v2. This is not a skinned-mesh sole-clearance measurement. At Walk t=0.35 s, hip translation is 1.418 studs in raw v2 and 1.182 in scale-neutral, exactly the expected 1.20 ratio after `Model:ScaleTo(6.6)`. It supports using the scale-neutral candidate on this already-scaled rig, subject to the active-round test. All variants retain the same duration (Walk 1.0333 s, Run 0.6333 s).

The saved [Walk comparison](../artifacts/poolslide-20260924/walk-v1-rest-v2-ab.jpeg) freezes a v1 rest flash at t=0.325 s; [Run comparison](../artifacts/poolslide-20260924/run-v1-rest-v2-ab.jpeg) freezes one at t=0.3167 s. The view is left v1, middle repaired v2, right scale-neutral v2. The exact summary values are in [`ab-metrics.json`](../artifacts/poolslide-20260924/ab-metrics.json). These are Studio MCP Play captures, not an active Level 2 corridor chase.

## Scoped Studio integration and active round

After the A/B, Studio Edit was reread. The verified template still had the v1 IDs, scale 6.6 and 20 bones. Only `Animations.Walk.AnimationId`, `Animations.Run.AnimationId` and the descriptive `RigNote` attribute were changed, guarded against that fresh baseline. The template now references scale-neutral Walk `100254982019982` and Run `80850407466977`. A later Edit readback confirmed both IDs, scale 6.6, 20 bones and the retained `(pre-1p10 backup 20260924)` sibling. No gameplay script was changed.

The Level 2 queue launched a real solo GameManager round. Its developer pump-pair command activated two distinct pumps through the normal actuator. The active Pool Slide runtime spawned 141.98 studs from the player (minimum 100), created one navigation context and entered CHASE. A server snapshot showed the new Run track playing at 16.86 studs/s while its path status was MOVING, with a successful 142-stud plan and no path failure. Moving the player to a generated patrol node 190.59 studs from the entity changed it to the new Walk track at 10.00 studs/s while CHASE remained active. In a second real round, a **transient Play-only** write raised `workspace.Level2Pumps` from 2 to 3 for an animation-speed probe; the replicated phase became ENRAGED, the new Run track played, path status was MOVING and measured speed reached 32.00 studs/s. The actual objective progress remained 2, so this is not a third-pump end-to-end test. The Play session was stopped; the transient counter and health changes did not enter Edit.

This establishes that both assets load and play on the live rig and that the phase-driven speed switch selects them. It does not yet establish skinned-sole contact, audio quality, physical phone/tablet FPS or memory, or a real third-pump activation after this ID change. The current Edit change is **not independently confirmed as saved to Roblox**; v2074 is the pre-change saved backup, and the latest published version remains v2061. The card stays open.
