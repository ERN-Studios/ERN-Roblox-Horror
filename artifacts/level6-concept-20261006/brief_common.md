# Level 6 concept images, second draft ("the Arena"), 2026-10-06

You generate concept images with your BUILT-IN image generation tool (not Meshy, not any MCP). Do not run git,
do not touch Roblox Studio, do not edit any file outside `artifacts/level6-concept-20261006/`.

Folder (paths relative to the repo root): `artifacts/level6-concept-20261006/`
- `refs/` reference images (the tool accepts at most five per image; pass the ones named for each image)
  - `refs/liked_court.png`       a picture the owner LIKED: the court and post with the frame all round. Keep this look.
  - `refs/liked_gate.png`        a picture the owner LIKED: the PLAY ZONE gate between the nets. Keep this look.
  - `refs/liked_from_above.png`  a picture the owner LIKED: the structure from above. Keep this look.
  - `refs/owner_frame_ingame.png` a real screenshot of the frame in the game (Roblox graphics): the real parts and colours
  - `refs/ingame_look.png`       the frame in clean Roblox game graphics (for the one image that asks for that look)
  - `refs/ref_plan.png`, `refs/ref_section.png`  the new plan and side view, drawn to scale (present for some jobs)
  - `refs/doll.png`, `refs/doll_ingame.png`, `refs/doll_counting.png`  the level's entity, "the Counter"
  - `refs/style_map.png`         the approved illustrated-map style
- `raw/`    save every generation as `<name>_raw.png` (a rejected try as `<name>_try2_raw.png`)
- `final/`  save the accepted image as `<name>.png`, exactly 1920 x 1080: aspect kept, centre crop, never stretched.

## What the level is now
A co-op hide-and-seek horror level. The WHOLE level is ONE gigantic soft-play frame: the multi-storey climbing
structure of padded posts, black safety-net fences, coloured mat decks, crawl tubes and slides that the owner
liked in the three "liked" pictures. There is NOTHING else: no reception, no snack bar, no party rooms, no
inflatables, no arcade, no ball pit, no open hall floor round the structure. A round warehouse hall, 155 metres
across with its steel roof 42 metres up, is filled wall to wall with the frame.

- THE COURT. In the exact centre is a round open court 22 metres across: blue-and-green checker foam floor, a
  yellow ring painted on it, and a short red padded post standing in the middle under the brightest light. The
  post is what the players must touch. The entity stands beside it.
- THE BOWL. The frame rises round the court like an amphitheatre or colosseum, on every side, 360 degrees:
  six concentric rings of frame, each ring TWO storeys taller than the ring in front of it. 2 storeys at the
  court, then 4, 6, 8, 10 and 12 storeys against the hall wall (a storey is a deck about 2.8 m above the last).
  The top of each ring is a netted terrace with a padded rail, 11 m deep, so the terraces step up and away from
  the court like giant stadium steps, and from the front edge of every terrace you look DOWN on the post. Soft
  foam stair aisles climb the terraces like stadium aisles. Tube slides run down over the steps. Under the
  terraces the rings are solid frame: decks, net corridors, crawl tubes.
- THE WAY IN. Players arrive in a small low padded tunnel through the hall wall ("a hole in the wall"). At the
  tunnel's inner end is a gateway: two padded posts and a padded blue lintel with the worn painted words
  PLAY ZONE in red, yellow, green and blue letters (exactly as in refs/liked_gate.png). Beyond the gate one
  straight lane of checker floor between net fences runs through the frame to the court, a canyon whose walls
  are twelve storeys high at the gate and step down to two storeys at the court.
- THE ENTITY, "the Counter": a porcelain ball-jointed doll child in a party hat, striped shirt and dungarees,
  2.3 m tall (a head taller than a grown man). Exactly as in the doll references. Only in images that ask for it.

## Look, for every photoreal image
Photoreal concept art in the look of the three "liked" pictures: wide lens, dim, dusty, abandoned, quiet. Lit by
sparse cold-white fluorescent strip fixtures far overhead, several dead: pools of light, long shadow, light haze.
Slightly brighter and more saturated than a real derelict building so the colours still read. Materials exactly
as in the references: blue-and-green checkerboard foam puzzle-mat floor, worn; steel posts wrapped in yellow,
red, blue and green vinyl padding; black knotted safety netting between the posts; coloured vinyl mat decks;
square red panels with a round clear bubble window; glossy moulded plastic tube slides, each ONE solid bright
colour (red, yellow, green, blue or orange; never striped); a few loose plastic balls on the floor; exposed
steel-deck roof with trusses and ducts. No people, no children, no animals. No entity unless the image asks for
it. No arcade machines, no neon, no inflatables, no ball pit, no watermark, no HUD, no UI. No lettering except
the sign text an image names; regenerate if lettering is garbled.

## How to work
For each image: write the full prompt, generate, LOOK at the result and check it against the image's own
description and this list: the frame is everywhere (no bare hall floor round it, no other attractions), the
terraces step up AWAY from the court, the heights are right, no striped slides, no garbled text, no people.
One retry if it fails; keep the better one. Export to `final/`. At the end write `prompts_<job>.json` in the
concept folder: per image the final prompt, the references passed and one honest line on what is still off.
Reply with a short list of the files and their weaknesses.
