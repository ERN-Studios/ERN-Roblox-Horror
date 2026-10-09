# Local contact-copy preparation — 10 September 2026

**Ready for native preview; not applied to production or uploaded.** No game source, original authored sequence, model template or production AnimationId was changed by this subtask. Studio calls were read-only inspection/export; root owns Play, camera, geometry changes and the temporary mesh-API setting.

## Actual data and proposed scope

`ServerStorage.TEMP_PipeEntityAnimations_20260909` exists and contains the original KeyframeSequences: Idle121 keys/4s, Walk32/1.033333s, Run20/0.633333s and Attack37/1.200000s. The complete original CFrames, easing, weights and markers are backed up in `pool-slide-original-authored-clips.json`; all210 keyframes were exported from the current Play copy without changing it. Original Root channels are identity. Hierarchy is RootPart(weight0)→Root(weight1)→Hips→actual leg/torso chains. Root bind relative to the model is a180° Y rotation, preserving world up. Attack has one marker and remains excluded from the correction builder.

The earlier asset-provider read established the same KeyframeSequence hierarchy. A repeat read returned an empty keyframe list after cleanup of the returned provider object; the exact cache/loading cause is unproven. The helper therefore clones the known original authoring sequences and never destroys provider-returned/shared originals.

The first candidate modifies **only one Root translation channel** in each of Idle/Walk/Run. Existing Hips/leg/foot/arm rotations, timestamps, priorities, loops and markers remain in their original copies. Root-only keys at the measured60Hz phases are added between existing30Hz keys. Closing Root values are identical to avoid a loop seam. No runtime Bone.Transform loop, IK, additional game system or mesh-API dependency is introduced: the correction lives in ordinary animation data.

- Idle and Walk cancel the measured lowest-sole height drift to leave0.08 stud above the actual floor at GroundOffset6. This preserves the other foot's relative lift.
- Run uses a smooth periodic baseline between its actual left/right low phases0.266667s/0.566667s, lowering those contacts while preserving the original flight between them. A floor clamp prevents the baseline from predicting penetration at measured samples.
- Attack is not copied/edited by the builder. The preview and sampler can play the original authored Attack as an unchanged control, including its hop and marker.

## Files and execution order

1. `prepare-pool-slide-contact-copies.py` reads the complete existing skin report offline and generates the correction JSON and two Luau artifacts. It has no network/Studio code. `pool-slide-contact-candidate-data.json` contains the measured-input correction curve and explicit predicted gaps.
2. Execute `pool-slide-build-contact-copies.luau` as a function definition, then call the returned function with the original sequence folder and actual model template. It returns an **unparented** `TEMP_PoolSlideContactCopies_20260910` folder plus a report. Root may parent that result in ServerStorage for this task. Do not replace the original folder or template. Each copied sequence is marked ContactPreviewOnly. It refuses nonidentity original Root poses and wrong clip durations.
3. In normal Play, execute `pool-slide-preview-contact-copy.luau` on the server. Edit its small OPTIONS block to choose clip, frozen phase, speed and stage pivot. It clones only the rig, prepares it with the actual RigAdapter and registers a copied KeyframeSequence locally through AnimationClipProvider. It changes no camera/player/round state. Default pivotY100 implies actual floorY93.92. The dedicated `_G.TrelloPoolSlideContactPreviewSession` holds its own model/track for subsequent cleanup or rate/phase changes. Rerunning replaces only its owned preview. Stop its track and destroy its model, then clear that one global when finished; stopping Play also removes it.
4. If the observing client does not evaluate the server's temporary Studio hash, the exact copied sequence is under the preview model as PreviewSequence. Register that copy in the observing client and load it into the clone's Animator locally, stopping only that clone's existing preview tracks. This is a local preview limitation, not justification to upload an unvalidated asset. Temporary IDs are never production IDs.
5. `pool-slide-measure-contact-copies.luau` reuses the reviewed full skin scanner, loading the three local corrected sequences and original local Attack through temporary registration. Root may run it after the builder. It records actual-vertex bind agreement and the exact skin extrema times omitted by the previous report. Full JSON is saved in the Play-only `ServerStorage.TrelloPoolSlideContactMeasurementFull` StringValue, with a compact returned summary. Save/read the string in chunks; the connector truncates returns near100k. A pre-existing report is not overwritten. The sampler cleans its own rig/tracks/readers/clips, and never destroys either source sequence folder.

These scripts have been offline-compiled with Luau0.737. They have **not been executed or natively approved** by this preparation agent. The authoring export and original measured skin are real inputs; the corrected results below remain predictions until root runs the preview/sampler.

## Predicted changes and visual risks

| Clip | Root world-Y range | Predicted lowest-foot gap | Main remaining check |
|---|---:|---:|---|
| Idle | -0.5204 to +0.4439 | ~0.08 | Other sole can remain up to0.302 higher; pitch/skew is unchanged |
| Walk | -1.5377 to +0.2458 | ~0.08 | Added counter-bob reaches12.97stud/s at1×; inspect body rhythm and toe roll |
| Run | -1.0831 to -0.3620 | ≥0.08, flight up to2.1402 | Verify two convincing contacts and preserved flight/landing |

The global pivot/nav GroundOffset stays6. This is phase-dependent **authored Root motion**, not an invalid constant offset that trades Idle penetration for worse Run hover. Dividing the desired world correction by model scale6 is intentional; root's bind axes provide the direction. Verify the new native Root movement scales as intended before accepting numeric gap predictions.

Root-Y baking does not fix foot pitch, all foot-height asymmetry or horizontal slip. Do not declare Idle's two feet planted merely because the lowest foot is. If the visible skew remains unacceptable, the next bounded authoring change is to counter-rotate the Foot poses during real stance, followed by recomputing the height curve from the changed skin. That is a second candidate, not already implemented. Avoid mixing such a rotation change into this first measurement, since it changes which vertex is lowest. For Idle, freezing/retargeting the small lower-body pose set is another localized option if it preserves the intended upper-body motion.

Use the earlier12.6/27.6 reference-speed proposal only as a visual starting point. This height-only candidate does not alter XZ paths or magically equalize left/right stride speeds; stance estimates may change after real contact is established. Validate walk10/run20/enraged32, transitions, attack recovery and the actual floor. Attack's original small low-pose penetration is deliberately still present because this task explicitly preserves that clip; report it rather than silently claiming every frame is corrected.

Upper-bound arithmetic puts corrected Idle top≤6.6777, Walk≤7.8993, Run≤8.1793 relative to pivot; original Attack still controls the existing measured top9.6988/radius7.2189. These are conservative arithmetic predictions, not a replacement for measuring blends and actual rendered geometry. Only after native acceptance and independent review should root upload the corrected copies through normal Studio UI, verify ownership/IDs and integrate those specific IDs. No upload or account change was performed here.

Primary API references: [AnimationClipProvider](https://create.roblox.com/docs/reference/engine/classes/AnimationClipProvider) supports loading clips and registering temporary local previews; [AnimationClip](https://create.roblox.com/docs/reference/engine/classes/AnimationClip) documents clip data and properties. These APIs do not publish the generated copies. `KeyframeSequenceProvider` is deprecated, so the new helper uses the supported AnimationClipProvider while retaining the existing native KeyframeSequence data format.
