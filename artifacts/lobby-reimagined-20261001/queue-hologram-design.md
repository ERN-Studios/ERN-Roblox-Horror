# Queue hologram and separate preview

Design only. Fresh read-only Studio inspections used the connected correct place `131311258779917` / universe `10559217407`, loaded version `2450`. `ServerScriptService.GameManager` (Script, 159,281 bytes) and `StarterPlayer.StarterPlayerScripts.RoundUI` (LocalScript, 260,892 bytes) both returned exact Source/editor parity. Selected authoritative lines are saved in [queue-state-readonly.json](queue-state-readonly.json), [queue-ui-readonly.json](queue-ui-readonly.json) and [queue-consumers-readonly.json](queue-consumers-readonly.json).

## Actual queue contract

The floor cylinder should appear **after the host's settings are accepted and the countdown begins**, not when somebody occupies the pad or opens the host phone UI.

| Actual phase | Current server authority / replication | Hologram |
| --- | --- | --- |
| Idle / no living eligible players | `resetStation`; no host/configuration; station title returns `0/6` | Off; base floor ring stays visible |
| Host configuring | `runStation` sets `host`, `awaitingConfig=true`, `configured=false`; `queuehost` goes only to the host, `queuewaitinghost` to other occupants | Off |
| Config accepted | Valid host `ConfigureQueue` event sets `configured=true`, `awaitingConfig=false`; `queueconfigured(maxPlayers, privacy, stationIndex)` goes only to the host | Start once the authoritative active/countdown phase is published |
| Countdown | Server recomputes accepted members and host eligibility. `lobbycountdown(seconds, acceptedCount, stationIndex, maximum, privacy)` goes only to accepted members each second | On; one smooth rise/fade, stable thereafter |
| Full | Existing full-capacity collision barrier is separately managed by server `setStationBarrier` | Hologram stays cosmetic; do not replace/duplicate that barrier |
| Cancel / host leaves or dies / empty | Setup cancel sets `cancelRequested`, moves host out; the station loop resets. Countdown cancels if host disappears/leaves or accepted count reaches zero; `lobbycancel` goes to last accepted group | Fade out; clear previous generation |
| Launch / load | `launchStation` sets `busy=true`, sends `loadinggame` to participants, then Studio round or reserved-server teleport | Hide on launching; do not leave a cylinder through loading/round lifecycle |
| Failure / reset | Studio busy and teleport failure send `lobbycancel`; reset clears host/configured/awaitingConfig/cancel/caches and restores station title | Off until a new accepted queue starts |

Evidence: GameManager lines 1392–1427, 3033–3125 and 3346–3467. Full parties and DEV fast queues shorten the countdown to 3 seconds; use server time/state, not a hard-coded 10-second local animation. `RoundUI` lines 4406–4468 confirm event argument order and UI teardown.

**There is currently no typed, publicly replicated queue phase for every spectator.** The `station` table is private server state; these RoundStatus events use `FireClient`/accepted groups, not a whole-lobby broadcast. The replicated station title/subtitle are presentation, not a stable semantic API. Neither raw occupancy nor parsing `GAME BEGINS IN` is an appropriate production trigger. Future live integration should publish a small server-owned per-pad snapshot (`Phase`, `Generation`, `ReadyCount`, `Maximum`, optional countdown deadline) at those exact transitions. Clients read existing snapshots on bind/stream-in and subscribe to changes. Cancel/reset/launch increments or invalidates the generation; old tweens cannot resurrect it. This future integration would require a separate scoped GameManager edit, **not part of the isolated preview**.

## Feasible cylinder render

Preferred asset: one reusable Blender cylindrical wall, about 14.82 studs diameter and 7–9 studs high, open visually at the top and center. Give its wall minimal volume, with a vertical UV strip whose RGBA color map is cyan and moderately transparent at the bottom, fading smoothly to alpha zero by the upper edge. Pre-author `SurfaceAppearance.AlphaMode=Transparency`; a small nonzero MeshPart transparency (at least 0.02) enables smooth alpha blending per Roblox's documentation. Animate only its local height/center and overall transparency during activation, keeping its lower edge fixed at the floor. Avoid changing uploaded PBR maps at runtime. [Roblox PBR alpha modes](https://create.roblox.com/docs/art/modeling/surface-appearance)

