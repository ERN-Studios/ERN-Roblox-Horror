# Friend Boost – rettelse og QA, 9. oktober 2026

Rettet og installeret i Studio. Ejeren bekræftede, at chippen viste **+0 %**, selv med en Roblox-ven i samme lobby.

Serveren genprøvede tidligere kun fejlede venneopslag ved join/leave eller rundestart. Et efterfølgende vellykket opslag ved rundestart kunne også opdatere cachen uden at opdatere lobbyens procent. Det kunne efterlade +0 % permanent i den lobby-session.

`ServerScriptService/FriendBoost.ModuleScript.lua` genprøver nu uafklarede opslag efter fem sekunder, opdaterer begge lobby-attributter efter opvarmning af cachen og behandler opslag gennem én worker. En versionskontrol af spillerlisten forhindrer, at et langsomt svar publicerer en forældet optælling efter join/leave. `Start` er idempotent. Der bruges Roblox’ aktuelle `IsFriendsWithAsync`; den gamle API svarede også korrekt i den native prøve og er ikke identificeret som fejlkilden. [Roblox API-dokumentation](https://create.roblox.com/docs/reference/engine/classes/Player#IsFriendsWithAsync).

Kun servermodulet og `tools/tests/test_friend_boost.py` er ændret som produkt/testkode i denne opgave. Klientens procentbinding virker allerede. Andre sessioners ændringer, herunder nyere Studio-kode i ZyntraMonetization, er bevaret.

## Verifikation

- **933 kontroller består** med både repoets payout-kilde og den frisk læste Studio-payout-kilde. Det er samme suite kørt med to kilder; tallene lægges ikke sammen. Luau-kompilering består.
- Den gamle, frisk læste serverkode **fejler** testen for automatisk genopretning: forventet én ven, faktisk nul efter et midlertidigt API-nedbrud og uden join/leave. Rettelsen består denne test samt samtidige opslag, join/leave under ventetid, genopretning ved rundestart og udbetalingsregler.
- Native Roblox API verificerer et kendt venskab. Det installerede modul tæller parret korrekt i en diagnostisk roster. Den anden rosterpost er en fixture; Play har **én rigtig tilsluttet spiller**.
- Med eksplicitte server-attributter viser den eksisterende PC-klient `FRIEND BOOST +10%`; touch-layoutet viser `FRIENDS +10%` og `FRIENDS +20%`. Teksterne er synlige og passer i deres tekstfelter. Dette kontrollerer binding og rendering, ikke en to-spiller multiplayer-session.
- Fixture-attributter og touch-override er gendannet. Play er stoppet; der er ingen midlertidig UI-fixture eller CAS-buffer i Edit. Outputloggen indeholder eksisterende lydadvarsler og ingen Friend Boost-scriptfejl.
- Frisk fuld `.Source`-readback matcher den installerede kilde. Den normaliserede SHA256 er `3ecdd96e368146fdfad94aaced595ec96ad26b89de2172f521aabdaa42e6cd0a`; rå Windows-fil med CRLF har SHA256 `b031f800fa6158d6feb8df47ec8095baa340e3b5f98a01dc2149128b2440119b`.

## Omfang og resterende dækning

En rigtig session med to tilsluttede Roblox-venner er ikke gennemført lokalt. Roblox cacher også definitive venskabssvar, så en ny venneforbindelse oprettet midt i en eksisterende session kan stadig kræve en ny server-session; automatisk genopretning her gælder fejlede/uafklarede opslag.

Boostet er fortsat +10 % pr. unik ven, og bonus-token kræver deltagelse i samme gennemførte runde. Fraktioner gemmes som hidtil; eksempelvis giver +10 % af to grundtoken 0,2 bonus-token, som akkumuleres frem til en hel token. Der er ikke ændret i udbetalingsformlen, sendt rewards i Play eller udgivet noget.

Detaljer: [server-fix/REPORT.md](server-fix/REPORT.md), [server-fix/PROOF.json](server-fix/PROOF.json), [install/audit.json](install/audit.json) og native logfiler i `native/`.
