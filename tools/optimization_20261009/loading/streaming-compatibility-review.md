# Streaming compatibility review, 2026-10-09

Scope: bounded offline source review of the revised LevelWorldStorage, Level 4
client/generator, Level 6 client and Level 2 runtime/clients. No runtime game edits,
tests or native property changes. Target 384 / Min 64 / Opportunistic / Improved
remains a tentative configuration until Edit inspection and gameplay checks.

## Findings

1. **Spectator region is the material compatibility gap.** SpectateController
   follows another body's Head with a Scriptable camera, while GameManager's
   validated target map originally only counted spectators. No replication-focus
   registration was found. The scoped spectate/ proposal addresses the missing
   extra focus; actual separated multiplayer spectators remain unverified.

2. **Revised Level 4 clients tolerate missing/reappearing root models.**
   watchModel releases registrations when a replica leaves Workspace and reacquires
   through Workspace.ChildAdded. DescendantAdded/Removing tracks zone lights,
   neon and screens; screen state is rebuilt for arrivals and cleaned on removal.
   Client Usher visuals are local with motion packets rather than dependence on a
   distant streamed server rig. The generator keeps Collision PersistentPerPlayer
   for eligible round players, so their whole proven floor remains replicated.
   That collision is a savings ceiling, not a reason to claim a radius reduction
   removes all distant collision. L4 notes, three reels and server Usher proxy
   separately remain Persistent in their authoritative controllers.

3. **Revised Level 6 client guards absent roots.** Its 0.1-second marker/finale
   loop computes on only when the map exists. Slides, audio anchors and props use
   guarded FindFirstChild paths. Marker target positions come from map attributes,
   so no far exit Part is required merely to draw the marker.
   A residual retention issue remains: litBefore holds strong light/neon references
   until the whole model disappears. Individual parts streaming out while another
   part keeps the root present are not removed from that table. This can reduce
   memory savings during long exploration/finale; it is not a demonstrated crash.
   Repeated stream-out/in cycles and native local-property restoration need checking.

4. **Level 2 gameplay runs on the complete server map.** Round Adapter parks/adopts
   the same authored model. Poolrooms Runtime's far markers, zones and physics
   queries execute server-side and are not removed by client streaming.
   The exit slide is explicitly Atomic. Existing slide continuation requests
   stream regions and tests for actual bore collision, rather than treating a
   RequestStreamAroundAsync return as proof.

5. **Level 2 presentation handles arrivals/removals.** It guards missing map roots,
   watches DescendantAdded for flicker holders and DescendantRemoving to cancel
   holder tasks/tweens. Camera clamping queries current collidable geometry.
   Level 2 Sound Controller indexes ambient anchors on arrival and checks parent
   and ancestry before use; it retains strong streamed-out anchor references until
   session reset because it has no matching DescendantRemoving prune. That is a
   residual memory concern whose actual impact depends on matching anchor count.
   Current native Collision streaming modes/properties were not inferred from code.

6. **Entry loading already uses concrete ground evidence.** Round Entry Client
   rechecks current map roots, requests the advertised position and raycasts an
   actual collidable floor at that position. Nearby asset census watches arrivals,
   keeps cancellation/ownership and does not require every remote map asset.
   Smaller radius therefore retains the admission contract, but cannot be declared
   safe for fast slides, teleports or slow network from inspection alone.

## Required verification

- Inspect actual Workspace properties and each map's relevant streaming modes in
  Edit before selecting the configuration.
- Verify lobby spawn, each level arrival, fast slides, teleport/continue/reset paths
  and a separated spectator under actual multiplayer streaming.
- Measure memory, server workload, retry/navigation and frame time on the same
  active-round routes/device. The Level 2 pump-distance/second-spawn/third-escalation
  checks from AGENTS.md remain required.
- Verify root/part stream-out/in cleans registration state and preserves local
  flicker, finale, screen and audio behavior.

The reviewed Roblox documentation explains Improved root disappearance,
Opportunistic stream-out beyond target and persistent/atomic exemptions:
[Roblox instance streaming](https://create.roblox.com/docs/workspace/streaming).
