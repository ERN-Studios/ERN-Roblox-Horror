# Include the three reviewed tracked-document deltas

These documents are already tracked and modified. **Include their reviewed deltas in the final curated commit**, rather than unintentionally leaving them behind. Exact allowlists are `reviewed-tracked-docs.txt` and `.nul`; nothing has been staged.

| File | Review of the actual delta |
|---|---|
| `README.md` | Five additions/six removals describe the existing 9 September Manager pursuit of hidden players. Current `nearestLivingPlayer` selects through the living/eligible player gate; tracking retains the table anchor and targets its outer approach, while the CHASE-target branch starts `TABLE_CHECK` before the untargeted patrol cooldown branch. Current tuning is a 2.0 s reaction window and 1.5 s flush immunity. The hiding controller leaves AI-owned BeingChased alone. The changed paragraph is consistent with the current published implementation. |
| `CLAUDE.md` | Four additions/two removals document the same targeted-table behaviour and retain its 9 September provenance. This is an appropriate project-memory companion to the runtime source. Its dated historical sections are not new completion claims. |
| `docs/ZYNTRA_MONETIZATION_SETUP.md` | Preserve the already-authored token-gift UI documentation together with the two root-authorized status corrections: only the v1865 two developer IDs, and the gift function retained in the subsequently published v1840 Monetization source. The new native gift-test paragraph remains a historical Studio check and explicitly does not claim a real DataStore purchase/server persistence test. Catalogue/pricing content was not changed. |

The shorthand “nearest living player” in the Manager prose remains subject to the actual existing eligibility gates (active round, present/living participant, not escaped, private Entity Shield inactive); it is not a claim that protected or lobby players can be targeted. No additional documentation rewrite or production change is needed to include these precise deltas.

The new current scope document is separate: add `docs/TRELLO_SCOPE_2026-09-10.md` after root records the final square-button release and Git outcome without retroactively changing historical checkpoints. The optional dated priority journal can follow as explicitly historical context. Do not add the raw Trello archives merely because these docs link local evidence.

Example explicit stage command **for root after final publication/audit**, not executed here:

```powershell
git --literal-pathspecs add --pathspec-from-file=artifacts/trello-20260909/git-readiness-prepared/reviewed-tracked-docs.nul --pathspec-file-nul
git add -- docs/TRELLO_SCOPE_2026-09-10.md
```

Then inspect the complete staged diff/stat and run the final `git diff --cached --check` with the already prepared mirror/test allowlists. This review is documentation consistency, not another gameplay/native score. No Git operation, pricing change, or source mutation was performed.
