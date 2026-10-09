# -*- coding: utf-8 -*-
"""Skriver de haandskrevne systemoversigter i '02 Systemer' gennem MCP."""
import json
import urllib.request

MCP_URL = "http://127.0.0.1:27200/mcp"
TOKEN = "eUGfeGxbX5CV8Hzrlm0DVT44hmzIlprwmjWOMCy7qT8"
P = "02 Systemer"
_id = [500]


def mcp(name, args):
    _id[0] += 1
    body = json.dumps({"jsonrpc": "2.0", "id": _id[0], "method": "tools/call",
                       "params": {"name": name, "arguments": args}}).encode("utf-8")
    req = urllib.request.Request(MCP_URL, data=body, method="POST", headers={
        "Authorization": "Bearer " + TOKEN, "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream"})
    with urllib.request.urlopen(req, timeout=120) as r:
        out = json.loads(r.read().decode("utf-8"))
    if "error" in out:
        raise RuntimeError(out["error"])
    if out["result"].get("isError"):
        raise RuntimeError(out["result"]["content"][0]["text"])
    return out["result"]["content"][0]["text"]


def fm(*tags):
    return "---\ntype: system\ntags:\n" + "".join("  - %s\n" % t for t in tags) + "---\n\n"


N = {}

# --------------------------------------------------------------- oversigt
N["Systemer (oversigt)"] = fm("oversigt", "system") + """# Systemer

Hvordan spillet faktisk hænger sammen. Hver note her samler ét system og
linker videre til de scripts der udgør det.

> [!info] Hvor kommer indholdet fra?
> Disse noter er skrevet ud fra [[README — fuld projektreference]],
> [[HANDOFF — status og næste skridt]], [[HANDOFF Level 2]] og
> [[CLAUDE — arbejdsregler for repoet]]. Hvor de siger noget om et tal eller
> en tilstand, er det repoets egen formulering — ikke et gæt.

## Rundens gang

- [[Lobbyen og runde-flowet]] — tunnellobbyen, køen, reserverede servere og
  hvad der sker når et niveau er gennemført

## Niveauerne

- [[Level 1 — Elevator, labyrint og entiteten]] — færdig
- [[Level 2 — Poolrooms]] — verden bygget, fjender live
- [[Level 3 — Mall]] — under udvikling, kampagnens sidste niveau

## På tværs

- [[Remotes og netværk]] — de 13 RemoteEvents og hvem der bruger dem
- [[UI, HUD og enheder]] — HUD, safe area, touch og regressionsmatricerne
- [[Lyd]] — positionel lyd, lydbiblioteker og de tomme slots
- [[Monetisering — Zyntra]] — butik, passes og donationsleaderboardet
- [[Testsuiter]] — hvad der køres, hvor, og hvad der ikke kan testes

## Det der venter

- [[Åbne beslutninger]] — fem ting der bevidst står stille, fordi svaret er
  et designvalg og ikke en fejlretning
"""

