UI stutter investigation, 2026-10-10. The owner reports continuing stutter since
the UI was introduced and confirms Level 4 admission now works. The owner's
offline-only restriction remains active while another session uses Studio.
This review and all preparation/tests used local files; no Studio input,
native calls, game installation, new backup or publication was performed.

The reviewed local baseline is HEAD `7fa4d2e1`. Repository mirrors are review
material; they do not replace a fresh authoritative Studio read before installation.
No frame-time, render-time or published-device measurement has established the
share of stutter caused by UI.

The strongest discrete hitch path is redundant input notification:

1. UIDevice.LastInput maps mouse movement, mouse buttons, mouse wheel and
   keyboard inputs to the same `Keyboard` category (UIDevice:215).
2. Its LastInputTypeChanged handler broadcasts `UIDevice.Changed` for every raw
   input change on a pointer form, even when that category is unchanged (:2001).
3. Consumers remount real GUI trees on that event: RoundUI rebuilds Results
   (:1383, :1527), both death cards (:4513, :4566), and an existing PartyDown
   card (:4436); LoadingCardView destroys and remounts its card (:134, :192).
   Those handlers do not require the panel to be visible. Dispatch layout also
   performs synchronous text measurements on device changes.

That path is present in the code. How frequently actual input events occur and
how expensive these rebuilds are on the affected players remain unmeasured.

`prepare_input_candidate.py` prepares one scoped offline UIDevice candidate:
cache the normalized LastInput category and broadcast only when that category
changes, or controller availability changes. The cache advances before the touch-form early return. Keyboard/mouse
and Gamepad1/Gamepad2 alias changes then avoid redundant consumer rebuilds;
genuine Keyboard/Gamepad/Touch transitions remain immediate. Existing hardware,
viewport, safe-inset, modal and control-zone signals are untouched. No UI
template, visual style, frame-based equipment admission or gameplay code is changed.
The generator only writes an explicitly selected new local file and does not
connect to Studio. It fails if the original handler anchor is not unique.

The second concrete recurring hotspot is ProtectionHUD: full `refresh` runs
every RenderStepped (:894), computes nested equipment state, repaints chips and
touch cells, and calls `placeKit` after the kit has mounted even while disabled
(:700-739). The chip painter has no appearance dirty cache (:615). RoundHud
also repaints objective/feed content every 0.1 seconds (:1515, :1538). Repeated
assignments of unchanged GUI properties alone do not establish engine layout
invalidation, and these code paths have not been timed. They are profiling
targets; this candidate does not change them. NoiseReporter already caches its
stamina/bar writes; prompt callbacks disconnect on hide with bounded pooling.

`test_input_candidate.py` runs the complete production UIDevice module in the
existing synthetic equipment DataModel. Sixteen added checks cover keyboard/
mouse aliases, gamepad subtype aliases, real category transitions, handheld
suppression/cache advance, pointer return, viewport resize, hardware notification
and modal notification. It rejects the original raw-event broadcaster, dropped
gamepad notifications and a cache that stops advancing on handhelds. It also
runs all 750 existing equipment/control-plan checks with the candidate module
and the actual imported HUD templates. The fake engine is extended only with
the real GetLastInputType API now used at module startup. The candidate compiles
with the installed Luau CLI. `offline-checks.json` records exact source and
candidate hashes and explicitly denies native frame-time verification.

```powershell
python artifacts/ui-stutter-20261010/test_input_candidate.py --source <fresh-native-source>
python artifacts/ui-stutter-20261010/prepare_input_candidate.py --source <fresh-native-source> --output <new-local-candidate>
```

Installation and gameplay/performance checks await the owner's explicit release
of Studio. At that point reread UIDevice's exact instance, Source and editor
source, verify its LastInput category semantics, reconcile any concurrent change,
regenerate the small candidate against
that baseline, and recheck that baseline within the scoped write. Do not use an
old repository copy to overwrite Studio. Native checks should compare the same
lobby/level scene while alternating mouse and keyboard, then changing to/from
gamepad and touch, and record actual frame-time spikes, GUI remount counts and
input/focus correctness. Compare ProtectionHUD/RoundHud CPU and GUI render cost
separately to establish what remains. An offline test pass does not establish
smooth gameplay, mobile performance, renderer cost or a published fix.


Installed and published follow-up, 2026-10-10

The owner released Studio access. All five reviewed sources matched their editor
source and repository mirrors on the fresh native read. The candidate was
regenerated from that native UIDevice source. Its input cache also records
GamepadEnabled: Binding depends on controller availability, so a subsequent
same-category input event must refresh after disconnect/reconnect. Sixteen
input checks, all 750 equipment/control-plan checks, compilation and four
mutation rejections passed. No physical controller or mobile device was tested.

A real focused Studio lobby reproduction recorded six same-category raw input
events at a stable 773 x 443 viewport with no queue/end modal change. Before
installation they produced six Changed notifications and 24 replacements of
four hidden GUI cards. A fresh Play after the scoped Source/editor baseline
checked write recorded the same six raw events with zero notifications and
zero card replacements; all four identities survived. Independent native
forced-touch, viewport and queue-modal checks passed and restored their borrowed
attributes. Only ReplicatedStorage.UIDevice was changed.

Observed frame intervals were mean 17.27 ms / max 121.76 ms before (19.12 seconds)
and mean 16.67 ms / max 19.72 ms after (12.63 seconds). These short, unequal-duration
single-client warm lobby samples are evidence of the reproduced event fix,
not a general performance, cold loading, active-round or multiplayer pass.
The separate ProtectionHUD on/off sample ran at the Studio 15 FPS background
throttle in both phases and is excluded from CPU attribution. Its recurring
work remains a profiling target; ProtectionHUD itself was not changed.

A full-module Edit compile/require probe unexpectedly left listeners/tasks alive
when its fresh ModuleScript was destroyed. A separate bounded lifetime probe
confirmed that destruction alone does not cancel such resources; that bounded
probe explicitly disconnected/cancelled its own handles. This Edit session was
cleared by closing and reopening the current place after successful publication.
AGENTS.md now records this measured cleanup requirement. No test code/object
was persisted in the game. The reopen preserved all 213 source/editor fingerprint
rows byte for byte, UIDevice properties/attributes, and authored instance-class
counts; only three lazily created engine services were absent afterward.

Studio explicitly reported successful publication to the existing place as
version 2943 at 2026-10-10 11:53:33 Europe/Copenhagen. Its live-edit PlaceVersion
property remains 2859 and is not used as publication proof. See
publish-confirmation.txt and native-session.json. No active servers were
restarted and no GitHub push was performed. The earlier offline-only section
above describes preparation history, not the final installed state.
