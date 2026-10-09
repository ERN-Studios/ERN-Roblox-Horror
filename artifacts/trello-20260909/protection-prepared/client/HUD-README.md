# Protection HUD — isolated proposal

`ProtectionHUD.proposed.lua` is intended as a new `StarterPlayer/StarterPlayerScripts/ProtectionHUD` LocalScript. It requires the prepared `ReplicatedStorage/ProtectionClient` and the prepared UIDevice `ProtectionUse` control slot. It has not been installed or published. No runtime source, Studio instance, DataStore or purchase was changed for this subtask.

The button uses a stored charge only on Q, D-pad Down or an explicit mouse/touch activation. A held input produces one intention. A pending use can be retried through the shared client's exact command; the HUD cannot retry a pending shop purchase or create its own command identity. It neither activates protection nor writes its attributes. The display reads the server deadline, clamps the countdown to five seconds and leaves expired state for the authoritative service to clear.

Visibility requires a current living character, InRound, active round, workspace `RoundLoadingState == "ready"` and the existing client `RoundEntryControlsReady` acknowledgement. The actual `RoundGui.LevelLoading.Visible` and `QueueHostShade.Visible` are checked directly as well. These are the real frames and attribute locations in RoundUI/GameManager, rather than an invented player loading flag. Lobby, death, escape (including the Level 2 exit transition), spectating, briefing, the four existing screen-owning modals, Roblox menus and focused text hide and disable the control. Selected UI objects and processed input prevent activation.

Living capture remains eligible: the HUD does not use anchoring, PlatformStand, PlayerModule disablement or `CaptureControlsDisabled` as a veto. DisplayOrder 1001 is above JumpscareGui 1000; the explicit modal/loading gates keep that exception bounded. The production protection service remains responsible for whether a living capture can actually be cancelled.

On desktop the 138×52 button starts at x98 and ends 92 pixels above the viewport bottom, clamped into the shared safe area. The existing torch spans x12–84 and the stamina bar is near bottom22, leaving separate rectangles at the measured baseline geometry. Desktop/controller captions occupy three lines; touch captions use two compact lines. Touch reads the existing control plan, requires a minimum 44×44 slot, registers the actual hit target and unregisters it on a form-factor change. This proposal does not duplicate or alter UIDevice's seven-control layout arithmetic.

Character binding never waits for a Humanoid. Child signals bind a late Humanoid, while current-character identity and an explicit CharacterRemoving gap prevent old callbacks from making a retired character eligible. Destruction releases input, render, character, health and layout connections, removes the control registration and destroys this HUD only.

## Verification

`python artifacts/trello-20260909/protection-prepared/client/test_hud.py` passes **92 checks**, executing the complete proposed HUD source. The host controls GUI objects, signals, input, characters, clock and the shared client's API. It covers all suppression states, living capture versus fatal damage, pending/retry ownership, zero/unavailable stock, nonautomatic countdown expiry, held/processed input, touch registration, character replacement/removal gaps, late Humanoid and complete cleanup. The full LocalScript compiles with Luau 0.737 (9 KB bytecode).

The shared client module's separate actual-module tests cover transaction identity and RequestNonce behavior. This HUD test uses an API spy; it does not claim real RemoteEvent delivery, native text metrics, device layout, collision, capture cancellation or persistence. The independent review is recorded below; the author has not assigned a score.

## Native acceptance still required

Check actual desktop/controller captions and flashlight/stamina separation; all seven touch controls in narrow portrait, short landscape and tablet orientations; safe-area changes and input-mode changes. Measure text bounds and the actual registered rectangle. Use real keyboard Q, D-pad Down, touch and mouse, including held keys, chat, Roblox menu, selected dialogs and a real loading cover. Confirm a live capture/floor pin keeps this control reachable above the cinematic, while the fatal frame hides it. Confirm shared Shop/HUD pending state, manual retry and server countdown without a second activation. Installation also requires the complete reviewed server service, transactions, damage/AI integrations and shared client modules.

Independent review: `spawn_diagnosis` scored this artifact **9/10**, independently reran all 92 full-source checks and compiled the whole HUD. His Level 2 exit-transition finding was corrected in the predicate, attribute listener and suppression fixture before that score. This is code/artifact acceptance; native input, device layout and gameplay integration remain pending.
