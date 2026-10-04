# Back to lobby — forslag før ændring

Problemet er, at den nuværende knap kræver et klik, mens førstepersonskameraet holder musen skjult/låst. En udvej skal kunne opdages og bruges, uden at spilleren mister sin normale kamerastyring under jagten.

## A. Lille handlingspanel — alternativ

En diskret, permanent synlig **MENU**-handling med en ledig PC-tast vist ved siden af. På touch er det en tilstrækkelig stor knap. Åbning viser **Fortsæt**, **Tilbage til lobby** og, når relevant, **Spectate**. Først inde i dette afgrænsede panel er en fri markør relevant; panelet kan også betjenes med tastaturfokus. Spillet pauser ikke, og det må fremgå tydeligt. Valg af lobby har en kort bekræftelse, der forklarer, at spilleren forlader den aktuelle runde. Lukning gendanner præcis den tidligere kamera-/musestatus.

Fordel: let at forstå og plads til de eksisterende valg. Ulempe: et ekstra trin og behov for korrekt samspil med chat, andre paneler, død og spectating. En specifik genvej vælges først efter konfliktkontrol; Roblox' reserverede Escape-menu må ikke kapres.

## B. Hold for at forlade — foretrukken retning efter ejerens svar

Vis **HOLD [tast] · LOBBY** på PC og en hold-knap på touch. En ring fyldes på eksempelvis 1,5 sekund; slip afbryder. Kræver ingen markør. Handlingen standses, når chat/tekstfelt eller et andet modalvindue er aktivt, og sender højst én serveranmodning. Samme eksisterende servervalidering og teleportfejlshåndtering bevares.

Fordel: hurtigt, enkelt og ingen mus. Ulempe: endnu en tast at lære og risiko for utilsigtet aktivering; teksten og annulleringen skal være tydelige. Tilstanden skal nulstilles ved død, fokus-tab og sceneovergang.

## C. Udvid døds-/spectator-menuen

Saml **Spectate**, **Prøv igen/respawn** og **Lobby** i det eksisterende flow efter død, med tydelig markering og tastatur-/touch-betjening. Det forbedrer den mest almindelige situation, hvor man vil ud.

Fordel: mindst ny UI. Ulempe: løser ikke behovet for at forlade en bane, mens man lever; kræver derfor A eller B som supplement for et komplet flow.

**Ejerens svar 15/9:** Forslaget skal ligge klar til i morgen; ejeren hælder til B med hold-tast på PC og hold-knap på mobil. Anbefalet udgangspunkt: 1,5 sekund med synlig fremgang og øjeblikkelig annullering ved slip. Der implementeres ingen ændring i nat. A og C er bevaret som alternativer til sammenligning.