# ------------------------------------------------------------------ lobby
N["Lobbyen og runde-flowet"] = fm("system", "zone/lobby") + """# Lobbyen og runde-flowet

## Tunnellobbyen

En permanent vejtunnel-lobby bygget ved serverstart af [[TunnelLobbyBuilder]]
(2.724 linjer). Du går rundt i **din egen Roblox-avatar** — tredjeperson, hop
tilladt, danse-emote på `G` ([[DanceEmote]]).

Seks **level-bays**, hvor **1–3 er aktive** og 4–6 er forseglede
("ACCESS UNSTABLE"). Hver bay er tematiseret efter sit niveau — gult kontor,
poolrooms-fliser, mall-party — og har fire **launch stations**: vægmonterede
skærme på leddelte arme over runde startplatforme. Træd op på en platform for
at hoste, vælg **partystørrelse (1–6)** og **public / friends-only**, og en
nedtælling starter mens partiet fylder op.

[[LobbyPartyModeController]] kører party-mode: loftslamperne tweenes gennem en
neonpalet i 10 sekunder og sættes tilbage bagefter. [[LobbyMusicController]]
ejer lobbyens musik.

## Fra lobby til runde

[[GameManager]] (2.591 linjer) er rundens motor: kø, reserverede servere,
runde-loop. Et launch teleporterer partiet til en **reserveret server** der
genererer præcis én verden til det parti — i Studio falder den tilbage til en
test-runde på stedet.

Når man går ind i en runde bliver alle skiftet til **hazmat-riggen**
([[Animate (StarterCharacter)]] i `StarterCharacter`) med normaliseret
avatarstørrelse for hitbox-paritet ([[AvatarNormalize]]), låst
førstepersonskamera og det fulde horror-HUD. Tilbage i lobbyen får du din egen
avatar og et afslappet kamera igen. **Alt er gated på `InRound`-attributten.**

## Når et niveau er gennemført

Ét **fuldskærms-resultatoverlay** for hvert udfald, på hvert niveau — der
findes ikke en anden "kort"-form. Level 1 og 2 giver to handlinger,
**CONTINUE** og **BACK TO LOBBY**; Level 3 er kampagnens sidste niveau og
giver kun **BACK TO LOBBY**. **Der er intet Level 4.**

Reglerne bor i ét modul: [[Round Completion Routing]] (1.585 linjer, rent
regelmodul), og [[Round Completion Test Suite]] (2.624 linjer) håndhæver dem.

> [!important] "CONTINUE flytter spilleren med det samme"
> Det er blevet fejllæst to gange, så README skriver det ud: at trykke Continue
> tager spilleren **væk fra den færdige server øjeblikkeligt**. Destinationen
> *staging'er* dem så — som den staging'er alle continuers — indtil kildens
> beslutningsfrist plus en afgrænset transportfrist, fordi den indtil da ikke
> kan vide om der kommer flere. **Staging er ikke venten:** de er fuldgyldige
> deltagere hele tiden, aldrig tilskuere, og lukkes ind senest ved frist +
> grace. Nedtællingen på 15 sekunder er auto-continue-fristen for dem der ikke
> har valgt — ikke en barriere den hurtige sidder bag.

Ét resultatvindue er **én session med et frosset roster**: medlemskabet
fastlægges når vinduet åbner og fjernes aldrig fra, kun beslutningerne bevæger
sig. Det er det der holder hovedtallet ærligt når en spiller trykker Continue,
rejser, og forlader serveren midt i vinduet.

Hver overførsel **claimes før den starter**, med sit eget id der rejser med i
teleport-data, så `TeleportInitFailed` matches til netop det forsøg. **Én
watchdog ejer enhver uafsluttet overførsel** — Roblox kan acceptere en
forespørgsel og så aldrig rapportere noget.

`Routing.TeardownPlan` afgør hvad der sker med verden bagefter: på en reserveret
server **beholdes kortet** under de spillere den ikke kunne flytte; kun en
offentlig server eller Studio river verden ned.

> [!warning] Cross-server-overførsler er utestede
> Studio har ingen TeleportService-destination, så intet her har set en rigtig
> reserveret server tage imod et parti. Det der **er** testet, er hver
> beslutning på begge sider af kaldet. Behandl den første publicerede
> multiplayer-Continue som den rigtige verifikation.

## Nøglescripts

| Script | Rolle |
| --- | --- |
| [[GameManager]] | Kø, reserverede servere, runde-loop |
| [[TunnelLobbyBuilder]] | Bygger tunnellobbyen og launch stations |
| [[Round Completion Routing]] | Alle regler for hvad et gennemført niveau fører til |
| [[Round Completion Test Suite]] | 397 checks, 0 fejl |
| [[AvatarNormalize]] | Hitbox-paritet på tværs af avatarer |
| [[LobbyPartyModeController]] | Party-mode i lobbyen |
| [[LobbyMusicController]] | Lobbymusik |
| [[RoundUI]] | Statusbjælke, åbningssekvens og resultatoverlay (4.981 linjer) |
"""

# ---------------------------------------------------------------- level 1
N["Level 1 — Elevator, labyrint og entiteten"] = fm("system", "zone/kerne") + """# Level 1 — The Yellow Maze

**Status: færdig.**

Procedurelt genereret **40×40 kontorlabyrint** — korridorer, pladser, pit-rum
og en børstet aluminiums-serviceelevator med sin egen loftstekstur. Nyt layout
hver runde. Bygget af [[MazeGenerator]] (2.008 linjer).

## Målet

Skalerer per spiller: hver spiller tilføjer 1 sikringsboks, 1 håndtag og ét
**farvet kredsløb**. Der spawner dobbelt så mange vægrelæer som der skal bruges
sikringer. Styret af [[PuzzleManager]] (2.116 linjer), vist af [[PuzzleUI]].

1. Træk **sikringer** ud af vægmonterede ZYNTRA-relæer. Loftslamperne i
   nærheden klynge-gløder som hint, og udtrækket larmer — entiteten hører det.
2. Sæt dem i vægmonterede **sikringsbokse**. Hver isætning hæver faren:
   flimmer, entitetsfart, og entiteten trækkes mod området. Alle bokse fyldt →
   vedvarende rød **ALERT**.
3. Træk alle **håndtag** inden for 10 sekunder af hinanden. Dør en holdkammerat,
   droppes synkroniseringskravet — håndtagene låser fast.
4. En radial **POWERDOWN**-bølge slukker lyset, **udgangsporten** åbner, og
   entiteten vogter den.
5. Undslupne bliver tilskuere. Runden slutter når alle levende er ude (sejr)
   eller alle er døde (tab).

**Farvede kredsløb:** hvert par af sikringsboks og håndtag får sin egen
kabelfarve (rød, blå, grøn, gul, magenta, cyan) med fysiske gulvkabler.
Kabinens vedligeholdelsesplakat viser hele kredsløbslisten **fra det øjeblik
elevatorturen starter**, så partiet kan planlægge før dørene åbner.

## Entiteten

Custom skinnet Meshy-rig, 51 knogler, fuldt Blender-animationssæt.

- [[EntityAI]] (1.296 linjer) — jager på **syn og lyd**. Sprint larmer,
  snigen er lydløs, din lygte forlænger dens synsvidde. Gridnavigerer den
  labyrint den har lært (klipper aldrig gennem vægge), husker din position
  5 sekunder efter den mister dig af syne, og vælger nyt jagtmål hvert minut.
- [[EntityAnimation]] — kobler Blender-klippene til tilstanden: Watch, Walk,
  Run, Howl, YellFromRun, Lunge, LungeFromRun, Kill.
- [[EntityKill]] — det 5 sekunder lange cinematiske ground-pin-drab med
  førstepersons kill-kamera, synkroniseret skrig og fade til tilskuertilstand.
- [[EntityShakeController]] — klientens rystelser.
- Glødende øjne (rav → **rød når den jager**), ballistisk **pounce lunge**, og
  et **hyl ved pit-kanten** der skubber folk der går på bjælker ud i tomrummet.

## Lyd

Den fluorescerende **summen er positionel, per loftspanel** — hvert tændt panel
summer for sig selv (kun de nærmeste, streaming-sikkert), og et panel der er
dødt, flimrende, blackoutet eller powered down er **stille**. Dine ører fortæller
dig hvilke armaturer der er live. Se [[Lyd]].

## Nøglescripts

| Script | Rolle |
| --- | --- |
| [[MazeGenerator]] | Labyrint, pits, elevator, lys, indretning |
| [[PuzzleManager]] | Sikringer → bokse → håndtag → udgang |
| [[PuzzleUI]] | Målsætnings-HUD |
| [[EntityAI]] | Entitetens jagt og navigation |
| [[EntityAnimation]] | Animationskobling |
| [[EntityKill]] | Drabssekvensen |
| [[Level 1 Sound Controller]] | Niveauets lyd |
| [[NoiseRegistry]] · [[NoiseReporter]] | Hvem larmer, og hvor |
"""

