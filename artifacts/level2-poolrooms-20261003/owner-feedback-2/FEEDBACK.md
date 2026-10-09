# Owner feedback on the published Poolrooms Level 2 preview (2026-10-03, after v2610)

Screenshots are the owner's own, taken in Roblox (Studio play of the dev preview). Files `1.png` .. `14.png` here.

## Verbatim (Danish)

> Okay, så der er mange fixes til level 2. Kig på mine billeder grundigt, jeg kommer til at skrive om dem.
> Der er mange steder hvor at en edge, eller sådan en smooth edge vender den forkerte vej, og så hjørner de har
> bare en smooth edge, men den har ikke resten af walkway eller lign til at gå med ind i hjørnet.
> Nogen tuneller har bare nogle hvide spots, og så en ring i en anden farve tile.
> Ret mange steder så ser det bare halv færdigt ud.
> Mange steder så går vandet ikke helt ud til kanten af rummet.
> Nogen tunneller matcher ikke tile farve til rummet som den er i billede 5 viser det godt.
> Sky lights har en stor fed blok, det skal det ikke være, meget mere seamless med loftet.
> Samt trapper op til loftet i nogen huller skal ikke gå helt op, man kan næsten hoppe ud af mappet.
> Så skal der ikke være så mange af dem, det er lidt overused.
> Nogen rum må gerne være swervy, der er et rum som bare har en swervy væg midt i det hele, som man kan gå rundt
> om. Hele rummet må gerne være swervy.
> Nogen steder er der bare en firkant der er hvid som sidder på væggen.
> Trapperne op til exit, skal fuldstændig laves om. de hakker når man går op af dem, og så gilænderet ude til
> siden, det er 0.1 mm tyk, og det svæver lidt væk fra trappen., pælen i midten af trappen kan man bare se ned
> igennem fra toppen.
> Der er ret mange kollissions som bare slet ikke er der, så man går bare igennem ting.
> Exit tube, ja, den er halvt inde i væggen, og har en stor åbning, og usynlig kollission med ingenting, og er
> halv gennemsnigtig.
> Samt nogen skylights er et firkantet hul med en tynd cirkel inde i.
> Du skal fikse alt det her, og så teste ALLE steder hvor at det her kan ske, og så sørge for det ikke sker, så
> det er flawless. Når det er lavet, så sender du billeder af det her i chatten, og får det ind i roblox, og
> committer og publisher.

## In English, as a numbered list

- F1 Smooth edges (coves / rounded edge pieces) face the WRONG WAY in many places (a convex bullnose where a
  concave cove belongs, or the reverse).
- F2 Corners have a smooth vertical corner piece, but the walkway / ledge / cove along the walls does NOT continue
  into the corner: runs stop short and leave the corner unfinished.
- F3 Some tunnels have white spots (patches) and a ring in a different tile colour.
- F4 Many places look half-finished.
- F5 In many places the water does not reach the edge of the room (dry pool floor shows between water and wall).
- F6 Some tunnels do not match the tile colour of the room they open into (image 5: collar/portal lighter than the
  hall wall).
- F7 Skylights hang a big fat block under the ceiling; they must be seamless with the ceiling.
- F8 Stairs up to holes in the ceiling go all the way up: you can almost jump out of the map. And there are too
  many of them (overused).
- F9 Rooms may be swervy. Today one room has a single swervy wall standing in the middle that you walk around;
  instead the WHOLE ROOM may be swervy (curved room walls).
- F10 Some places have a plain white square (frame) stuck on the wall.
- F11 The stairs up to the exit must be completely redone: walking up them is jerky (steps hitch), the railing
  is paper thin (~0.1) and floats away from the stairs, and you can look down through the central pole from the
  top (hollow column).
- F12 Many collisions are simply missing: you walk through things.
- F13 Exit tube: half inside the wall, has a big opening, invisible collision with nothing (collision where nothing
  is visible), and it is semi-transparent.
- F14 Some skylights are a square hole with a thin circle inside.
- F15 Fix everything, then TEST EVERY PLACE where each of these can happen and make sure it cannot happen:
  flawless. Then send pictures, put it into Roblox, commit and publish.

## Image index (what each shows)
1. Wall foot next to a walkway: a long rounded "cove" piece lies on the floor against the wall with its round
   side bulging OUT (convex bullnose, wrong way); it ends in a flat cut end; a small gap under it at the wall. (F1)
2. Narrow pipe, aqua floor: a white square patch on the floor (worn overlay), partial rings (ribs) in a darker
   tile colour that stop at the floor. (F3)
3. Small room / chamber corner: water stops short of the walls (dry blue tiled floor strip visible), the white
   cove along the wall foot, the vertical corner cove, the ceiling cove; at the left a walkway/ledge ends with a
   rounded end before the corner. (F2, F5, F1)
4. Pool edge: water stops before the walkway/wall leaving dry tiles; the walkway deck is a plain box that ends
   short; a small rounded curb sits on it; the cove into the wall corner is cut off. (F2, F4, F5)
5. Tunnel mouth in a hall wall: the collar rectangle around the round opening is a LIGHTER tile colour than the
   wall; the walkway curbs left and right stop at the collar. (F6, F2)
6. Ceiling: a light well is a thick rectangular block hanging below the ceiling with a round hole in it. (F7)
7. Curved channel hall: a free-standing curved partition wall in the middle of the pool. (F9)
8. A white rectangular frame (wall void) on a wall: looks like an unfinished square. (F10)
9. Seen from ABOVE the roof: a spiral stair well whose centre column rises to the top of the round ceiling hole;
   the stairs reach right up to the opening. (F8)
10. Exit spiral stairs: wedge steps with jagged edges and a thin railing standing off the steps. (F11)
11. Looking down the exit stair's centre pole from the top: it is hollow, you see the water below. (F11)
12-13. Exit hall: a green, semi-transparent curved tube segment half inside the big round wall, the flume
   portal frame with open sky behind it. (F13)
14. Ceiling seen from below: a SQUARE hole to the sky with a thin round ring hanging inside it. (F14)
