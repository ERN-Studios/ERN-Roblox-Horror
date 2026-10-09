# Native natural ceiling-sweep analysis

**All five trajectories appear in18 complete sweeps.** The1,626-frame capture spans339.657s across28 lamps at14 Z stations (-888 to-641, X±9). One final opposing-lane sweep is truncated and excluded from complete coverage.

| Pattern | Complete sequences | Quantitative peak travel |
|---|---|---|
| 1: increasing Z | 2, 8, 17 | increasing-Z lag (left row; right row matches) 3.965..4.202s |
| 2: decreasing Z | 7, 10, 12, 14 | increasing-Z lag (left row; right row matches) -4.183..-3.967s |
| 3: centre to ends | 1, 3, 6, 15 | centre→ends lag 3.582..3.797s |
| 4: ends to centre | 5, 11, 13, 18 | centre→ends lag -3.933..-3.737s |
| 5: opposing lanes | 4, 9, 16 | left ΔZ lag 4.000..4.219s; right -4.219..-4.000s |

Brightness stayed within **1.25–1.8125 (1.00–1.45× baseline)**, with no sampled darkening. All28 lamps returned to exactly1.25 after each complete sweep; all intervening samples were at baseline. There are no immediately repeated classifications.

Recorded visible spans are5.183–5.715s. This is shorter than the private6s sweep because the pulse begins/ends beyond the lamps and the capture samples roughly4.78Hz (largest interval0.221s). Independent free-duration fits yield5.981–6.010s. Phase-derived rest estimates after a6s sweep are9.161–14.688s, consistent with the source9–16s rest; these are estimates, not directly logged scheduler timestamps.

All five candidates were compared for every segment. Best source-model brightness RMSE is0.00526–0.00764; the closest incorrect pattern is at least0.17257. The classifications are therefore well separated in this data; per-lamp peak times and all interval indices are retained in the JSON.

**Limits:** Party, ReduceFlashing and InRound are false in every frame; root's separate UI/lifecycle evidence is required for those gates. This capture records brightness, not per-frame color/Enabled/range. The still native-ceiling-view.jpg shows pale cyan fixtures and a cyan-green vault with dark arches; it is palette evidence only, not a five-pattern motion or visual-comfort claim. Parent identifies this as normal unseeded production execution; no private random state was collected. This analysis made no Studio/UI/source writes.

Input SHA256 `dc772631a8326a46bcebae5975c6b526ee46b43938a37143cfa670b12fd5b06f`; controller `235a26d42b0d0ee80de5768bc3da428a1296aa73f9d08967594476ae129f2198`. Reproduce with `python artifacts/trello-20260909/lobby-ceiling-sweeps-prepared/analyze_native_frames.py`.
