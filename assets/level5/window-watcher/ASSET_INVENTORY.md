# Window Watcher asset inventory

**Final frozen local asset files.** Blender authoring and export audits are complete. **Native Roblox Studio import is still blocked pending the file picker/user action; Roblox animation playback has not been verified.**

## Generation provenance

| Stage | Task ID | Result | Actual Meshy credits |
| --- | --- | --- | ---: |
| image-to-3d | `01a0d8e3-3fdd-752a-b810-ea9cace0266e` | SUCCEEDED | 15 |
| rigging | `01a0d8ec-0c4f-71fc-b513-af1e1d1e59b4` | SUCCEEDED | 5 |

**Actual total: 20 Meshy credits (15 geometry + 5 rigging).** Download/preview history rows are not additional paid generations. Signed URLs and credentials are excluded. Imagegen usage is separate and not quantified here.

## References

- conceptImage: [window-watcher-concept.png](reference/window-watcher-concept.png)
- originalConceptImage: [02-the-window-watcher.png](../entity-concepts-20260925/02-the-window-watcher.png)
- conceptPrompt: [02-the-window-watcher.prompt.txt](../entity-concepts-20260925/02-the-window-watcher.prompt.txt)
- conceptProvenance: [02-the-window-watcher.provenance.json](../entity-concepts-20260925/02-the-window-watcher.provenance.json)
- aPoseImage: [window-watcher-a-pose.png](reference/window-watcher-a-pose.png)
- aPosePrompt: [window-watcher-a-pose.prompt.txt](reference/window-watcher-a-pose.prompt.txt)

## Final model and animation verification

Blender 5.2.0 LTS; one rig with 25 bones, one mesh with 8,968 vertices and 11,862 triangles, one packed image plus a standalone base-color PNG. Mesh audit records zero unweighted vertices, vertices above four influences, non-normalized weights or root-weighted vertices. Height 2.4 m; authored at 30 FPS.

Clips: WatchingIdle (6 s), SlowWindowLean (5 s), GlassTap (4 s). All compact clips identify the frozen model GLB and match the hashes in the final coordinate audit. The compact clips use serialized GLB local rest bases: **do not conjugate local deltas by the world Y-up conversion.**

The final animation-quality audit and GLB/FBX roundtrip audit both pass with empty issue lists. The earlier GlassTap frame-step issue was corrected before freeze. These are Blender/export checks; they do not prove native Roblox import or playback.

Frozen model GLB SHA-256: `cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e`. Final GlassTap compact data: **186,886 bytes**, SHA-256 `139640ae4ad89c3a59525c45746520af3f5de25b670817734be894a72b62222a`.

## Final deliverables

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| [model.glb](model.glb) | 6,501,680 | `cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e` |
| [model.fbx](model.fbx) | 6,596,124 | `3d5834fb84b094d1d76c4b0c4041a09dcc66fa0f3e91c988facd50af2cd23beb` |
| [model.blend](model.blend) | 6,996,669 | `134e485ba1e8479d668a9460e87e18a9c87083f52ff4ae1a89dc4bbe0ac2f0ad` |
| [WatchingIdle.fbx](WatchingIdle.fbx) | 6,983,532 | `669a226866f551eda4f0ad10aa182927e786bae15df550f91d1b7886a46362de` |
| [SlowWindowLean.fbx](SlowWindowLean.fbx) | 6,948,620 | `11a8fa3e7c14a5b2e7d3191ece272fcc9d51ec8b1fe28520c535f9a37ef79eca` |
| [GlassTap.fbx](GlassTap.fbx) | 6,903,804 | `39548720519eb92acac53e02991286aadca0e403254ba79f356da7405691c3c0` |
| [WatchingIdle-roblox-30fps.json](WatchingIdle-roblox-30fps.json) | 278,337 | `e3abd0959248f376f6c6a8f6a5d5036d114c96f8d9b96422e4c5085d7b8b9ce4` |
| [SlowWindowLean-roblox-30fps.json](SlowWindowLean-roblox-30fps.json) | 235,895 | `9062803490136db35f3ad76a1e5b1cb3b18bcea56f9a4596485d6335221f5f8b` |
| [GlassTap-roblox-30fps.json](GlassTap-roblox-30fps.json) | 186,886 | `139640ae4ad89c3a59525c45746520af3f5de25b670817734be894a72b62222a` |
| [WatchingIdle-three-quarter.png](renders/WatchingIdle-three-quarter.png) | 1,133,315 | `b61df7151e3f74999a70cddc6e3932ac9555f91b2362fe13ee56aa21fe983b01` |
| [SlowWindowLean-three-quarter.png](renders/SlowWindowLean-three-quarter.png) | 1,130,990 | `c2af136cde712daf30090cd098aaeae701435505ddf2714f71a5c8fa3ccbf9e0` |
| [GlassTap-three-quarter.png](renders/GlassTap-three-quarter.png) | 1,136,946 | `27edeed02049e173507daa1f7ba21ecffe03605210853db98c6ab1be95a9702d` |
| [GlassTap-palm-closeup.png](renders/GlassTap-palm-closeup.png) | 1,419,808 | `ac087f4cf0cb206dab2e9ec87dbbbec36cb248687ccb57cb26ea0ef70c38e89f` |
| [WindowWatcher-contactsheet.png](renders/WindowWatcher-contactsheet.png) | 2,078,969 | `6f0fe20a4dc140e364930b5fc02ac47771ce769dc93d6662b9a46622723f556f` |
| [serialized-glb-coordinate-audit.json](serialized-glb-coordinate-audit.json) | 44,468 | `21d66d39cb702f80d3477a9f002ab6e9544b94535e230bc2289752215e1de0d9` |
| [WindowWatcher-basecolor.png](WindowWatcher-basecolor.png) | 5,952,974 | `3229b3bc4eec4498379348bcfabb74dfac136dc1ab51d8a18cb073c34bb01133` |
| [animation-quality-audit.json](animation-quality-audit.json) | 1,374 | `5d87d23c02fb172e032d6f8bd27ed372adeceb2c68113428dd664dcae31e6d06` |
| [roundtrip-audit.json](roundtrip-audit.json) | 172,881 | `65679b939d3b877d822be6573840e2dcbbf5a8c0c39507471942d80a60fd3fa0` |
| [placement-reference.json](placement-reference.json) | 9,079 | `90646a50fea3956c5aea58d6da8f9593b47173bd848bc1d78e69e962671b89cc` |
| [GlassTap-raising-arc.png](renders/GlassTap-raising-arc.png) | 1,138,480 | `92fbb63bc6b6a322d751a16686f235cece1bf3cd3bcba0cd56e3b568d3110988` |

**20 core final files listed above.** The full repository package additionally contains Meshy source models, Blender authoring scripts and the compressed expanded matrix evidence. `repository-inventory.json` records every packaged file except itself. Original receipt paths in the provenance JSON refer to private task-local records; final deliverable paths refer to this directory.

Remaining: complete native Studio import, then verify the imported rig/materials and all three animations in Roblox.
