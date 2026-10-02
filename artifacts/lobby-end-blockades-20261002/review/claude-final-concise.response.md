**CODE PASS** — limited to the pasted source and measured geometry; I could not recompute the hashes. The pass rests on four checks:
- The plan holds 93 + 86 = 179 placements and 66 colliders.
- Sampled cabinet, desk and CRT poses reproduce their stated bbox centres under the code's `CFrame.Angles` × source-offset convention.
- The Builder change is one hunk inside the existing pcall, before `Ready`.
- The gate script maps L5 to `IsAllowed` and L6 to `IsLevel6PreviewAllowed`, fails closed, and creates only local instances.

**Material blockers:** none in the code. One install-order condition: `EndBlockades` must exist as Builder's sibling before the Builder swap. The inline `WaitForChild` has no timeout and sits after the concurrency assert, so a missing module hangs Build.

**Unverified live checks:** the kit holds all eight families with the offsets the plan assumes; the build yields 28 lenses whose long axis matches the fixtures; the non-collidable South foreground row has front faces 3.1–4.3 studs in front of the South blocker face (z −131.5), so it reads as walk-through unless an existing collider covers it; whether a jump from the 0.8 curb reaches the 8.13 outer column tops; the hard-coded header-to-gate offset (−17.2, −1.42) and shutter fit; subtitle stretch (900×80 canvas on a 14×0.75 face, about 1.66× wide); prompt names and bay ancestry for the hide logic; streaming, multiplayer and performance.