# ---------------------------------------------------------------- level 2
N["Level 2 — Poolrooms"] = fm("system", "zone/level-2") + """# Level 2 — Sunken Leisure Complex

**Status: verden bygget, fjender live.**

Et lyst, solbeskinnet liminalt **poolrooms-vandland** med sin **egen** generator
— den deler kun flisetekstur og vandets udseende med Level 1. Det tidligere
håndbyggede Flooded Poolrooms-niveau er bevaret i
`ServerStorage.Level2Backup_20260805` (se [[Arkiv (oversigt)]]).

## Generering

**Binær rum-partitionering** af en 1400-studs region: ~45 haller på maks ~250
studs per side (`MaximumLeafSize`), forbundet af oversvømmede
**arch-tunnel-korridorer**. **Nyt tilfældigt seed hver runde.** Vand dækker
gulvet **væg til væg** i hver poolhal — kun i vadedybde, ingen svømmer nogensinde.

- [[Level 2 Layout Generator]] — BSP-layoutet
- [[Level 2 World Builder]] (5.984 linjer) — layout → geometri
- [[Level 2 Configuration]] — alle tal ét sted
- [[Level 2 Round Adapter]] — koblingen til runde-loopet

> [!bug] `Level2Seed = 0` låste kortet — rettet 2026-08-19
> Vagten var `type(requestedSeed) ~= "number"`, og 0 **er** et tal, så et
> nulstillet attribut genopbyggede stille seed 0's layout hver runde. Nu betyder
> 0, negative tal, NaN og ikke-tal alle "vælg et tilfældigt seed"; kun et tal
> **≥ 1** låser. `Level2_SeedPinned` i state-mappen viser hvilken tilstand en
> runde kørte i.
> **[[Level 3 Round Adapter]] bærer stadig præcis den samme fejl** ved sin egen
> seed-læsning — latent, fordi der ikke sættes noget `Level3Seed`-attribut i dag.
> Se [[Åbne beslutninger]].

## Verdenen

**Ægte sollys:** gennemsigtigt skyggeløst glastag og **skylight-mønstre per hal**
— fulde linjer, streger, et udstanset skakbræt eller et enkelt midterbånd — så
ingen to lofter ser ens ud. Glatte trompet-kurvede søjler går fra gulv til loft;
et verdensbredt søjleregister plus keep-out-striber ved døråbninger garanterer
at ingen søjle nogensinde overlapper noget eller spærrer en udgang.

**Legeinventar i hver vandhal**, randomiseret per seed og kollisionsverificeret:
rutsjebanesæt, **vippetårne** med blå/gule/røde/grønne vipper i flere højder,
legetårne med rørflumer, overdækkede udsigtsplatforme, og en sværm af
**opdriftige** nudler, badebolde, ringe og flåder der vipper og driver når
spillere vader ind i dem.

**Rutsjehaller (3):** mezzaninedæk, parallelle flumer med farvestøbte kar, en
tæt heltursspiraltrappe, og en **helix-rutsjebane på sin egen dedikerede søjle**
fodret af en catwalk-bro. At køre en rutsjebane er en rigtig fysiktur
([[Level 2 Slide Controller]] + [[Level 2 Slide Ragdoll Service]]).

Den store hal fører udgangsflumen mod øst ind i en **uendeligt genbrugt helix**:
en rytter der når bunden af tromlen sættes en hel omgang højere op igen med
tangentens momentum, så turen aldrig slutter af sig selv — det er
gennemførelsesvinduet der tager dem ud af den.

**Børnefløj:** hyggelige malede rum med ankeldybt vand i hele rummet,
børnerutsjebaner i rummets egen farve, en hex-pakket **boldkugle (~370 bolde)**
og runde tagvinduer. **Pumperum:** hævet gangring + pumpeø over lavt vand.

## Målet

Start **3 pumpestationer** — hver dræner en oversvømmet korridor (terrænvandet
fjernes faktisk) — hvorefter trykdørene ind til den store hal åbner. Kør så
udgangsflumen fra topdækket. Styret af [[Level 2 Objective Controller]], vist af
[[Level 2 Objective UI]] og [[Level2AlertClient]].

## Fjenderne

**Pool Foam** — controller, navigator, observer, proxy-rig og animationsadapter:

- [[Level 2 Pool Foam Controller]] · [[Level 2 Pool Foam Navigator]] (2.492 linjer)
- [[Level 2 Pool Foam Observer]] · [[Level 2 Pool Foam Proxy Factory]]
- [[Level 2 Pool Foam Animation Adapter]] · [[Level 2 Pool Foam Client]]
- [[Level 2 Pool Foam Configuration]] · [[README - LEVEL 2 POOL FOAM]]

**Slidemouth** — [[Level 2 Slidemouth Controller]] (3.705 linjer) og
[[Level 2 Slidemouth Client]].

> [!important] Slidemouths spawn måles i RUM-HOP, ikke studs
> En hal er 85–270 studs på en side og ét korridorhop spænder ~110–330 studs, så
> et fast studs-bånd betød "to rum væk" på ét seed og "samme rum, fjerneste
> hjørne" på det næste. Vælgeren går den samme hal-graf som navigatoren — inkl.
> trykdørs-porten — så et endeligt hop-tal også beviser at væsnet kan nå partiet
> derfra. Den bruger **aldrig** et rum hvor en levende spiller står, kræver 1–2
> rum fra den **nærmeste** levende spiller, og en nærhedsbund.
> Det er **hårde adgangskrav, ikke præferencer**: et anker uden for vinduet
> afvises, det degraderes aldrig til et lavere niveau som en anden rangering kan
> hive op igen. Er intet tilladeligt, **venter** spawnet — det tager aldrig det
> mindst dårlige rum.

> [!note] Et skridt valideres i stykker, ikke kun ved endepunktet
> Ved højeste jagtfart beder én frame om 3,6 studs (36 studs/s × controllerens
> egen 0,1 s-klemme), og de kanter væsnet skal forcere er 1,2 / 1,4 / 0,8-studs
> pool- og trappekanter og 0,70–0,80 kantsten. Én placering spænder over dem
> alle. Skridtet vandres nu i stykker på højst `MaxTravelStep` (0,9), hver med
> fuld gulvopløsning og kropsvolumen-test, med loft på 12 stykker så et absurd
> delta fejler **lukket** i stedet for at falde tilbage på ét uvalideret spring.

## Test

[[Level 2 Slidemouth Test Suite]] (6.280 linjer) kører mod en **rigtig genereret
verden** og udleder hver spawn-egenskab **uafhængigt** af controlleren.
Seneste resultat: **391 checks, 0 fejl** ved den autoritative modelskala.
[[Level 2 Exit Transition Test Suite]] dækker udgangsgeometrien.

Se også [[HANDOFF Level 2]] og [[README - LEVEL 2 TWEAKS]].
"""

