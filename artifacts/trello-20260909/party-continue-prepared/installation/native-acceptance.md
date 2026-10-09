# Continue native acceptance — 2026-09-10

Two actual Studio clients, Player1 (-1) and Player2 (-2), joined the normal Level 1 queue and arrived together, healthy and unanchored. Controlled `PuzzleWon=true` fixtures advanced the ordinary GameManager win predicate only after normal round readiness; these were not full puzzle playthroughs or earned-completion tests.

Player1 clicked Continue. Player2 saw Player1 CONTINUE and itself WAITING after 34.653 seconds (native-wait-duration.json). The session stayed in Level 1. Player2 then clicked Continue; the real server logged two continuing/cohort two, and both clients arrived in Level 2. Screenshots and the targeted server log accompany this note.

After the second controlled result, Player1 clicked Continue, then Back to Lobby. Player2 saw that authoritative choice change to LOBBY. Player2 continued; the server logged one continuing/one returning/cohort one. Both returned to the lobby through the existing Studio mixed-choice fallback. This does not verify a live reserved-server split or rejected TeleportService request.

Six-row rendering was tested separately using a synthetic server win/choice payload with six 20-character usernames. Native text rendering passed desktop, 568×270 and 390×844 layout fixtures. On the synthetic mobile fixtures the actual result frame was resized along with the existing UIDevice override, so TextFits measured the intended widths. All eleven visible labels/actions fit; shallow buttons were 239×44 pixels and all bounds stayed inside the frame. This was six-row display coverage, not six-client gameplay.

The native shallow screenshot exposed the old decorative divider crossing rows five/six. The final source hides that divider only while the party decision screen is active. The corrected six-row screenshot has no crossing; a native lose-screen fixture confirmed the divider remains visible there. This final change touches no party or transport logic.

All runtime overrides were cleared and Play stopped. Final native compile: 125/125. Repository/Studio audit: 125 matched, zero drift, with the previously allowed trailing newline for Level 2 Lighting Controller.
