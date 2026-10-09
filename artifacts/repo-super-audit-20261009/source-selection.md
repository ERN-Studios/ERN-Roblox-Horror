# Source-valgliste: Studio er source of truth

Første native inventar:200 indholdsmatches,18 drift,10 repo-only og12 Studio-only. Dette er et valggrundlag; ingen filer er slettet/importeret af auditten. GameManager/RoundUI blev eksternt ændret og spejlet under auditten; brug de to final-snapshots og lav frisk parity før ændringer.

## Indholdsdrift:18 filer

Hent fra aktuel native Source før cleanup. Bevar class/enabled/RunContext. Snapshots nedenfor er verificeret; normaliser kun projektets dokumenterede newline-kontrakt.

| Native path | Repo-fil | Native snapshot |
|---|---|---|
| ServerScriptService.ZyntraMonetization | ServerScriptService/ZyntraMonetization.Script.lua | [source](studio-sources/ServerScriptService/ZyntraMonetization.Script.lua) |
| ServerScriptService.Level5PreviewAccess | ServerScriptService/Level5PreviewAccess.Script.lua | [source](studio-sources/ServerScriptService/Level5PreviewAccess.Script.lua) |
| StarterPlayer.StarterPlayerScripts.Level 1 Sound Controller | StarterPlayer/StarterPlayerScripts/Level 1 Sound Controller.LocalScript.lua | [source](<studio-sources/StarterPlayer/StarterPlayerScripts/Level 1 Sound Controller.LocalScript.lua>) |
| StarterPlayer.StarterPlayerScripts.First Entry Guide | StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua | [source](<studio-sources/StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua>) |
| StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt | StarterPlayer/StarterPlayerScripts/Level4PreviewPrompt.LocalScript.lua | [source](studio-sources/StarterPlayer/StarterPlayerScripts/Level4PreviewPrompt.LocalScript.lua) |
| ServerScriptService.Level 3 Systems.Level 3 World Builder | ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua | [source](<studio-sources/ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua>) |
| ServerScriptService.Level 3 Systems.Level 3 Round Adapter | ServerScriptService/Level 3 Systems/Level 3 Round Adapter.ModuleScript.lua | [source](<studio-sources/ServerScriptService/Level 3 Systems/Level 3 Round Adapter.ModuleScript.lua>) |
| ServerScriptService.Level 3 Systems.Level 3 Layout Generator | ServerScriptService/Level 3 Systems/Level 3 Layout Generator.ModuleScript.lua | [source](<studio-sources/ServerScriptService/Level 3 Systems/Level 3 Layout Generator.ModuleScript.lua>) |
| ServerScriptService.Level6PreviewAccess | ServerScriptService/Level6PreviewAccess.Script.lua | [source](studio-sources/ServerScriptService/Level6PreviewAccess.Script.lua) |
| ServerScriptService.Level 3 Systems.Level 3 Worn Party Room Dressing | ServerScriptService/Level 3 Systems/Level 3 Worn Party Room Dressing.ModuleScript.lua | [source](<studio-sources/ServerScriptService/Level 3 Systems/Level 3 Worn Party Room Dressing.ModuleScript.lua>) |
| ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter | ServerScriptService/Level 3 Systems/Level 3 Worn Party Visual Adapter.ModuleScript.lua | [source](<studio-sources/ServerScriptService/Level 3 Systems/Level 3 Worn Party Visual Adapter.ModuleScript.lua>) |
| StarterPlayer.StarterPlayerScripts.Level6PreviewTransport | StarterPlayer/StarterPlayerScripts/Level6PreviewTransport.LocalScript.lua | [source](studio-sources/StarterPlayer/StarterPlayerScripts/Level6PreviewTransport.LocalScript.lua) |
| ServerScriptService.LobbyReimaginedPreview.Bootstrap | ServerScriptService/LobbyReimaginedPreview/Bootstrap.Script.lua | [source](studio-sources/ServerScriptService/LobbyReimaginedPreview/Bootstrap.Script.lua) |
| ServerScriptService.LobbyReimaginedPreview.QueueBridge | ServerScriptService/LobbyReimaginedPreview/QueueBridge.ModuleScript.lua | [source](studio-sources/ServerScriptService/LobbyReimaginedPreview/QueueBridge.ModuleScript.lua) |
| StarterPlayer.StarterPlayerScripts.R4DevGateController | StarterPlayer/StarterPlayerScripts/R4DevGateController.LocalScript.lua | [source](studio-sources/StarterPlayer/StarterPlayerScripts/R4DevGateController.LocalScript.lua) |
| ServerScriptService.LobbyReimaginedPreview.DevBayAccessGuard | ServerScriptService/LobbyReimaginedPreview/DevBayAccessGuard.ModuleScript.lua | [source](studio-sources/ServerScriptService/LobbyReimaginedPreview/DevBayAccessGuard.ModuleScript.lua) |
| ServerScriptService.LunaTribute | ServerScriptService/LunaTribute.Script.lua | [source](studio-sources/ServerScriptService/LunaTribute.Script.lua) |
| StarterPlayer.StarterPlayerScripts.Level 5 Lighting Controller | StarterPlayer/StarterPlayerScripts/Level 5 Lighting Controller.LocalScript.lua | [source](<studio-sources/StarterPlayer/StarterPlayerScripts/Level 5 Lighting Controller.LocalScript.lua>) |

