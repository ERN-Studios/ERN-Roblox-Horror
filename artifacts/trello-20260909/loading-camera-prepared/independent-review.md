# Independent prepared-code review — 9/10

I read the exact RoundUI delta, transformation, actual callback host, original negative control and Continue commutation check. Independently ran `test_camera.py`: **65 actual callback checks**, the original-camera negative control and **two complete compiles pass**.

The change removes only this automatic elevator callback's camera read/write and its side/lift/roll/pitch calculations. In particular, the positive stop-pitch during the late settle interval is removed. The callback still runs its original timing, cabin light and door effects and exact restoration. It does not change camera mode, subject, focus, FOV, player input, entry sequencing, briefing or result behavior. Removing the unnecessary camera-presence early return also permits the cabin restoration timeline to continue while no camera is present.

The existing source finding supports this scope: the L3 elevator is seven seconds, whereas the old callback starts after one second and runs another eleven; start only resets the scheduling latch, so it did not cancel that later camera motion. Other inspected writers are capture/death/escape, hiding or encounter driven, and no second automatic loading pitch writer was found. This is a source diagnosis; root's native before/after is still needed to tie the callback to the reported perceived motion.

Tests compare the real old and new cabin property timelines, preserve changing input poses across the sweep and settle, and cover absent/replaced cameras and rearming. Their pose arithmetic is explicitly a recording stub, not an engine-camera simulation. Source boundaries establish that all remote/loading/briefing/Continue code outside the deletion remains unchanged. Applying the two independent camera and revised-Continue transforms in either order produces the identical compiling result.

Score: **9/10 for the bounded code/artifact**, no required correction before native testing. No reviewer runtime or Studio mutation occurred.

Reviewed proposed RoundUI SHA-256: `baea58303d309a493645b763d40b9492ccffeb9a5948147ee6a012874e6a40f6`.

If Continue is installed first, apply the narrow camera transform to that fresh source rather than replace it with the older full-file proposal. Native manual look before/after loading and late settle, without attributing unrelated gameplay camera effects to this removal, remains root's acceptance.
