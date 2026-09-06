# Prompt til Claude Fable 5.1 med Ultracode

Kopiér teksten nedenfor ind i en lokal Claude-session med adgang til G:\Roblox\MongoTV. Implementeringen findes nu som lokale ændringer; promptet kan køres sideløbende som read-only review. Codex ejer integrationen i Studio.

```text
Du er uafhængig kritisk reviewer på Roblox-spillet BACKROOMS: STAY QUIET.
Arbejd i G:\Roblox\MongoTV. Brug Ultracode til en afgrænset undersøgelse,
gerne én reviewer af livscyklus og én af fejltests. Ingen bred repo-audit.

Læs CLAUDE.md, HANDOVER-2026-09-05.md og
docs/TRELLO_IMPLEMENTATION_PLAN_2026-09-05.md.
Ejerens valg er: Runden starter først, når alle forventede tilsluttede
spillere er helt indlæst. Ved én fælles 60-sekunders loading-frist
afbrydes starten, hele holdet får fejlbesked og sendes tilbage til lobbyen.
Det er ikke 60 sekunder per spiller eller retry.

Opgaven er Trello-kort https://trello.com/c/DIktjy8U:
karakterindlæsning kan efterlade spillere uden brugbar karakter,
og en reserveret server kan opgive admission uden at sende dem hjem.

Kilde ved research var c5ffa2dcfd628f7cd92fb1d2de72225fc44643a3.
Graphify-grafen var ældre (e3904931) og underdækker GameManager.
Kontrollér aktuel HEAD og kilde; grafen er kun navigationshjælp.
Studio blev read-only auditeret: 101 scripts matcher repo, 0 drift.
Senere ændringer kan naturligvis have ændret det.

Undersøg især GameManager.Script.lua, Round Completion Routing,
Round Completion Runtime, Round Completion Test Suite,
Round Loading Runtime, Round Loading Test Suite, Round Entry Client,
RoundUI og SpectateController, samt fælles loader-brug i re-entry
og Level 2-overgangen. Find faktiske filnavne i checkoutet. Se også
tools/tests/test_round_loading_host.py når den er til stede, og
docs/TRELLO_IMPLEMENTATION_VALIDATION_2026-09-05.md for målte testresultater.

Stress-test denne retning med konkrete event-tidslinjer:
- Ét shared entry-flow validerer frisk/current Character, levende Humanoid,
  root og faktisk vellykket placering ved alle tre startveje.
- Én 60-sekunders deadline fra holdets loading på destinationsserveren
  omfatter admission/world build, global kø/lås, LoadCharacterAsync,
  klientens verden/gulv-readiness og placering; token/ejercheck afviser
  sene resultater. Rundeur/fjender frigives først når alle er klar.
  Bevar continuation-cohort og dens transportaftale; tidlig ankomst
  må ikke starte alene. Test grænsen ved 60 s og sene ready-signaler.
  Manglende forventet continuer er ikke automatisk et gyldigt opt-out.
  Helt indlæst betyder spilbart startområde/karakter/kritiske controls
  og assets, ikke at hele den streamede bane skal ligge i hukommelsen.
- Timeout starter ikke et overlappende engine-load og frigiver ikke
  StarterCharacter-låsen, mens en gammel operation stadig ejer den.
- Afbrudt gruppestart giver korrekt fejl og lobby-recovery uden at
  mutere den oprindelige roster under iteration eller kræve betalt re-entry.
- UI-fejl vises også når et efterfølgende lobby-avatar-load hænger.
- Afvist/tom admission får idempotent boot-fejlstatus; også senere
  PlayerAdded-arrivals sendes gennem eksisterende recovery.
- Eksisterende teleport-claims, retries, watchdog og verdenens levetid
  genbruges; opbyg ikke endnu et teleport-system.

Prøv at bryde dette med: engine-call der aldrig returnerer, sen succes
efter timeout/nyt forsøg, gammel Character efter API-fejl, spiller der
forlader under yield, manglende root, placering der returnerer false,
alle loads fejler, sen spiller efter boot-abort, og lobby-teleport
der enten kaster fejl, melder fejl dobbelt/sent eller aldrig svarer.
Kontrollér at tests driver produktionslogikken og ikke kun en kopi af den.

Hvis der endnu ikke findes et fix, review planen og angiv hvilke
kontrakter/testhooks implementationen behøver. Hvis fixet findes,
review den faktiske diff og foreslå målrettede fejltests.
Lever kun konkrete fund med alvor, fil/linje, udløsende rækkefølge,
observerbar konsekvens og mindste rettelse. Skeln mellem bekræftet
fejl og hypotese. Gentag ikke fund, som den aktuelle kode allerede løser.

Arbejd read-only: ingen kildeændringer, Studio-skrivninger, spilstart,
uploads, commits, pushes, publicering eller Trello-opdateringer.
En anden session ejer implementation og integration. Rapportér i chat.
Hvis Studio er utilgængeligt, fortsæt lokalt og angiv begrænsningen.
Påstå ikke, at rigtige teleports er valideret i Studio.
```
