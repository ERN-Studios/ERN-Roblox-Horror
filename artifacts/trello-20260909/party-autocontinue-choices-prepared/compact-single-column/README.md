# Compact rows: one column

Root reproduced the remaining font-width failure in a real Studio custom viewport of 567×270 with no synthetic attributes. `../compact-correction/native-568-before.json` records a 543×25 list and 259.5×25 rows. The 20-W username plus ` — CONTINUE` measured 291×11 pixels and `TextFits=false`.

This proposal adds only `if compact then columns = 1 end` and its comment immediately after the existing compact predicate. It gives the measured case a 531-pixel row, keeps each complete name/choice on one line, and retains all six rows through the existing scroll canvas. Noncompact two-column/two-line behavior, original title/divider/countdown/buttons, serial/revision handling and routing are unchanged. No font reduction or shortened name is used.

Run `python artifacts/trello-20260909/party-autocontinue-choices-prepared/compact-single-column/prepare_and_test.py`. It reuses the existing actual client/geometry host, adds the exact measured width regression at 567×270 plus 568×270 and 767×274, checks resize restoration and reset, requires the former source to fail the named width assertion, compiles the complete proposal and proves an exact one-hunk inverse. Source and tests are artifacts only; the runtime is checked for drift and never written.

The input is the exact first compact correction `eaf4053bfdd165089045413c3999dd91b3f78187ae528a1947e1068a0765f7de`. Preserve its native failure evidence. Independent author review and native retest of the final text/scroll geometry are required before treating this correction as complete. The measured text width is reused from native evidence; the offline host does not simulate Roblox font rasterization.
