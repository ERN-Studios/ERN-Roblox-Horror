# Trello — komplet kortoversigt, 21. september 2026

Alle 131 kort og alle checklists er læst. Listen bevarer arkiverede og Done-kort som historik. Et Done-kort er ikke i sig selv et nyt runtime-bevis. Status og arbejdsfase nedenfor er auditens fortolkning; Trello er ikke ændret.

Fasehenvisninger peger på `G:/Roblox/MongoTV/docs/CLAUDE_PROMPT_2026-09-21.md`. Rå beskrivelser/kommentarer findes i `trello-board-snapshot.json`; alle checklists i `trello-checklists.json`. Level 4 er også udskrevet i `LEVEL4_DESIGN.md`.

## To Do (23)

| Kort | Vurdering / næste arbejde |
|---|---|
| [Remove "Access ready 4 queues max 6 each from the level screens in the lobby"](https://trello.com/c/a2jXXL76) | ARKIVERET — bevares som historik. |
| [test](https://trello.com/c/Xwe1aiYI) | ARKIVERET — bevares som historik. |
| [test](https://trello.com/c/NSX2YrHm) | ARKIVERET — bevares som historik. |
| [Alert developers when an in-game purchase is completed](https://trello.com/c/XuxYAtTA) | UDSKUDT — Discord/købsnotifikationer; ingen webhook eller besked. |
| [New entity idea for level 3: Mutated clown.](https://trello.com/c/6JjIbpg6) | ARKIVERET — bevares som historik. |
| [Add entity sounds for level 2: Wait for sound IDs](https://trello.com/c/oHGyjAm4) | ARKIVERET — bevares som historik. |
| [When spectating a player, the player being watched should see a small spectator counter showing how many people are currently spectating them. It should only show the number, not the spectators’ names.  Spectators should also hear the exact same sounds as the alive player they are watching. For example, the walking sound currently plays the default Roblox sound for spectators, while the alive player hears our custom walking sound. The spectator should hear the exact same custom sound.  This should apply to all relevant sounds, so the spectator’s audio matches what the player they are watching is hearing as closely as possible.](https://trello.com/c/UDf4pzNZ) | ARKIVERET — bevares som historik. |
| [Make a temporay 14 days sales on every purchase, make it 50% on everything. Disregard this until 20. October.](https://trello.com/c/GxhsmCC5) | UDSKUDT — ignorér udsalg frem til 20. oktober; ingen scheduling/prisændring. |
| [New store upgrade: Token Earner Multiplier: 2x, 3x, and 5x. Each different pricepoints of course.   When purchased, the multiplier also applies instantly to the player's current token balance which is also informed.](https://trello.com/c/EtdsUM4e) | D3 — tokenøkonomi; pris, tokenkilder og upgrade/stacking kræver ejerbeslutning. |
| [P1 · Shop: prøv udstyr og forstå hvert køb før betaling](https://trello.com/c/UNRk7Qy8) | B1/B2/D1 — DELVIST LEVERET; bevar tre demoer, tilføj måling og senere kamera-demo. |
| [P1 · Entity-regler: lær spilleren at overleve før første straf](https://trello.com/c/us5TWr9O) | B3/C4 — lær entity-regler med tilgivende første møde og korrekt dødsforklaring. |
| [P2 · Nye hazmat- og udstyrsskins med 3D-preview](https://trello.com/c/VSCGGIA9) | C2 — kosmetiske hazmat-skins, persistens/preview; art til Codex, nye priser ubesluttede. |
| [P2 · Entity-arkiv: udbyg Field Notes med progression og belønninger](https://trello.com/c/nWCCdowB) | C1 — udbyg eksisterende Field Notes; bevar gamle data/titel og once-only rewards. |
| [P2 · Level-variation: skift spor og opgaver mellem gennemspilninger](https://trello.com/c/OBjSW30k) | C3/C4 — kontrolleret fælles variation; genbrug generator og bevar solo-reachability. |
| [P3 · Research Camera: gratis foto-opgaver og Advanced Camera](https://trello.com/c/cqvNQIIc) | D1 — gratis basiskamera efter research/arkiv; Advanced Camera-pris kun forslag. |
| [P3 · Frivillige udfordringer efter gennemførsel](https://trello.com/c/FnF49TWk) | D2 — personlige rekorder med sammenlignelige regler og once-only rewards. |
| [Level 4](https://trello.com/c/Y2xXThBN) | C4 — fuld 10-punkts-tjekliste; blokmodel → prototype → gameplay → Codex-polish. |
| [Clarify shop range wording and fix misleading pressure plate instructions](https://trello.com/c/xQWVkwhw) | B1 — konkrete nuværende shoptekster og usynlig plate-trigger. |
| [Level 2 · Pool Slide: ret chase-lag, nye Blender-animationer og større model](https://trello.com/c/rXhi1SZ8) | A1 — chase-lag + nye Blender-walk/run + større aktuelle rig; ikke kun refresh-tuning. |
| [Investigate render distance and nearby loading to reduce lag](https://trello.com/c/Zpj0Gkbb) | A4 — mål separat klient/server og beskyt eksisterende streaming-readiness. |
| [Level 2 · Pool Slide: fjerne groans før spawn og mundlyde under chase](https://trello.com/c/LigItMHi) | A2 — eksisterende groans, koordineret ambience/mund-state, korrekt despawn/streaming. |
| [Level 2 · Pool Foam: undgå overlap og hold afstand mellem entities](https://trello.com/c/jecT8s86) | A3 — reelt ingen modeloverlap, lokal separation og smalle passager. |
| [Level 3 · Fast første CD og synlig CD-reader med rumindikator](https://trello.com/c/6BVH4WmN) | A5 — første CD fast i reelt første rum, fire random, reader øverst til højre. |

## In Progress (0)

Ingen kort.

## Testing (2)

| Kort | Vurdering / næste arbejde |
|---|---|
| [Controller: tre HUD-handlinger uden gamepad-sti, sprint-lås og terminal-luk](https://trello.com/c/uI8hg2At) | UDSKUDT — ejer 15/9; console/controller hardware-QA ikke bestået. |
| [Robusthed: spillere kan strande bag loading-dækket (to tilfælde)](https://trello.com/c/DIktjy8U) | SKIPPED — ejer 16/9; kendt implementering bevares, live 2–6-player acceptance ikke udført. |

## Done (99)

| Kort | Vurdering / næste arbejde |
|---|---|
| [Replace the old shop with a much larger floating hologram shop and automatic interaction](https://trello.com/c/IA6VOViX) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Give Daily Rewards a standalone UI and its own side button](https://trello.com/c/EnbSc9ak) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Rework Lucky Wheel into an actual wheel with a dedicated side button](https://trello.com/c/rZC8cJHy) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Restrict Developer tag and dev cheats to LaverSneglen and Mikkelczar](https://trello.com/c/036tYqti) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Allow switching between Continue and Return to Lobby](https://trello.com/c/rLDqjpE4) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Redesign Shop and Upgrades as square buttons with two-color imagegen icons](https://trello.com/c/Nn65pxPk) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 2: Pool Slide monster appears unable to kill players](https://trello.com/c/UmtTK3MA) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Prevent players from entering the circle when a lobby is full](https://trello.com/c/u0rLQTOe) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 3: Lengthen the slide and stagger spawns higher up](https://trello.com/c/iuP2GkZL) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Simplify Stamina Capacity upgrade text](https://trello.com/c/pCSeWVcQ) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Drop carried fuses and CDs on death for easy pickup](https://trello.com/c/IpCKlAsz) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Fix forced upward camera movement after loading in](https://trello.com/c/pzVtej6w) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Rework Upgrades and Shop logos — require 10/10 critic review before release](https://trello.com/c/PkEUQQ74) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Lobby: The ceiling lights should make like cool sweep patern at random. Make 5 different cool ones.](https://trello.com/c/lXtjnc8N) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 1: Exit door reader/pointer should be an arrow instead of a triangle. Give it a circle, so its like a compass.](https://trello.com/c/tnnPzDyn) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Lobby: Move the floating intro back on top of the gate](https://trello.com/c/hhRhOMX5) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Restore the old end-of-level UI with auto-continue and visible player choices](https://trello.com/c/zlI8Rmto) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 1: Make chase audio directional and fade with distance](https://trello.com/c/2GlQSXUc) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Rename Protect charges and move them under Upgrades](https://trello.com/c/qFCuCf3w) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Fix players spawning on top of each other in levels](https://trello.com/c/bwMzNaSs) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Lobby: Add a music toggle button](https://trello.com/c/DEmpCU8O) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Award 2 tokens for completing a level](https://trello.com/c/ne5X0bYj) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Create icons for Upgrades, Gear, and Shop](https://trello.com/c/WJLErpHx) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Give players a short introduction to the studio. That we are only 2 DEVS and we are working on any bugs, and appreciate any feedback.](https://trello.com/c/kQ4GNLUU) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Redo the logos for the developer items and passes.](https://trello.com/c/RynrscFW) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Add a token-purchasable item with 5 seconds of invisibility and death protection](https://trello.com/c/ak8Mgaeq) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Add a Developer name tag for devs](https://trello.com/c/ZAlinXFV) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 2: Increase tunnel height to allow a larger pool slide entity](https://trello.com/c/KcUdv690) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Automatically dismiss the Round Loading Failed message](https://trello.com/c/ON6ZsrFJ) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Lobby: Fix overlapping textures on the level selector doorframe](https://trello.com/c/xDmiuTCx) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Review shop prices against the market](https://trello.com/c/KBDJouxI) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Explore percentage discounts for shop items and a possible ad campaign](https://trello.com/c/3wDozWJa) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Brainstorm additional shop items](https://trello.com/c/n7uSFoMX) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Unfinished levels: Show Coming soon, work in progress, and a percentage bar](https://trello.com/c/AzpxrZMR) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Lobby: Add a direct shop button below the Equipment button](https://trello.com/c/7FXZy8ae) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Lobby: Make the Zyntra Equipment button much bigger and rename it](https://trello.com/c/IS3zOeKP) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [weird bar at the entry of levels](https://trello.com/c/mirOf8aF) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 3: Fix the slide entry](https://trello.com/c/psRtwdjR) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 3: Make the map more square](https://trello.com/c/k6e4BnS1) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 3: Escaping does not require a button press](https://trello.com/c/8hIQpNOw) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Remove the forced flashlight](https://trello.com/c/nS5vj1RM) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 2: Fix spawning into the level from the lobby](https://trello.com/c/DOIafNTw) | ARKIVERET — bevares som historik. |
| [Level 3: Make it clear that spawn is not the exit](https://trello.com/c/el9lI94F) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Add in-game voice chat (VC)](https://trello.com/c/echzcDhm) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Remember to gift the player that gave us feedback in discord with the upgrades from advanced equipment package and 10 research tokens.](https://trello.com/c/3FGClSDh) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [We need a "Back to lobby" option when in a level.](https://trello.com/c/FON3SKNO) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Emergency Re-entry: sæt produktet on-sale og beslut vinduets længde](https://trello.com/c/R5tjB30m) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Unlock younger audiences: fix publishing warning + reach 250 qualifying players](https://trello.com/c/iMTZhXMy) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 2 - Entity not spawning](https://trello.com/c/GdkBpbkc) | ARKIVERET — bevares som historik. |
| [Opret 4 Roblox-badges (ikoner + id'er) til Backrooms](https://trello.com/c/sHKVULaS) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Line needs to be removed, and made level text bigger](https://trello.com/c/2GPXBNC4) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [test1](https://trello.com/c/D77iBxrZ) | ARKIVERET — bevares som historik. |
| [Level 3 maze generator needs to be fixed, not one big rectangle](https://trello.com/c/XwFEH1Tp) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [A CAT IN THE LOBBY PLEASE](https://trello.com/c/fdl6NB0b) | ARKIVERET — bevares som historik. |
| [Remove "Access ready 4 queues max 6 each from the level screens in the lobby"](https://trello.com/c/3zK75F0g) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 1 entity scripts run in the lobby, level 1 entity is also loaded in the lobby](https://trello.com/c/Ku6YeWJz) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Make the Level 2 pool noodle entity accelerate and chase](https://trello.com/c/5VpRo6A8) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Fix running turning itself off in the lobby](https://trello.com/c/WC1ZQRyH) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Allow the flashlight while hiding under a table](https://trello.com/c/rrZu4S20) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Remove Zyntra Supporter from levels](https://trello.com/c/0XurRnWf) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Research more items players can buy with tokens](https://trello.com/c/O0h3ag8I) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Dev cheats: Add ESP for all players](https://trello.com/c/53c4MFE5) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Dev cheats: Add free respawn for developers](https://trello.com/c/bwyxIUz1) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Correction to (Lobby: The ceiling lights should make like cool sweep patern at random. Make 5 different cool ones. ) The pattern should be turning the lights on and off in a pattern.](https://trello.com/c/j2JrjfkG) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Roblox Analytics for the last 28 days shows: - Phone: 47.7% — 1,874 player-days - PC/computer: 32.3% — 1,269 player-days - Tablet: 20.0% — 788 player-days - Console/VR: no recorded activity So 67.7% of the audience plays on touch devices. Phone is the largest platform, but PC is still a substantial third. Therefore a full and x optimization for mobile and tablet view is essential. For example the shop and upgrades tab are to big on the phone, the tabs can stay the same size, but the contents have to be shrunk. ](https://trello.com/c/0xPyX762) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [When a player joins the game for the first time, there should be an arrow or a guiding line leading from the player to the entrance of Level 1, so they know exactly where to go to start the game. This guide should only appear on their first login and should not be shown again afterward.](https://trello.com/c/69agyLbr) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [When spectating a player, the player being watched should see a small spectator counter showing how many people are currently spectating them. It should only show the number, not the spectators’ names.  Spectators should also hear the exact same sounds as the alive player they are watching. For example, the walking sound currently plays the default Roblox sound for spectators, while the alive player hears our custom walking sound. The spectator should hear the exact same custom sound.  This should apply to all relevant sounds, so the spectator’s audio matches what the player they are watching is hearing as closely as possible. Also the UIs, so when for example a exit arrow is showing or just any UI the specated player can see. But when spectating a DEV the specators should not be able to see ESP when toggled on ](https://trello.com/c/J67RPeIy) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Donation leaderboard: Include all in-game purchases](https://trello.com/c/gTgtoztS) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 3 entity spawns at the start of the level when you have completed the level and start running down the long hall, before the exit.](https://trello.com/c/jhwiqOIL) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Show a physical barrier around the level-entry circle when the party is full](https://trello.com/c/tqcZqFqk) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Pool Foam er lydløs: lav lyde og monter en looping emitter på hver entity](https://trello.com/c/24sCzSO6) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Rehink the "Top Supporter" sign. Center and enlarge the text.](https://trello.com/c/ErO9MCnP) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Fix the hide under the table avatar animation in level 3.](https://trello.com/c/fLcenSjE) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 1: Make the instructions much clearer and more accessible. Display a text prompt to the entire team whenever a player picks up a fuse, powers a fuse box, or pulls a lever. Each prompt should clearly state who performed the action, what they did, and what the team needs to do next, while matching the game’s existing UI design.  For example, if more fuse boxes still need to be powered, clearly tell the team how many remain. This should apply throughout the entire level so players always understand their current objective and next step.  Also, make the cables show a subtle but clearly visible electrical current flowing toward the fuse box. Once the fuse box is powered, the current should reverse direction and flow toward the lever, visually guiding players to where they need to go next. At the same time, display a prompt instructing the team to follow the current and pull the lever.](https://trello.com/c/IgTt0K3h) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Show a dev-only free respawn option in the respawn purchase prompt](https://trello.com/c/VCIk4Sli) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Add progressive playtime rewards, starting after 5 minutes](https://trello.com/c/NP80aPPC) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Add a daily lucky wheel for tokens and other rewards](https://trello.com/c/4DOb30AO) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Explore more token-purchasable items, including a Speed Boost Potion](https://trello.com/c/cmsPkLhK) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Fix pathfinding for the pool mouth entity in level 2, its stops up.](https://trello.com/c/Mlicft6v) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Create more purchasable, high-quality items for the shop, and make sure every item actually works correctly after purchase.  Rethink the entire shop experience. Instead of a basic shop, create an actual **SHOP area built into the wall**, with a large **SHOP** sign using Zyntra’s neon colors. It should feel extremely inviting and immediately make players curious enough to walk over and explore it.  For the physical shop, experiment with something like **pressure-plate purchase displays**. Each purchasable item could have its own display or pedestal, with a box or representation of the item hovering above it. Make the products visually exciting and obvious to interact with. Use image generation to create custom textures/assets for the purchasable items so they feel native to Zyntra rather than like generic placeholders.  Also redesign the **SHOP UI icon** to increase visibility and clicks. Give it a strong circular border treatment, potentially with a subtle animated/glowing/pulsing effect around the edge using Zyntra’s visual identity. It should attract attention without becoming annoying.  Overall, treat the shop as a major part of the game rather than just another UI menu. The goal is to make players **notice it → become curious → interact with the products → understand what they are buying → actually want to purchase them**.](https://trello.com/c/Tv8xvUGO) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Add Daily Rewards as a tab, just like Shop and Upgrades, but make it bouge.](https://trello.com/c/c2YZJk60) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Make all lobby colors more saturated.](https://trello.com/c/oB8Lqsln) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Donation leaderboard: Remove historical-purchase footer and align columns](https://trello.com/c/ypGhJj76) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Unify in-game UI using Objectives and Mission Brief as the style reference](https://trello.com/c/UwFJOWZH) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Speed potion needs to give 30% speed boost.](https://trello.com/c/a85w9YZj) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Rework Entity Shield Charges UI to match the Objective UI](https://trello.com/c/W61O37go) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Codex: Create a table-hiding animation in Blender via MCP](https://trello.com/c/FXH0ddhN) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Research and redesign the shop to be much larger](https://trello.com/c/32xgCdtM) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Make a nice sign with saturated colors, but still fits the Zyntra neon colors that says supplies and upgrades over the purchasable items in the lobby.](https://trello.com/c/LswEFLHq) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [When players either use or buys a re-entry they should spawn the exact same place where they died, but they have a 10 seconds grace period which stated as "you are invisible to monsters (10 seconds timer)](https://trello.com/c/Ejo5OPkG) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 3 · Mall Manager må ikke skubbe skjulte spillere ud](https://trello.com/c/DYnBEZHk) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [The exit door indicator for level 1 should be placed in the top right cornor.](https://trello.com/c/w07K0m5E) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [When a player in every levels completes a step, like in level 1, finding a fuse, powering fuse box, pulls lever. This should be stated as message on screen for everybody which should be visible and with the username for the person who did that certain thing. This is for all levels.](https://trello.com/c/FAgRQho1) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [When a player completes Level 2 and clicks “Continue” to load into Level 3, they can sometimes clip through the slide, fall out of the map, and die from fall damage.  Please fix this so players cannot clip or fall out of the slide during the transition into Level 3.  Also, increase the thickness of the tube’s outer walls by 50% to make sure players cannot fall or clip through them.](https://trello.com/c/xIjizflN) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [P1 · Advanced Equipment: tilføj fokuseret lygte og tydelig produktværdi](https://trello.com/c/n1yx5OdQ) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [P2 · Expedition Pack: re-entry, Entity Shield og Route Markers](https://trello.com/c/eigEDZAH) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [Level 1: halve objectives, permanent lever pulls og lokalt spotting-skrig](https://trello.com/c/DR1Isx73) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [P1 · Zyntra Entity Detector: kort fare-scanning](https://trello.com/c/Zyrtgu79) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |
| [P1 · Research-opgaver: daglige mål og frivillige fund i levels](https://trello.com/c/wEFTmguQ) | DONE — bevar eksisterende løsning; genåbn kun ved konkret ny regression. |

## Ideas (0)

Ingen kort.

## Before big adsspend (7)

| Kort | Vurdering / næste arbejde |
|---|---|
| [P1 · Før større ads: mål frafald fra join til første genstart](https://trello.com/c/bIFdNWUf) | B2 — analytics-kode + reelle data/kohorter; ingen automatisk adudgift. |
| [P1 · Før større ads: kortere og tydeligere vej fra lobby til gameplay](https://trello.com/c/EYIT99eM) | B3 — mål lobby→gameplay og genbrug eksisterende førstegangs-guide. |
| [P1 · Før større ads: stærk første oplevelse og tidlig succes](https://trello.com/c/2fiHi4q4) | B3 — observer ny spiller/early success; ingen opdigtet retention-effekt. |
| [P1 · Før større ads: forståelig første død og nemt nyt forsøg](https://trello.com/c/PR0ersiy) | B3 — korrekt første dødsforklaring og almindeligt retry; eksisterende exit-flow. |
| [P1 · Før større ads: verificér mobil og tablet i rigtige runder](https://trello.com/c/lUKD3R8G) | B4/A4 — fysisk telefon/tablet/svag enhed kræver reelle runtime-tests. |
| [P2 · Før større ads: match annonce og thumbnail med første gameplay](https://trello.com/c/kydyBl7u) | B4 — gameplay-evidens til Codex-annoncepolish; ingen kampagnestart/budgetændring. |
| [P1 · Før større ads: test hele solooplevelsen og spil igen med venner](https://trello.com/c/V7m3zDSa) | B4 — fuld solosession og to venner med nyt forsøg; afventer reelle tests. |
