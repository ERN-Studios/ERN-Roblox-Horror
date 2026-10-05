# Level 6 concept images, third draft ("the Arena", tall walls), 2026-10-06

You generate concept images with your BUILT-IN image generation tool (not Meshy, not any MCP). Do not run git,
do not touch Roblox Studio, do not edit any file outside `artifacts/level6-concept-20261006b/`.

Folder (paths relative to the repo root): `artifacts/level6-concept-20261006b/`
- `refs/` reference images (the tool accepts at most five per image; pass the ones named for each image)
  - `refs/owner_ref.png`   THE picture the owner picked: "I like this ref picture a lot. Make it like that."
                           Everything must look like the structure in this picture. Pass it for EVERY image.
  - `refs/tall_walls.png`  the SECOND picture the owner picked: "this is also nice, a blend of the two for the main
                           area". Twelve storeys of galleries rising sheer round the court. Pass it whenever the
                           court or the walls round it are in view.
  - `refs/liked_court.png`, `refs/liked_gate.png`  earlier pictures the owner liked (materials, mood)
  - `refs/old_staircase_look.png`  what the owner does NOT want: wide round steps, "a circle staircase". Never pass it.
  - `refs/hatch_idea.png`  an earlier picture of a hatch in the court floor with green light (for the finale images)
  - `refs/doll.png`, `refs/doll_ingame.png`, `refs/doll_counting.png`  the level's entity, "the Counter"
  - `refs/ingame_look.png`, `refs/owner_frame_ingame.png`  the frame in real Roblox game graphics
  - `refs/ref_plan.png`, `refs/ref_section.png`  the new plan and side view, drawn to scale (present for some jobs)
  - `refs/style_map.png`   the approved illustrated-map style
- `raw/`    save every generation as `<name>_raw.png` (a rejected try as `<name>_try2_raw.png`)
- `final/`  save the accepted image as `<name>.png`, exactly 1920 x 1080: aspect kept, centre crop, never stretched.

## What the level is
A co-op hide-and-seek horror level. The WHOLE level is ONE gigantic soft-play frame, wall to wall in a round
hall 155 metres across with a steel roof 42 metres up. There is nothing else in the hall.

- THE COURT. In the exact centre is a round open court 25 metres across: blue-and-green checker foam floor, a
  yellow ring painted on it, and a short red padded post standing in the middle under the brightest light.
- THE WALLS OF GALLERIES. A BLEND of the owner's two pictures. From refs/tall_walls.png: the sheer height and
  steepness, twelve storeys standing round the court like the inside of a silo. From refs/owner_ref.png: the
  detail, every storey a real gallery you could walk in, with tubes, slides and bubble panels, and the wall
  broken by narrow ledges. So: the frame rises round the court as a
  curved WALL of netted galleries, storey stacked on storey, all the way round, 360 degrees. Four storeys
  straight up from the court's edge, then a narrow ledge (a walkway 4 m deep), four more storeys, another narrow
  ledge, four more: TWELVE storeys in all, 34 metres, leaning back only slightly. Every storey is a netted
  gallery of padded posts, mat decks, red bubble-window panels, crawl tubes and punch bags, and solid-colour
  tube slides hang down the face. Behind that face the frame goes on, solid, twelve storeys deep to the hall
  wall. It must NOT look like wide stadium steps or a round staircase of terraces: it is a tall, steep wall of
  stacked galleries, like the inside of a colosseum or a silo.
- THE WAY IN. Players arrive in a small low padded tunnel through the hall wall. At its inner end is a gateway
  with a padded blue lintel reading PLAY ZONE, and beyond it one straight lane of checker floor between net
  fences runs through the twelve-storey frame to the court.
- THE ENTITY, "the Counter": a porcelain ball-jointed doll child in a party hat, striped shirt and dungarees,
  2.3 m tall. Exactly as in the doll references. Only in images that ask for it.
- THE FINALE. When the players have touched the post for the third time, every light turns DEEP RED and the
  post starts a ONE-MINUTE COUNTDOWN: a band of bright white digits glows round the top of the post, and the
  yellow ring on the floor lights up as a clock dial of sixty glowing segments that go dark one by one. When it
  reaches zero the post sinks into the floor and leaves a round hole 2.5 m across with GREEN light shining up
  out of it. Under the floor a padded shaft with a yellow spiral slide drops to a small padded room with a
  green illuminated EXIT sign over a door. That is the way out.

## Look, for every photoreal image
Photoreal concept art in exactly the look of refs/owner_ref.png: wide lens, dim, dusty, abandoned, quiet. Lit
by sparse cold-white fluorescent strip fixtures far overhead: pools of light, long shadow, light haze. Materials
exactly as in that picture: blue-and-green checkerboard foam puzzle-mat floor, worn; steel posts wrapped in
yellow, red, blue and green vinyl padding; black knotted safety netting; coloured vinyl mat decks; square red
panels with a round clear bubble window; glossy moulded plastic tube slides, each ONE solid bright colour; a few
loose plastic balls; exposed steel roof with trusses. No people, no children, no animals, no entity unless the
image asks for it. No arcade machines, no neon, no inflatables, no ball pit, no watermark, no HUD, no UI. No
lettering except what an image names; regenerate if lettering is garbled.

## How to work
For each image: write the full prompt, generate, LOOK at the result and check it: the structure looks like
refs/owner_ref.png (tall steep walls of stacked galleries, NOT wide round steps), twelve storeys where the
whole height is in view, no bare hall, no other attractions, no striped slides, no garbled text, no people
unless asked. One retry if it fails; keep the better one. Export to `final/`. At the end write
`prompts_<job>.json` in the concept folder: per image the final prompt, the references passed and one honest
line on what is still off. Reply with a short list of the files and their weaknesses.
