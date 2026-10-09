# Native Party and ReduceFlashing analysis

**Party restored the28 lamps and ambient motion resumed within the existing capture.** No extra capture is needed for that resumption.

- Before Party: recorded ambient maximum1.553325 versus baseline1.25. The first Party frame starts0.803s later; exact activation latency is not measured.
- Frames1–44: Party=true and all28 brightness values1.55 within native precision, with the multicolor Party palette. Frames45–48 show the restoration while Party remains true.
- Frame49 (2026-09-10T16:51:56.466+00:00): Party=false; all28 brightness values exactly1.25 and all recorded RGB values back to cyan(73,245,204) within1e-6.
- Frames49–107 remain at baseline. Frame108 begins a later ambient highlight **12.664s after the first false Party flag**. All28 lamps brighten; maximum1.812439. The recorded RGB/brightness relation matches the source's pale-cyan blend with maximum channel residual5.2e-08.
- Frame134 restores every lamp; frames134–140 remain at baseline. The visible sampled highlight spans5.313s, not an exact private6s scheduler measurement.

The separate **26 ReduceFlashing=true samples** span25.381s and all report min=max=1.25. This supports idle suppression. The actual click arrived after the earlier sweep, so it does **not** demonstrate cancellation mid-sweep. Parent reports the preference was restored false separately; that later readback is outside this file.

This analysis is based on the140 actual Party frames (largest gap0.218s) and the26 preference readbacks. Root owns the actual E input, Settings UI and subsequent round/lobby lifecycle evidence. The sampled trace does not certify arbitrary replication ordering or a human assessment of every visual effect. Exact indices, timestamps and file hashes are in native-party-reduce-analysis.json.
