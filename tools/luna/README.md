# Luna — the lobby tribute dog

Luna was the owner's white Swiss Shepherd. In the lobby she sleeps in her bed on the west wall between the
Level 3 and Level 5 gates, gets up to wander and sniff around, and when a player pets her (prompt **Pet**) she
sits, gives her right paw and then follows that player for 5 seconds (walking, or running when they are far).

Runtime: `ServerScriptService/LunaTribute.Script.lua` (one server Script, nothing else in the place). It loads the
rig and the bed from group-owned Model assets with `InsertService`, plays group-owned Animation assets, and moves
her kinematically (server-owned, `AlignPosition`/`AlignOrientation`, PathfindingService); no Humanoid.

## Pipeline (all reproducible; big files live in `G:\Roblox\_local\luna`, never in git)

The owner's photos are in `G:\Roblox\_local\luna\refs` and must stay out of the repository.

1. Reference image: Meshy image-to-image (nano-banana-pro) from her photos -> `ref_standing_v1.png`.
2. Mesh: Meshy image-to-3d (meshy-7, textured, 16k tris) -> `meshy/luna_v1.glb`.
3. `normalize.py` — spine on +Y (nose +Y), feet on Z=0, 3.3 studs to the ear tips (1 Blender unit = 1 stud).
4. `build_rig.py` — 29-bone quadruped armature + automatic (bone heat) weights; `straighten.py` turns the
   scanned 22.6 degree head yaw out and makes the straight head the rest pose -> `blend/luna_rig2.blend`.
   `overlay.py` / `posetest.py` render the bones and stress poses.
5. Clips: `anim/clips_loco.py` (Idle, Walk, Run, Sniff), `anim/clips_sit.py` (SitDown, Sit, GivePaw, StandUp),
   `anim/clips_sleep.py` (LieDown, Sleep, WakeUp) on top of `anim/lunalib.py`; `anim/build_all.py` builds them
   all into `blend/luna_anim.blend`. QA: `anim/check_clips.py` (floor, paw sliding, loop seams, continuity) and
   `anim/sheet.py` (contact sheets).
6. `export_glb.py` (`--anim` for clips) -> skinned GLB; `glb_to_rbxmx.py` -> one KeyframeSequence per clip
   (`Pose = rest_local^-1 * animated_local`, every bone on every frame).
7. `upload_asset.py` uploads a `.glb` as a Model or a `.rbxmx` as an Animation to group 1039373905 through Open
   Cloud (key in `~/.codex/secrets/roblox.env`); receipts in `receipts/`. The Model import drops the clips, keeps
   all 29 bones (every bone carries weight) and turns the rig 180 degrees: her nose is the mesh's +Z, which the
   script undoes with the weld.
8. Bed: Meshy image-to-image + image-to-3d (smart topology) -> `bed_prep.py` (6.2 x 5.1 x 1.3 studs, cushion
   ~0.7 studs up, opening on the bed's -Z side).

9. Owner feedback round (2026-10-04):
   - GivePaw v2 holds the offered paw in line with the forearm; it was hanging straight down (`clips_sit.py`, `offer_phi`).
   - `paint_closed_eyes.py` makes the closed-eyes texture that she wears while asleep (image 86024350432064).
   - `player_pet_anim.luau` is the petting player's R15 clip: kneel, stroke, take the paw. It is uploaded from Studio with `AssetService:CreateAssetAsync`, group-owned (135130382947090).
   - The bed moved to lobby rel z +52, clear of the wall service panel.
   - The plate is drawn by its SurfaceGui with LightInfluence 0, and a warm SpotLight hangs over the bed.
   - Published as v2676 (`artifacts/luna-tribute-20261004/publication.json`).

10. Belly rub (2026-10-04/05):
    - `anim/clips_belly.py` holds RollOver, BellyUp, BellyRub and RollUp, after the owner's photos `refs/3.jpg` and `refs/4.jpg`. It went through two adversarial review rounds. The uploaded versions are the b2 clips.
    - `player_pet_anim.luau` `buildBelly()` is the player's R15 rub clip (114539659229386).
    - The plate reads RIP / LUNA / paw-heart-paw.
    - Published as v2697 (`artifacts/luna-tribute-20261005/publication.json`).

`studio.py` runs Luau in the open Studio place; `mcp.py` calls any Studio MCP tool and saves `screen_capture` images; `inspect_glb.py` / `render_views.py` / `landmarks.py` are the
inspection helpers used while building the rig.
