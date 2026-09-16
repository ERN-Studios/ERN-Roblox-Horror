# Daily Rewards — færdig grafik til Claude

Disse assets er genereret med den indbyggede imagegen, ikke af Claude.
Alle fire billeder har transparent baggrund og kan bruges direkte i ImageLabels.

- Token: 5-minutterskortet, 1 token.
- Speed potion: 15-minutterskortet, 1 potion.
- Entity shield: 35-minutterskortet, 1 shield.
- Gave: Rewards-headeren (og eventuelt det eksisterende Rewards-sideikon, hvis det skal matche).

Claude skal IKKE tegne eller generere erstatningsikoner. Brug de uploadede billeder.
Selve panelrammen, farvede kortbaggrunde, UIGradient, UIStroke, tekst, nedtællinger, claim-knapper, X og status/check er almindelig Roblox-UI. De skal bygges som responsive UI-elementer, så tekst og status kan ændres uden nye billeder.
Ingen tekst eller cooldown er bagt ind i PNG'erne.
Brug ScaleType.Fit og bevaret aspect ratio, undgå stretching og hård cropping. PNG'ernes luft omkring ikonet skal medregnes i den visuelle størrelse.
Token-kort kan have varm gul/orange baggrund, potion-kort cyan/blå, shield-kort lilla/grøn kontrast. Gaveikonet bruges ved en varm header. Hold belønningen stor og dominant.
Hvert kort viser belønning, tærskel (5/15/35 minutter) og aktuel serverstyret status. Bevar eksisterende claim/persistence. Ingen syvdages-streak eller nye belønninger.
Verificér indlæsning i en rigtig ImageLabel i Studio og faktiske desktop/mobil-visninger før publicering; et upload-ID alene beviser ikke runtime-visning.

## Uploadede assets

| Motiv | Roblox image | Lokal fil |
|---|---|---|
| token | rbxassetid://93116899475472 | assets/shop/rewards-token-v1.png |
| speed-potion | rbxassetid://120211340805188 | assets/shop/rewards-speed-potion-v1.png |
| entity-shield | rbxassetid://126728249949579 | assets/shop/rewards-entity-shield-v1.png |
| gift | rbxassetid://117126194981100 | assets/shop/rewards-gift-v1.png |

