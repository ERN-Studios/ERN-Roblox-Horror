# Independent code review — centered music controls

**9/10. No remaining code blocker; GO for root's native acceptance.**

Subsequent final Dispatch/capitalization and native acceptance is recorded in [the final review](../center-music-buttons-revision/native-final-independent-review.md). That final Store hash supersedes the prepared composition below.

Reviewed final Store: `cdae3e9610561db95fa281edfb5ca6a735ff817dd2ddf51e68bb9f4852d478c0` at `composed/StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`.

Reviewed RoundUI: `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3` at `proposed/StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua`.

The final layout input is `71e4bd19647233ddba91e50509f90a6b76f8979cb80e9bddd4b9e3a9111da821`. The shared Settings fragment remains `ff8c75213308d1f621ba2ebdf403ba911fbb75b29dfa9854b2449297d8a7810d`. I read both complete deltas and verified that removing the state fragment restores the whole layout proposal, while RoundUI is byte-identical to the pre-side-dispatch-copy source. Existing dispatch controls and their preference are retained.

I independently reran **261 actual-source layout checks, three targeted negatives and two whole compiles**, plus **31 shared-state checks, the original-row-only negative and two whole compiles**. The final tests execute the actual UIDevice remembered capability functions as well as the production Settings fragment. These bounded hosts do not claim native rendering or live persistence.

The review found a real initialization defect in the earlier e302 composition: explicit `musicButton.Selectable=false` was permanently cached by UIDevice as the control's capability. A simple mock had missed it. The final composition removes that initial assignment, so temporary loading/hidden states can disable selection and later restore it. A negative control and load/hidden recovery checks now cover the actual capability behavior. The only other final delta from e302 is insertion of root's uploaded Music asset `102262986416811`; no state behavior changed in that correction.

Both the square and Settings row call one request function with the same current value, pending boolean, serial, acknowledgement and 12-second fallback. OFF remains actionable. Rapid reversals retain the existing Settings behavior; an old timer or mismatching acknowledgement cannot clear a newer pending intent. The new music control performs no direct local music-attribute write. Root must observe the actual replicated `LobbyMusicEnabled` attribute and both decks, not just the optimistic caption, during acceptance.

The complete three-square stack is centered in the desktop safe area. The measured phone compromise is explicit:180px total at ideal y65–245 must move36px upward to y29–209 for8px clearance before the actual glyph at217. Existing layout passes reread the glyph; no per-motion watcher is claimed. If no safe above/below placement exists, the code deliberately retains the visible centered rail; unusually constrained viewports are not guaranteed collision-free. The planned normal desktop/phone acceptance must not be generalized to all viewport or simultaneous-touch combinations.

The music v2 image was independently viewed beside the existing Shop and Upgrades masters. Its note, two-color appearance and rounded forms are suitable for the same family (**prepared artwork 10/10**). Actual asset loading, optical balance, text fit, centering, tap consumption, Settings synchronization and final design score remain native acceptance steps. No production, Studio, upload, publication or external-message action was performed by this reviewer.
