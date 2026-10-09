# Lommelygte: offline-kortlægning af alle lysveje

Dato: 2026-10-08. Denne underopgave brugte ingen Studio-kald, tog ingen lås og ændrede ingen runtime-filer. Ingen commit, push eller udgivelse. Konklusionerne beskriver repoets frosne baseline; de er ikke et bevis for live Studio eller rendererens adfærd.

De fem scripts i `offline-baseline.json` var stadig identiske med snapshots ved afsluttende hashkontrol. `studio-sync-manifest.json` var ændret af samtidig arbejde og må læses igen før enhver senere synkronisering. Graphify blev brugt først (`flashlight spectate lighting`, BFS); grafen er bygget fra `a6551306`, mens HEAD var `1be05fc9`, og inkluderer historiske artifacts. Grafresultater blev derfor kun brugt som søgekort, aldrig som autoritativ kilde.

## Ejerskab og writers

| Lysvej | Egenskaber og writer | Betydning for flimren |
|---|---|---|
| Egen `Workspace.FlashlightMount` | FlashlightController 50–86 bygger Core SpotLight (`Shadows=true`), Spill (`false`) og Fill PointLight (`false`, .28/11). `MongoFlashlight` RenderStep ved Camera+2 (134–199) er eneste CFrame-writer; 172 skriver mount. | Ingen anden gennemgået script-writer til den samme egen mount. Lyset har tre komponenter, ikke kun core. |
| Egen profil | Controller 94–101 og Profiles 48–71. Cache-nøgle er levelprofil + focused; direkte B/R/A-sæt, ingen tween. | Stabilt level/focus giver stabile B/R/A. RenderStep kalder apply flere gange, men cache afviser identiske writes. |
| Egen on/off | Controller `setLights` 593–600, `warnBlink` 606–620, død/spawn/round-state 710–731 og batteri 886–916. | **Tilsigtet flicker findes**: ved 50% ét blink, 25% tre blink; hvert mørkt interval .08 s og pause .14 s. Det ændrer kun egne Enabled, ikke serverflag. Må skilles fra buggen. |
| Serverens `Workspace.ReplicatedFlashlight_<id>` | FlashlightSync 43–91 bygger Core/Spill, begge `Shadows=false`. On/off via ToggleFlashlight; aim 125–142 skriver CFrame. ProfileApply hver accepteret aim. | Klienten sender aim ca. 15 Hz (Controller 190–195); server accepterer højst 30 Hz. Andre klienter kan se trappetrin i denne mount. |
| Lokal undertrykkelse af egen serverkopi | Controller 177–188 finder egne serverlys og skriver `Enabled=false` hver RenderStep. | Egen dobbeltrender er forsøgt undertrykt. Replikationstidspunkt/øjebliksvis re-enable skal måles i Play; source kan ikke bevise fravær af én-frame-glimt. |
| Holdkammeraters head-lys | Controller 744–764 bygger `MateBeamCore` (`Shadows=true`) og Spill (`false`) på Head. Heartbeat 827–861 opdaterer profil/focus og Enabled. | Hos en anden spiller eksisterer både server Mount og disse head-lys. Der er ingen tilsvarende undertrykkelse af andres serverkopi. Det øger lysmængden; source alene beviser ikke et Roblox-budgetproblem. |
| Holdkammeraters synlige shaft/lens | Controller 768–801 og 844–859. Shaft begynder ved Head Attachment(.35,-.25,-.7), 40-stud mateRay flytter endpoint. | Ray-hit ændrer **kun shaft/lens**, ikke head-lysets origin/Enabled. Shaft, head-lys og server aim-mount har forskellige originer/directions. |
| SpectateBeam | SpectateController 142–154 har Core `Shadows=true`, Spill false. RenderStepped 194–248 skriver camera/mount og profil. Stop 360–374 slukker og fjerner parent. | Egen flashlight er slukket ved død. Spectate-mount parentes til CurrentCamera, mens egen mount bevidst er flyttet til Workspace pga. en tidligere renderingfejl. Det er et særskilt regressionspunkt, ikke dokumenteret årsag til levende spillers flicker. |
| Shop-demo | Shop Display Client 460–496 bygger egen `ZyntraLocalFlashlightDemo`, core shadow=true, og følger kamera RenderStepped i seks sekunder. | Separat mount; demo starter kun uden InRound og stopper hvis InRound bliver true. Ingen write til den rigtige torch. |
| Level 4 reel-glint | Level 4 Round Client 190–260 bygger kort PointLight (Range8, Shadows=false) og particles på reel. Brightness 2.5→0 eller mild 0→1.4→0; destroy efter 1.1 s. | Glimt er tilsigtet og kan ændre pixels ved sweep over reels, men skriver aldrig torchens egenskaber. Log reel-glint ved siden af torch-events. |

