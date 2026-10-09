# Final independent review — centered Shops / Upgrades / Music

**Overall release score:9/10. Final requested button design:10/10. No blocking finding.**

This decision covers the latest user revision: three equal squares on the left, vertically centered where the safe geometry permits, ordered **Shops → Upgrades → Mute/Unmute**, a matching new music-note image, and all three controls usable during lobby Dispatch. It supersedes the previous dispatch-mute-copy design review.

## Exact accepted implementation

| Source | SHA-256 |
|---|---|
| Store | `cb9396a4a796810a1725426c5f3732c808f96fe6e0c5c60740c601756ae290b0` |
| RoundUI | `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3` |

Both current filesystem sources matched those hashes on final review. The final Store delta is reviewed in [dispatch-available/independent-code-review.md](dispatch-available/independent-code-review.md); its preceding layout/state composition is reviewed in [music-toggle-revision/independent-code-review.md](../music-toggle-revision/independent-code-review.md). RoundUI restores the exact pre-side-copy bytes, leaving the original Dispatch controls and preference intact.

I independently reran304 actual-source layout, capability, visibility and real open-path checks, including the earlier261 cases; the old briefing-gate negative fails as intended. I also reran31 shared Settings-state checks and their original-row-only negative, and whole-compiled the relevant proposals. These counts are overlapping checkpoints, not additive coverage totals. The earlier initial-Selectable bug was found during independent review, fixed, and tested using actual UIDevice remembered-capability functions. No speculative music-connection patch was introduced.

The image assets remain Shop132462891522145, Upgrades119432640057145, and Music102262986416811. I viewed all three original image masters and the actual rendered controls. Their shapes, colors and complete inset artwork form a coherent family; the three squares now have matching dimensions and spacing, and their captions remain distinct from the icons.

## Native desktop

[native-desktop-final-on.jpg](native-desktop-final-on.jpg) and [JSON](native-desktop-final-on.json) show a1518×675 camera viewport and1518×617 GUI safe area. The three64px squares sit at x8 and y205/277/349. The208px stack has204.5px ideal top/bottom margins; its integer placement differs by only half a pixel. All three images are loaded and capitalized captions fit. The outlines are complete.

Root's fresh first side-click, before opening Store, is captured in [native-first-click-observed.json](native-first-click-observed.json): the actual server action requests `LobbyMusicEnabled=false`, both server and client read false, and both decks are stopped at volume0. [native-desktop-dispatch-off.jpg](native-desktop-dispatch-off.jpg) shows those controls alongside the actual LIVE Dispatch panel. In the original JSON, `dispatch` means the **ZyntraMuteDispatch preference**, not whether a briefing is active.

[native-desktop-settings-off.jpg](native-desktop-settings-off.jpg) shows the existing Lobby music Settings row agrees with OFF. Root then used that Settings control to restore ON; [native-desktop-final-on.json](native-desktop-final-on.json) records music=true, caption Mute, DeckA playing at approximately0.12 and DeckB stopped. Root also verified the actual Upgrades opener during Dispatch. The existing tab/last-tab behavior is preserved; this review does not assert a new forced-Upgrades-tab behavior.

## Native phone emulator

[native-phone-dispatch-on.jpg](native-phone-dispatch-on.jpg) and [JSON](native-phone-dispatch-on.json) show actual Studio iPhone13 emulation, camera749×368 and safe GUI749×310, with `briefing=true` and `dispatchActive=true`. **All three buttons are visible, active and selectable.** Their captions are Shops, Upgrades and Mute; all images are loaded and all captions report TextFits=true.

Every square is56×56, at x8 and y29/91/153. The180px stack would be centered at y65–245, but that intersects the visible thumbstick glyph at y217. The accepted minimal36px upward shift gives y29–209 and approximately8px of clearance. Thus desktop is centered exactly to pixel rounding; this phone layout intentionally shifts upward for the movement control. The screenshot confirms readable labels, matching squares, full borders and clear separation from the visible joystick.

[native-phone-shop-during-dispatch.jpg](native-phone-shop-during-dispatch.jpg) records the actual Shop opening from this state. Opening the terminal owns the screen and suppresses the briefing through the existing modal behavior; the rail is restored after closing.

The final phone [OFF JSON](native-phone-off.json) and [image](native-phone-off.jpg) show music=false, caption Unmute, both decks stopped at volume0 and the music button still usable. [ON JSON](native-phone-on.json) shows music=true, caption Mute, DeckA playing at approximately0.12 and DeckB stopped. These agree with the actual audio state, not merely the shared optimistic UI. The lower DeckA volume around0.0288 during active Dispatch is the existing music ducking behavior, distinct from muting the Dispatch voice.

[native-phone-input-taps.json](native-phone-input-taps.json) records the terminal-close and both music taps as Touch events with `processed=true`, maximum MoveDirection0 and displacement0. The separate [joystick trace](native-phone-input-joystick.json) records `processed=false`, maximum MoveDirection1 and displacement0.260586351studs. This supports the intended active-GUI use within the joystick's broad invisible activation region while keeping its visible glyph clear; it is not exhaustive simultaneous-multitouch coverage.

Selected immutable evidence hashes:

| Evidence | SHA-256 |
|---|---|
| Phone Dispatch ON | `f188586c44c23917d70779f9cca9cee96555feb94ff0766ed2b69f0adfcf31fe` |
| Phone OFF | `931b6d1285d650cd944e8debf6a881bbb91f3dfd60e998e50714a2e3631f6696` |
| Phone ON | `1f47e25e5bfb322d256eaab43795d2d001fa46419a9ce5318c38a1b0ade60ff0` |
| Phone taps | `c0d6539fcf0dce008edc66ac22c35122fbe657316b2a202b35c6c438514444f7` |

## Limits and disposition

The original [native-desktop-off.json](native-desktop-off.json) remains an unsuccessful/unresolved observation: the optimistic Unmute caption accompanied music=true and an active deck. Its cause was not established. The fresh first-click server/client/deck evidence and subsequent desktop/phone transitions pass without a speculative connection change. The original observation is not deleted, relabeled a pass or claimed fixed by an unrelated caption change.

Phone results are Studio device emulation, not a physical-phone certification. Portrait, extreme-height/no-safe-glyph fallback, concurrent-touch behavior, physical gamepad navigation and live DataStore/rejoin persistence are not newly certified. Focused source tests cover pending reversals, stale timeout/acknowledgement behavior and restored selection capability. No purchase, level completion or deferred DEV/ESP feature is included in this release decision.

Root reports temporary observers removed, LobbyMusicEnabled restored true, Dispatch mute restored false, and Play stopped. Root owns the final stopped-Edit audit and mouse publication. This review supplies GO for these exact sources after that ordinary final audit; it does not claim publication has already occurred. No Studio, production, Git, Trello or Discord operation was performed by this reviewer.
