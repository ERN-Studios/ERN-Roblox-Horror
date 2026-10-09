# Music square and removal of the side dispatch copy

Prepared from the actual published v1876 source. The user's clarified request is a square **lobby music** toggle under Shop and Upgrades in the left stack. The original briefing MUTE DISPATCH and STOP DISPATCH controls remain unchanged. No production, Studio, UI, asset upload, Trello, Git or Discord action was performed by this preparation.

## Exact ownership and composition

- `proposed/StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua` restores SHA `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3` from current `59c29543…4a519f`. The output is byte-identical to the preserved pre-side-copy baseline. Only v1876's side dispatch copy and its idle exception are removed; all original dispatch, Continue and camera behavior is retained.
- Maxwell owns the centered three-square geometry, `ZyntraMusicButton`, its visibility and logo construction in `center-music-buttons-revision`. The old `ZyntraSideMuteSlot` is removed there. Layout input used here is `71e4bd19647233ddba91e50509f90a6b76f8979cb80e9bddd4b9e3a9111da821`.
- `Store-settings-state.diff` changes only the existing Settings closure. `settings-state.before.luau` and `settings-state.proposed.luau` are exact source fragments, not standalone runtime scripts. `prepare.py --store-source <reviewed layout source>` applies that narrow delta without replacing the layout or other Store regions.
- `composed/StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` is the resulting complete proposal, SHA `cdae3e9610561db95fa281edfb5ca6a735ff817dd2ddf51e68bb9f4852d478c0`. It includes the actual uploaded Music image ID `102262986416811` and the correction preserving the GuiButton Selectable capability. Root owns the subsequent native image-load/rendering acceptance. The earlier empty-ID composition is preserved in `composed-before-capability-fix`.

There are no new remotes, global state, local-only music attributes or music controllers. The existing `LobbyMusicEnabled` Settings entry remains the single setting. Its normal `SetAccessibility` payload is:

```lua
actionRemote:FireServer("SetAccessibility", {
    Key = "LobbyMusicEnabled",
    Enabled = wanted,
})
```

The server continues to validate/persist the config-listed boolean and publish the attribute. `LobbyMusicController.shouldPlay()` still requires that actual attribute to be true and normal lobby eligibility; its two decks, crossfade, fade and dispatch ducking are untouched. This changes lobby music, not level music, dialogue, footsteps or other effects.

## Shared UI behavior

Both the Settings Toggle and the new square invoke the same local `requestToggle()`. They share the original `currentValue()`, `entry.Pending`, `entry.Serial`, attribute acknowledgement and serial-fenced 12-second fallback. The existing ability to reverse a pending request is preserved: pending false is a real OFF request, not an empty state. An older timer cannot clear a newer request.

The square's visible caption is `mute` when music is desired ON, and `unmute` when it is desired OFF. Its full parent Text is `mute music` / `unmute music`. While the server preference is unknown, the square remains visible as `music` but disabled; the music setting's original row is disabled too. Both become usable when the actual boolean arrives. Layout controls visibility; the state closure never makes a hidden square visible and rechecks lobby/modal eligibility at activation. OFF remains clickable so the player can turn music back on.

The captions reflect the shared pending intention immediately. Actual sound changes only after the server attribute updates; captions alone are not evidence of muted decks or a completed durable write. Normal music does not take the old config-absent `entry.Local` fallback, and no local `SetAttribute("LobbyMusicEnabled", ...)` is added.

## Verification and root handoff

Run `python artifacts/trello-20260909/music-toggle-revision/test_music.py` after composing against the frozen layout. It executes 31 actual-source checks for unknown/saved-OFF readiness, both input routes, rapid ON/OFF requests, matching/mismatched acknowledgements, stale/current timers, hidden/modal/round guards, isolation from other Settings rows, and actual UIDevice rememberedFlag/SetEnabled/SetInteractive behavior across unknown/hidden to ready/visible transitions. The original row-only source fails the specific missing-copy negative. Exact inverses prove layout/source preservation, both complete proposed files compile, and both production baselines remain unchanged. See `validation.json` and `composition.json`.

Minimal native acceptance belongs to root:

1. Verify the three actual centered squares and loaded note logo on desktop and phone, including mute/unmute caption fit and normal modal/round visibility. Confirm there is no side dispatch copy or old slot; the original briefing controls still exist normally.
2. Read the original `LobbyMusicEnabled`. Click the real square OFF, observe the matching Settings row and server attribute, then both `SoundService.LobbyMusicDeckA/B` volumes falling to zero and stopping through the unchanged 1.4-second fade. ON must restart through the existing fade. Verify dialogue/dispatch remains independent.
3. Toggle once from Settings and verify the square follows; perform a few deliberate rapid alternating clicks and allow server acknowledgement/fallback to settle. Compare the final actual attribute and both deck states, not only optimistic captions. Restore the initial preference if these actions were only acceptance setup.

This host does not claim native font/load/audio verification, every network ordering, or real durable rejoin persistence. Root owns installation, final native review, separate publication and announcement preview.

The existing image pipeline is `mcp__Roblox_Studio__upload_image({imagePaths: [httpURL], studio_id})`, returning URL-to-`rbxassetid://...` mappings. Prior authoritative use is saved in `square-shop-buttons-prepared/upload-result.json`. Root can serve the approved local PNG through its bounded existing helper, upload once, record the actual response, then observe client loading/rendering. No product/pass assignment or pricing change is needed for this section logo; this note does not perform the upload.

Independent code review: **9/10**, no remaining blocker. The reviewer reran the31 state checks with actual UIDevice helpers, the261 layout checks, their negative controls and whole compiles. See `independent-code-review.md`. Native acceptance and publication are still root-owned and not claimed by this prepared package.
