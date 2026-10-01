**Verdict: approved for final Play verification. I found no blocking bug on code read, but it is unproven: the photos show the 159-fill trial, not this ~137-fill candidate.**

**Visual observations (photo pair)**
- Ceiling grid and fixture housings now read while staying far darker than the walls. Carpet (≈+7%) and wall (≈+2%) spill isn't noticeable to me, so the mood holds.
- One acceptable tell: small warm hot-spots beside the housings, beading above the far fixture. If it reads in the long City Party view, a lower anchor is the untested lever (likely slightly more wall/floor spill).

**Code analysis (untested)**
- `light` must be the in-scope SurfaceLight at that point; otherwise the build errors immediately.
- Grep for code selecting lights by class or recolouring SurfaceLights at runtime. Fills shouldn't inherit gateway PointLight handling or keep a stale colour.

**Checks before publish**
1. Re-shoot arrival on the final build; re-measure ROIs.
2. Count `Level 6 Ceiling Fill`: one per non-flicker working fixture, no adapter duplicates, Level 3 light count unchanged.
3. Two full blackout cycles: no Output errors, ceiling back to black, fills restored to exactly 0.16.
4. Pre-blackout/recovery: the longer Light arrays don't stretch any per-index stagger or leave a fill lit beside its dark lamp.
5. Flicker fixtures: no regular dark ceiling holes, no neighbour fill visibly persisting through flicker.
6. Red Party ceiling doesn't glow; FPS/frametime against baseline in the largest City Party view.
