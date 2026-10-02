# Read-only live developer gate audit — 2026-10-02

Target: Studio `0552e451-d540-464e-ad9f-478d00392f88`, place `131311258779917`, universe `10559217407`. Studio was in Edit. No Studio writes, Play mode changes, native geometry changes, account changes or Git writes were made by this audit.

Every exported relevant Source matched ScriptEditorService.GetEditorSource at the initial live read. Exact UTF-8 bytes and SHA-256 are in `source-hashes.json`. The four core-script Source/editor bodies are in `live-core-source-editor.json`; the access module and preview controllers are in `live-security-source-editor.json`. GameManager was captured in JSON-encoded chunks because MCP truncates outputs at 100,000 characters; its initial Source/editor equality and exact byte count are retained in `GameManager-source-editor-proof.json`. Its reconstructed UTF-8 Source is 174,786 bytes and SHA-256 `7e4d34889d0900626a6717129f7310170872e307aa108ed1891c9d642f91cc4f`.

## Findings and minimal changes

1. The revised lobby is currently a developer preview. `GameManager.playerInsideZone`, line 1195, rejects every revisionOwned queue, including public Level 1–3 queues, unless Studio or `DevAccess.IsLevel6PreviewAllowed(player)` returns true. New public spawn must remove that blanket filter or narrow it to preview levels. The existing `station.previewQueue` branch then remains responsible for server preview admission via `QueueBridge.AllowsPreview`. Public campaign queues retain their original level/unlock/living-character checks. Do not loosen Level 4 choice modes or campaign routing.

2. `R4DevGateController` creates colliding local shutters for denied Level 5 and 6 access and hides queue titles/subtitles and their developer preview prompts. Its denial display has no progress bar. Preserve the doorway transform and overlap, but add the original ComingSoonDisplay design: black/red portrait display, COMING SOON, WORK IN PROGRESS, ProgressTrack, ProgressFill and numeric progress text. The current authoritative TunnelLobbyBuilder template sets Level 5 to 70% and Level 6 to 30%. These are owner-authored development estimates, not this task's completion percentage. Exact template is retained in `coming-soon-template-live.json`.

3. DevAccess.IsAllowed includes user IDs 40920547 and 9488575949. IsLevel6PreviewAllowed also allows 11374988579 (ZenMeister02), the owner's current account. Level 5 currently uses IsAllowed in its local gate and its server readyPlayer/perimeter checks. Level 6 uses IsLevel6PreviewAllowed. To preserve narrow general developer command rights while allowing the owner into both preview bays, use the existing narrow preview predicate for Level 5 presentation and both corresponding server checks, or introduce an explicitly scoped shared lobby-preview predicate. Do not add Zen to the general IsAllowed allowlist merely for this request.

4. Preview queue launch callbacks already recheck developer authorization through the existing controllers: Level5 readyPlayer and Level6 playerReady. QueueBridge validates the living character, exact owned station, current registered controller, zone membership, frozen cohort and authorization before preparation/commit. The server must remain the authority; local shutter visibility must not act as the authorization boundary.

5. Local shutter collisions normally prevent denied users entering the bay, but an altered client could remove the local shutter. Server preview admission still denies teleport/queue launch. For strict bay access, also use a bounded server-authorized barrier or perimeter rejection for Level 5/6 in the new lobby, independent of client presentation. Never make a globally noncolliding opening accessible merely because one developer is present.

6. Level5PreviewAccess.liveSpawn and Level6PreviewAccess.lobbyPart('LobbySpawn') currently resolve the original ServerLobby. Spawn promotion must update these return paths alongside GameManager spawn/return/reset handling; otherwise preview returns will strand players in the old lobby. Retain the old lobby geometry as requested and route through one validated revised-lobby spawn lookup.

7. Level6PreviewAccess.streamReady uses a nonce, expiry and an authorization recheck; preserve those. Level5's existing 0.5-second distant-preview unauthorized-player sweep also uses IsAllowed and must change consistently if Zen is authorized for Level 5.

The revised runtime model is not instantiated in Edit. `revised-gate-geometry-live.json` is intentionally an empty list from that read; it is not evidence of missing runtime geometry. Runtime visibility/collision/display checks require actual Play.

## Required verification

- Actual nondeveloper identity: opaque Level 5 and 6 closures with ComingSoon/progress display, no preview prompts or queue UI; walk/jump cannot enter; server rejects queue/preview admission even if local wall presentation is removed.
- Developer identities: both openings visible, Level 5/6 preview prompts and queues usable, return to revised spawn. Zen must work without granting broad developer command rights.
- First spawn, death/reset, return-to-lobby and campaign completion route to the new validated spawn; no reserved-round server spawn regression.
- Public Level 1–3 queue UI/admission remain functional in the revised lobby; preserve Level 4's developer trial/preview chooser and authorization.
- No material gameplay or multiplayer claim can be made from this source audit alone.
