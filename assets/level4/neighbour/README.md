# The Neighbour — four-view T-pose reference

Five full-resolution PNG references for the friend building the Level 4 entity:

| View | File | Roblox group image ID (reference only) |
|---|---|---|
| Front | `neighbour-tpose-front-v1.png` | `rbxassetid://88634650905286` |
| Back | `neighbour-tpose-back-v1.png` | `rbxassetid://92623804113231` |
| Character's left profile, face points left | `neighbour-tpose-left-v1.png` | `rbxassetid://78489637675861` |
| Character's right profile, face points right | `neighbour-tpose-right-v1.png` | `rbxassetid://131131639582058` |
| Original front-three-quarter design concept | `neighbour-concept-three-quarter-v1.png` | `rbxassetid://92466950154067` |

All four show the same original character in a straight-armed T-pose: tall narrow body, faded blue-grey utility coat, dark trousers and boots, and a blank matte smoked-glass faceplate. Side views foreshorten the outstretched arms naturally. The hands differ slightly across AI-generated angles; use the front and back open hands as the hand reference. Use the front image for front details and the back image for the plain rear coat seam. Do not copy any image's pixel measurements as exact geometry.

**Modeling scale and rig contract:** the authoritative target is `docs/LEVEL4_CONTRACTS_2026-09-21.md` §6. Overall height is 9.5 Roblox studs and widest body envelope 4.2. Torso is 3.4 × 3.42 × 1.5; head 1.6 × 1.9 × 1.6; mask 1.2 × 1.2 × 0.2; upper arms 0.7 × 1.9 × 0.7; forearms 0.6 × 2.85 × 0.6 (**1.5× upper-arm length**); legs 0.8 × 4.18 × 0.8. The art may understate the forearm ratio, so follow those dimensions. The head tilt (0.22 rad pitch, 0.14 rad roll) belongs in the final rig or animation; the reference's neutral head angle makes modeling easier.

Keep separate named rig parts/bones for `HumanoidRootPart` (PrimaryPart at hips), `Torso`, `Head`, `Mask`, `UpperArmLeft`, `UpperArmRight`, `ForearmLeft`, `ForearmRight`, `LegLeft`, and `LegRight`, plus `HeadAttachment` and `FootstepAttachment`. Give Claude the model/rig file and its actual bone hierarchy before replacing the placeholder. These PNGs are modeling references, **not** a finished mesh or in-game entity. No place instances or game code were changed for this set.

The handoff for the 3D artist and Claude is in `MODEL_HANDOFF.md`. The five siding/ceiling textures in `assets/level4/materials/` belong to the **world**, not to this character. The Roblox copies are 682 × 1,023 px because Studio downscaled the import; give the modeler the full-resolution PNG files from this GitHub directory instead.

All five image IDs were confirmed as `Image` assets in ERN Roblox Studios' group inventory (group `1039373905`) and loaded as `EditableImage` in Studio on 23 September 2026. They are **reference images only**: no model, mesh, animation or live Studio instance was created from them.

Created with Codex's built-in imagegen tool on 23 September 2026, using the original `assets/concepts/level4-neighbour-v1.png` concept as the identity reference. Generation direction: one orthographic full-body T-pose per view, uniform neutral background, consistent coat/mask/boots, no labels, props, effects or gore; back and side views edited from the front reference to retain identity. The four native generation outputs were copied without image edits.