# ---------------------------------------------------------------- level 3
N["Level 3 — Mall"] = fm("system", "zone/level-3") + """# Level 3 — Mall Backrooms Party

**Status: under udvikling.** Kernesystemerne er på plads og bygges videre ud.
Det er kampagnens **endepunkt — der er intet Level 4**, og niveauet tilbyder kun
ruten tilbage til lobbyen.

En død indkøbscenter-festetage bag bay 3.

## Systemerne

- **[[Level 3 Layout Generator]]** — deterministisk generator: lige,
  akse-justerede forbindelser, én centreret åbning per rumside, ingen diagonale
  korridorer. [[Level 3 World Builder]] bygger geometrien.
- **[[Level 3 Mall Manager AI Controller]]** (3.572 linjer) — en
  serverautoritativ kinematisk custom-rig-fjende: multi-ray-perception,
  server-udledt hørelse, klæbrig multiplayer-målsøgning, hukommelse om sidst
  kendte position, strategisk ruteføring gennem authored rum, fastkørings-
  genopretning og fair line-of-sight-angreb.
  [[Level 3 Mall Manager Visual Smoother]] glatter det ud på klienten.
- **[[Level 3 Music Sequence Controller]]** — ét autoritativt serverur kører
  cyklussen: 5 sekunders varsel → **2:30 blackout** mens sangen spiller færdig →
  en sidste **30 sekunders jagt** fra Mall Manager → ujævn fluorescerende
  genopretning → næste synkroniserede sangcyklus.
- **[[Level 3 Hiding Controller]]** — servervalideret **skjul under borde** med
  prompts, belægning og karaktergenoprettelse. Klientdelen er
  [[Level 3 Table Hiding Client]].
- **[[Level 3 Objective Controller]]** og [[Level 3 Reader Client]] (1.109 linjer)
  — målet og udgangslæseren.
- Egne lys- og lydcontrollere: [[Level 3 Lighting Controller]],
  [[Level 3 Sound Controller]].
- **[[Level 3 Test Suite]]** (3.573 linjer) — stor in-Studio testsuite.
  Seneste: 20 navigationsseeds, 9 baner, 321 møbeldele bevaret. **PASS**.

## Konfiguration

[[Level 3 Configuration]] ejer tallene, [[Level 3 Round Adapter]] kobler det til
runde-loopet, og [[Level3Generator]] er døråbningen fra `ServerScriptService`.

> [!warning] To ting står åbne på Level 3
> **Ingen vægkunst i genererede rum.** `ROOM_ART_COUNTS` / `BUNTING_ROOMS` er
> nøglet til pensionerede authored rum-id'er (`PartyA`, `CityPlay` …), mens
> generatoren udsteder id'er i stilen `L3_S1_R01`. Derfor spawner der aldrig
> børnetegninger, sedler, bunting eller heltballon i et genereret rum.
> Korridorkunst virker stadig.
>
> **Musikmixet er drevet fra hinanden** mellem klientkonstanterne og
> `Configuration.MusicSequence` (0,85 vs 1,15 fade; 0,85 vs 0,32
> synkroniseringstolerance). Konfignøglerne læses ikke, så **klientværdierne er
> dem der shipper.**
>
> Se [[Åbne beslutninger]].
"""

