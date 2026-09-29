# Level 5 public-preview access drafts

Prepared against the fresh v2150 Studio export. These files are not installed in Studio or copied into the repository.

## Files

- `sources/ServerScriptService/GameManager.Script.lua`
- `sources/ServerScriptService/Level 5 Systems/Level 5 Round Adapter.ModuleScript.lua`
- `sources/ServerScriptService/Level 5 Systems/Level 5 Window Watcher Encounters.ModuleScript.lua`
- `access.patch`: exact unified diff against the baseline
- `manifest.json`: baseline and draft SHA-256 hashes
- `validation.json`: compile and behavioral results
- `build_drafts.py`, `verify_drafts.py`: reproducible draft preparation and checks

## Behavior

GameManager defaults `Level5PublicPreviewEnabled` to true only when unset. Explicit false retains the private developer-only preview. Public access allows exactly Level 5 and passes transport ceiling 5 to the existing outbound packet and destination clamp. Level 4 still requires its own flag and an entirely developer roster. Level 6 stays rejected. Campaign maximum, continuation rules, DevAccess and developer commands are unchanged.

The adapter and Watcher accept either the public preview or their existing developer mode. The adapter's two generated signs explain that this is a playable preview and that the final slide/ending remain unfinished. Entry and H-end signs refer to the existing lobby control. The resting chip says HOLD L • LOBBY, and its confirmation says BACK TO LOBBY. Signs are noncolliding, depth-tested and owned by the generated world; ordinary cleanup removes them with that world. They do not set Escaped/PuzzleWon, award a clear, or initiate travel.

Level5_MapOnly identity attributes remain because existing lighting, gaze, visual, ceiling-eye and progression controllers use them.

## Validation

- All three complete scripts compiled at `-O0` inside the Studio-style `return function() … end` wrapper.
- 256 behavioral assertions passed using the exact GameManager authorization functions, exact adapter authorization block, exact Watcher enable predicate and unchanged full Routing module.
- Matrix covered public/private flags, ordinary/developer/mixed parties, Level 4 denial, Level 6 denial, preserved developer access, launch packet destination, destination clamp, campaign continuation, explicit disable and invalid numeric levels.
- Scope checks verified no new completion writers and preserved preview identity.

## Integration and remaining native checks

Apply scoped hunks after re-reading both current Source and editor source, reconciling any simultaneous audio/puzzle edits. Do not bulk replace scripts from these files. The adapter adds preview notices after architecture generation; other work may edit that same build region.

This patch does not open or style the lobby gate/bay. The root task owns those changes. When the public flag is false, only developer access remains; this patch does not dynamically close the native lobby door.

The two sign positions follow the authored arrival/descent endpoint. They still need native sightline/text-fit inspection. Entry, all puzzles, Back to Lobby, ordinary/mixed party routing and real reserved-server transfer remain native QA requirements. Compilation and pure policy assertions are not gameplay proof.

H still contains geometry only. No slide mechanic or normal completion is claimed.

