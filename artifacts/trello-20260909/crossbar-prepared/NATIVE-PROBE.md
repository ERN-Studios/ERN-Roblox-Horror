# Crossbar read-only native acceptance

`native-acceptance.luau` runs once on the normal Studio Play server after
`ServerLobby` is built. It prints `CROSSBAR_NATIVE_ACCEPTANCE <JSON>` and returns
the same table. It creates no instances, changes no attributes, fires no remotes,
and moves neither camera nor player. No Builder require or rebuild is performed.

The probe reads the actual Builder folders and parts. It verifies all eight
conduit intervals, height/thickness/material and non-collision; tests all 48
conduit/aperture volume pairs; casts 108 conduit-only aperture rays from both
sides; and includes 16 positive rays through the actual segments. A missing or
unqueryable bar cannot masquerade as a clear-aperture pass. Another 36 rays and
direct collider/geometry/attribute checks verify the three actual SealedDoor
parts. Their presence does not establish the absence of every alternate route.
All 24 actual LaunchZone/FutureLaunchZone instances and the twelve post/header
overlaps are logged. The latter remain facts, because Crossbar does not silently
include the separate Doorframe fix.

`camera-fixtures.json` saves four Builder-derived poses for each of six levels,
including native `CFrame.lookAt` readback matrices at the actual lobby center.
They are data only. Root may select lobby/bay straight or oblique views and
adjust for furniture occlusion. Camera positions do not count as screenshots.

The complete probe compiles (11 KB). `test_native_acceptance.py` executes that
entire source against actual emitted old/new conduit geometry and the actual
frame/gate/queue source sections. The new fixture passes 314 checks/160 host
queries; the actual baseline and three defective variants are rejected. The
host uses AABB ray intersections, so that result alone is not native evidence.

Root subsequently ran the normal native probe: **314 checks and 160 Roblox rays
passed**, preserved in `../crossbar-native-acceptance.json`. This file was parsed
to produce the saved camera recipes. Root separately reported twelve views and
actual queue open/decrease/close passing; those interactions were not performed
by this read-only script. See `../crossbar-native-validation.md` for root's
visual/interaction evidence and `native-probe-validation.json` for scope/hashes.

Do not rerun `prepare_and_test.py` against a later runtime expecting it to
overwrite the original baseline: its baseline guard deliberately refuses that.
The native probe and its host test do not write runtime sources or refresh the
original proposal snapshots.

Independent critic reviewed the complete read-only probe, its positive controls
and the native evidence: **9/10**. Crossbar was subsequently mouse-published as
**v1832**, 10 September 2026 at **03:50:59.169 DK**; the separate release journal
and Trello readback record the completed card.