## Studio-only:12 scripts

Disse har aktive features/dependencies, som delrapporterne beskriver. De skal registreres i spejlet, frem for at blive overset ved repo-oprydning.

| Native path | Class | Verificeret snapshot |
|---|---|---|
| ServerScriptService.Level 3 Kit Warmup | ModuleScript | [source](<studio-sources/ServerScriptService/Level 3 Kit Warmup.ModuleScript.lua>) |
| ServerScriptService.Level 3 Systems.Level 3 Balloon Dressing | ModuleScript | [source](<studio-sources/ServerScriptService/Level 3 Systems/Level 3 Balloon Dressing.ModuleScript.lua>) |
| ServerScriptService.Level 3 Systems.Level 3 Crayon Wall Art | ModuleScript | [source](<studio-sources/ServerScriptService/Level 3 Systems/Level 3 Crayon Wall Art.ModuleScript.lua>) |
| ServerScriptService.Level 6 Systems.Level 6 Playground Game | ModuleScript | [source](<studio-sources/ServerScriptService/Level 6 Systems/Level 6 Playground Game.ModuleScript.lua>) |
| ServerScriptService.Level Leaderboards | Script | [source](<studio-sources/ServerScriptService/Level Leaderboards.Script.lua>) |
| ServerScriptService.Live Level Server | Script | [source](<studio-sources/ServerScriptService/Live Level Server.Script.lua>) |
| ServerScriptService.Lobby DJ | Script | [source](<studio-sources/ServerScriptService/Lobby DJ.Script.lua>) |
| ServerScriptService.Lobby Tunnel Reach | Script | [source](<studio-sources/ServerScriptService/Lobby Tunnel Reach.Script.lua>) |
| ServerScriptService.ServerKind | ModuleScript | [source](studio-sources/ServerScriptService/ServerKind.ModuleScript.lua) |
| StarterPlayer.StarterPlayerScripts.Level 6 Dev ESP | LocalScript | [source](<studio-sources/StarterPlayer/StarterPlayerScripts/Level 6 Dev ESP.LocalScript.lua>) |
| StarterPlayer.StarterPlayerScripts.Lobby DJ Client | LocalScript | [source](<studio-sources/StarterPlayer/StarterPlayerScripts/Lobby DJ Client.LocalScript.lua>) |
| StarterPlayer.StarterPlayerScripts.Lobby Tunnel Reach Client | LocalScript | [source](<studio-sources/StarterPlayer/StarterPlayerScripts/Lobby Tunnel Reach Client.LocalScript.lua>) |

## Repo-only:10 scripts

**Må ikke automatisk installeres tilbage.** Vælg archive/removal fra det aktive mirror efter tooling-/ownercheck. Repo-only er ikke et bevis på, at en manuel QA/authoring-funktion er værdiløs.

| Manifest native path | Repo-fil | Valg |
|---|---|---|
| Workspace.Level 4 Cinema V9 QA.OccasionalFixtureFlicker | Workspace/Level 4 Cinema V9 QA/OccasionalFixtureFlicker.Script.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| Workspace.Level 4 Cinema Preview.OccasionalFixtureFlicker | Workspace/Level 4 Cinema Preview/OccasionalFixtureFlicker.Script.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| StarterPlayer.StarterPlayerScripts.Level 2 Pool Slide Dev ESP | StarterPlayer/StarterPlayerScripts/Level 2 Pool Slide Dev ESP.LocalScript.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| Workspace.Level 4 Cinema V9 QA.AutomaticDoors.AutomaticDoorMotion | Workspace/Level 4 Cinema V9 QA/AutomaticDoors/AutomaticDoorMotion.Script.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| Workspace.Level 4 Cinema Preview.AutomaticDoors.AutomaticDoorMotion | Workspace/Level 4 Cinema Preview/AutomaticDoors/AutomaticDoorMotion.Script.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| ServerScriptService.Level 6 Systems.Level 6 Preview Runtime | ServerScriptService/Level 6 Systems/Level 6 Preview Runtime.ModuleScript.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| StarterPlayer.StarterPlayerScripts.Level 6 Lighting Controller | StarterPlayer/StarterPlayerScripts/Level 6 Lighting Controller.LocalScript.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| StarterPlayer.StarterPlayerScripts.Level 6 Mall Manager Visual Smoother | StarterPlayer/StarterPlayerScripts/Level 6 Mall Manager Visual Smoother.LocalScript.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| StarterPlayer.StarterPlayerScripts.Level 6 Table Hiding Client | StarterPlayer/StarterPlayerScripts/Level 6 Table Hiding Client.LocalScript.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |
| StarterPlayer.StarterPlayerScripts.Level 6 CD Dev ESP | StarterPlayer/StarterPlayerScripts/Level 6 CD Dev ESP.LocalScript.lua | Ikke valgt; C03/C31/CORE-033/LE-05 efter område |

## Final sources efter eksternt arbejde

- [GameManager](studio-final-sources/ServerScriptService/GameManager.Script.lua):190167:c1244f6c:dba1fa2a.
- [RoundUI](studio-final-sources/StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua):238896:38f2ada6:3420710e.
- Aktuelt disk-mirror matcher begge efter den relevante newline-kontrakt. Kontroltidspunktet er afgrænset; hver efterfølgende session skal reread.

