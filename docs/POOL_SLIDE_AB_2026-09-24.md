# Pool Slide Walk/Run isolated Studio A/B — 24 September 2026

This is a **test result, not a game integration or publication**. After Claude finished its Studio round, Codex tested the existing group-owned Walk/Run animation IDs against two new candidates on copies of the current 20-bone rig. The owner approved this isolated Studio MCP test. The live template and its IDs were never changed.

The four candidate Animation assets were created through Open Cloud at expected price 0. Each create-operation receipt reports `state: Active` and `moderationState: Approved`:

| Variant | Walk | Run | Source/receipt |
| --- | ---: | ---: | --- |
| Live v1 | `103719823156557` | `128800704640816` | Existing Studio template |
| Dropout-repaired v2 | `95711439274562` | `74954076089837` | [`candidates/animations`](../assets/models/pool_slide/candidates/animations) |
| Scale-neutral v2 | `100254982019982` | `80850407466977` | [`candidates/scale-neutral/animations`](../assets/models/pool_slide/candidates/scale-neutral/animations) |

In Studio Play Server, the verified template (`ServerStorage.Level2Assets.Level 2 Pool Slide Template`, `ScaleTo(6.6)`) was cloned three times at y=1000. The clones were anchored, noncolliding, nonqueryable, and away from gameplay. `ContentProvider:PreloadAsync` loaded each animation before `Animator` playback. Each clip was frozen at its authored keyframe times, with 20 `Bone.Transform` values and both foot-bone world positions sampled. No gameplay script or template property was edited. The Play session was stopped; Edit mode was confirmed with no test folder, and the live Walk/Run IDs remained the original IDs. The [saved v2074 native backup](../artifacts/poolslide-20260924/README.md) existed before the test.

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

**Recommendation:** proceed with the scale-neutral v2 pair only after a guarded Studio swap with fresh source/editor conflict checks and native backup, then test walk 10, chase 20, enraged 32 studs/s, turns, full contact/attack envelope, collision/navigation and sound in real seeded Level 2 rounds. Compare visual foot contact and skinned soles at each speed; measure physical phone/tablet FPS and memory. If any regression appears, retain the current IDs. The card stays open and no new place version was published by this test.
