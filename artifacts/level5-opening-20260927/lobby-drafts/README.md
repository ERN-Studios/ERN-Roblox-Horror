# Level 5 lobby draft

Drafted against the fresh v2150 `TunnelLobbyBuilder` export. No Studio or repository edits were made. Root must recheck current Source/editor text before installing the patch. Hashes are in `draft-manifest.json`.

## Result

- Existing chamber/vestibule surfaces use Level 5 carpet, cream plaster and a rear floral wallpaper band.
- Three shallow domestic fronts form a stepped silhouette. Closed wood doors, dark interiors behind tinted window glass, white trim and a raised white balcony rail echo the real residential map.
- Four shared fluorescent ceiling fittings replace the generic fixtures' visible light; the original fixture instances remain hidden/disabled.
- All five texture IDs and MaterialVariant names come directly from the current Level 5 Architecture source. Existing matching variants are preferred; installed textures are a fallback.
- Exactly **67 decorative Parts** plus four SurfaceLights are added. They are anchored, noncolliding, non-touching and non-querying. No prompts or runtime puzzle/entity names are added.

## Source changes

`TunnelLobbyBuilder.diff` adds the helper and callable `Builder.RefreshLevelFiveRoom(roomModel)`, calls the helper for future Level 5 room construction, sets only Level 5's definition `active=true`, and labels its doorway **LEVEL 5 / RESIDENTIAL PREVIEW**. Level 4/6 definitions remain false; the existing special developer room creation expression remains unchanged.

`RefreshLevelFiveRoom` requires the existing `Level5QueueRoom`, LevelNumber 5, all four existing detector Instances, and the original chamber dimensions. Each detector may be named `FutureLaunchZone17`…`20` or `LaunchZone17`…`20`; duplicate active/future names are rejected. It derives orientation from the existing doorway sign. It changes only named chamber surfaces, its own decorative model/textures, the generic chamber fixtures, and three room style attributes. Queue station Instances, displays, IDs, detector transforms and parent references remain intact.

The native `level5-live-queue.json` snapshot has **FutureLaunchZone17–20**, offline station labels and `LevelEnabled=false`. The source's developer-active room expression applies to a future `Build`; it does not describe that instantiated lobby. The original draft's Launch-only check was corrected after comparing these snapshots.

`Builder.ActivateLevelFiveStations(roomModel)` is a **separate** operation. Before writing, it checks all four existing detector transforms/sizes, unique names and existing offline labels. It then renames only Future detectors to their matching Launch names, updates those offline labels and sets LevelEnabled. It preserves identity and returns existing station records plus a rollback receipt. Already active stations retain their live labels. `Builder.RestoreLevelFiveStationActivation(receipt)` restores exactly those names/labels/attributes only if none have changed since activation.

Renaming native markers does **not** register a running queue: GameManager's `lobbyStations` is a private table returned by `Builder.Build` at startup (GameManager lines 608, 692, 1445). The helper returns the normal records for an explicit runtime registry handoff, if root implements one. Future servers already obtain the correct active L5 records from the patched Build. Do not claim existing-server queuing works from an edit-mode marker rename.

The helper deliberately does **not** remove the existing sealed Level 5 doorway or rewrite existing wayfinding displays. That is a separate scoped root action after comparing the current Level 5 doorway objects. The Build definition handles future servers. Do not call full `Builder.Build()` to preview this room: it replaces the whole lobby. A running cached `require` will also need a controlled module reload before it exposes the new helper.

## Verification

- Full draft compiles with the local Luau compiler.
- `python3 run_geometry_checks.py`: **1,456 assertions pass**, executing the exact helper with offline vector/CFrame and Instance mocks.
- All decor corners fit within radius **26.892 studs**, below the chamber's inner wall radius **27.375**; all are above the existing floor top (0.28) and below its ceiling underside (21.7).
- Low decor (below 10 studs) sits at least **5.395 studs** beyond the four queue detector squares' outer X envelope. The upper balcony is at least **4.39 studs** beyond that envelope.
- Refresh is idempotent: it replaces only its owned decoration and textures. Unknown owner and changed dimensions are rejected before restyling. All four queue detector objects survive by identity. Future markers are accepted without being renamed by cosmetic refresh. Activation preflight rejects changed labels without partial writes; repeated activation changes nothing; rollback restores the original false LevelEnabled attribute and rejects newer queue display changes.

These checks cover authored transforms and ownership behavior. They do not prove native texture loading, visual quality, actual queue entry, frame rate, or player movement. Root should inspect the room from the tunnel entrance and each station after scoped installation and verify that Levels 4 and 6 remain sealed.
