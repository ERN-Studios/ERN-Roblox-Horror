# PoolSlide: Idle→Walk incoming phase comparison

Artifact `pool-slide-idle-walk-phase-grid.luau`, compiled with Luau0.737. It reuses the independently reviewed complete mesh reconstruction and native single-track endpoint checks. No production animation, fade, Root curve, grounding value, priority or movement reference is changed.

Sixteen cases: outgoing Idle phase fractions0/.25/.5/.9999 crossed with incoming Walk fractions0/.25/.5/.75. Each uses default .16-second fade, 17 alpha samples, source phase advance at1x and Walk advance using actual WalkSpeed/10.82. Total272 skin samples and32 required isolated endpoint comparisons. Positive active weights and phase/target checks remain strict. Inactive cached raw weights are recorded and accepted only after the endpoint equals the remaining clip alone.

The compact report gives all16 minima plus each incoming phase's worst floor gap over all four outgoing phases. This is candidate selection; positive clearance at four sampled Idle phases does not establish continuous phase coverage or smooth visual starts. A chosen candidate still requires fresh real-time measurement and visual review. No other solo, channel, 72-case transition or live-fade sweep is repeated.

Recreate the reviewed V1/V2 local clip folders with the existing artifact builders in the next normal Play; use the existing saved original authoring folder. Full report chunks are saved under `ServerStorage.TrelloPoolSlideIncomingPhaseFull`, 40,000 characters each, with `_G.TrelloPoolSlideIncomingPhaseResult` fallback. This probe is independent of the previous Play session's mesh/animation objects. Parent owns Studio execution and restoring the temporary Mesh/Image API setting to OFF before publication.

Prior native evidence: all seven fresh real-time baseline/fade-comparison cases passed their lifecycle, weights and endpoint checks. Default Idle→Walk at outgoing .25 dipped about−.13013 studs (repeat−.13097). Shorter .08/.04 fades worsened that to−.14802/−.15327 and were rejected. This new test explores incoming phase without making a production change.
