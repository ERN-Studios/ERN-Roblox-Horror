# WallConduit removal from entrances — prepared patch

Artifact-only proposal for [mirOf8aF](https://trello.com/c/mirOf8aF), 10 September 2026. The runtime Builder has not been edited. This agent read the saved image-description note; root subsequently confirmed the visible object natively (below).

Native identification by root after the Level3 win/return: the horizontal black bar crossing the Level1 aperture projects to viewport(384.79,190.38), and an actual ray from the observed camera through world(-33.2,40.5,-840) hits exactly `Workspace.ServerLobby.TunnelDetails.WallConduit`. Screenshot: `../lobby-crossbar-native-before.jpg`. The two actual conduits are centred atX±33.2/Y40.5/Z−760, size0.65×0.65×274, non-collidable. DoorHeader is separately centredX−34/Y45/Z−840. This confirms the candidate; no bar geometry was changed and the patch still awaits the preceding feature's publication.

The current Builder creates one dark, non-collidable 0.65×0.65×274 conduit on each wall at local X=±33.2/Y=10.5. It runs Z=-137..137 straight through all six level entrances. The proposal uses the existing `wallRanges` so the conduit follows only closed wall sections. Its original end setbacks, height, thickness, color and non-collision state remain intact.

Each wall receives four segments with Z intervals **[-137,-90], [-70,-10], [10,70], [90,137]**. These leave the three existing 20-stud doorway spans clear. The ends terminate within the doorposts; no floating shortened bar remains in the aperture. Two original parts become eight parts (+6), with no other geometry changes. Door headers, entrance lintels, sign hardware and the separate frame-overlap card are untouched.

Files:

- `before.lua`: exact source snapshot, SHA256 `EC3593A320BCDA26B7F1CF0D7F3FF3E71312F27E3AAC40E09B58260EED9F7AE0`.
- `proposed.lua`: full compilable proposed source, kept outside the runtime tree.
- `lobby-wall-conduit.diff`: the limited patch for root to inspect/apply later.
- `prepare_and_test.py`: regenerates the proposal from the snapshot, refusing if current runtime source no longer matches that baseline.
- `geometry-validation.json`: actual emitted-part verification.

Run with `LUAU_BIN` set to the official Luau interpreter:

```powershell
python artifacts/trello-20260909/crossbar-prepared/prepare_and_test.py
```

**4,464 checks passed**. The test executes the actual old/new Builder road/ledge/paint/conduit source section, then queries the emitted boxes every quarter stud along both walls. All **474 sampled baseline intrusions** inside the six apertures disappear; coverage on the closed wall sections and original outer extent remains correct. It compares all other emitted road/ledge/curb/paint parts unchanged. The complete proposed Builder compiles with Luau 0.737 (3 KLOC/96 KB bytecode).

Native acceptance is still required: select the reported visible bar and confirm its name/position; inspect all six apertures from both sides and oblique angles; walk into each active level bay and interact with its queue; verify future gates remain sealed. Apply only after the preceding feature's publication, get an independent critic score and publish this fix separately with the mouse. The current evidence does not claim a native visual match, applied change or completed card.
