# Signal Architect Ascendant — Studio integration record

**25 September 2026:** integrated in Studio Edit for place `131311258779917` (universe `10559217407`). **Unpublished.** Studio Play visual checks passed; this record is not a release receipt.

## Native pre-edit backup

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `before.rbxl` | 9,623,343 | `D8F18C623DACC8191A23A1A27B754D95A8216901057CD035B029BF58C5DBD98A` |

The backup is the full native place saved before the non-script asset edits. It is a local artifact, not a published version.

## Scoped Studio integration

- `ServerStorage.HazmatSkin_SignalArchitect_20260924` keeps the existing canonical skinned body; its `char1.SurfaceAppearance.ColorMap` uses group-owned Image `115045548138657`.
- `ServerStorage.HazmatSignalArchitectTopper_20260925` contains the imported single-part halo from group-owned **Model** `112810865153770`. Its `Model.WorldPivot` was normalized to the MeshPart bounding-box center. The Model asset ID must not be used as a MeshId.
- `ServerScriptService.HazmatSkinVisuals` attaches it through the existing cosmetic topper path with measured placement `Scale = 2.6, Y = 1.1, Z = 1.35`; the part remains non-collidable, non-touchable, non-queryable and massless in play.
- `ReplicatedStorage.ZyntraSkins` retains skin ID `SignalArchitect` and `Kind = "Developer"`, with ColorMap Image `115045548138657` and standing-card Image `110021662787844`.
- `StarterPlayer.StarterPlayerScripts.HazmatSkinDriver` uses cyan mote Image `124315518046326` at a low local rate. Existing ReduceFlashing, 40-stud culling, first-person/hiding and visual cleanup rules also govern this effect. `ReplicatedStorage.ZyntraSkinsPage` draws a sparse 2D preview effect because a ViewportFrame does not render ParticleEmitters.

The three Image IDs and halo Model ID were approved for group `1039373905`; source files and upload moderation receipts are in [`../../assets/hazmat/developer-signal-architect-v2/`](../../assets/hazmat/developer-signal-architect-v2/). Entitlements, DevAccess, Token/wheel/Robux paths, gameplay lighting, hitboxes, movement and sound were not changed for this cosmetic upgrade.

## Verification and remaining gate

- Final reported Studio script parity: **182/182 scripts match the repository in both live Source and editor-source**.
- Luau parse passed for the four changed script files. Offline tests passed: skins **31**, HazmatSkinDriver cleanup **12**, developer revocation **34** checks.
- In Studio Play, a temporary local clone of the server-built preview showed the front silhouette and large cyan/gold halo from behind. The Skins page showed the new standing card and `EQUIPPED` status. A temporary synthetic round created `ZyntraHazmatSkinVisual` and its `ZyntraPremiumTopper` on the developer player. The client revealed the suit mesh, hid the topper locally in first person, and created the low-rate cyan emitter disabled for that near-head view. The temporary preview and round attributes were removed, and Play was stopped.
- Movement footage, physical mobile silhouette/frame time and a published-server visual check were not obtained. The owner previously accepted hardware-dependent checks without a device run, but these results must not be represented as measurements. No publish version or Roblox receipt has been recorded for Ascendant; keep [Trello SYUaXHKQ](https://trello.com/c/SYUaXHKQ) open until publication is confirmed.
