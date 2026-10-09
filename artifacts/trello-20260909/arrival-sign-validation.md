# Level 3 spawn is not the exit — verified release

[Trello el9lI94F](https://trello.com/c/el9lI94F) is **Done**, published as **v1820** on **9 September 2026 at 23:29:42.038 Danish time**. Root used the mouse through **File → Publish to Roblox** and confirmed the version in native Studio Output. Final independent critic score: **9/10**.

The change adds exactly **32 lines** to `ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua`: one amber 14 × 3.6 stud sign above the slide mouth, reading **NO EXIT** and **ONE-WAY ARRIVAL**. It faces the arrival room along +X, is anchored and decorative, and has collision, touch and query disabled. The slide geometry and actual exit behavior were not edited in this delta. See [exact diff](arrival-sign.diff) and [before snapshot](arrival-sign-before.lua). Studio push backup: `.studio-push-backups/20260909-212459/`.

Root tested a normal Level 3 launch through queue 9, changed party size from six to one with the UI, and completed the countdown. The character reached the level with loading ready and 100 HP. The sign's NO EXIT heading was clear from the actual spawn head position looking back at about **23 studs**, and from an oblique position at about **32 studs**. Its secondary line is smaller; the clear primary heading conveys the required distinction. The critic independently viewed both images before giving the final 9/10.

- [Spawn view](arrival-sign-spawn.jpg)
- [Oblique view](arrival-sign-oblique.jpg)
- [Native property/visibility evidence](arrival-sign-native.json)

Full compilation passed **122/122** and the source audit showed **zero drift**. Root stopped Play before publishing. This verifies the sign in the tested normal Studio arrival and camera views; it does not add a new claim about public multiplayer transport or every device layout.

Trello's original request was preserved, release evidence appended, and the card moved to Done and marked complete.
