# First side-music click: bounded diagnosis

No additional connection, server or music-controller correction was made. The fresh observed click reached the existing server handler before Store was opened, so the proposed lazy-initialization explanation is not supported. The earlier mismatch is preserved as an unresolved observation rather than labelled fixed by an unrelated caption/visibility edit.

## What was observed

1. Root's first `cdae3e96` run produced an optimistic `unmute` caption, while `center-music-buttons-revision/native-desktop-off.json` still showed `LobbyMusicEnabled=true` and DeckA playing at approximately0.12. Root reports fallback after12 seconds. This JSON has no received-action timestamp or payload; it cannot identify whether an action was absent, refused, superseded or affected by input timing.
2. Actual Settings OFF then worked; the agent's read-only Server/Client snapshots at server time1789063684.27/.34 show false on both sides and both decks stopped at0. See `diagnosis-after-settings-readonly.json`. These readings were taken after that Settings click, not retroactively attributed to the first side click. Root also observed a later side Unmute work.
3. Root restarted with `cb9396a4` (caption capitalization and availability during dispatch). In `center-music-buttons-revision/native-first-click-observed.json`, the server observer records exactly one `SetAccessibility` payload with key `LobbyMusicEnabled`, enabled=false, at85292.4742845. The server reports false; the client reports false and both loaded decks stopped at0. All three desktop squares are visible/active/selectable and the Music caption is `Unmute`. Root states this was the first side click before opening Store. No music-state/remote correction was added between these two source checkpoints.

The final JSON in step3 has `dispatch=false`. It directly proves receipt and music outcome; it does not by itself prove that the briefing was still active at the click. Any active-briefing claim requires the separately recorded contemporaneous UI observation. Root owns the remaining cross-control and layout acceptance.

## Actual source findings

- Store gets `ZyntraAction` eagerly at line26. It builds the Settings request closures at script startup and starts its initial GetProfile task eagerly, without a modal-open condition. `setMainVisible` is not a required initialization step for this path.
- Server `ZyntraGetProfile.OnServerInvoke` at1821 waits for an existing session and returns its public profile. It does not install the action handler or enable music requests.
- `SetAccessibility` uses a per-key one-second action window at2392–2404. An unchanged value returns without another attribute publication at2476. These are real potential silent-refusal paths, but the first failed observation does not establish either as its cause.
- For a valid changed value, the handler updates session Settings at2477, records the coalesced target, then calls `applyAttributes` immediately at2482. The six-second persistence floor is not an intended six-second delay before the music attribute changes.
- `accessibilityValue` at418–421 preserves an actual boolean false. There is no false-to-default bug in that function. The existing client pending/serial/12-second fallback remains appropriate to an unacknowledged intention and was retained.

Only read-only Studio snapshots and scoped source/log inspection were performed by this agent. No mute remote, attribute, sound property or UI input was written. The optional `native-action-observer.server.luau` was prepared and compiled, but never armed; root used their own bounded observer. Its report would also be evidence of receipt and attributes, not direct access to private server acceptance state.
