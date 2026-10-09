# Bounded probe-transport

Offline hjælpere: `_local/flashlight-flicker/capture_frames.py`, `attribute_transport.luau` og `transport-smoke.luau`. Ingen Studio-kald er udført af denne agent.

Under næste faktiske Studio-bevilling køres først:

```powershell
python -B _local/flashlight-flicker/capture_frames.py --label transport-smoke-stageB --probe _local/flashlight-flicker/transport-smoke.luau
```

Smoken måler cirka 0,3 sekunders RenderStepped-callback og fjerner forbindelsen før retur. Et felt med multibyte UTF-8 fylder mere end 20 kB, så mindst to attributter skal kunne skrives, hentes og slettes. Kræv både `Success=true`, `CleanupVerified=true`, `ProbeComplete=true` og smokereportens `Summary.Disconnected=true`. Offline-testen beviser ikke disse Studio-kapabiliteter.

Efter godkendt smoke kan samme CLI bruges med den konfigurerede faktiske probe:

```powershell
python -B _local/flashlight-flicker/capture_frames.py --label L1-high-after-full --probe _local/flashlight-flicker/L1-high-after-full.luau
```

Proben skal slutte med `return json(report)` og selv have fjernet alle callbacks/restaureret kameraet før retur. Dette er en kontrakt; runneren kan ikke bevise cleanup i vilkårlig probe-kode. Den eksisterende bounded-frame-probe har en finalizer. Ingen rå rækker eller metrics forkortes.

Transporten reserverer nonce-ejerskab i en metadataattribut, kører proben i samme kald, og lagrer først det returnerede resultat efter proben er afsluttet. Rå UTF-8 deles ved hele tegn i højst 20.000 bytes pr. chunk, højst 256 chunks. Noncen er 96 tilfældige bits; ethvert eksisterende attributnavn med samme prefix giver en collision-fejl uden sletning.

Runneren genbruger `qa.py`-klasserne, kontrollerer Studio-låsen før hvert MCP-send og vælger præcis én Studio med placeId `131311258779917`. Hvert execute-kald kontrollerer også `game.PlaceId`. Hver hentning returnerer `H:JSONEncode({Index, Text})` og sletter straks den pågældende attribut. Samling kræver indeksorden, UTF-8, fuldt byteantal, DJB2 og et gyldigt JSON-objekt. Hele resultatet gemmes byte-for-byte i `play/<label>.txt`; `play/<label>.transport.json` indeholder receipt og separate assembly/cleanup-statusser. stdout indeholder kun en kort status.

`Success` betyder alene korrekt transport **og** verificeret attributoprydning; `ProbeComplete` skal vurderes særskilt. En korrekt samlet råfil kan eksistere efter cleanup-fejl, men CLI returnerer fejl og receipt viser `Success=false`. Ved delvis slettefejl beholdes ejerskabsmetadata til sikker retry. Mistet Studio-lås stopper også cleanup-kald; den oplyste prefix/nonce kan senere bruges med `cleanup_code(prefix, nonce)` under en ny bevilling. En fremmed/ukendt prefix uden matching metadata slettes ikke.

Offline-validation: 12 checks bestod; 247.801 bytes i 13 chunks, alle 600 syntetiske rækker og multibyte-tegn bevaret. Included: collision, byte/checksum/index-fejl, delvis lagringsfejl, fejlet cleanup og sikker retry. Default- og smoke-wrappers kompilerede samlet med `-O0 --null`. Se `transport-offline-validation.json`; faktisk Studio-smoke er endnu åben.
