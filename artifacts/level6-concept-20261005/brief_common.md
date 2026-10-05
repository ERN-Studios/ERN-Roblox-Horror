# Level 6 concept images, 2026-10-05

You generate concept images with your BUILT-IN image generation tool (not Meshy, not any MCP). Do not run git,
do not touch Roblox Studio, do not edit any file outside `artifacts/level6-concept-20261005/`.

Folder (all paths relative to the repo root): `artifacts/level6-concept-20261005/`
- `refs/` reference images (the tool accepts at most five per image; pass the ones named for each image)
  - `refs/style_frame.png`   the approved look of the play frame (photoreal, dim warehouse) - the STYLE to keep
  - `refs/sheet_ingame.jpg`  four real screenshots of the level in the game today - the real colours and parts
  - `refs/ref_plan.png`      the new floor plan, drawn to scale - the LAYOUT to follow
  - `refs/ref_height.png`    the new heights from the side - the SCALE to follow
  - `refs/style_ball.png`    the approved look of the ball pit zone
  - `refs/style_map.png`     the approved illustrated map of the OLD layout - the style of the map picture
  - `refs/doll.png`, `refs/doll_ingame.png`  the level's entity, "the Counter" (only where an image asks for it)
- `raw/`    save every generation here as `<name>_raw.png` (keep rejected tries as `<name>_try2_raw.png`)
- `final/`  save the accepted image here as `<name>.png`, exactly 1920 x 1080: scale with the aspect kept and
  crop the centre (sips or ffmpeg), never stretch.

## What the level is
An abandoned 1990s indoor soft-play centre inside an enormous warehouse, the "Backrooms" kind of empty: nobody
there, dim, dusty, quiet. A co-op hide-and-seek horror level; players hide inside the play frame.

## What the new draft changes (this is what the pictures must show)
1. The hall is twice the floor and the roof is far higher: about 34 metres (the old one was 13). It must feel
   cathedral-high, the roof almost lost in the dark.
2. THE BIG FRAME, the multi-storey soft-play climbing structure of padded posts, net fences, mat decks, tubes and
   slides, is now nearly HALF of the whole hall and SIX storeys high everywhere (one storey = a deck about 2.8 m
   above the last), SEVEN in "Tube Town" and TEN in "the Tower". It is the size of a city block. Its slides are
   correspondingly long: tubes that drop six, seven and ten storeys.
3. The arcade is REMOVED. No arcade cabinets, no claw machines, no prize shelves, no neon anywhere.
4. Home Base (a yellow circle on the floor with a short red padded post in the middle) is a round court INSIDE
   the frame, open to the roof, with the frame rising on every side like an arena.
5. The ball pit ("Ball Ocean") is sunk INSIDE the frame with net bridges crossing above it. It is ALMOST EMPTY:
   a bare blue padded pit floor with only a few dozen loose plastic balls. Never draw a pit full of balls.

## Look, for every photoreal image
Photoreal concept art, wide lens, eye height unless stated. Lit only by sparse cold-white fluorescent strip
fixtures hanging far overhead, several dead, so there are pools of light and long stretches of shadow, with a
light haze. Slightly brighter and more saturated than a real derelict building: the colours must still read.
Materials exactly as in the references: blue-and-green checkerboard foam puzzle-mat floor, worn, a few tiles
missing over grey concrete; steel posts wrapped in yellow, red, blue and green vinyl padding; black knotted
safety netting stretched between the posts as fences and walls; coloured vinyl mat decks; square red panels
with a round clear bubble window; moulded plastic tube slides and open slides, glossy, each ONE solid bright
colour (red, yellow, green or blue; never striped, never black); exposed steel-deck roof with joists and ducts.
Scattered loose plastic balls on the floor. No people, no children, no animals, no entity unless the image asks
for it, no arcade machines, no neon, no watermark, no HUD, no UI. No lettering except the sign text an image
names; if a generation shows garbled lettering, regenerate it.

## How to work
For each image: write the full prompt, generate, LOOK at the result, and check it against this list:
storeys counted (at least six stacked decks visible where the frame is in view), roof very high, no arcade
machines, no full ball pit, no striped slides, no garbled text, no people. One retry if it fails; keep the
better one. Then export to `final/`. At the end write `prompts_<job>.json` in the concept folder: for each image
the final prompt, the references passed, and one honest line on what is still off. Reply with a short list of
the files and their weaknesses.
