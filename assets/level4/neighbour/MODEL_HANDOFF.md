# The Neighbour — model delivery brief

Use the five PNGs in this directory as visual references for the original Level 4 entity. The four orthographic T-pose images show front, back, left and right. The three-quarter concept shows the intended mood and silhouette. The game contract in `docs/LEVEL4_CONTRACTS_2026-09-21.md` §6 takes precedence over any AI-image inconsistency: particularly the forearms, which must be **1.5× the upper-arm length**. Keep the faceplate blank matte smoked glass, the utility coat faded blue-grey, and the trousers/boots dark. No eyes, weapon, tie, gore or borrowed horror-character likeness.

## Scale and orientation

- 9.5 Roblox studs tall at intended runtime scale; maximum moving silhouette width 4.2 studs. The T-pose span in the images is for modeling and is wider than the moving silhouette.
- Roblox orientation: +Y up, face forward toward -Z. Root/pivot at the hips. The faceplate sits 0.85 studs in front of the head.
- Required proportional blocks (studs): `Torso` 3.4 × 3.42 × 1.5, `Head` 1.6 × 1.9 × 1.6, `Mask` 1.2 × 1.2 × 0.2, each upper arm 0.7 × 1.9 × 0.7, each forearm 0.6 × 2.85 × 0.6, each leg 0.8 × 4.18 × 0.8. The final mesh can refine contours while keeping the gameplay envelope and named mapping.
- Neutral head in the modeling rest pose. The game's recognizable head tilt is 0.22 rad pitch and 0.14 rad roll, applied by the rig/controller or animations.

## Rig and return files

- Provide the native source project (preferably `.blend`), an exported `.fbx` or `.glb`, and every external texture file. Include the actual bone/part hierarchy and the export scale/unit setting in the delivery note.
- Keep distinct, clearly mapped nodes or bones for `HumanoidRootPart`, `Torso`, `Head`, `Mask`, `UpperArmLeft`, `UpperArmRight`, `ForearmLeft`, `ForearmRight`, `LegLeft`, `LegRight`. `HumanoidRootPart` is an invisible 2 × 2 × 1 box at the hips and will be the Roblox Model `PrimaryPart`.
- Reserve `FootstepAttachment` and `HeadAttachment` on the root at local `(0, -4.75, 0)` and `(0, +4.37, 0)` for audio. The game also needs the existing detector tag/attributes and five animation states; Claude will handle runtime wiring.
- A rigged T-pose mesh is the first deliverable. Animation clips are not required from the modeler for this handoff. Keep elbows, wrists, hips, knees and neck movable for later Idle, Walk, Search, Chase and Attack work.

**Integration boundary:** the current Roblox entity is a Humanoid-less set of independently CFrame-posed anchored Parts. A skinned mesh does not replace it automatically. Claude must inspect the actual delivered hierarchy and adapt the controller/animation bindings while preserving collision, AI, attachments, detector behavior and state readbacks. The four PNGs are concept references, not animation or mesh asset IDs. Do not mark the Level 4 card complete from these files alone.
