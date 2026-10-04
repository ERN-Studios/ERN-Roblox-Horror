# Nattens leverance — 16. september 2026

## Udgivet

Roblox **v1907**, 16/9 kl.00:10 dansk tid, bekræftet i Creator Dashboard med
Show published only. V1906 udførte den historiske import; v1907 fjerner dens
midlertidige servermodul. Claude/Fable-manageren og Opus-agenterne udførte
hovedimplementeringen; Codex overtog ved Claudes sessionsgrænse og gennemførte
assets, rettelser, integration, kontrol, import og udgivelse.

- Fysisk shop med 12 genererede/importerede textures og eksisterende produkter.
- Fælles UI-stil, mobiltilpasning og rettede overlap i shop, skjul og exit-guide.
- Tydeligere Level1-teamvejledning og retningsskiftende strøm i kablerne.
- Blender-animeret skjul under borde med korrekt placering og oprydning.
- Rettet fastlåsning i Level2 pool-entity-navigation.
- Gratis udvikler-respawn i den almindelige respawn-prompt.
- Større centreret supporter-tavle og mere mættede lobbyfarver.

## Køb og leaderboard

**44 køb,39 spillere,21.207 Robux.** Alle39 live-profiler er læst tilbage;
alle40 oprindelige kvitteringer er bevaret. Ingen ændring af tokens,
opgraderinger, rettigheder eller øvrige ejendele. Importens live-claim viser
Done=true,Applied=44,Failed=0 og inkluderer succesfulde leaderboard-skrivninger.
Fremtidige developer products registrerer faktisk CurrencySpent; nye
pass-/private-serverkøb kræver fortsat salgseksport for præcis historisk pris.

CSV, køberdata og importmodul er kun gemt i den Git-ignorerede _local-mappe.
Se publication-and-import.md og leaderboard-reconciliation-proof.md.

## Kontrol og resterende begrænsning

122/122 scripts kompilerede før udgivelse; det ene midlertidige importmodul
er bagefter fjernet. Fokuserede checks for køb, shop, prompts, kabler, animation,
palette, respawn og navigation bestod. Native Studio-kontroller omfattede
desktop/telefon, Level1-fuse→box→lever→exit, hiding/leave/død/fallback samt
Level2-jagt. Live-spillet indlæste den nye lobby og shop.

Den brede ældre UI-suite havde gamle fixtures; den er ikke rapporteret som
fuldt grøn. Konkrete reproducerbare layoutfejl blev rettet og genkontrolleret;
se native-ui-triage.md og de relevante native-rapporter.

**#16 forbliver Testing:** faktisk teleport/MemoryStore med 2–6 samtidige
live-spillere, opt-out, manglende ankomst og disconnect/rejoin kræver flere
live-klienter. Lokal continuation beviser ikke denne transport. Ingen ny fejl
er observeret, men testen er ikke udført. Derfor er pc'en ikke slukket:
ejerens betingelse om, at alt er færdigt først, er endnu ikke opfyldt.

## Trello

Done: #36,#78,#80,#81,#82,#86,#90,#98,#99.
#88 har fået den godkendte eksisterende shop; nye produkter afventer review,
så kortet står åbent. #18/#24/#71 var afsluttet efter ejerens bekræftelse.
#16 er Testing. #17 controller-QA er udskudt efter ejerens besked.

Udskudt: #69 Discord,#79 lyd,#87 udsalg. Ingen udsalgsstart/-planlægning.
Ideas og Before big adsspend er ikke sat i gang.

## Til gennemgang i morgen

- FORSLAG-TIL-MORGEN.md: rewards, gratis dagligt hjul og mulige nye items.
- BACK-TO-LOBBY-FORSLAG.md: hold-tast på PC/hold-knap på mobil.

Forslagene er ikke implementeret.

## Backup

Fuld native Studio Download a Copy:
_local/trello-20260915/BACKROOMS-published-v1907.rbxl (9.247.533 bytes).
Kildekode, assets og kontrolrapporter er gemt lokalt. Tre eksisterende
Level2-audiofiler er bevaret uændret fra nattens udgangspunkt.

Automatisk overvågning er sat på pause, og den midlertidige texture-server er
stoppet. Ingen shutdown er planlagt.
