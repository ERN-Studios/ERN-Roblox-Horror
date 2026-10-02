# Claude baseline review summary

The actual external review completed successfully using requested `opus` / effort `max`, with reported canonical and assistant model `claude-opus-5-5`, reported tools `[]`, strict empty MCP configuration, 525.37 seconds elapsed, exit code 0, no timeout, and confirmed exit of the directly spawned child. See `baseline/receipt.json` for the exact command, input SHA256 and completion evidence; `baseline/response.md` preserves the unedited model response. That raw response contains 1,256 whitespace-separated words; this concise summary stays below the requested 1,200-word ceiling.

The review covered explicitly supplied baseline excerpts only. It did not access Studio, execute gameplay, test multiplayer, measure performance, or review the later candidate in that invocation.

## Findings from the baseline

- Objective triggers after any living player crosses, instead of all. Exact halfway is already excluded; crossings are character-scoped and latched. A living character lacking a root/character can drop from the denominator.
- AI tries four positions (.97, .95, .93, .90) and imposes the normal 90-stud distance gate, so a fast runner near the exit can prevent the finale indefinitely. Fixed finale placement should have one position and no ordinary near-player distance veto; physical clearance remains necessary.
- Protected living players count in Objective but are excluded from AI spawn and targets. All-protected participants can prevent the reveal; no target also starts random mall patrol. Finale chase membership should retain living protected players while attacks remain immune, and no-target finale should hold position. The supplied baseline lacked the full protection-cleanup body, so its effect was explicitly inferred; the independent audit inspected it separately.
- Adapter retains any existing session and only warns if Start throws. Normal Music DONE transition clears Hunt before the finale, but runtime must verify one fresh finale rig, successful asset readiness, and no silent failed-start state.
- Recovery bookkeeping does not itself relocate. Claude did not receive all physical steering/route functions, so its broad recovery conclusion remained unverified. The independent spawn-path audit inspected those additional functions and found no production teleport.
- Pause refuses movement and attacks; resume behavior needs runtime verification. A crossed player walking back remains latched; a revived character already beyond halfway can latch from its own position.
- Claude flagged Objective cleanup dropping ChaseActive before Hunt. The additional independently inspected Adapter Cleanup lines 530–534 disconnect lifecycle and stop the Manager before stopping music/objective, so normal cleanup already prevents that live-profile edge. No broader flag reorder is needed for this task.
- Reader has no CD-player mode. Absence of visible beacons does not prove all discs are secured: WORLD/DROPPED discs may lack a replicated position. Mode must inspect each current CD state, ignore cumulative collection progress, and handle unknown state conservatively.
- Publish the actual post-Visual CD-player position and clear both state and workspace mirrors. Missing target position must not reuse an old one.
- Existing exit guidance clamps bearing to ±90 degrees and smooths a scalar across the ±180-degree seam. Precise CD-player guidance needs full-circle bearing, safe handling at vertical camera pitch, and correct behind-camera projection. Use camera RightVector to preserve yaw when LookVector is vertical.
- Pointer visibility must follow existing hidden/toast/modal/dispatch/hiding/subject gates, remain non-interactive, and clean up with the reader. Product UI should use ordinary player-facing terms.

## Runtime cases still required

Finale: multiple survivors with one before halfway; exact midpoint; last survivor just beyond midpoint; death/escape/disconnect shrinking the roster; non-round spectator; missing root; revived life; all-protected survivors; fast runner or coincident runner at the fixed endpoint; paused trigger/windup/resume; final insertion during ordinary hunt; blocked fixed endpoint; repeated path/recovery failures; reset removing owned rig/audio/state and callbacks.

Scanner: last CD picked up; a carrier drops/dies/disconnects; WORLD disc without position; unknown state or missing goal; all CDs inserted; bearings ahead/left/right/behind; vertical camera pitch at different yaw; subject change/death/escape while spectating; hidden panel/toast/modal/dispatch/hiding; touch rotation/notches and tap-through; reset/script/GUI teardown.

Candidate fixes and extracted-source mocks are recorded separately. Neither their existence nor this review establishes actual gameplay, multiplayer, replication, physics, or performance success.
