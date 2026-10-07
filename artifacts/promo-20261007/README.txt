BACKROOMS: STAY QUIET [CO-OP HORROR] - PROMO PICTURES, 2026-10-07
43 pictures: 12 for the gallery, 6 thumbnails, 25 for an ad campaign.

HOW THEY WERE MADE
1. Claude went into all six levels in Studio (full graphics quality) and took 42 pictures: every level's
   look, the player's suit front and back, and each entity up close. They are in "In-game references".
   What each level is and how it is cleared is in "ANALYSIS - the six levels.txt".
2. Claude wrote one brief per picture from those references and Codex (gpt-6-astra, the fast tier, its
   built-in image tool, seven jobs side by side) made the pictures WITHOUT any lettering.
   68 generations, 43 kept, 25 retries.
3. Claude checked every picture against the references, then cropped them to exact size and set all the
   lettering in one typeface (DIN Condensed), so nothing is misspelled and LEVEL 3 looks the same everywhere.
Every picture exists twice: with lettering, and in "clean (no lettering)".

WHAT IS IN THE FOLDER
1 Gallery (1920x1080)        12 pictures, two per level, with a small "LEVEL n | THE PLACE" in the corner
2 Thumbnails (1920x1080)      6 pictures with the title
3 Ad campaign                25 pictures, each with a line and the game's name
     landscape 1920x1080      9   (YouTube, Discord, X, in-feed)
     square 1080x1080         8   (Instagram, Facebook, Discord)
     vertical 1080x1920       8   (TikTok, Reels, Shorts, Stories)
contact sheets               everything at a glance, and the thumbnails at the store's 320 x 180
In-game references           the 42 pictures from the playtest
ANALYSIS - the six levels    look, entity and how to clear each level
prompts.json                 the brief, the references and Codex's own note on what is still off, per picture

WHAT I WOULD USE
Main thumbnail    T01_hero_office_hide: two teammates hiding, the Entity in the light, the yellow rooms.
                  It is what the genre research said to lead with and it reads at 320 x 180.
Second            T02_hero_six_levels: the only picture that says "six different places" in one look.
Rotate / test     T04 (the finger to the mask), T03 (the Counter), T05 (the Usher), T06 (the Mall Manager).
Gallery order     T01, T02, G03, G05, G08, G09, G11, G02, G04, G12 (Roblox takes ten).
Strongest ads     A09 THEY ARE ALL LISTENING (all four hunters), A12 SHHH, A03 DON'T. MOVE.,
                  A11 READY OR NOT, A20 A THOUSAND DOORS, A25 SIX LEVELS. ONE RULE.

READ THIS BEFORE PUBLISHING: LEVEL 2
Every Level 2 picture shows the NEW map (the sunlit bath-house, no entity). In the game today that map is a
developer preview behind a pedestal; the public Level 2 queue still starts the old poolrooms round.
G03, G04, A02, A08, A16 and A20 should go out when the new map is what players get.
The six-level pictures (T02, A25) show the new Level 2 as well.

WHAT IS NOT EXACTLY THE GAME (honest list)
- These are generated promotional pictures built on real screenshots, not screenshots.
- THE MALL MANAGER IS SHOWN WITH THE LIGHTS ON. In the game it only comes with the blackout. It is lit in
  G05, G06, T06, A03, A13, A17 and A23 so that it can be seen.
- THE USHER "only exists in the dark". T05, A14 and A22 show it in the neon-lit corridor. G08 and A04
  (dark hall, torch beam, red emergency light) are the faithful ones.
- Neither of those two was seen hunting on this run (the Manager needs the blackout, the Usher needs the
  power on). Their looks come from the game's own models, photographed in the level.
- The players come out a little taller and more detailed than the in-game figure in some pictures, and in
  A06 and A24 the gloves have separate fingers where the game has mittens.
- T03: the Counter's eye shadows are heavier than in the game. A09: its face is a little more expressive.
- A18: the player walks toward the counting Counter; in the game you would be hiding at that moment.
- A08: the whole rotunda is drawn flooded, with the deck chair in the water. In the game the pool is a round
  basin with a dry deck round it, and the chair stands on the deck.
- G01: the Entity is turned a little toward the camera, not in strict profile.
- The Level 4 pictures with the power on (G07, T05, A22) lean on the in-game references of 2026-10-04;
  on this run the round was only seen in its power-off state.
- Levels 2 and 5 have no entity and none is drawn. No picture shows gore, weapons or UI.

SIZES
Checked by the finishing tool: every file is exactly the size its folder says, cropped from the centre,
never stretched. The generations are 1536 x 1024 (landscape), 1024 x 1024 and 1024 x 1536, so the 1920 x 1080
and 1080 x 1920 files are enlargements of about 25 percent. They hold up at screen sizes; they are not for print.

TO CHANGE A LINE OR REBUILD
The sources are in the repo: artifacts/promo-20261007 (references, briefs, every generation) and
tools/promo (make_briefs.py holds every picture's text and tagline, finish.py crops and sets the lettering).
Change a tagline in make_briefs.py, run both, and the folder is rebuilt in under a minute.
