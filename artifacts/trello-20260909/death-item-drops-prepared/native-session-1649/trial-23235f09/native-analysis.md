# L1 — faktisk to-fuse death-drop og peer-pickup

Run `23235f09-1198-433c-a437-bc235f623153` med to faktiske lokale Studio-klienter. Komplette retained serverrecords matcher hvert JSON-felt i hver af de fire faktiske klient-INPUT-pakker; ingen input gentages for at rekonstruere rapporten.

| Trin | Faktisk resultat |
|---|---|
| A: første relay | E/Triggered1, carry1,100HP |
| A: anden relay | E/Triggered1, carry2,100HP |
| Kontrolleret død | Server Died/HP0 på samme karakter; A carry0 |
| Gulvdrop | Én stak FuseCount2 ved præcis deathXZ, Y.9; marker `FUSES ×2`, aktiveret Pick up-prompt, hold.25/range9 |
| B: stak | E/Triggered1, carry2,100HP; server Drops[] og CarriedFuseVisual til stede |
| B: fuse-box | E/Triggered1, carry1; faktiske InstalledFuse-dele0→1 |

Alle fire kommandoer bevarer ServerSameContext, samme faktiske karakter/runde og key-release. Begge klienter er registreret ready i samme serverkanal. B's pickup virker gennem den normale production prompt, efter scriptet gulvstaging og kameraretning.

Billedet `native-fuse-stack-b.jpg` er læst: guldteksten FUSES ×2 og E/Pick up er tydelig nær liget. Selve sikringen er delvist skjult af ragdollen. Dette dokumenterer den konkrete native visning, ikke generel afstandslæsbarhed eller menneskelig reaktion.

**Bevarede fejl og setup:** Den første afbrudte session/fejlede E er historik. I dette run er fire oprindelige enkeltlinje-JSONs afkortede; alle er bevaret som fejl. Tre efterfølgende UTF-8 chunkeksporter (5/5,3/3,9/9) er komplette uden fejl. Kanaleksporten indeholder de originale resultater; det komplette stack-before-b-snapshot er en senere faktisk læsning. AI-pausen udløb15:21:14.072UTC og blev kontrolleret genarmeret15:22:54.802 før B-pickup. Det døde A og levende B/stakken var stadig i samme aktive runde. A's Health=0, placeringer og kamera er eksplicit testopsætning.

Dette checkpoint støtter L1 collect→death→anden spiller pickup→brug. Normal cleanup, anden death/redrop, CD-halvdelen og publicering er endnu ikke omfattet. JSONanalysen indeholder præcise målinger, kildelinjer, hashes og afgrænsninger.

## Senere overgang til L3

Kontrolleret ObjectiveComplete er logget for L1 kl.15:25:32.762UTC og L2 kl.15:25:54.429UTC. De normale efterfølgende ready-markører viser begge faktiske spillere100HP/InRound/uankret ved L2 kl.15:25:54.429 og L3 kl.15:26:18.993. OldPuzzleItemsRemoved=true i begge. Dette er normal transition efter et kontrolleret objective-signal, ikke gennemspilning af begge puzzles. Helperens removed-felt accepterer også et oprindeligt nil-reference; markøren alene beviser derfor ikke en sammenhængende descendants-optælling eller fjernelse af alle inventoryfelter. CD-testen starter nu separat.
