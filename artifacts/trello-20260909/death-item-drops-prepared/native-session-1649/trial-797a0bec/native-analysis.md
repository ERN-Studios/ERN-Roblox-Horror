# L3 — faktisk CD01 death-drop og peer-pickup

Run797a0bec med to faktiske lokale Studio-klienter. Alle12 exports/31 UTF-8 chunks er komplette uden rekonstruktionsfejl; A- og B-input matcher den fulde retained serverkanal og hver tilsvarende klient-INPUT-pakke.

| Trin | Faktisk resultat |
|---|---|
| A samler CD01 | E/Triggered1, count1/mask1,100HP; collected1/carried1/inserted0 |
| Kontrolleret død | Samme karakter Died/HP0; Acount0/mask0 |
| Gulvdrop | Præcis ét CDindex1 ved deathXZ, Y24.16; collected1/carried0/dropped1/inserted0 |
| B samler samme CD | E/Triggered1, count1/mask1,100HP; collected1/carried1/dropped0/inserted0, ingen dropped modeller |

Den faktisk udførte8b1c3bc-fixture udsender slutmarkøren først efter exact drop.Parentnil og samme originale source CARRIED/owner−2. Dermed er samme-CD-overførslen også verificeret via assertions i den udførte fixture; sourcefelterne er ikke foregivet at være rå snapshotfelter.

**Synlighed:** native-cd-stack-b.jpg er læst. E/BIRTHDAY MUSIC CD01/PICK UP DROPPED CD er synligt og læsbart. Verden er meget mørk; cyanlabel og disc-krop er ikke synlige i billedet. Der hævdes derfor kun korrekt nær-pickup-UI, ikke fysisk/cyan-marker-synlighed eller generel opdagelighed.

Det første bfb12e0b-input gik i en konkurrerende hiding-prompt og er bevaret separat sammen med normal LeaveHiding. Den nye851f039-fixture placerer kun den faktiske spiller udenfor andre E-ranges og bevarer alle productionprompts. Begge placeringer og kameraretninger er kontrolleret setup; A.Health=0 er et dødsfixture. Normal L3 fulgte tidligere kontrollerede objectives, ikke fuldt puzzle-playthrough.

To nye afkortede CHANNEL_RESULT rålinjer er bevaret som fejl; de fulde chunkexports indeholder originale resultater uden gentagelse. Ingen broad multiplayerrace, alleCD’er/smalehjørner/pits eller andre viewafstande er hævdet native-testet. Normal slutcleanup er nu bestået nedenfor; samlet uafhængig releasevurdering og faktisk publicering håndteres af root.

## Faktisk normal slutcleanup

D8da6e8-fixturen satte kun det kontrollerede sidste objective-signal og observerede den normale uændrede GM-afslutning. `cd-normal-final-cleanup.json` er fuld4/4chunks,1626bytes, SHAa9cc457d…0930a. Passed=true. Fra første observerede PostWin til gammel verden fjernet gik15.150110sekunder; der påstås ikke præcist frame-tidspunkt for hele vinduets start.

Begge faktiske spillere fik nye, levende100HP, uankrede lobbykarakterer med InRound=false og CDcount/mask0. Gamle verden/source/drop og begge gamle karakterer er fjernet. Alle fireCDtællere er0, ingen drops eller FuseHandVisual tilbage. Testens præcise remote er fjernet, Stop er kaldt på testens ejede helpers, og EntityPaused er tilbagefalse. Guardene læser faktiske gamle instansreferencer, så dette er stærkere cleanupbevis end det tidligere L1→L2 nil-or-removed-felt.

Denne slutkontrol beviser normal cleanup efter et kontrolleret objective-signal, ikke fuldt puzzle-playthrough. Publication er endnu ikke påstået af denne analyse. Historiske inputfejl, konkurrerende hidingprompt og alle originale truncatedlinjer bevares.
