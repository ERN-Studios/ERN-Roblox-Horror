# Native unscaled caption fit

The actual84px phone squares reported TextScaled=false and TextSize16. Their72×15.12 caption boxes could not hold the observed70×16 “upgrades” /43×16 “shops” text. The earlier host assumed authored TextScaled=true persisted. No global typography writer was found in the current125 sources; its cause is unconfirmed and is not claimed here.

This correction explicitly uses unscaled text in an18px-high caption box with4px side padding.84/104/112px squares retain16px type; the64px fallback uses12px. Caption top follows the existing74% placement, capped to leave4px below the text box. Centering, palette, image IDs, square placement, input and DEV-chip behavior are unchanged. The unused UITextSizeConstraint is removed.

The captured16px width70 fits the84px box76. At64px, the56px box allows an estimated52.5px width at12px; that proportional estimate is not native font proof. Root should confirm actual TextFits at84 and64, clearly labelling any constrained synthetic layout for the fallback. No physical phone profile is asserted to necessarily choose64.

`test_caption.py` reuses the complete actual builders/visibility and existing host, explicitly reproducing the observed post-construction TextScaled=false state. It checks font, line height, full box bounds and captured/estimated widths through the existing layouts. Exact before code fails the native line-height check. Full compiles and an independent diff-span inversion preserve the baseline. No old prepared variants or production files are modified by this task.

Inputfa63 and outputb031 full hashes are recorded in manifest.json. Parent owns native testing, installation and the final required10/10 review.