# --------------------------------------------------------------- remotes
N["Remotes og netværk"] = fm("system") + """# Remotes og netværk

Spillet har **13 RemoteEvents**. De ligger i `ReplicatedStorage` i tre grupper,
og hver enkelt har sin egen note med en liste over hvilke scripts der nævner den.

## `ReplicatedStorage/Remotes` — de fælles

| Remote | Hvad den bærer |
| --- | --- |
| [[RoundStatus]] | Rundens tilstand til klienten. Også kanalen Level 2's klient rapporterer `entryready` på |
| [[PuzzleStatus]] | Level 1's sikringer, bokse og håndtag |
| [[ToggleFlashlight]] | Lygte til/fra |
| [[DropGlowstick]] | Glowstick droppet med `G` i en runde |
| [[ReportNoise]] | Klientens larm ind til [[NoiseRegistry]] |
| [[Jumpscare]] | Udløser [[JumpscareUI]] |
| [[DevControl]] | Udviklerkommandoer — serversidevalideret mod [[DevAccess]] |

## `ReplicatedStorage/Level 2 Pool Foam Remotes`

| Remote | Hvad den bærer |
| --- | --- |
| [[ClientEvent (Level 2 Pool Foam Remotes)]] | Pool Foam-effekter til klienten |
| [[ClientReport]] | Klientens rapport tilbage til controlleren |

## `ReplicatedStorage/Level 3 Remotes`

| Remote | Hvad den bærer |
| --- | --- |
| [[ClientEvent (Level 3 Remotes)]] | Level 3-hændelser til klienten |
| [[Level3HideRequest]] | Anmodning om at skjule sig under et bord |

## Løse i `ReplicatedStorage`

| Remote | Hvad den bærer |
| --- | --- |
| [[Level 2 Sound Event]] | Lydcues til Level 2's klient |
| [[Level2AlertEvent]] | Alarm-tilstanden på Level 2 |

> [!note] Hvorfor `.txt`-filer i repoet?
> En RemoteEvent har ingen kildekode. Repoet spejler dem som tomme
> `.RemoteEvent.txt`-markører, så manifestet kan holde styr på at de findes i
> Studio. Se [[Studio-sync — status]].

## Adgangskontrol

[[DevAccess]] er **én delt whitelist** for hver eneste udviklerkommando, klient
som server. Den er nøglet til **UserId** og ikke brugernavn — brugernavne kan
ændres og må aldrig være en autoritetsgrænse. Tidslinje-søgning på Level 3 er
bevidst smallere end de delte udviklerværktøjer.
"""

