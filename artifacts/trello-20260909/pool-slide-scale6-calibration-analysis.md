# Scale 6 calibration analysis — 10 September 2026

Read-only analysis of the complete, parsed `pool-slide-scale6-measure-full.json` (116,116 characters). This supersedes the truncated return, whose nested clip data must not be treated as complete. No additional Studio/API execution or runtime edits were made for this analysis.

## Reliable measured scope

Both existing mesh assets were read during root's temporary supported API enablement: 13,105 + 1,986 vertices, 417 animation poses, 6,292,947 reconstructed vertex positions. Both bind scales were5.9999966; unit-basis rest mapping errors were below0.0000155 studs and rest vertices exceeded part boxes by at most0.0000735. Four clips had observed motion, seek error≤0.000000112 seconds, and closed foot-loop endpoints within0.00075 stud. The later actual-vertex bind-agreement hardening is not present in this report and must not be claimed as executed.

| Clip | Sampled minY | Sampled maxY | Span | Radial maximum |
|---|---:|---:|---:|---:|
| Idle | -6.443901 | 6.233810 | 12.677711 | 5.979161 |
| Walk | -6.245804 | 7.653442 | 13.899246 | 6.138854 |
| Run | -5.638016 | 8.541290 | 14.179306 | 6.743577 |
| Attack | -6.300911 | 9.698792 | 15.999702 | 7.218926 |
| Union | -6.443901 | 9.698792 | 16.142693 | 7.218926 |

All Y values are relative to the model pivot. Attack controls the top and radial extent; Idle controls the lowest point. The existing stored-envelope scaling prediction12.915 is insufficient for the sampled actual skin.

Current controller margins imply minimum sampled AgentRadius7.318926 and AgentHeight16.442693. The proposed **R7.5/H16.7** leaves0.181074/0.257307 beyond those required minima, as finite-sampling reserve. This is a reasonable physical-preview candidate, not final certification: transitions, actual rendered landmarks and new-geometry navigation remain required. Preserve the actual `AnimatedEnvelopeRadius/Height` distinction from agent safety dimensions.

**Exact body crest times were not recorded in this report.** It stores each clip's aggregate skin bounds and per-phase foot data. Therefore Attack is the known crest clip, but assigning its body maximum to a precise time would invent evidence. Visual inspection can begin around the measured foot-lift apex0.674s and attack contact0.5s, then seek the actual head/hand extreme. Those starting points are not asserted body-crest times.

## Exact foot phases to inspect

These use the real weighted vertex groups, 728 left-foot and725 right-foot vertices, at GroundOffset6 plus the navigator's0.08 clearance. Negative gap means penetration below that floor plane. Group selection still needs visual confirmation; it is not an IK/contact solver.

| Clip/foot | Lowest-gap time | Lowest gap | Highest-gap time | Highest gap |
|---|---:|---:|---:|---:|
| Idle left | 1.133333s | -0.277750 | 2.533333s | 0.645514 |
| Idle right | 1.133333s | -0.363901 | 2.533333s | 0.600386 |
| Walk left | 0.366667s | -0.165804 | 0.050000s | 1.760984 |
| Walk right | 0.833333s | -0.055269 | 0.033333s | 1.617697 |
| Run left | 0.266667s | 0.441984 | 0.500000s | 4.301710 |
| Run right | 0.566667s | 1.163061 | 0.133333s | 3.156591 |
| Attack left | 0s | -0.000208 | 0.673973s | 3.796583 |
| Attack right | 0s | -0.220911 | 0.673973s | 3.725203 |

Run's **entire reconstructed skin** remains at least0.441984 above the floor in this static placement; neither foot group has any sample within±0.2 of the floor. A run can legitimately have flight phases, but an entire cycle without a stance reaching the floor needs native visual verification. Idle right is below the floor in163/241 samples; left70/241. This is not a one-frame isolated contact glitch.

## Minimal calibration scope

1. **Geometry first:** use the measured body envelope for taller-tunnel acceptance, with R7.5/H16.7 as a test candidate. This does not require changing the rig's offsets or clips, and does not depend on audio. Keep rig/fit approval flags pending their actual evidence.
2. **Rate preview only:** increase the two existing animation-reference speeds; do not introduce another animation framework. Foot-derived candidates are Walk13.9589(left)/11.2459(right), Run30.0902(left)/25.0296(right). An equal-foot compromise around **Walk12.6/Run27.6** gives rates0.79365 at walk10 and0.72464/1.15942 at run20/32. It greatly reduces the old scale4-rate mismatch but needs actual moving-foot inspection before being selected as final.
3. **Do not treat heuristic intervals as verified stance.** Walk estimates use only6/4 intervals around0.30–0.40s and0.783–0.85s. Run left uses just2 intervals0.233–0.267s; right's5 intervals0.55–0.633s vary from45.15 to4.58 studs/s. Those run feet are still above the floor. The rate medians can guide a preview but are not reliable contact-speed calibration by themselves. Equal-foot compromise is preferable to blindly weighting whichever foot produced more threshold intervals.
4. **A single constant height adjustment cannot fix this.** Raising GroundOffset by0.364 removes the deepest Idle penetration but increases Run minima to0.806/1.527. It also violates the controller's current requirement that GroundOffset agree with the static box by≤0.12. Lowering to plant Run makes Idle/Attack penetrate further. Do not silently relax that assertion or add a moving pivot compensation just to make the tests appear green.
5. If normal visual Play confirms the vertical defects, correct the existing animation's authored root/hip height/contact timing, then republish those corrected clips through the established asset workflow and remeasure the affected clips. This is an animation correction, not just a scalar reference-speed change. Prefer that over per-frame scripted Bone.Transform edits, new IK or state-specific magic offsets. If no current editable clip workflow is available, preserve the concrete limitation and finish the independently testable tunnel geometry while leaving entity activation unapproved.

At reference12.6, the two Walk proxy slips predict approximately+1.08/-1.07 studs/s at speed10. Their asymmetry means no single reference meets a strict±10% target for both current medians: the admissible intervals would require R≥12.690 and R≤12.495 simultaneously. That proposed QA threshold is not a user rule; the fact matters because repeatedly tuning one constant cannot remove asymmetric authored strides. At Run27.6 the median proxy errors are about+9.02%/-9.31%, but airborne/weak stance selection prevents treating that as a pass.

The brief 1× track replay ratios1.048–1.103 use only six Heartbeats against wall clock. They confirm advancing tracks but are too short and frame-boundary sensitive to justify changing playback rates by an additional correction factor.

Root owns native validation and the temporary experience API setting. Restore that setting to its original state before publishing as already recorded by root; no setting changes were performed by this agent. Full-frame performance measurements must run separately without the vertex scanner.
