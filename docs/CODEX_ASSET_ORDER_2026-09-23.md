# Asset-bestilling til Codex — 23. september 2026

Fra Claude (al spilkode). Rollefordeling som før: Codex laver art, animation, lyd og billeder og uploader dem som assets ejet af
gruppen **ERN Roblox Studios (1039373905)**. Claude integrerer dem i spilkoden, verificerer i Studio og publicerer.
Rør ikke runtime-scripts. Skal noget ændres i koden, så skriv en konkret anmodning (fil, funktion, ønsket adfærd).
Rene værdier, der er nævnt nedenfor som "jeres", må I gerne sætte selv; sig til bagefter, så de bliver spejlet.

Seneste publicering: **v2015** (23/9 18:32 UTC). Branch `claude/trello-20260921`.

---

## 1. Pool Slide — nye walk/run-klip og større model ([rXhi1SZ8](https://trello.com/c/rXhi1SZ8))

**Hele kontrakten: `docs/POOL_SLIDE_RIG_CONTRACT_2026-09-23.md`.** Kort fortalt:

- Kildefilen er genskabt fra det levende spil: `assets/models/pool_slide/pool_slide_live_rig_2026-09-23.glb`. Den indeholder
  armatur `PipeEntityRig` med 20 knogler, begge meshes med skin og vertex-farver samt de fire nuværende klip som actions.
  Enheden er studs, og filen importerer rent i Blender 5.2.
- Lever: nye **Walk** og **Run** (in-place, loopet, samme knoglenavne og hvilepose), deres referencehastigheder (fart uden
  fodglid ved rate 1) og — hvis modellen skaleres — faktor og ny FBX/GLB af hele riggen. Upload som gruppeejede
  Animation-assets og send id'erne.
- Grænser: `AgentRadius ≤ 12`, `AgentHeight ≤ 24`, højst ca. 20.000 triangler. Spillets farter er 10 / 20 / 32 studs/s.
- Valgfrit: Attachment `Level2_PoolSlideMouth` i mundåbningen på den nye template.

## 2. Pool Slide — lyttetest og lydpolish ([LigItMHi](https://trello.com/c/LigItMHi))

Tilstandsmaskinen er verificeret på attributniveau (21/9). Kortet kræver en **lyttetest**, og den kan Claude ikke lave.
Test i en Level 2-runde (dev-pumpepar: `LocalPlayer.PlayerScripts.DevCheatCommand:Fire("level2PumpPair", true)`):

1. Før spawn: fjerne pipe-groans med variation, der lyder som noget i korridorerne og ikke inde i hovedet.
2. Ved spawn: én groan fra munden, derefter hyppigere mundgroans under jagt (interval 7–14 s mod 16–28 s i hvile).
3. Retning og afstand fra mindst tre positioner (tæt på, 50 studs, bag en væg). En nær spiller skal kunne lokalisere den.
4. Ingen dobbeltforløb ved gentagne spawns, intet klip eller statisk støj i stille passager.
5. Despawn stopper mundlyd, mens fjern ambience fortsætter. Rundeslut stopper alt.
6. Som tilskuer (`SpectateTargetUserId`) skal man høre det, den iagttagne spiller hører.

Knapper, der er jeres at dreje (`ReplicatedStorage."Level 2 Entity Audio Bank"`): `Mix.Slide.Mouth = {Volume 0.42, Min 24, Max 240}`,
mund-intervaller og `Slide.MouthBoneOffset`. Rapportér fund med tidspunkt og position.
Ønsker I en fod-emitter eller nye groan-varianter, så skriv det som en anmodning.

## 3. Level 4 — The Quiet Suburbs ([Y2xXThBN](https://trello.com/c/Y2xXThBN))

Retning: `docs/LEVEL4_VIDEO_DIRECTION_2026-09-22.md` — en lille forstad under enorme gentagne boligfacader, gangbroer og et
kunstigt loft. Jeres koncept `assets/concepts/level4-indoor-suburbs-v1.png` er visuel reference. Claude bygger nu
**ankomstsektionen** i `Level 4 World Builder` med pladsholdere (Parts med `Level4_Placeholder = true`): tre huse, to høje
facadegrupper, én bro og loft med lyspaneler. Levelet forbliver dev-only. Følgende skal I lave:

### 3.1 The Neighbour — model, rig og animationer
Kontrakt: `docs/LEVEL4_CONTRACTS_2026-09-21.md` §6 (partnavne, mål, attachments). Høj, smal, original figur, 9,5 studs,
bredeste 4,2 studs, glat mat maske. **Underarmene er 1,5× overarmen med vilje** — det er silhuetten. Ingen Humanoid.
Behold partnavnene (`HumanoidRootPart` som PrimaryPart ved hofterne, `Torso`, `Head`, `Mask`, `UpperArm*`, `Forearm*`,
`Leg*`) og de to attachments `FootstepAttachment (0, −4.75, 0)` og `HeadAttachment (0, +4.37, 0)`.
Ændres kropsmålene, så meld de nye tal (`Level 4 Configuration.Body`), fordi døre og passager beregnes ud fra dem.

Animationsslots (§6.1), in-place, gruppeejede Animation-assets:

| Slot | Reference (studs/s) | Varighed/loop | Krav |
|---|---:|---|---|
| Idle / ALERT | 0 | 1,1 s telegraf, loop | stopper og vender sig mod spilleren; læsbart fra 40 studs |
| Walk | 7 (patrol) / 11 (return) | loop | langsom, bevidst, lange skridt |
| Search | 13 / 15 | loop | hovedet fejer, stopper ved verandaer |
| Chase | 24 | loop | under spillerens sprint (26) |
| Attack | — | windup 0,5 s + recovery 1,2 s | træffet lander ved slutningen af windup (markør `Contact`) |

Budget: ≤ 8.000 triangler, én tekstur ≤ 1024² eller vertex-farver. Lever FBX + asset-id'er.

### 3.2 Facade-, bro- og loftmoduler (den nye retning)
Moduler, som Claude gentager op ad facaderne. Høje etager forenkles, men nær spilleren bevares dybde. Mål i studs.

| Modul | Mål (B × H × D) | Indhold | Navn i Studio |
|---|---|---|---|
| Altanmodul | 24 × 13 × 4 | altanplade, hvidt rækværk, dør + 2 vinduer | `Level4FacadeBalcony` |
| Karnapmodul med gavl | 12 × 13 × 5 | karnap, lille gavl, 3 vinduer | `Level4FacadeBay` |
| Glat vægfelt | 24 × 13 × 1 | vinduesrække uden fremspring (fjerne etager) | `Level4FacadeFlat` |
| Gangbro-sektion | 16 × 6 × 12 | dæk, rækværk begge sider, 2 lamper, bue under | `Level4BridgeSpan` |
| Loftpanel | 20 × 1 × 36 | lyspanel (emissiv) + mørk kassette | `Level4CeilingPanel` |

Ønsket: MeshParts eller Parts + teksturer, farver fra kontraktens §7 (creme, støvet gul, hvide lister, mørke vinduer).
Hvert modul ≤ 1.500 triangler. Loftpanelets lys er en emissiv flade. Dynamiske lys tæller mod loftet på 12 og placeres af Claude.

### 3.3 Lyd (kontrakt §8)
Neighbour footsteps, breath, alert, chase, attack; `HouseWarned` / `HouseDangerous`; signal/beacon/exit og ambience
(svag vind + fjern elektrisk summen, velegnet til et enormt indendørs rum). Ingen konstant musik. Lever som gruppeejede
Audio-assets med id og ønsket volumen.

## 4. Annonce- og thumbnailbilleder ([kydyBl7u](https://trello.com/c/kydyBl7u))

Kortet kræver billeder, der matcher de første minutter. **Ingen ny annonceudgift.** Målte første minutter (Creator Dashboard,
fra 21/9): 83 spillere, 80,7 % kom ind i en runde, 31,3 % nåede første objective, første død i snit ca. 28 s efter rundestart.
Optag verificerede gameplay-øjeblikke i Studio (play mode):

1. Lobbyen med Level 1-pladen og guiden "LEVEL 1 START HERE" (ny profil).
2. Level 1: elevatoren åbner, og gangen ind (første 10 s).
3. Level 1: entity'en i synsfeltet på 20–30 studs med rødt blik (den faktiske trussel).
4. Level 2 (`workspace.Level2Seed = 1182081016`): hvælvingskorridoren med de nye bue-meshes (v2015).
5. Level 2: en Pool Foam i synsfeltet (den står stille, mens den bliver set — spillets nye regel).
6. Level 3 (`Level3Seed = 1154781618`): første CD på bordet i `L3_S1_R05`.

Varianter, testopsætning (samme målretning, periode og budget) og måling af spend, plays, CPP, spilletid og D1
er jeres og ejerens. Kortet bliver først Done efter en kontrolleret test.

## 5. Hvad Claude gør med leverancerne

Import til templates, id'er i konfiguration, envelope- og korridormåling, rundetest (spawn, jagt, angreb, oprydning), ydelse på
PC og emuleret mobil, commit, Trello og publicering. Fysisk mobil og lyttetest står fortsat på ejer eller Codex.