# ------------------------------------------------------------------- ui
N["UI, HUD og enheder"] = fm("system") + """# UI, HUD og enheder

## De to moduler der bærer det hele

- **[[UIDevice]]** (1.974 linjer) — formfaktor og safe-area-layout for HUD'et.
  Publicerer `Safe`, `ModalViewport` og `TopRightPanel`. Det er den der ved om
  du sidder på en telefon i portræt, en tablet i et cover eller en PC.
- **[[UIRegression]]** (8.859 linjer) — hele HUD-regressionsmatricen. Projektets
  største enkeltscript.

## HUD'et

[[RoundUI]] (4.981 linjer) ejer statusbjælken øverst og åbningssekvensen med
målsætningen. [[PuzzleUI]] viser Level 1's mål, [[Level 2 Objective UI]] og
[[Level2AlertClient]] Level 2's, og [[Level 3 Reader Client]] Level 3's.
[[SpectateController]] giver fuld førstepersons-POV af overlevende når du er død
eller undsluppet. [[JumpscareUI]] og [[EntityShakeController]] leverer skrækken.

> [!info] Loading-dækket er delt, ikke per niveau
> Level 2 holder et loading-dække mens klienten streamer ind. Skærmen bor i
> [[RoundUI]] og farves af `LOADING_PALETTES` — Level 2's er vandblå.
> Klienten rapporterer `entryready` på [[RoundStatus]] når der er rigtig grund
> under den, og [[GameManager]] holder runden indtil da, ligesom elevatorturen
> holder Level 1. **Level 1 og Level 3 er uændrede.**

## Tre ting deler samme stribe af skærmen

Dispatch-briefingen, lobbyens queue-host-modal og Zyntra-butikkens opener
besætter alle UIDevice's TopBand. Reglen er nu ét udtryk i
`dispatchAudio.refresh`, publiceret som spillerattributten `DispatchBriefingOpen`:

- **queue-modalen vinder altid**, i begge retninger;
- **intet rives ned** — transmissionen, dens cue-timer og
  `ZyntraDispatchClientActive` røres ikke, så det at lukke modalen bringer
  panelet tilbage midt i sætningen;
- butiks-openeren træder tilbage gennem `UIDevice.SetInteractive`, som rydder
  `Visible`, `Active` **og** `Selectable` — den forlader **input-stakken**, ikke
  bare skærmen.

Målt ved 705×338 før rettelsen: openeren lå helt inde i briefing-panelet og
overlappede dets MUTE/STOP-række med 172×42 px.

## Touch

On-screen **RUN / JUMP / SNEAK** + lygtens tap-mål. SNEAK er touch-versionen af
`Ctrl`. **POV**-knappen er kun for udviklere (`devAllowed`). Hvert touch-mål skal
være mindst **44 × 44 px** — det håndhæves af `TouchTargetMatrix()`.

> [!important] Et modul-lokalt felt kan ikke observeres fra en matrix
> Studios `execute_luau` kører i en **separat `require`-cache** end de kørende
> LocalScripts: et modul required derfra er en anden tabel med sine egne
> upvalues. Det blev bevist direkte. Derfor skal alt en matrix skal påstå noget
> om, bo i delt tilstand — en attribut eller en instansegenskab. Se også
> [[Edit-mode require-cachen]] hvis den note findes.

## Studio-kun regressionshooks

Alle gated på `RunService:IsStudio()`, alle slået fra som standard, så ingen af
dem kan nås i et publiceret sted:

| Attribut | På | Effekt |
| --- | --- | --- |
| `UIRegressionForceDispatchActive` | spiller | `hasActiveTransmission()` svarer sandt |
| `UIRegressionSuppressDispatch` | spiller | Skjuler den ambiente transmission *og dens undertekst* |
| `UIRegressionViewport` / `ForceTouchUI` | workspace | UIDevice rapporterer simuleret størrelse/formfaktor |
| `UIRegressionSafeInsets` | workspace | `Rect(left, top, right, bottom)` — uden den kunne ingen matrix bevise at layoutet respekterer et sensorhus |
| `UIRegressionForceLevel3Reader` / `UIRegressionForceReaderHidden` | spiller | Tvinger Level 3-læseren aktiv/skjult |

Se [[Testsuiter]] for resultaterne.
"""

# ------------------------------------------------------------------ lyd
N["Lyd"] = fm("system") + """# Lyd

## Arkitekturen

[[SoundController]] (1.523 linjer) er klientens lyd-hub. Hvert niveau har sin
egen controller ovenpå: [[Level 1 Sound Controller]],
[[Level 2 Sound Controller]] (759 linjer) og [[Level 3 Sound Controller]]
(1.214 linjer). [[LobbyMusicController]] ejer lobbyen.

Larm den anden vej går gennem [[NoiseReporter]] → [[ReportNoise]] →
[[NoiseRegistry]], som er det entiteten faktisk hører.

## Level 1 — positionel per panel

Den fluorescerende summen er positionel **per loftspanel**: hvert tændt panel
summer for sig selv, kun de nærmeste, streaming-sikkert. Et panel der er dødt,
flimrende, blackoutet eller powered down er **stille**. Dødsskrig, jagtmusik,
hyl, fodtrin og bedstefarurets slag er positionelle og live.

Det positionelle **entitets-vokalsystem** er implementeret — serverplanlagt, så
hele serveren hører samme take fra entitetens faktiske retning — men dets
asset-slots for fjernskrig, lunge og idle-vokal er **stadig tomme**, så netop de
lyde spiller ikke endnu. Det er polish-slots, ikke manglende kode.

## Level 2 — biblioteket og de trimmede skridt

[[Level 2 Sound Controller]] plus StringValue-slots i
`ReplicatedStorage["Level 2 Sound Library"]`: ambience-senge, authored cues
(trykdøren får et rumligt multi-emitter korridor-ekko), tilfældige kontekstuelle
one-shots forankret i rigtig verdensgeometri.

**Vadefodtrin** er den interessante: runtime afspiller **trimmede
skridt-vinduer klippet ud af kildefraserne** — ikke de komplette fraser — plus
et stille undervands-modstandslag, drevet af et rigtigt vand-raycast. Der er et
separat **tørflise-slot** (`Level 2 Player Dry Tile Walking Sound`) med indbygget
fallback, til at gå hvor der ikke er vand under.

Slidemouth er koblet til pumpe/rutsjebane-lydbilledet med varslings- og
skrige-serialer og fire monster-brummere.

Seneste måling: 3 våde kørsler og 1 tør, **intet vådt hul over 0,480 s**. **PASS.**

## Level 3 — én cyklus, ét ur

[[Level 3 Music Sequence Controller]] kører hele musik/blackout-cyklussen fra ét
autoritativt serverur. Se [[Level 3 — Mall]].

## Lydfilerne

12 mp3-filer ligger i repoets `assets/sounds/` og er kopieret ind i vaulten —
du kan afspille dem direkte i [[Lyd (assets)]] hvis den note findes, ellers i
noten **Lyd** under `06 Assets`.

> [!todo] Tomme lyd-slots
> `SCREAM_SOUNDS` 1–4, `LUNGE_SOUND`, `ENTITY_STEP_RUN`, `IDLE_SOUNDS`,
> `BREATHING_SOUND`, `LOBBY_FOOTSTEP_SOUND`, flere Level 2-biblioteksslots og
> Level 3's `ExitUnlocked`/`Escape`-cues. Alle er indholdsarbejde, ikke kode.
"""

