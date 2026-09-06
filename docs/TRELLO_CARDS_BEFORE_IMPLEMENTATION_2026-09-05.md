# Trello-kort før opdatering af beskrivelser

Bevarer det fulde oprindelige auditgrundlag. Trello-connectoren begrænser nye beskrivelser til 2048 tegn, så kortene får en kort aktuel status og henvisning hertil.

## Robusthed: spillere kan strande bag loading-dækket (to tilfælde)

https://trello.com/c/DIktjy8U/16-robusthed-spillere-kan-strande-bag-loading-d%C3%A6kket-to-tilf%C3%A6lde

To bekræftede fund fra docs/AUDIT-2026-09-04.md (Robusthed 1 og 2). Begge er små rettelser i GameManager.

**1. En spiller, hvis karakter aldrig loader, sidder fast i runden**
Rundestart sætter pendingExplicitPlacement[player] = true og kalder spawnGameplayCharacter; returnerer den nil efter fire forsøg (4 × 6 s), sker der intet. Spilleren bliver i participants, kommer aldrig i alive, kan ikke dø, ikke undslippe og får aldrig et death-event, så tilskuerkameraet starter ikke — sort loading-dæk hele runden. Latchen bliver oveni stående, så en sen LoadCharacterAsync lander karakteren hvor motoren vil (i Level 2 uden for ankomstdækket).
Steder: GameManager.Script.lua:1953-1954 (post-win continuation), :2382-2383 (Studio station launch), :2719-2720 (reserveret boot), :440-458 (spawnGameplayCharacter).
Fix: i alle tre entry-loops, ved nil: ryd pendingExplicitPlacement[player], fjern spilleren fra participants og fyr "spectating" eller "loadfailed", så de får tilskuerkameraet.

**2. En reserveret server, der opgiver admission, strander alle**
Boot-tasken kalder stageArrivingParty() og returnerer bare, hvis beslutningen ikke er "admit" (efter 40 s uden gyldig BackroomsRound-pakke, fx når GetJoinData fejler eller nogen joiner privatserveren uden teleport-data). Spillerne har fået "loadinggame", har ingen karakter og ingen verden bygges. Intet sender dem hjem.
Steder: GameManager.Script.lua:2678-2679 og :2688 (bare returns), :889-894, :2622; Round Completion Routing.ModuleScript.lua:598-602 (AdmissionEmptySeconds = 40).
Fix: erstat begge bare returns med `fireGroup(Players:GetPlayers(), "loadfailed"); returnGroupToLobby(Players:GetPlayers())`, samme vej som en fejlet ensureWorld.


## Controller: tre HUD-handlinger uden gamepad-sti, sprint-lås og terminal-luk

https://trello.com/c/uI8hg2At/17-controller-tre-hud-handlinger-uden-gamepad-sti-sprint-l%C3%A5s-og-terminal-luk

Tre bekræftede fund fra docs/AUDIT-2026-09-04.md (Mobil og controller 1-3). Alle er små.

**1. Objektiver (H), mute dispatch (M) og tilskuer-skift (Q/E) findes ikke på controller**
Knapperne på skærmen er ingen fallback: en runde låser LockFirstPerson og skjuler cursoren, og intet sætter GuiService.SelectedObject (kun PARTY DOWN-kortet). Værst for spectate: en død controller-spiller ser den samme makker resten af runden. STOP DISPATCH viser mønsteret (tager ButtonB ved siden af N).
Steder: RoundUI.LocalScript.lua:1847-1856 (mute, kun M) vs :1875-1887 (stop, N + ButtonB), :2614-2632 (objectives, kun H), :194 vs :221 (Binding-captions); SpectateController.LocalScript.lua:340-347, :240-242.
Fix: ButtonSelect til objectives, ButtonL1 til mute, DPadLeft/DPadRight ved siden af Q/E i SpectateController, og glyffen som andet argument til UIDevice.Binding/Caption.

**2. En tabt L2-udløsning låser sprint resten af runden**
gamepadSprintDown()/keyboardSprintHeld() genlæser hardware, men kun i lobby-grenen af Heartbeat (returnerer før in-round-stien). Mister controlleren forbindelsen mens triggeren holdes: WalkSpeed på sprint, stamina tømmes, og reporteren melder "sprint" til fjenderne hver gang stamina kommer igen. Samme hul for Shift.
Steder: NoiseReporter.LocalScript.lua:676-706 (genlæsningerne :684-690, return :705).
Fix: flyt de to genlæsninger op over `if not inRound()`, så én Heartbeat reparerer begge latches i alle tilstande, og slet lobby-kopien.

**3. Gamepad-spillere kan ikke pålideligt lukke Zyntra-terminalen**
En konsolspiller, der trykker X ved kiosken, har ingen sikker vej ud af panelet igen (luk-knappen er ikke selectable/har ingen binding).
Steder: ZyntraStore.LocalScript.lua (luk-knappen og terminalens åbn/luk-binding). Fix: ButtonB lukker terminalen, og GuiService.SelectedObject sættes til første fane ved åbning.


## Pool Foam er lydløs: lav lyde og monter en looping emitter på hver entity

https://trello.com/c/24sCzSO6/15-pool-foam-er-lydl%C3%B8s-lav-lyde-og-monter-en-looping-emitter-p%C3%A5-hver-entity

Level 2's eneste fjende laver ingen lyd på nogen afstand. Lydrørene findes (Configuration.AudioIds, syncAudioLibrary, klientens SOUND_IDS), men alle tolv id'er er tomme, og det eneste der kan afspille dem er en 2D one-shot i SoundService. Der findes ingen looping emitter på entiteten, så selv med id'er kunne man ikke høre den nærme sig. Level 1's entity har fodtrin, howl og fire positionelle skrig; Mall Manageren har fodtrin på riggen.

**Hvad der skal laves**
1. Lydassets (upload til Roblox, notér id'er): Walk-loop (vådt, lavt, slæbende skum), Hunt-loop (hurtigere/vådere), Caught-sting, Attack-hit, Collapse, Idle-ambience. Seks slots pr. entity-type (Primary + én til), tolv i alt.
2. Kode (kan jeg lave, når id'erne findes): én looping Sound pr. entity parentet til PrimaryPart med InverseTapered rolloff (min ~12, max ~110 studs), der skifter clip når animations-adapterens _applyState skifter tilstand. Klientens playSound beholdes til stings.
3. Indsæt id'erne i `ServerScriptService/Level 2 Systems/Level 2 Pool Foam Configuration` → `AudioIds`.

**Beviser (docs/AUDIT-2026-09-04.md, Spildesign nr. 2)**
Level 2 Pool Foam Configuration.ModuleScript.lua:182-199; Level 2 Pool Foam Controller.ModuleScript.lua:109-137, :727-737; Level 2 Pool Foam Client.LocalScript.lua:30-38, :218-240.
 