`ProtectionHUD` rører kun FlashlightWidget-skabelonen i HUD (77,403). `NoiseReporter` omtaler input/UIDevice-kontrakten (516), men skriver ikke flashlight Light. SoundController læser FlashlightOn for kliklyd; Level 1/3/4/6 AI læser flag/mount til gameplay. Søgningen fandt ingen ekstra writer til egen Core/Spill/Fill.

## Raycast: præcis geometri og mulige spring

Controller 150–169 beregner `eye + .25*rightFlat - .25*Y + .3*look`. Rayen går kun fra øje til hånd, ikke langs hele den synlige stråle. Ved vandret blik uden camera-roll er længden `sqrt(.215) = 0.463681` studs. En streng generel øvre grænse er `sqrt(.25²+.25²)+.3 = 0.653553` studs. Ved hit bruges direkte `max(hitDistance-.3,0)` langs samme ray; ingen interpolation af hit-clamp.

Et grazing hit/no-hit kan derfor flytte mount-origin omtrent .3–.464 studs ved vandret kamera (op til .654 som generel bound). Et hit inden for .3 studs flytter origin helt tilbage til øjet. Det kan give diskontinuitet nær en kant; et objekt fem eller 20 studs fremme **kan ikke** rammes af denne øje→hånd-ray og kan ikke alene udløse clampen. Proben skal derfor måle kamera-relativ origin/clamp-distance og hit-instance, ikke kalde normal world-motion et flicker-event.

Own-ray filter er `{camera, local character}`. Egen mount har `CanQuery=false` (55), server mount false (Sync52), mate lens false (796), spectate mount false (147). De mounts/lens kan derfor ikke være den normale self-hit-kandidat. Der er ingen eksplicit exclusion af andre avatars, collision-folder, transparente parts eller CanCollide=false parts; der er heller ingen eksplicit RespectCanCollide/IgnoreWater-setting i flashlight-rayen.

Konkrete kandidater fra placerings-/builder-koden, der kræver live-instance-verifikation:

- Level 4 `makeCollider` kalder invisible (Transparency1, CastShadow=false) og sætter CanCollide/CanQuery=true for almindelige colliders (tools/level4_blender/place.luau 255–282). Synlige meshes har CanCollide=false/CanQuery=false og Automatic RenderFidelity (425–436). Torch-ray kan altså blive styret af grovere usynlig collision-geometri frem for den synlige mesh. Ikke et bevis for buggen.
- Level 4 door Leaf er Transparency1/CastShadow=false/CanCollide=true (517–522), uden eksplicit CanQuery-assignment. Dørens aktuelle CanQuery skal aflæses i Studio.
- Level 2 Entry Cradle Collision er Transparency1/CanQuery=true/CastShadow=false (World Builder 2873–2885); Column Base Flare Collision tilsvarende (1307–1317). Synlig geometri og ray-geometri kan være forskellige.
- Level 1 møbelparts får ofte CanQuery=false (MazeGenerator1594), og usynlige entity-sight-volumener har false (1725). Disse konkrete grupper er ikke den oplagte clamp-kandidat, men andre map-/props egenskaber skal måles.

