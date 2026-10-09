Rettet i Studio og spejlet til repository. Studio er efterladt i Edit uden vores midlertidige testobjekter; k?en blev frigivet 9. oktober 2026 kl. 02:08 dansk tid. Ingen commit, push eller udgivelse.

Den nye dragt v?lges nu p? den nye gameplay-karakter fra dens oprettelse. Den venter ikke l?ngere p? `RoundActive`, som f?rst bliver sand efter Level 1-briefingen. De tre gamle shoulder/neck-kugler fjernes ogs? fra den indlejrede `SuitGapFix`-mappe. Klienten skjuler eventuelle sent ankomne gamle dele, mens rig og mesh bliver modtaget. Kameraskjulning g?lder egen karakter eller den faktiske spectate-karakter, s? en t?t holdkammerat forbliver synlig.

Advanced Equipment-farven anvendes p? den nye standarddragt, s? den tidligere farveundtagelse ikke v?lger den gamle model. Den usynlige R15-driver med Humanoid og led bevares til bev?gelse, kamera og animation; den gamle synlige dragt og de tre kugler vises ikke under det testede gameplay.

?ndrede Studio-scripts og tilsvarende filer:

- [GameManager](../../ServerScriptService/GameManager.Script.lua): markerer kun en vellykket ny gameplay-karakter.
- [HazmatSkinVisuals](../../ServerScriptService/HazmatSkinVisuals.Script.lua): bruger markeringen, fjerner pr?cis de tre gamle dekorationsdele og bevarer farven p? den nye dragt.
- [HazmatSkinDriver](../../StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua): skjuler gamle dele under replikering og begr?nser kameraskjulningen til kameraets egen spiller.
- [Feedback-testens fixture](../../tools/tests/test_level2_newmap_feedback.py): tilpasset den faktiske lifecycle og pending-skjulning. Andre sessions' ?ndringer er bevaret.
- [Sync-manifest](../../studio-sync-manifest.json): kun de tre ber?rte entries' bytes og hashes opdateret; alle ?vrige felter bevaret.

Den endelige rigtige tospiller-test brugte normal Level 1-k? og den eksisterende briefing. Testproben placerede spillerne p? k?pladen og brugte de normale UI-knapper; den ?ndrede ikke `InRound`, `RoundActive`, gameplay-markering, profiler eller developer-adgang. Efter briefingen styrede proben kamera og `Humanoid:Move` i seks navngivne scenarier.

- 1.238 klient-tidsm?linger; 720 spillerobservationer med vist ny dragt f?r `RoundActive`.
- 0 synlige gamle dele under ventetiden p? riggen, 0 gamle dele sammen med en vist ny dragt og 0 synlige SeamLiners p? begge klienter.
- Alle seks kontaktforl?b bestod: t?t tredjeperson, t?t f?rsteperson og fire g?-passager. 216 klientm?linger uden usynlige holdkammerater, manglende mesh, synlige gamle kropsdele eller defekte welds. Spillerne kom ned p? 0,17 studs afstand; helbredet forblev 100.
- Retur til lobby via normal hold-L-funktion og en ny Level 1-k?/briefing blev ogs? afpr?vet. Endelige pending-?ndringer blev derefter testet i en frisk tospiller-runde.
- Ingen HazmatSkin-advarsler i serverens eller klienternes logs. Source, editor-buffer og repository er ens for alle tre scripts; alle kompilerer med Luau `-O0`.

[Endelig Play-kvittering](multiplayer-final-pending.json), [l?sbart QA-resultat](final-qa-summary.json), [sk?rmbillede af den nye dragt uden kugler](final-new-suit-no-blobs.jpg), [frisk Source/editor-eksport](final-studio-export/export-manifest.json) og [offline-validering](pending-hide-validation-20261009/REPORT.md).

Offline: 295 fokuserede checks bestod, 5/5 lifecycle-mutationer blev fanget, og den eksisterende round-loading-host-test bestod 98 checks. Den delte feedback-test bestod 104 checks. Tidligere kode fejlede de nye regressionschecks for indlejrede kugler og partial-rig loading.

Aktuelle syv dragt-assets blev l?st i Studio og har det forventede mesh og 22 bones. Farvetesten var en afgr?nset runtime-diagnose p? en negativ Studio-testspiller, hvor midlertidige ownership/farve-attributter blev gendannet; den verificerer tint og nyt mesh, ikke k?b eller ejerskab. Ved en defekt asset eller et rig, som aldrig bliver komplet, bevares sikker fallback; pending-skjulning har en femsekunders gr?nse. Alle level-typer er ikke gennemspillet i Studio i denne opgave.

Konsollen havde eksisterende lyd-/Level 2-advarsler samt avatar/badge-fejl for Studios negative test-id'er. De er uden for rettelsen. Den lange `multiplayer-contact-final.json` fik en MCP-transporttimeout og bruges ikke som pass-bevis; de to efterf?lgende korte runder returnerede komplette kvitteringer med best?ede tests.
