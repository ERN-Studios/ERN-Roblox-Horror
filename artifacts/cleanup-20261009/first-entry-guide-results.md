# T09 fixture foundation — current WELCOME/HELP

Only `tools/tests/test_first_entry_guide.py` changed. No runtime source, Studio
instance, manifest, input module or shared fake-engine file was edited. The exact
previous fixture is checkpointed at
`.git/mongotv-cleanup-20261009/tooling-before/tools/tests/test_first_entry_guide.py`.

The old fixture failed before its assertions: its fake services did not expose
the current source's `TweenService`. It also expected the older guide/layout.
`first-entry-guide.baseline.txt` records that failure; this was a stale fixture,
not evidence that the authoritative WELCOME/HELP feature was broken.

The replacement loads the entire current
`StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua` and the
actual `ReplicatedStorage/ZyntraConfig.ModuleScript.lua` in real Luau 0.737. It
reuses only the shared fake-engine primitives from `hud_harness.luau`, validates
that extraction boundary, and supplies fake Player/Workspace, UIS, TweenService,
UIDevice's published layout/modal boundary, and a yielding deterministic clock.
Tasks advance under that clock; the real LocalScript remains unmodified.

Dependency closure: Players/profile/loading/round flags, PlayerGui/PlayerScripts,
UIDevice layout/Changed/modal suppression, ZyntraRailSwitch/CloseHelpPanel,
ZyntraConfig, TweenService, UserInputService, lobby spawn/stage/camera/character,
Badges/left-rail button bounds. The current guide has no UIStyle require. The
fixture imports `test_round_hud.HARNESS/long_string`; its main test does not run
when imported.

Gate command: set `LUAU_BIN` to the installed 0.737 interpreter and run
`python tools/tests/test_first_entry_guide.py`. Results:

- 133 assertions PASS: first/repeat/late profile, loading cover, Studio-only
  override, reserved/round guards, four pages, keyboard/gamepad/buttons,
  replay/authoring controls, config-derived reward/prices and config-error
  fallbacks, all ten HELP topics, scroll reset, current header, narrow/wide
  columns, modal/rail bounds and reflow, suppression handoff, close/reentry,
  listener disposal, lobby camera ownership/respawn/missing-root paths.
- Six source mutants made solely in temporary test programs are rejected by
  independent contracts: bypassed first-login gate, reversed navigation,
  disabled movement suppression, missing rail reservation, hardcoded config
  reward, missing HELP header. No mutant was written to the runtime mirror.
- Python AST, generated fixture Luau compile, and exact protected input hashes
  PASS. `first-entry-guide-checks.json` records the real counts and hashes;
  `first-entry-guide.after.txt` records executable output.

Two separate diagnostics stay outside the passing contract assertions. C21 is
reproduced: processed Space while a TextBox is focused still advances the
tutorial. C22 computes Skip as 54.27 x 25.84 effective authored pixels at touch
568 x 320. These runtime issues remain retained for their own test/decision
ports; this fixture repair does not fix or endorse them.

Status: offline T09 fixture repair **gennemført**; native UX portion **afventer
test**. Fake-engine geometry and events do not establish native font metrics,
UIScale/viewport rendering, actual mouse/touch/gamepad/chat routing, animation
timing, actual WaitForChild timeout scheduling, multiplayer or streaming. The
test-owned Stop helper clears fixture workers; it is not a native script-lifetime
cleanup claim. No Studio calls, HTTP requests, performance measurements or
publication were made.
