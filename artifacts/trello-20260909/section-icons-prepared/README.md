# Upgrades, Gear and Shop section icons

Trello: https://trello.com/c/WJLErpHx. One Store-source proposal, independently reviewed **9/10**, including the native ghost-caption correction. Root owns installation, native acceptance and separate mouse publication; this folder does not claim publication.

The existing UPGRADES & GEAR entry receives an up-arrow and backpack; the existing SHOP entry receives a shopping bag. Three consistent teal vector symbols use eleven Frame primitives, rounded corners and UIStroke. The original text, routing, button dimensions and input/modal guards are retained. There is no new Gear tab, asset upload, currency change or image dependency.

The 20-pixel icons sit inside the original large controls. Captions remain GothamBold18; the phone caption can wrap. Available width below188 pixels uses the original text-only layout, and the touch DEV chip keeps its original136×44 layout and caption. The glyphs and new captions are noninteractive children of the original buttons.

## Native finding and focused correction

Root's initial native rendering found ghost original text: direct Contextual UIStroke children of TextButtons remained visible when TextTransparency was1. The eight-line `ghost-caption-correction.diff` disables only those direct Contextual strokes while decorated captions are visible and restores them for narrow/DEV text fallback. Border-mode strokes and nested icon outlines remain enabled. The first installed candidate is preserved in `before-ghost-caption-correction.lua` and must fail the new actual-source negative control.

Final proposed Store SHA256: `1d9517771609e1d689daedab7c479ed62fe5bd971027cf6d765fdc683b445f0c`. The immutable original raw baseline is `5909381164763adca36287df4da351fb666165bd925122e5a4af020929e3a2af`; root has since installed the initial candidate and correction, so the runtime is no longer expected to equal that original baseline. No runtime mutation was made by this proposal's scripts or author.

## Validation and artifacts

Run `python artifacts/trello-20260909/section-icons-prepared/test_icons.py`. **92 actual-source checks** pass, including the original19 layout checks, narrow restore, DEV/modal rules, exact vector bounds, all four direct contextual strokes, preserved nested/border strokes and the regression's initial-candidate negative control. Both complete Store files compile: this proposal and the merge preview after Player ESP. The printed intermediate65 count is cumulative; it includes46 builder checks plus the original19 layout checks.

`section-icons.diff` is the complete focused delta against the original baseline. `prepare.py` contains the narrow, single-match transform; its main path refuses to overwrite the original snapshot after the runtime changes. `manifest.json` and `validation.json` record source provenance and results.

`upgrades.svg`, `gear.svg`, `shop.svg` and `section-icons-preview.png` are exported from geometry emitted by execution of the actual helper. The PNG uses bundled Montserrat as a schematic approximation; it is explicitly not a Studio/Gotham screenshot. Actual native font fit and stroke rasterization must be judged from root's native evidence.

## Merge and native handoff

The Player ESP proposal changes a separate Dev controls entry and keyless caption. `merge-preview-after-player-esp.lua` applies this icon transform to that proposal and compiles; it is an artifact only. Preserve the current Store checkpoint: apply the focused transform/delta rather than copying an older full Store proposal over an already published feature. Each feature retains its own publication checkpoint.

Root's focused acceptance should cover actual desktop/phone-size caption fit, narrow text-only fallback, unchanged DEV, and clicks on each icon/caption reaching the original button. Recheck the contextual strokes after the correction. Root already reported clean corrected native rendering; full evidence and final publication remain root-owned. MockGUI tests and the schematic preview do not establish physical-device input or native rendering.