Mate-ray er anderledes: 40 studs fra hand attachment med filter `{mate char, mate lens}` (853–855). Andre avatars/parts kan være det første hit og dermed flytte shaft endpoint brat. Den er ikke den fælles årsag til egen torch, fordi den ikke skriver til egen mount eller head-lys.

## Level-writers og de seks hypoteser

Level 2 Lighting Controller skriver Lighting-grade, bloom og GlobalShadows (75–142), ved attributændringer og ca. .75 s Heartbeat (144–153); ingen flashlight Light. Level 4 Lighting Controller tager grade ved bounds/levende spiller (129–144), følger power-state hvert .25 s og re-applier .75 s (284–324), og håndhæver globale Lighting-properties via Changed (275–280). Alpha er clamp(Rate*dt,0,1); ingen overshoot. Stars tweens ændrer mesh-transparency. Ingen af dem skriver own Core/Spill/Fill.

Level 4 Round Client scanner kun cinema-descendants og tracker lys med holderens L4Zone plus lysets L4Brightness (318–346); zone-stutters 373–425 kan skabe tilsigtet miljøflimren. Egen torch ligger direkte under Workspace og har ikke disse attrs. Level 3 Lighting Controller baseline/flicker-lister tages kun fra `Level 3 Generated World` descendants (259–285,834–835); den kan tween/blinke miljølys, men normalt ikke den egen Workspace-root mount, server mount eller avatar Head-lys.

| Hypotese | Offline-status | Hvad Play skal afgøre |
|---|---|---|
| 1. Eye→hand-origin hopper | **Plausibel tæt ved collision/kanter**, kvantificeret ovenfor. Ingen sweep-fremad-ray. | Visuel flimmer skal tidsmæssigt følge hit-switch/clamp-residual; samme kamera med midlertidig runtime A/B uden clamp kan afgrænse årsag, uden at godkende produktfix. |
| 2. Shadow-light-budget | Egen + mate + spectate + level shadow-lys findes. Serverkopier er dog shadow=false. | Stabil Enabled/B/R/A/origin mens pixels popper; count nearby shadow/nonshadow lights, kvalitet og kameraafstand; isolér andre lys i runtime A/B. Ingen budgettal er bevist af source. |
| 3. Geometri/skyggeartefakter | Glas/Neon/alpha meshes med CastShadow=false, Automatic fidelity, query-only usynlige colliders findes i builder/placeringskode. | Match den faktiske hit/surface, material, shadow/query/transparency/fidelity og overlap i live scene til flimmer. |
| 4. Streaming | Ingen runtime-kode ændrer StreamingEnabled. Source-only mirror registrerer ikke den aktuelle place-property. | Live property + streamed descendant churn/hit availability ved event. Kort eye→hand-ray påvirkes kun af geometri meget tæt på kamera; synligt lys kan stadig afhænge af fjern streamed geometri. |
| 5. Overshoot eller flere loops | Egen CFrame har én writer; clamped Lerp udelukker overshoot i den viste formel. Profiles gør direkte sæt, ingen torch-tweens. **Enabled har dog flere tilsigtede writers**: toggle/death/reset/batteri-warning. | Mål lokale Enabled-edges, profil/focus/camera-swaps og server self-copy edges; udeluk battery warnings med DevUnlimited og frisk full charge. |
| 6. Technology/LightingStyle | Ingen runtime-script-writes til Technology/LightingStyle fundet. Kommentarer siger Realistic, hvilket ikke beviser live property. | Læs live Technology/LightingStyle/prioritize/quality og mål faktisk renderer. PC device emulator er ikke hardwaretest på en telefon. |

Der er ingen entydig rodårsag endnu. Ingen runtime-fix er foreslået eller anvendt. Et properties-jump er en kandidat-event, ikke i sig selv bevis for synligt flicker; et visuelt blink med stabile properties kan omvendt være renderer/miljø. Before/after skal sammenligne samme sweep og begge måletyper.
