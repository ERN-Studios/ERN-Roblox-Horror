Den primære kandidat er isoleret fra checkoutets scripts og Studio.

- `GameManager.Script.lua`: fem linjer i `loadGameplayCharacter`; markerer kun den nye, succesfuldt indlæste krop som `ZyntraGameplayCharacter` før load-gaten frigives. Lobby-kroppen mærkes aldrig.
- `HazmatSkinVisuals.Script.lua`: kroppen er berettiget ud fra denne markering; `InRound` og `RoundActive` afgør ikke længere suitens levetid. Serveren lytter til markeringens ændring og afkobler ved CharacterRemoving/PlayerRemoving. Fjerner den tidligere previewBodies-special-case og RoundActive-listener.
- `HazmatSkinDriver.LocalScript.lua`: samme markering styrer klientens reconcile. Eksisterende 0,2 s genkontrol og to poseframes bevares. Ingen ændring af kollisions- eller afstandshåndtering.

Markeringen bliver på den udgående gameplay-krop ved død og lobbyretur. Dermed genvises den gamle R15 ikke, når flagene nulstilles før karakterudskiftningen. CharacterRemoving rydder visual/state som hidtil. Level 2 new-map preview bruger allerede den fælles LoadGameplayCharacter. De spejlede Level 5/6 developer previews flytter deres lobby-avatar og bliver fortsat ikke skinnet; Level6PlaygroundPreview-koden findes ikke i den aktuelle mirror, så dens fælles load-call skal bekræftes i Studio.

Test:

- Alle tre primære scripts kompilerer med Luau 0.737 `--null -O0`.
- `test_loading_marker.py`: 40 checks på de faktiske kandidatfunktioner; fem separate mutationer fanges alle (load-stamp, lobbyudelukkelse, markersignal, udgående krops kontinuitet, clientbrief).
- Den isolerede `test_level2_newmap_feedback.py`: 83 checks, inkl. 10 server skin- og 5 driverchecks (udvidet 2026-10-09 til faktisk colour-helper/custom-colour-checks). `existing-test-minimal.diff` indeholder de nødvendige ændringer til den delte harness uden artefaktets lokale ROOT/source-redirection.
- Round-loading-host-harnessen erstatter spawnGameplayCharacter med en fake og slicer ikke loadGameplayCharacter; derfor kræver den ingen ny karakterstub alene pga. denne ændring.

Valgfri farvehunk i `optional-tint/HazmatSkinVisuals.Script.lua` (diff mod primær kandidat: `optional-tint.diff`): advanced custom colour på standard skin anvendes på den nye Meshy-mesh via samme `SurfaceAppearance.Color`, som Monetization bruger på den gamle krop. Tint indgår i visual-cachen, så farveændring genbygger visualen. Navngivne skins beholder deres authored farver. Manglende SurfaceAppearance giver den hidtidige sikre fallback. Den valgfri server kompilerer `-O0`; `optional-tint/test_tint.py` passer 15 checks. Den er ikke indført i primær kandidat: template-overflade og farvens udseende skal først kontrolleres visuelt i Studio.

Primær kandidat bevarer derfor den eksisterende keepsAdvancedColor-undtagelse samt fallback ved manglende/invalid asset eller sen profile-load. Hvis ejeren skal have kun den nye model også ved betalt custom colour, skal den valgfrie farvehunk verificeres og medtages. Den fysiske R15-krop/joints beholdes som motor for de nye Meshy-Bones; den gamle synlige skin skjules af driveren, når den nye visual fungerer.

Ingen delt script, test, manifest eller lock-fil er ændret af denne delopgave. Ingen Studio-adgang eller Play-QA udført.

Opfølgning 2026-10-09: Alle tre harnesses accepterer nu `--source-dir`. Den kombinerede kandidat med tint passer 216 samlede Luau-checks og 5/5 lifecyclemutationer; se `COMBINED-TINT-VALIDATION.md`.
