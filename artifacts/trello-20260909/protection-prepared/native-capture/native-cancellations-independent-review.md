# Independent native L1 cancellation review

**9/10 for the two observed L1 cancellation cases.** Both the pull-stage and completed ground-pin cases pass within the scope below. This is not a score for all levels, multiplayer or the entire Protection release.

All four saved files were parsed independently: full `native-pull-cancel.json` (101,408 bytes), full `native-pin-cancel.json` (108,279 bytes) and their two `native-*-input.json` action/readback records. Source hashes and exact metrics are in `native-cancellations-analysis.json`; the analysis script performs no Studio operations.

| Evidence | Pull | Ground pin |
| --- | ---: | ---: |
| Samples / completed recording | 219 / 14.014533s | 217 / 14.013840s |
| Actual events retained (cap160) | 53 | 64 |
| Input request after actual capture | 0.932681s | 2.348866s |
| Matching actual CancelKill after capture | 1.049661s | 2.499254s |
| Charges | 2→1 | 1→0 |
| HP throughout | 100 | 100 |
| First restored control sample after cancel | 0.033399s | 0.050933s |
| First Kill-track absence after cancel | 0.166983s | 0.183491s |
| Last active / first inactive relative to deadline | −0.050408s / +0.016591s | −0.048953s / +0.016493s |
| Recording continues beyond original lethal time | 7.199009s | 7.049067s |
| Recording continues beyond effect deadline | 5.283008s | 3.683532s |
| Separate measured client walking displacement | 10.600952 studs | 9.992178 studs |

Each case begins with a genuine entity touch and one capture ID. Each then retains exactly one matching CancelKill event. The first case cancels during the pull; PlatformStand never becomes true. The second has PlatformStand=true beginning at capture+1.500999 seconds and a horizontal root before cancellation, so it genuinely exercises restoration from the full floor pin rather than only cancelling an upright grab.

The private fixture state becomes active once, consumes one stored test charge and retains Tokens5. Each trace contains exactly one positive expiry deadline. From the installed service's `ExpiresAt=activationTime+5`, the inferred committed activation times are capture+1.049334 and +2.498868 seconds; this is explicitly derived from the recorded deadline and service implementation, not confused with the first sampled Active timestamp. The measured active/inactive samples bracket those deadlines. There is no sampled active state at or after the deadline and no refresh or reactivation.

At the first restored samples, both players are unanchored and upright with WalkSpeed16, JumpPower50, AutoRotate=true and PlatformStand=false. X/Z matches the last pre-capture sample exactly in each trace. The first post-release Y differs by −0.072798/−0.101359 studs while physics settles; subsequent client snapshots are at about Y3.60 and show upright movement. This supports restoration to standing behavior, without claiming access to the exact hidden saved CFrame or independent visual inspection of every foot contact.

The actual Kill track is already stopped while its normal fade completes. Its last observed post-cancel weights are 0.027778 at +0.100154 seconds for pull, and 0 at +0.116720 seconds for pin. It is absent in the next samples shown above and never appears again. HP stays100 beyond both original lethal deadlines, so neither old capture's delayed damage resumes within the recorded windows. Unlike the unprotected control, neither produces a death.

The client records show CameraType=Custom, the current Humanoid as subject, restored HUD, HP100 and real subsequent walking. Camera position follows that movement. The orientation matrix is unchanged between the two client snapshots in each case, so these files establish camera restoration/follow behavior, **not a separate camera-rotation-input test**.

Root explicitly used actual-player positioning near the entity as setup and a later actual-player retreat teleport. The entity was not relocated and touches were not fabricated. Accordingly, only the isolated before/after client walking segments are counted as movement evidence; cumulative world-position changes are not presented as pathfinding or full-route acceptance. The two charges are existing isolated memory test inventory. The already retained real five-token purchase test covers acquisition separately.

Normal round-to-lobby cleanup is outside these 14-second recordings and remains separate root evidence. These files also do not certify two simultaneous players, Level2 Foam/Slide immunity, Level3 hiding behavior or pit-bottom contact. The event buffers did not saturate, and no native issue requiring a change was found within the two reviewed L1 cancellation cases.
