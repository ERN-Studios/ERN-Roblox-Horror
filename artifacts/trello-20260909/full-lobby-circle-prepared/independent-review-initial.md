# Første uafhængige review — historisk forslag

**7/10 for GameManager `319f9f523ff2f2f470b6ab73f54688aa892e17e4e84c8ac3f65e876c9bd3215a`. Ikke godkendt til installation.** Den efterfølgende rettelse skal vurderes separat; dette notat bevarer det konkrete fund.

Jeg genkørte de 150 actual-source checks, begge negative kontroller og begge hele compiles. Cirkulær containment, faste accepterede character-identiteter, capacity/host-prioritet, frisk occupancy efter et yieldende venneopslag og host/epoch/lifecycle-fences var sammenhængende. Det ændrede kodeområde bevarer Continue- og launch-transportpolitikken.

Root fandt en reel mangel i den fysiske placering, som min læsning bekræfter: et fast mål på cirklens radius +1,5 studs kan ende blot 1,5 studs fra et accepteret medlems HRP ved kanten. To afviste spillere på samme radial får desuden samme mål. De 150 tests dækkede ikke disse krops-overlap. Resultatet kan dermed flytte eller støde de accepterede spillere, selv om medlemslisten holder korrekt kapacitet.

Den nødvendige afgrænsede rettelse er at vælge en faktisk ledig udvendig plads før PivotTo, uden yield mellem valg og placering. Den eksisterende arrivalPointFree-kontrakt kan genbruges sammen med få deterministiske kandidater, faktisk bay-/forhindringskontrol og afstand til andre køcirkler. Hvis ingen kandidat er sikker, skal der ikke tvinges en overlapplacering. Tests skal dække et accepteret medlem på kanten, to afviste på samme radial og en fuldt blokeret kandidatliste.

En tidligere reviewbemærkning om CanQuery er præciseret: den er ikke et separat dokumenteret enginefund. Roblox beskriver, at CanQuery=false får effekt når CanCollide er false. Et eksplicit RespectCanCollide=true gør den nye querys fysiske formål klart, men en offline fixture må ikke bruges som bevis for, at den tidligere native query udelod solide dele. Se [Roblox BasePart API-kilden](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/BasePart.yaml) og [OverlapParams API-kilden](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/OverlapParams.yaml).

Ingen runtime-, Studio-, UI- eller Trelloændring blev udført af reviewet. Native fysisk indgang/afvisning/udgang og eventuelle netværkskorrektioner er fortsat udestående.