# --------------------------------------------------------- monetisering
N["Monetisering — Zyntra"] = fm("system") + """# Monetisering — Zyntra

Butikken hedder **Zyntra** i fiktionen ("Zyntra Transit — Powering the Future.").

## Scriptene

| Script | Rolle |
| --- | --- |
| [[ZyntraMonetization]] | Serversiden, 1.822 linjer |
| [[ZyntraStore]] | Klientens terminal, 2.200 linjer |
| [[ZyntraConfig]] | Delt konfiguration |

Hele opsætningen — produkter, passes, id'er, dashboard-trin — står i
[[Zyntra monetisering — opsætning]].

## Emergency Re-entry

Det produkt der griber ind i selve runden: går du ned, bliver du tilskuer
gennem en holdkammerat — **medmindre nogen bruger en Emergency Re-entry**, som
sætter dig tilbage på benene i **samme runde**.

## Supporter-passet og Mimic'en

> [!bug] Mimic'en bar købsbadgen — rettet 2026-08-19
> Level 1's Mimic **kloner kildespillerens karakter i sin helhed**
> ([[RoundUI]], `mimicBuild`), så alt der er parented til en karakter rider med
> over på tilsynekomsten. Zyntra Supporter-passet parenter en BillboardGui til
> hovedet — og Mimic'en gik rundt med den. Et købsmærke over et monster, og et
> øjeblikkeligt afslør. Klonen strippes nu for hver eneste `BillboardGui`.
>
> **Husk det her før du hænger noget nyt på en spillerkarakter.**

## Leaderboardet

Top-10-boardet i spillet rangerer **udelukkende donationer**. Det er ikke en
rangering efter dygtighed, fart eller overlevelse, og intet ved rundeindsats
påvirker det.

## Terminalen og testen

`ZyntraTerminalFitMatrix()` i [[UIRegression]] åbner terminalen gennem dens
**egen** produktions-toggle ved ti enhedsstørrelser og vælger hver fane — inkl.
DEV — gennem den produktions-`selectTab` spilleren selv rammer. Seneste
resultat: **557 checks, 0 fejl**.

[[ZyntraStore]] publicerer også en Studio-kun `BindableFunction`
(`UIRegressionZyntraStoreProbe`) der driver terminalen gennem dens egne
produktionsindgange, så en matrix ikke kan bestå mod en reimplementering af
fane-skift som spilleren aldrig kører.

Ikoner og kildebilleder ligger i vaulten under `06 Assets` → **Monetisering**.
"""

# ------------------------------------------------------------- testsuiter
N["Testsuiter"] = fm("system") + """# Testsuiter

Suiterne kører **inde i en Play-session** mod rigtigt genereret indhold, og de
er skrevet til at fejle frem for at bestå stille.

## Verificerede resultater — 2026-08-30

| Suite | Resultat |
| --- | --- |
| [[Level 2 Slidemouth Test Suite]] | 391 checks, 0 fejl, authored skala — **PASS** |
| [[Round Completion Test Suite]] | 397 checks, 0 fejl — **PASS** |
| `UIRegression.RunAll` | 21 scenarier, 0 fejl — **PASS** |
| ↳ `QueueModalMatrix` | 695 checks — **PASS** |
| ↳ `BriefingFitMatrix` | 244 checks — **PASS** |
| ↳ `BriefingExclusionMatrix` | 88 checks — **PASS** |
| ↳ `ObjectiveCornerMatrix` | 152 checks — **PASS** |
| ↳ `DispatchCompactMatrix` | 115 checks — **PASS** |
| ↳ `ZyntraTerminalFitMatrix` | 557 checks — **PASS** |
| `UIRegression.TouchTargetMatrix` | 408 checks, 0 fejl — **PASS** |
| Level 2 udgangsovergang | 105 studs/s krydsning + 75 s genbrugstur — **PASS** |
| Level 2 bevægelseslyd | 3 våde + 1 tør kørsel — **PASS** |
| Level 3 navigation + møbler | 20 seeds, 9 baner, 321 dele — **PASS** |
| Responsiv enhedssweep | Galaxy A06, iPhone 17 Pro, iPhone 17 portræt, iPad Pro M5 — **PASS** |
| Hele stedet: compile + Studio/repo-paritet | 114/114 — **PASS** |
| Roblox-publicering + live dashboard | place v1641 — **PASS** |
| `tools/tests/test_push_repo_to_studio.py` | **IKKE KØRT** — ingen `luau`-binær på maskinen |

## Sådan køres de

```lua
-- server
local Adapter = require(game.ServerScriptService["Level 2 Systems"]["Level 2 Round Adapter"])
Adapter.Build()
print((require(game.ServerScriptService["Level 2 Systems"]["Level 2 Slidemouth Test Suite"])
    .RunAll(Adapter.GetManifest())))
print((require(game.ServerScriptService["Round Completion Test Suite"]).RunAll()))

-- klient
print((require(game.ReplicatedStorage.UIRegression).RunAll()))
print((require(game.ReplicatedStorage.UIRegression).TouchTargetMatrix()))
```

> [!danger] `os.clock()` i Studio er PROCESSORTID, ikke vægur
> Fire-seed-sweepet rapporterede 343 "sekunder" efter cirka **25 minutter** på
> uret. En deadline skrevet sådan er altså langt løsere end den læser. Den er en
> nødbremse, ikke en tidsplan. **Den rigtige grænse er den endelige seed-liste**
> — løkken er endelig uanset hvad timeren gør. Skriv aldrig timeren som det
> eneste der stopper en løkke.

Forvent **20–30 minutters vægtid** for det fulde sweep. `execute_luau` giver op
længe før, så driv det fra kalderen og poll resultatet — aldrig en bar løkke,
som kan kile editoren fast.

## Offline sync-test

```bash
python tools/tests/test_studio_source_contract.py
python tools/tests/test_full_sync_contract.py
python tools/tests/test_push_repo_to_studio.py --fixture-only
```

Se [[Værktøjer (oversigt)]].

## Hvad der ikke kan testes herfra

- **Cross-server-overførsler.** Studio har ingen TeleportService-destination.
- **DataStore-genindtræden i produktion.** Dispatch-mute og engangs-claimet på
  lobby-briefingen persisteres, men første live leave/rejoin er den eksterne
  verifikation.
"""

