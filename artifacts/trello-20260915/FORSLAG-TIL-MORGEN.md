# Flere grunde til at spille igen

**Forslag til din gennemgang. Intet på denne side er godkendt til implementering.**

Mit forslag er én flot **DAILY REWARDS**-fane med to tydelige dele: dagens spilletid og en gratis daglig belønning. De samme belønninger skal kunne ses ved butikkens fysiske terminal. Der skal være en grund til at gennemføre runden, også efter man har hentet dagens gave.

## Udgangspunkt i spillets aktuelle økonomi

- En gennemført bane giver **2 Research Tokens**.
- **1 token** køber en permanent **+5 % stamina- eller batteriopgradering**. Den aktuelle kode har ikke en stigende tokenpris pr. niveau.
- Der er heller ikke et maksimum for disse opgraderingsniveauer i den aktuelle kode. Et eventuelt loft kræver en særskilt beslutning med bevarelse af allerede købte niveauer.
- Entity Shield koster **5 tokens** for én gemt aktivering på **5 sekunder**.

Derfor anbefaler jeg få gratis tokens og mere samling/udseende ved de længere milepæle. Ti ekstra tokens om dagen ville alene kunne give +50 % til én kapacitet hver dag. Vi skal ikke ændre eksisterende spilleres køb eller opgraderinger for at få et nyt reward-system til at passe.

## 1. Progressive playtime rewards — #83

Tid opsamles gennem dagens aktive runder og gemmes ved leave/rejoin. Første version:

| Samlet spilletid den dag | Belønning | Hvorfor |
|---|---|---|
| 5 minutter | 1 Research Token | En hurtig, forståelig første belønning |
| 15 minutter | 2 forskningsstempler | Fremgang mod noget permanent kosmetisk |
| 35 minutter | 4 forskningsstempler | Større belønning efter en længere session |

**Forskningsstempler** er i dette forslag en enkel, synlig samlebjælke til et valgt kosmetisk mål, ikke en ekstra betalt valuta. Eksempel: 12 stempler låser en Zyntra-kuffert-/lommelygteskin op; næste skin kræver 18 nye. Spilleren vælger selv den næste belønning og ser den fra starten. Hvis du vil undgå endnu et progressionsmål, kan vi i stedet gøre de to sidste milepæle til faste kosmetiske delmål, men jeg vil ikke erstatte dem med store tokenbeløb.

Lobbyventetid tæller ikke. Kortvarigt stille ophold og legitimt skjul i en runde skal tælle; ren tastaturbevægelse må ikke være eneste aktivitetsmål. Ved længere AFK standses optjeningen uden at tage allerede optjent tid fra spilleren. Dagens belønninger kan hver hentes én gang, også på tværs af servere. Ingen tabt streak eller betalingsmulighed for at indhente en mistet dag.

## 2. Daily lucky wheel — #84, samme fane som #89

Mit forslag er et **Zyntra Supply Wheel**: en lille industrielt udformet forsyningsvælger i cyan og ravgul, med én gratis drejning pr. kalenderdag. Vis næste tilgængelige tidspunkt og gevinstlisten. Ingen køb af drejninger, tickets, luck boosts eller rerolls.

**Min anbefaling efter gennemgang med Claude:** start med kosmetiske forskningsstempler i hjulet: 75 % giver1, 20 % giver2 og5 % giver3. Så tilføjer dagens rewards kun **1 gratis token**, fra femminuttersmilepælen. Det passer bedre til de nuværende billige, permanente opgraderinger. Tabellen nedenfor er en mere generøs **alternativ variant**, hvis du ønsker tokens også i hjulet.

| Gevinst | Sandsynlighed |
|---|---:|
| 1 Research Token | 75 % |
| 2 Research Tokens | 20 % |
| 3 Research Tokens | 5 % |

Det giver i gennemsnit **1,30 tokens pr. drejning** (0,75 + 0,40 + 0,15). Sammen med femminuttersbelønningen er første forslag gennemsnitligt **2,30 ekstra tokens pr. aktiv dag**, ud over banegennemførelser. De tal er balanceforslag, ikke dokumenterede optimale værdier. Hjulet giver altid noget; ingen falske næsten-gevinster. En kort animation skal kunne springes over og respektere reduceret bevægelse/flashing. Resultatet gemmes før animationen, så disconnect ikke giver et nyt kast.

