# Current independent review criteria

The latest user request supersedes the left Shop/Upgrades/dispatch-mute column. Review the new artifacts against these requirements, not against the previous design's 10/10.

- Three equal square buttons at the left edge: Shop, Upgrades, then music mute. The latest additional revision requires visible captions **Shops**, **Upgrades**, and **Mute/Unmute**. Keep complete outlines, centered icons and readable labels; the third icon is the new image-generated music note in the same two-color family.
- Center the column vertically in the desktop safe area. On the measured phone safe area (height310), three56px squares with two6px gaps form180px. Ideal y65–245 overlaps the actual visible thumbstick at y217. The minimum upward shift36px yields y29–209 and8px glyph clearance. This is an explicit phone compromise, not exact phone centering.
- The new control changes `LobbyMusicEnabled` through the existing Settings `SetAccessibility` path and shares its pending value, serial, acknowledgement and timeout handling. It must stay visible and usable when music is OFF; a pending-state caption or icon must not remove the control or defeat another authorized toggle.
- All three controls must remain visible and usable during Dispatch. This applies to the real open/toggle handlers as well as visibility; the former briefing veto must not silently reject an otherwise visible Shop/Upgrades button. Existing queue/full-terminal/round gates still apply where they own the screen.
- The Settings row and side button must agree after either is used. Native acceptance should inspect the actual attribute and both music decks, in addition to captions/icons; optimistic UI alone is not proof that sound stopped or resumed.
- Remove only the previous side dispatch copy from RoundUI. Preserve the original dispatch button, M/LB behavior and preference. Do not confuse dispatch muting with the new music control.
- Desktop and actual Studio phone-emulator screenshots must show all three equal squares, complete artwork/outline and readable captions. Phone rail taps should be consumed without starting movement, with the visible joystick still usable separately. Do not claim a physical-phone or exhaustive simultaneous-touch test.
- Keep Store tab/purchase behavior and modal/round visibility within the existing scope. Do not activate or ship the deferred ESP/DEV work.

Code and combined behavior require an honest score of at least8. The retained visual design requirement is an honest10 after native evidence. Preparation alone does not certify appearance or publication.
