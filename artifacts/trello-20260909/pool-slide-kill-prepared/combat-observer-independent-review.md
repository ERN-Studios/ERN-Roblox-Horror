# Combat observer diagnostic review — 9/10

Reviewed 10 September 2026. I read the complete `CombatReadOnly.Server.Script.lua`, independently compiled it, and matched its exported NAV foot, Controller debug fields, LOS exclusions/parameters and PlayerProtection display attributes to the current sources. No blocker found before root's diagnostic use.

The normal server script uses the existing module cache and creates only its owned BindableFunction. It has no pump/spawn/begin/attack call and does not modify old WithFoam reports. Snapshot requires an actual player and one current runtime model, uses the exported foot position, and repeats the Controller's ray from foot + Y3 with the same exclusions, IgnoreWater and RespectCanCollide settings. Owned destruction cleans its Bindable and cached facing observation.

Its limitations are correctly explicit: the expected source hash is metadata, not a runtime source-hash verification; pivot look is a facing proxy; first observed ATTACK time is not the private windup start; private character/HitChecked/Shield eligibility is unavailable. `EligibilityCertified=false` remains appropriate even when the geometric gates pass. The observer deliberately avoids PlayerProtection.IsActive because that API may clear expired state. ForceField and Shield display fields aid diagnosis but do not independently establish damage eligibility or cause.

This is a diagnostic artifact score, not a score for the combat fix or an assertion that native attacks passed. No Studio/runtime action was performed by the reviewer.