Ved30aktive dage svarer tokenvarianten til69tokens, cirka3,45af de nuværende20-tokenpakker. Sammenlignet med pakkepriserne svarer2,30tokens til cirka17–28Robux i katalogværdi pr.dag; det er **ikke** en prognose for tabt omsætning. Den anbefalede variant med stempler i hjulet holder tokenbeløbet på30pr.30aktive dage.

Foreslået nulstilling: **00:00UTC**, vist som en lokal nedtælling (02:00dansk sommertid /01:00vintertid). Optjent tid gemmes på tværs af dagens sessioner. Tilskuertid giver ikke ny optjening. En spiller, der står stille i et legitimt skjul, skal fortsat kunne gøre fremskridt; aktivitet skal vurderes med spillets tilstand og validerede interaktioner.

En gratis handling uden Robux eller købt valuta er adskilt fra betalte tilfældige varer i Roblox' regler. Jeg foreslår stadig synlige odds, fordi det gør belønningen forståelig. Hvis der senere ønskes betalte drejninger, skal den løsning vurderes særskilt. [Roblox: paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items)

## 3. Flere ting i butikken — #85 og den nye produktdel af #88

| Forslag | Første prisforslag | Præcis effekt og begrænsning | Min prioritet |
|---|---:|---|---|
| Route Marker Pack | 2 tokens | 3 pile, som holdet kan se. Højst 3 aktive pr. spiller, fjernes ved rundeslut. Viser kun den retning spilleren selv vælger. | Først |
| Flashlight Casings | 8 / 12 / 16 tokens | Permanent udseende, samme lys/batteri/rækkevidde. Kan prøves visuelt før køb. | Først |
| Speed Boost Potion | 3 tokens, én brug | Forslag: +10 % bevægelseshastighed i 6 sekunder, højst én pr. runde. Ingen stabling eller ekstra stamina. Afventer måling af jagterne, især den tætte Level 3-finale. | Test senere |
| Results Frame | 6 / 10 tokens | Permanent ramme på slutskærmen, ingen gameplayeffekt. | Lille opfølgning |

Jeg ville starte med **Route Marker Pack og tre casings**. Speed Boost Potion er relevant til kortet, men den kan ændre selve udfaldet af jagten. Den bør først komme ind, når effekten er afprøvet mod alle tre baners entities. Den må ikke gøre exit-finale eller skjul overflødigt. Hjulet deler ikke potions ud i første version.

## 4. En grund til en ny gennemspilning

Som senere forslag: **Zyntra Field Notes**. Én ny opdagelse pr. runde kan føje en kort illustration/tekst til en lille samling. Placér den langs eksisterende mulige ruter, aldrig som krav for at åbne exit. En færdig samling giver en kosmetisk titel eller casing. Det kan skabe variation i mazerne uden et ekstra level eller tvungen grinding. Det er et udvidelsesforslag til godkendelse, ikke en del af nattens implementering.

## Hvordan jeg ville frigive og vurdere det

1. Godkend først belønninger, tal og de konkrete produkter.
2. Byg én fælles fane og én gemt claim-mekanisme. Afprøv leave/rejoin, to samtidige servere, midnat, fejlet gemning og mobilvisning.
3. Udgiv i små trin. Se på hvor mange der spiller en ny runde, tokenoptjening/forbrug, wallet-størrelse og fuldførelse med/uden nye items. D1/D7 kan først vurderes, når de relevante dage er gået.

Roblox anbefaler at følge både valutaens kilder, forbrug og brugen af købte items og at vurdere et events forventede økonomiske effekt. De konkrete tal ovenfor er mit forslag ud fra jeres nuværende katalog. [Roblox: balance virtual economies](https://create.roblox.com/docs/production/game-design/balance-virtual-economies)

## Beslutninger til dig

- Er retningen med få tokens + kosmetisk samling den rigtige, eller ønsker du rene tokenbelønninger med en ændret opgraderingsøkonomi først?
- Skal første pakke være Rewards-fanen/hjulet og Route Markers + Casings?
- Vælg belønningsbudget: anbefalet1token/dag + kosmetisk hjul, eller den mere generøse variant med i gennemsnit2,30tokens/dag.
- Speed Boost Potion foreslås til separat balancetest før lancering.

**Kildegrundlag:** Trello #83–85, #88–89 læst 15/9/2026, det eksisterende token-item-forslag fra 14/9 samt aktuelle ZyntraConfig og ZyntraMonetization. Ideas og Before big adsspend er ikke sat i gang.
