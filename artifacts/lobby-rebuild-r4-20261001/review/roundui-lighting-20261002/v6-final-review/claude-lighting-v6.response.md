**PASS FOR ACTUAL PLAY** — I found no blocking state/restoration defect in the supplied v6 text. Nothing was run or hashed by me.

**Observed in the code**
- The nine `values` keys equal the old literal writes and the nine properties the warm/maze branches set, so the snapshot covers every Lighting property this pass writes.
- Both 2/3 exits trace correctly: the top `restore()` compares readback to readback, writes baseline and clears both maps; the guard's second `restore()` is a no-op.
- `lighting` and `applied` are created and cleared together with no yield between. The pending baseline survives the L4 branch, so return-inside-L4 cannot re-snapshot R4 values.
- New writes only persist under the 2/3 early-return guards; elsewhere the warm branch overwrites all nine. No regression path found.

**Confirm in play (not blockers)**
1. **Release order:** if `InRound`/`Level6InRound` clears before an L2/L3/L6 controller restores a captured R4 snapshot, the first tick mismatches and clears the maps. The later controller write then re-leaks R4 while markers linger. Join each level from inside R4, then return to the original lobby.
2. **Coincident values:** ClockTime 0, FogStart 0, FogEnd 100000 and black shifts are indistinguishable from an owner's identical write. A partial restore can leave a mixed state under lingering markers.
3. **Baseline meaning:** it is the pre-R4 state, not canonical warm. A first entry under active guards restores whatever was there.
