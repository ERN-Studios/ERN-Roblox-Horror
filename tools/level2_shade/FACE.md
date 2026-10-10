# Level 2 shadow-realm face — second pass

Rebuild from the worktree root (one Blender process):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python tools/level2_shade/build_face.py
```

`build_face.py` builds all geometry, animation, lighting, renders and packaging. No assets are downloaded. For a lighting review, append `-- --preview 26 33`; this writes only those frames and the blend, so run the full command afterwards to regenerate a consistent delivery.

## Sculpt and performance

A dense continuous mesh uses shaped anatomical cross-sections, recessed unequal sockets, orbital bones and brows, hollow temples/cheeks, sharp cheekbones, an angular jaw and an excessively long chin. One side sits lower. The narrow neck has two raised tendons, branching surface veins and low bony shoulders with collarbones. Four tapered wet filaments hang from the chin/jaw. The lower face has no lips, opening, teeth, blood or wounds: vertical folds cover the entire mouth area.

Thirty-six shape keys animate irregular fine mesh displacement, lower-face bulging/suction, stretching vertical folds and a travelling jaw lump. Animated 4D shader noise adds crawling pores. The fixed orthographic camera watches a rig with constant pose keys: two-frame holds during approach/stare, a 35-degree tilt by 18, an upright snap on 19, a violent return on 20 and two further dislocations on 21–22. Projected head height is about 30% initially, 73% at 18, and 92–94% in 23–30. Skin motion continues during the pose holds.

The eyes are spherical, wet, lidless and deep-set, with one orb 25% larger and lower. Fine branching dark capillaries run across their surfaces. Grazing emission falls off to a darker spherical rim; small reflections show curvature. Eyes enlarge during 23–30 and 31–33, with the surrounding brow and sockets still readable. On 34–36 the emission becomes solid white. Capillaries disappear at 34; engulfed skin/strand geometry and lights disappear at 35 to prevent occlusion artifacts inside the final glow.

## Lighting and delivery

The world is black. Real cold side/crown/jaw rim lights expose the irregular silhouette; the skin has no emissive outline. Two point lights at the eyes and a dim downward eye-glow reflection expose the bridge, cheekbones and sealed skin folds. A weak overhead light reveals dark skin between small wet highlights. Broad skin remains near black; specular points/ridges are deliberately brighter. All skin lights are suppressed for the opening six frames. Compositor fog glow blooms the white eyes.

EEVEE renders 680×680 and Blender downsamples to 340×340, RGB, 8-bit, no alpha. Blender image APIs/numpy assemble the four borderless 1020×1020 sheets in row-major order and a 2040×2040 contact. ffmpeg writes the looping GIF at 12 fps / 3 seconds (GIF delays alternate hundredths). A soft corner vignette retains black corners in 1–30 and dark extreme corners on the final white flash. The JSON records dimensions, ordering and sheet SHA-1 hashes. Assertions check counts, dimensions, PNG RGB/depth and black corner values.

Outputs remain in `artifacts/level2-shade-face-20261010/`. The saved blend opens on frame 26. `preview/frame26_comparison.jpg` places first-pass frame 26 from the supplied reference contact on the left and the new render on the right; that reference is optional and is not a scene asset.

## Visual verification

Reviewed the contact sheet and full-size frames 3, 12, 18, 20, 26, 33 and 36, plus frame 7 and the side-by-side frame 26. Frame 3 contains only small opening white eyes. Frame 7 introduces the uneven skull/neck outline and shoulders. Frame 12 reveals deep orbs, bony sockets, wet skin, long jaw and tendons. Frame 18 has the excessive tilt and larger gaunt silhouette. Frame 20 violently returns to the tilt, closer, with flared eyes and stretched skin. Frame 26 has hollow cheeks, asymmetric shaded/veined eyes, glossy vertical mouth-area folds and dangling chin strands; the plain egg silhouette of pass one is gone. Frame 33 retains the brow, sockets and sealed lower face around enlarged eyes. Frame 36 is white glow with dark extreme corners and no polygon/strand occlusion. The contact shows lower-face pressure changing across 23–30. Fine pores and the smallest capillaries are subtle at 340 pixels.

This is an offline Blender asset delivery. No Studio changes, publication, helpers or git commits are part of this brief.

Final independent file checks: 36 RGB 8-bit 340×340 frames; four RGB 8-bit 1020×1020 sheets with every tile byte-identical to its source frame in the required order; all manifest SHA-1 hashes matched. Corner channel maximum in frames 1–30 was 0. Frame 36 had 92.92% of channel values at least 250/255. ffprobe confirmed the GIF is 340×340, 36 frames and exactly 3.000 seconds. The final `.blend` is 5,106,399 bytes. The full build ended with `FACE BUILD VERIFIED`.
