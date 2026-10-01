**Preferred: Candidate A, low end.** In the existing controller, raise only the normal-grade Ambient by +3 per channel: (18,17,16) → (21,20,19). Step to +4 only if +3 shows no visible change. Leave everything else untouched, including the unlocked grade and blackouts.

**Why A over B**
- Existing Level 6 gating and capture/restore keep lobby and Level 3 isolated.
- No new lights: blackout baselines, the 10-lamp flicker list and render cost are unchanged.
- Ceilings get little direct light from downward fixtures, so a flat lift should show most there and least in lit pools.
- B edits a WorldBuilder candidate still lacking a live baseline, depends on carrier orientation, and its uplights may not follow name-tracked lamp flicker.

**Tradeoff:** A also lifts floor and corner blacks slightly. If shadows flatten before ceilings read, stop and report; B in large rooms only is the fallback.

**Required in-game checks**
- Matched pairs: same camera position, FOV and graphics quality, lamps steady rather than mid-flicker, in a Party room, Hall, corridor and dead-fixture area.
- Pass: ceiling detail is legible, the difference shows only when flipping between shots, and lamp pools and darkest corners look unchanged.
- Unlock hand-off, blackout and completion blackout look unchanged.
- Lobby and Level 3 shots match before/after; Lighting values after exit equal the captured ones.

I was given no screenshots, so this rests on the described source. Compare-and-set only proves the value changed; the matched pairs decide subtlety.
