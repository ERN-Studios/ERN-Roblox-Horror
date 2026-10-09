# Lobby music switch — prepared, not installed

Trello [DEmpCU8O](https://trello.com/c/DEmpCU8O): add a button that lets each player turn lobby music off and back on. This proposal adds **Lobby music — ON/OFF** to the existing Settings tab in the Upgrades & Gear terminal. It uses the established responsive button, feedback and saved preference path. It creates no new assets, sound tracks, remotes, HUD or profile framework.

Only two proposed runtime files change:

- `ReplicatedStorage/ZyntraConfig.ModuleScript.lua`: one visible `AccessibilitySettings` entry, key `LobbyMusicEnabled`, default true, with clear lobby-only wording. Existing settings, paid purchase fields, reward amount and Protection are preserved.
- `StarterPlayer/StarterPlayerScripts/LobbyMusicController.LocalScript.lua`: require the loaded profile's attribute to be true in `shouldPlay`, and subscribe to attribute changes. Missing state is silent, preventing a saved-OFF player hearing music before profile loading. The existing two decks, original group-owned track, 35-second entrance, 0.12 base gain, fades, briefing duck and equal-power crossfade remain unchanged.

The actual existing Store settings inventory/Activated handler is config-driven and supplies the button without a Store edit. The server builds its allow-list from the same config, normalizes missing/invalid values to the configured boolean default, exposes the value through profile/attribute updates, and uses the existing coalesced setting save. Those source dependencies are snapshotted under `before/` as read-only references; they are not proposed runtime replacements. The preference can be changed from the existing terminal and will only affect the lobby music reader.

## Validation

Run `python artifacts/trello-20260909/lobby-music-prepared/test_music.py` from the repo root. `LUAU_BIN` may select the existing Luau executable; the current fallback is the known local 0.737 binary.

**49 checks pass**, using the entire actual proposed music controller against a deterministic Roblox API host. Scenarios cover unknown/saved-false/default-true state, late track readiness, toggle notification, rapid changes, toggling during the actual crossfade, ducking/return, every current round-status exit signal, late lobby events while InRound, reserved-server/lobby-presence guards and preserved gain. The original whole controller is a negative control: it fails the specific no-playback-before-profile-readiness assertion. Both complete proposed files compile.

The same harness executes the actual existing server boolean-normalization, public-profile, attribute-loop and SetAccessibility handler snippets with the actual proposed Config. It checks default/saved-false/invalid values, unknown/non-boolean rejection, unchanged no-op and last queued target. Queue delivery is a stub in this narrow harness; this is not a new live DataStore/coalescer/rejoin proof. `validation.json` records baseline parity and results. No native audio, real persistence or button interaction has yet been tested for this feature. **Independent artifact/code review: 9/10**, with the reviewer independently rerunning all49 checks, baseline negative control and both whole-file compiles; see `independent-review.md`.

## Root handoff and publication boundary

`before/` contains immutable captured sources, `proposed/` contains the two copies, `lobby-music.diff` is the normalized focused delta, and `manifest.json` pins all raw hashes. `prepare.py` only writes inside this artifact directory and refuses to regenerate against a changed runtime baseline. No production source, Studio object or Trello field was changed during preparation.

Root is delivering Protection and the two-token completion reward separately. **Merge these small music changes onto the current post-reward Config; do not install the full earlier Config copy if it would reset LevelCompletionTokens or Protection.** `transform_config(current_text)` and `transform_music(current_text)` in `prepare.py` are pure, exact single-match transforms that can prepare new artifact copies for that reviewed rebase. Keep the original before snapshots. Review the rebased diff and run the focused checks with its current source before root's normal source CAS/sync.

Native acceptance after root stages this feature:

1. Enter the normal lobby with a loaded profile, open Upgrades & Gear → Settings, and activate the actual Lobby music button OFF and ON. OFF should fade both deck volumes to zero and stop them within the unchanged 1.4-second fade; ON starts the existing 35-second entrance and fades in. Inspect the current phone/tablet layout and actual input button, preserving the shared 44px minimum.
2. Repeat OFF/ON/OFF quickly, including during a seam crossfade, and wait beyond the existing pending/save interval. Last choice must win. The Settings state and playing audio must agree.
3. Start a normal round while ON: the lobby decks stop. Return to the lobby with OFF: they stay silent. Briefing/dispatch ducking still works when ON; voice, effects and level music remain unaffected.
4. Verify a saved-OFF rejoin stays silent from startup, and an old/fresh profile without this key receives ON as the default. Use the already isolated memory fixture if avoiding real profile writes; label that backend honestly.
5. Clean up Play fixtures, compile/audit the scoped source changes, obtain final independent native review and mouse-publish this feature separately. Record its actual version; no publication is claimed by this preparation.
