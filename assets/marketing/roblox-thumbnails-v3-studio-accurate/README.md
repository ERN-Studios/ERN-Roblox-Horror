# Roblox carousel v3 — Studio-accurate set

Generated on 2026-08-27 after inspecting the live Roblox Studio place (`placeId: 131311258779917`) and staging the real in-game rigs inside the generated maps for scale and appearance checks.

## Deliverables

The PNG files are the ImageGen source renders (1672 × 941). The JPEG files are upload-ready 1920 × 1080 exports at quality 92.

1. `01-level1-entity-corner-chase` — Level 1 maze chase with the real corrupted hazmat Entity.
2. `02-level1-entity-flashlight-ambush` — close Level 1 flashlight encounter emphasizing the real long black fingers.
3. `03-level2-pool-foam-kids-room` — exact yellow-mosaic kids pool room and Pool Foam silhouette.
4. `04-level2-slidemouth-grand-slide-hall` — exact Grand Slide Hall palette and the four-legged Slidemouth.
5. `05-level3-mall-manager-disc-relay` — red party-room maze, Mall Manager, and real CRT/VCR disc relay.

## Studio source-of-truth audit

- Default player: `StarterPlayer.StarterCharacter`; muted mustard/olive suit, black featureless visor, black gloves/boots, compact ribbed black backpack. Shared color map: `rbxassetid://116183270522679`.
- Level 1 Entity: `Workspace.Entity`; giant corrupted hazmat rig with hunched shoulders, oversized boots, arms nearly to the floor, long black claw fingers, and two tiny amber-yellow visor pinpoints. Mesh: `rbxassetid://113409117000796`; texture: `rbxassetid://104698412375264`.
- Pool Foam: `ServerStorage.Level2Assets.PoolFoamPrimaryTemplate`; tangled glossy primary-color foam tubes with a narrow stacked-cone top and no face. Mesh: `rbxassetid://70395501730675`; color map: `rbxassetid://108927756252297`.
- Slidemouth: `ServerStorage.Level2Assets.Level 2 Slidemouth Template`; four glossy playground-pipe legs, red/green/blue/yellow body, huge yellow-rimmed circular mouth, dense cream conical teeth. Mesh: `rbxassetid://99102503208838`; color map: `rbxassetid://134465279157918`.
- Mall Manager: `ServerStorage.Level3Assets.EntityTemplates.MallManagerTemplate`; tall thin uniformed humanoid with a smooth red featureless head, long pale arms, red hands, black trousers and shoes. Mesh: `rbxassetid://109940356128050`; color map: `rbxassetid://139917107442839`.
- Level 1 map: generated 964-stud maze with sickly yellow-green damask wallpaper, low beige drop ceiling, dark green-gray carpet, blocky partitions, and sparse fluorescent panels.
- Level 2 map: generated yellow-mosaic kids pool room with oval skylights and cyan pads; white-tiled flooded Grand Slide Hall with hanging yellow/pink/turquoise tubes and a blue spiral slide.
- Level 3 map: orange-red party rooms, stained burgundy children's carpet, off-white acoustic ceiling, balloons, plastic furniture, CRT/VCR relay, and a 560-stud red PA-speaker exit corridor.

## QA notes

- Every composition uses the same default in-round avatar silhouette.
- The first Level 1 render was rejected because its visor pinpoints were blue; the retained image is the corrected amber-yellow version.
- No previous concept-art entity designs were used as creature references.
- These files are prepared for review and upload. They have not replaced the live Roblox carousel in this task.

