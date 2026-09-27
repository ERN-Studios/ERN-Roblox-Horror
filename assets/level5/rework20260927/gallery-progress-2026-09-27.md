# Level 5 rework progress — 2026-09-27

## Authoritative Studio export

Studio instance `e7dbf962-5b02-4de6-9494-ef440fb543aa`, place `131311258779917`, universe `10559217407`, Edit DataModel. The following exact `ModuleScript` instances were read immediately before each scoped write. Their live `Source` and `ScriptEditorService:GetEditorSource` both matched the previous committed source byte for byte. `UpdateSourceAsync` checked the same baseline inside each write, and both live representations matched the new repository file afterward.

| Studio path under `ServerScriptService.Level 5 Systems` | Class | Previous bytes / SHA-256 | Installed bytes / SHA-256 |
| --- | --- | --- | --- |
| `Level 5 Reference Facades` | `ModuleScript` | 54,009 / `cb5ab04b66c95d37b21b9065d0823ea5a79c4b5ece88746c4a47e3380a3683a0` | 58,257 / `8fcf6c5756a053253bc2efccb0b5ee8c9618b5563c88a9302d9703535988a690` |
| `Level 5 Reference Anomalies` | `ModuleScript` | 88,154 / `54e1d028929e559911dcd56c818cc39b945bc1caf275a0cb4aea63bf1d89a0e2` | 92,499 / `801656b214c6ac01492d4beb443ab38bcd17f4210f4202e5e87c3fad51b85400` |

Their mirrors are `ServerScriptService/Level 5 Systems/Level 5 Reference Facades.ModuleScript.lua` and `ServerScriptService/Level 5 Systems/Level 5 Reference Anomalies.ModuleScript.lua`. The 16,402-byte `Level 5 Rework Gallery` module, `Level5PreviewAccess`, `ReplicatedStorage.DevAccess`, and public-round flags were not edited. This remains the same DEV-only sealed Level 5 door flow as before, using the same server `DevAccess.IsAllowed` gate as Level 6. Every cell still has `FidelityStatus=unverified-draft`; the gallery version is `reference-gallery-2026-09-27-v1`.

No new texture was generated in this pass. The previously generated ChatGPT imagegen candidates remain gallery-scoped: clapboard `rbxassetid://107441812561821`, carpet `rbxassetid://136282007145831`, lawn `rbxassetid://108216315862080`. The full native backup `pre-rework-place.rbxl` predates this pass; a new post-change native backup is outstanding.

## Isolated visual QA

Claude CLI `claude-opus-5-5` at `medium` effort reviewed the remaining references read-only; findings are in `claude-opus-remaining-refs-2026-09-27.md`. The local builder proposals were installed into temporary cloned modules, built separately in Studio Edit, captured from each cell's `ReferenceCameraCFrame`, and the temporary gallery roots/modules were removed. Final isolated build: **10,740 descendants**, below the 30,000 gallery limit.

| Section | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Descendants | 1,791 | 359 | 1,087 | 1,065 | 1,440 | 1,599 | 469 | 1,279 | 1,282 | 307 |

The revised [03](proposal-pass5-ref03.jpg), [04](proposal-pass5-ref04.jpg), [06](proposal-pass8-ref06.jpg), [07](proposal-pass8-ref7.jpg), and [10](proposal-pass8-ref10.jpg) captures show the current proposals. Section 03 has closed upper side gaps and a farther cylinder; 04 has narrower, offset balcony stacks; 06's black cutaway is visible from the corrected lawn-center camera; 07 has open stair rooms and soffits; 10 shows left windows, the balcony view, and the six-panel door. These Studio captures are landscape. The user references are portrait screenshots attached in conversation, so a pixel overlay and 1:1 acceptance have not been completed.

## Playable route proposal

`playable-ab-proposal-2026-09-27.lua` is a **local draft**, separate from the authoritative runtime mirror. It adds the indoor courtyard ceiling and apartment/house facade work to playable A, and a fluorescent townhouse corridor to playable B. A full isolated Studio Build from this draft and fresh live Furniture/Neighbourhood/Landmark dependencies succeeded with **27,431 descendants**, 26,124 BaseParts, 3,429 A descendants, 1,210 B descendants, four A clue homes, 18 Watcher anchors, seven gates, and 133 waypoints. A roof-up Edit capture showed the new ceiling closing the upward sky gap. This did not change the live `Level 5 Architecture` ModuleScript. Navigation, collision, round runtime, and the other playable districts still need verification before it can replace the live source.

No fresh Play test or Roblox publish is claimed for this pass. The existing experience was not published because visual fidelity and playable integration still have material gaps.
