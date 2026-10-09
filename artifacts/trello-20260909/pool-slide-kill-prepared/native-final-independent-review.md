# Pool Slide kill behavior — final independent review

**9/10 for the bounded feature. No remaining blocking finding. Ready for root's separate publication after the final Edit compile/source-parity checks. This note does not claim publication.**

The accepted Controller is `a9c53bf7c95e7d81b08998c0fcfdfe41c9722801712ca30d5c92ea47c91debd0`; the accepted Navigator is `24507756188f5bd0bf80a94570222b3b77542d1ed44831223d4a88c819e26bd8`. Melee range is 10.5 for the accepted large body. A separate 0.2 final-waypoint tolerance prevents the safe approach being consumed too early; intermediate tolerance stays 1.4. Existing full-body movement checks, windup, cooldown, facing arc, vertical range, LOS, Shield and character ownership remain intact. I independently reran 61 terminal/placement and 219 combat checks, five targeted negatives and four whole-file compiles.

## Native evidence reviewed

The open control (`native-seed272080896-open.json`) records actual NPC navigation followed by attack serial 1 and HP100→0 at about 10.46 studs, with Foam hundreds of studs away. The side-wall control (`native-seed1861792796-sidewall.json`) records attack at 10.30669 studs, constant foot/facing during the living windup and subsequent HP0; the later ragdoll position slightly beyond range is not the impact position. Both used the same 10.5 combat reach before the additional terminal-only correction.

The failed corner remains recorded in `native-seed188232071-corner.json`: its terminal waypoint was about 10.0 studs from the tester, but the old follower consumed it 1.35019 studs early and remained ARRIVED at 11.16503 studs for nearly 18 seconds without attacking. This genuine failure is not relabelled as passing.

I independently parsed all **433** samples in `terminal-arrival/native-seed188232071-corner-retest.json` (SHA256 `6468d9683d40db9b86f25328e24c13927420e11314a14a04d30bdee122089a7e`) and the five events in `terminal-arrival/native-dodge-events.json` (SHA256 `acd251ba76eec3d3308dbdc686fe1c78dfca3ec747550a3d0ce5c5231b6c5e4c`). The exact failing layout was generated again through a normal queue. The actual NPC travels **126.329 studs** over **11.787 seconds** from its first recorded position to first ATTACK; two spawn probes use one Navigator build with zero failed spawn passes.

First ATTACK, serial 1, occurs at **10.31187 studs**. At +0.163 seconds from the observer's first attack detection, the fixture moves the actual player 25.456 studs diagonally: distance becomes 15.14442 and frozen facing dot −0.999942. HP remains100 at +1.243 seconds, beyond the original impact window. The NPC foot is unchanged through that attack. This demonstrates native rejection after the target leaves the attack window; it is a scripted dodge, not a measured human movement-speed or reaction-time test, and it changes both range and angle together.

After the player returns to the corner, serial 2 starts at the same **10.31187** distance. All eight living windup samples retain the same NPC foot/facing, clear LOS and facing dot1. HP loss is bracketed at **+0.4564 to +0.5242 seconds** after the first sampled second ATTACK, consistent with the unchanged 0.5-second windup. The nearest Foam is **782.149 studs** away at HP0; no ForceField is reported. These are sequential observations, not an atomic damage-event timestamp.

The attack starts while the follower is still about **0.36665 studs** from its final waypoint. The native result proves that it now advances beyond the previous early stop into melee range; it does **not** prove reaching 0.2 or ARRIVED before attacking.

I viewed `native-corner-retest-view.jpg` and `native-corner-retest-after.jpg`. They show the actual large creature's close corner attack pose and subsequent ending. The QA camera and local avatar transparency adjustment are disclosed; the screenshot is windup, not exact mesh/hand contact at impact. `native-cleanup.json` confirms normal return to a new living lobby character at HP100, no original world/models/tags, cleared manifest and stopped Slide/Foam controllers.

## Practical limits

There is no fresh native Shield or opaque-wall negative case in this run; their unchanged actual-source gates and regression negatives provide the current coverage. No universal guarantee is made for every obstructed goal, arbitrary avatar size, multiplayer arrangement or physical device. The observer does not read the private Shield/Attack records. Existing small animation-blend cosmetic residuals are outside this narrow combat fix and have not been erased from prior evidence.

The reproduced failure, targeted source correction, actual corner attack, native dodge survival and normal cleanup provide sufficient evidence for this release scope. No additional broad test framework is required. This reviewer made no Studio, production, UI or publishing changes.
