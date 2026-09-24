# Pool Slide — eksport- og rigkontrakt til nye walk/run-animationer og større model

Skrevet af Claude 23/9/2026 til Codex. Kort: [rXhi1SZ8](https://trello.com/c/rXhi1SZ8) (animationer, større model) og
[LigItMHi](https://trello.com/c/LigItMHi) (mundlyd). Chase-koden er rettet og skal bevares; kortet mangler kun art.

## 1. Kilden er genskabt fra det levende spil

Den oprindelige FBX/GLB/BLEND findes ikke længere. Den levende rig er derfor trukket ud af Studio via EditableMesh
(geometri, vertex-farver, UV, skin-vægte, bind-pose) og KeyframeSequences (de fire klip) og samlet til én fil:

**`assets/models/pool_slide/pool_slide_live_rig_2026-09-23.glb`** — 1.624.160 B,
sha256 `12e70fe4e0c2724dc50d74add4f7074fe5679408410dafebf96b3b3d52b6a763`.

| Indhold | Værdi |
|---|---|
| Enhed | **1 unit = 1 stud**. glTF er Y-op; Blender vender til Z-op ved import |
| Armatur | `PipeEntityRig`, 20 knogler (§2), rod `Root` ved modellens pivot |
| `Mesh_0` (krop) | 13.105 vertices / 17.916 faces, mål 11,53 × 12,00 × 3,96, 4 palette-vertexfarver (rød, orange, grøn, blå), ingen tekstur |
| `Mesh_02` (hovedstykke) | 1.986 vertices / 1.898 faces, mål 3,82 × 3,79 × 2,79, sort; sidder 3,283 over og 0,482 bag pivot |
| Skin | 4 vægte pr. vertex, summer til 1, alle vertices vægtet |
| Actions | `Idle` 4,000 s · `Walk` 1,033 s · `Run` 0,633 s · `Attack` 1,200 s (markør `Contact` @ 0,50 s). Alle bagt i 60 fps; Idle/Walk/Run loopet |

Kontrolleret ved headless Blender 5.2-import: 20 knogler med samme positioner som live-templaten, begge meshes
vægtet på 20 vertex-grupper, alle fire actions med korrekte længder, Walk løfter foden ca. 0,6 stud.
Genskabelsen kan gentages: `tools/pool_slide_rig_to_glb.py` (Studio-udtræk beskrevet i scriptets docstring).
De oprindelige Blender-objektnavne står i templatens `InitialPoses`: `PipeEntityRig` og
`Level2SlideEntity_ApprovedGeometry_ExactPalette`.

## 2. Skelettet — navne og hvilepose skal bevares præcist

Live-template: `ServerStorage.Level2Assets."Level 2 Pool Slide Template"`, PrimaryPart `RootPart` (0,6³), pivot = bbox-centrum
(0, 4, 0 i ServerStorage), `Mesh_0`/`Mesh_02` med statiske Motor6D fra RootPart, `AnimationController/Animator`, mappe
`Animations` (Idle `116085684636171`, Walk `140239794149902`, Run `101625402038627`, Attack `121778490512649`).

| Knogle | Forælder | Lokal translation (studs) | Position i modelrum (studs) |
|---|---|---|---|
| Root | RootPart | (0, 0, 0), roteret 180° om Y | (0, 0, 0) |
| Hips | Root | (0, 0,72, 0) | (0, 0,72, 0) |
| Spine | Hips | (0, 0,72, 0) | (0, 1,44, 0) |
| Chest | Spine | (0, 1,26, 0) | (0, 2,70, 0) |
| Neck | Chest | (0, 1,92, 0) | (0, 4,62, 0) |
| Head | Neck | (0, 0,72, 0) | (0, 5,34, 0) |
| LeftShoulder / RightShoulder | Chest | (0, 1,14, 0) | (0, 3,84, 0) |
| LeftUpperArm / RightUpperArm | …Shoulder | (0, 2,94, 0) | (∓2,94, 3,84, 0) |
| LeftLowerArm / RightLowerArm | …UpperArm | (0, 1,6475, 0) | (∓3,84, 2,46, 0) |
| LeftHand / RightHand | …LowerArm | (0, 2,0933, 0) | (∓4,74, 0,57, 0) |
| LeftUpperLeg / RightUpperLeg | Hips | (±1,14, 0, 0) | (∓1,14, 0,72, 0) |
| LeftLowerLeg / RightLowerLeg | …UpperLeg | (0, 2,4084, 0) | (∓1,71, −1,62, 0) |
| LeftFoot / RightFoot | …LowerLeg | (0, 3,5912, 0) | (∓2,10, −5,19, 0) |

Rotationer står i GLB'en. Nye klip må **ikke** ændre knoglelængder, akser eller navne. Pivot skal stå lodret
(`UpVector·Y ≥ 0,999`), og sålen ligger **6,0 studs** under pivot (`GroundOffset`, kontrolleres ±0,12).

## 3. Hvad der skal leveres

### A. Nye walk- og run-klip (kortets krav)

1. Lav klippene på armaturet fra GLB'en uden at ændre hvileposen. In-place: ingen rodbevægelse (controlleren flytter modellen),
   og `RootPart` rører ikke. `Root` må vippe og bobbe lodret (de nuværende klip bruger −0,26…+0,07).
2. 30 eller 60 fps, loopet, samme første/sidste pose. Walk skal læses som almindelig bevægelse, run som jagt.
3. **Mål og send referencehastighederne**: den fart i studs/s, hvor fødderne ikke glider ved afspilningshastighed 1. I dag er de
   `WalkAnimationReferenceSpeed = 10,82` og `RunAnimationReferenceSpeed = 27,6` i `Level 2 Pool Slide Configuration`.
   Spillets farter er walk **10**, run **20** og enraged **32** studs/s. Afspilningsraten er fart ÷ reference, begrænset til
   0,05–2,5, med blend 0,16 s.
4. Attack er uændret, medmindre I også leverer et nyt: så skal markøren `Contact` sidde på træffet og længden oplyses.
   Controlleren bruger `AttackWindup = 0,5` og `AttackRecovery = 0,7` (1,2 s i alt).
5. Eksport: FBX eller GLB med armaturet og klippene. Upload hvert klip som **Animation-asset ejet af gruppen
   ERN Roblox Studios (1039373905)**, ellers kan spillet ikke afspille dem. Send asset-id'er og referencehastigheder.

### B. Større model (kortets krav — størrelsen fastlægges visuelt)

- Skaler ensartet (mesh + skelet). Oplys faktoren. Klip skal laves på den skalerede rig, fordi translationsspor ikke
  skaleres automatisk.
- Grænser, som controlleren kontrollerer: `AgentRadius ≤ 12` og `AgentHeight ≤ 24`. Ved +20 % bliver bbox cirka
  13,8 × 14,4 × 4,8, `AgentRadius ≥ 8,9` og `AgentHeight ≈ 20`.
- Lever som ny FBX/GLB (armatur + begge meshes + klip). Claude importerer den som ny template, måler envelope
  (`AgentRadius/Height`, `AnimatedEnvelopeRadius/Height`, `GroundOffset`) og genverificerer korridor-fit på tre layouts,
  før `Level2_PoolSlideRigVerified` og `Level2_PoolSlideCorridorFitVerified` sættes. Ingen scripts, prompts eller
  kollision i art-filen. Visuals `CanCollide = false`.
- Budget: højst ca. 20.000 triangler i alt (i dag 19.814), vertex-farver eller én tekstur ≤ 1024².

### C. Mundlyd (LigItMHi)

Mund-emitteren følger `Head`-knoglen med `MouthBoneOffset = (0, −0,3, −0,8)` i knoglerum, skaleret med modelhøjde ÷
`MouthReferenceHeight 12`. Vil I placere den præcist, så læg en Attachment `Level2_PoolSlideMouth` i mundåbningen
i den nye template. Den vinder over offsettet. Walk/run-loopet spiller i dag også fra munden; en fod-emitter kan bestilles
som polish.

## 4. Accept (det Claude verificerer efter integration)

- Walk og run afspilles i Level 2 ved farterne 10, 20 og 32 uden tydelig fodglidning eller hak ved skift.
- Den større model passerer korridorer og åbninger på tre layouts uden at sidde fast eller klippe (envelope-assertions grønne).
- Spawn stadig ≥ 100 studs fra alle levende spillere, anden pumpe spawner, tredje eskalerer samme entity, angreb lander ved `Contact`.
- Mundlyden kommer fra munden efter skalering. Den endelige lyttetest laves af ejer eller Codex.
- Alle nye assets er gruppeejede, og id'erne står i templatens `Animations`-mappe.