Alternative if mesh alpha blending is visually unsuitable on target devices: a modest ring of vertical Beam strips, each with bottom/top attachments, a height-wise transparency NumberSequence, and no scrolling. Beams support gradient transparency; they are 2D projections, so this fallback needs an actual round-view check for gaps/angle artifacts. LightEmission affects blending and does not illuminate the room. [Roblox Beam API](https://create.roblox.com/docs/reference/engine/classes/Beam)

Render clones locally under a dedicated client effects folder. All cosmetic Parts/MeshParts are anchored, `CanCollide=false`, `CanTouch=false`, `CanQuery=false`, `CastShadow=false`; no new PointLights, particles, gameplay tags or collision groups are needed. Do not cap the cylinder with an opaque disk. Keep floor-ring/monitor labels readable, with normal depth occlusion. Suggested transition 0.4–0.7 seconds, no pulses/strobes/noise: with `ReduceFlashing=true` use the stable low-intensity cylinder directly, with minimal fade. Low quality can retain just the floor ring plus one lightweight shell; cull distant effects and remove local effects/listeners when the preview/lobby disappears or the client enters a round. These are targets requiring device testing.

The fresh GameManager now **does use circular containment** when `QueueDetectorShape='Circle'` and valid `QueueRadius` is present (lines 1100–1124), despite an older builder comment saying otherwise. Current radius is 7.41. Preserve its floor/approaches, host exit destination, accepted-member clearance and the existing radius+0.7 full-party barrier. A hologram never creates an admission rule.

## Separate preview placement and interaction

Use a distinct model such as `Workspace.LobbyReimaginedPreview` at **world `(220,30,-760)`**. The current lobby's rightmost bounding-box edge is X93.83. A preview design envelope X125–315, Y28–92, Z−905–−615 leaves at least **31.17 studs of clear side gap**. Read-only scan checked all 34,736 Workspace BaseParts by world AABB, including non-query parts: zero intersections. Bounded Terrain voxel read at resolution4 also found zero non-Air/positive-occupancy voxels. Full receipt: [preview-placement-readonly.json](preview-placement-readonly.json). This is placement evidence, not a collision/gameplay test; fresh recheck before import is required.

Keep preview pad names distinct (`PreviewQueuePad`/`PreviewQueueRing`), not `LaunchZone#`, and clone **none** of the current lobby/controller scripts. Existing effects seek `ServerLobby`; the preview must not rename itself to that or fire `Remotes.ConfigureQueue`/`RoundStatus`. A separate preview-only E action labelled `START QUEUE PREVIEW` can start a local cosmetic cycle, followed by reset/cancel; it does not launch, teleport, reserve a server, alter real queue membership or play the current lobby soundtrack twice. Keep original spawn, real shop, gate prompts and launch controllers untouched.

For comparison, retain a static floor ring when idle, and show the hologram only after that explicit preview action. A parent-installed preview-only client/controller may bind that unique prompt later; this document supplies no implementation script.

## Gate QA and DJ height

The user-approved [Level 3 gate render](concepts/02-level-gate.png) now clearly shows both the portal header and a horizontal projecting `LEVEL 3` sign with an arrow. Its shape and two-sign hierarchy are approved; reproduce the readable broad face along the tunnel, and mirror the reverse-face directional arrow so it points toward the correct gate from the other approach. Background generated level labels are illustrative; current Studio gate coordinates/level identity remain authoritative.

The desired DJ platform height is **4–5 studs**. Speaker towers remain separately floor/ledge mounted so this extra height does not push them into the curved roof. Stairs need a wider landing and verified bounds beyond the Z80 gate approaches. This supersedes the earlier 2.5–3-stud deck estimate.

No Studio/UI/Play changes were made for this audit. The latest user scope authorizes building/importing a separate preview; root owns that implementation and its backup/CAS/verification/publication workflow.
