# HUD build: notes for the other sessions (2026-10-08)

- **Level 5 session:** `DeathAdvice` `L5Fall.Tip` is 85 characters; `tools/tests/test_death_advice.py` caps tips at 72. Your
  entry, left alone here.
- **Level 6 session:** `L6Manager` has no `DeathAdvice` entry, so a Level 6 death shows the generic card.
- **MOBILE_QA_20261008 session:** your Studio edits were pulled into the mirror unchanged: UIDevice, ZyntraConfig,
  ZyntraDetectorVisual, DevAccess, Crouch State Server, ZyntraDetectorService, NoiseReporter, ProtectionHUD,
  SpectateController, Round Exit Client, ZyntraDetectorClient, Level 3 Reader/Table Hiding Client,
  EntityShakeController, Zyntra Shop L4, ZyntraStore, and the new Found Footage HUD and Achievements Client (both added to
  the manifest). The shop's fake-engine harness gained `Vector2` arithmetic for your title placement code.
- **Everyone:** the place is named "(UPDATE) BACKROOMS: STAY QUIET". `tools/sync_from_studio.py` accepts that name
  now (`UPDATE_STUDIO_NAME`); `push_repo_to_studio.py` still needs `--studio-name`.
- **HUD templates** live in `ReplicatedStorage.ZyntraHUD.Templates` (`HUD_PC`, `HUD_Touch`, `HUD_Screens`), staged from
  the Framewisp imports by `install/01_hud_templates.luau`. Re-run that script after any re-import: it also renames
  `TouchCluster/Cell` to `Cell_Glow`, because Framewisp strips `_Glow` as a tag.

## Evening update (20:55)
- **Working-tree incident, about 20:20-20:25.** A `git stash` from this session failed halfway on a Windows file lock. For about a minute, 86 modified files read as their HEAD versions and 17 deleted files came back. Everything was restored file by file from the stash blobs; the tree now equals the stash exactly, and no other session's change was lost (0 conflicts). If your session read, tested or pushed a mirror file around 20:20, re-read it. The stash entry is kept as a safety net (`a865bde5`).
- **The place was renamed again**, to `[UPDATE] BACKROOMS: STAY QUIET` (brackets). `tools/sync_from_studio.py` accepts it (`UPDATE_STUDIO_NAME_BRACKETS`), so `install_new_scripts.py` and pull work again.
- **HUD B1 is in Studio** (not published by me):
  - new `ReplicatedStorage.RoundHud`;
  - `UIStyle.Hud`;
  - the flashlight widget, equipment chips and detector card on PC;
  - Level 1's PuzzleUI receiver lifted to 228 px on PC.

  Whoever publishes next ships B0 + B1, both tested in a Level 1 round (`qa-b1/B1-QA.md`).
- **Seen in a Level 1 round:** `PlayerGui.Level5VoidHud.Line` (1130x26 at y 400) and `PlayerGui.LobbyDJ.NowPlaying` (460x26) report Visible inside the round. Neither drew anything visible in the capture, but the Level 5 and lobby sessions may want to gate them on `InRound`.
- **Studio drift not pulled by me:** 23 STUDIO-AHEAD and 14 NOT-IN-MANIFEST scripts (Level 3, Level 6, the lobby, Monetization, Luna, ...) belong to other sessions.
- **22:45** resumed after the owner's pause: B2 build and B3 map restarted from scratch (nothing was cached).
