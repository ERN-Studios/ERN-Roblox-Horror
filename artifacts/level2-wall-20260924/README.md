# Level 2 wall decals — active Studio round, 24 September 2026

Codex entered a real solo Level 2 round from the Level 2 lobby station in the current Studio place, then inspected the generated `Workspace["Level 2 Generated World"]["Level 2 Wall Decals"]` folder. It held **three** parts: one Visitor Traces in Hall 16 and two Maintenance History copies in Halls 25 and 28. The parts were transparent, `CanCollide=false`, `CanTouch=false`, and `CanQuery=false`. Their decal Image IDs were exactly `126468681550310` and `70761413249378`. No objective/AI/asset source was changed.

The client camera was temporarily held on each wall via Studio MCP in Play mode; the regular Level 2 lighting and HUD remained. Screenshots:

- [Visitor Traces, Hall 16](visitor-hall16.jpeg) — handprints and scratch tally beside a normal water-edge hall.
- [Maintenance History, Hall 25](maintenance-hall25.jpeg) — aged pipe diagram beside a normal water-edge hall.

These screenshots are evidence of the in-game scale, wall placement and lighting, not owner style approval or physical mobile performance.

## Active-round collision and sight-line check

In a separate real solo Level 2 round, the generated layout placed Visitor Traces in Hall 13 and Maintenance History in Halls 03 and 09. The folder reported three decals and contained exactly three. Each plane had `Anchored=true`, `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `CastShadow=false`, and `Transparency=1`; their Image IDs matched the two approved uploads. Placement changes with the round seed, so these hall numbers differ from the screenshots above.

The live Pool Slide controller source uses `workspace:Raycast` for `clearLine` with an exclusion filter and `RespectCanCollide=true`. Using the same collision rule, a 12-stud ray cast from six studs in front of each decal through its centre hit the real Level 2 Hall wall 6.05 studs away, never the decal. An Include-only ray targeting each plane hit nothing even with `RespectCanCollide=false`. Thus the generated decals did not add a collision or ray-query blocker at any of the three sampled placements. This tests the enemy's sight-line *query behavior* in an active round; it does not claim that an enemy chase happened at each decal.

Both Play sessions were stopped afterward, discarding transient queue and camera changes. No Edit source or asset was changed by this QA. Latest verified publication is still v2061; integration commit `644be20` is newer and unpublished. Keep [the Trello card](https://trello.com/c/DDqjXkyU) open until owner visual review, physical phone/tablet draw-count/FPS/memory checks, publication, and receipt.
