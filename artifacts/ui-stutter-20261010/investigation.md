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
changes. The cache advances before the touch-form early return. Keyboard/mouse
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
existing synthetic equipment DataModel. Fourteen added checks cover keyboard/
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