# -------------------------------------------------------- aabne beslutninger
N["Åbne beslutninger"] = fm("system", "beslutning") + """# Åbne beslutninger

Fem ting står bevidst stille. De er hver især **verificeret** og derefter ladt i
fred, fordi det rigtige svar er et designvalg — ikke en fejlretning. Kilderne er
[[HANDOFF — status og næste skridt]] §3 og [[CLAUDE — arbejdsregler for repoet]].

## 1. Holdkammeraters lygter tegnes to gange

Klientens "MateBeam"-hovedlys **og** [[FlashlightSync]]'s replikerede
workspace-mounts tegner begge hver holdkammerats stråle — tre kilder mens du er
tilskuer. At fjerne den ene ændrer hvor lyse holdkammerater ser ud.

Er de replikerede mounts den tilsigtede renderer, er den overflødige halvdel
[[FlashlightController]], linje **462–535**.

## 2. Level 3-rum får ingen vægkunst

`ROOM_ART_COUNTS` / `BUNTING_ROOMS` er nøglet til pensionerede authored rum-id'er
(`PartyA`, `CityPlay` …), mens generatoren udsteder id'er som `L3_S1_R01`. Derfor
spawner der aldrig børnetegninger, sedler, bunting eller heltballon i et
genereret rum. **Korridorkunst virker stadig.**

At nøgle dem om ville tilføje visuals til live runder — derfor er det et valg,
ikke en oprydning. Se [[Level 3 — Mall]].

## 3. Slidemouth startes aldrig

[[Level 2 Slidemouth Controller]] har en komplet `Start`/`Stop`-flade som
**intet kalder**. Skal den live, skal
`SlidemouthController.Start(manifest, generation)` / `.Stop()` kobles ind i
[[Level 2 Round Adapter]] ved siden af Pool Foam.

Bemærk at controlleren er fuldt testet: [[Level 2 Slidemouth Test Suite]] kører
391 checks mod den. Det er kun opkoblingen der mangler.

## 4. Level 3's musikmix er drevet fra hinanden

Klientkonstanterne og `Configuration.MusicSequence` er uenige: **0,85 vs 1,15**
fade, **0,85 vs 0,32** synkroniseringstolerance. Konfignøglerne læses ikke, så
**klientværdierne er dem der shipper**. Værd at beslutte hvilke der er de
tilsigtede. Se [[Level 3 Configuration]].

## 5. Level 3 Round Adapter bærer stadig seed-fejlen

Vagten `type(requestedSeed) ~= "number"` accepterer 0 som et gyldigt seed. På
Level 2 betød det at et nulstillet attribut stille genopbyggede seed 0's layout
hver runde — det blev rettet 2026-08-19. **[[Level 3 Round Adapter]] har præcis
den samme fejl ved sin egen seed-læsning.**

Den er **latent**: der sættes ikke noget `Level3Seed`-attribut i dag. Men den
udløses i samme øjeblik nogen gør det. Se [[Level 2 — Poolrooms]] for hvordan
rettelsen blev formuleret på Level 2.

---

## Og en huskeregel

> [!danger] Alt der parentes til en spillerkarakter rider med på Mimic'en
> Level 1's Mimic kloner kildespillerens karakter i sin helhed. Zyntra
> Supporter-passets BillboardGui endte derfor over et monster. Klonen strippes nu
> for `BillboardGui`, men **den næste ting du hænger på en karakter, er ikke
> dækket.** Se [[Monetisering — Zyntra]].
"""

if __name__ == "__main__":
    for title, content in N.items():
        mcp("create_vault_file", {"path": "%s/%s.md" % (P, title), "content": content})
        print("OK", title)
    print("\n%d systemnoter skrevet." % len(N))
