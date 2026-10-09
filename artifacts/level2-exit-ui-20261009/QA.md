# Objective og mobil-devmenu — færdig 2026-10-09

Installeret i Studio og det delte checkout, testet og læst tilbage fra frisk
`.Source`. Disse ændringer er ikke udgivet; ingen commit eller push.

- Level 2 viser kun **Find the exit**. Kompas, meter, rutetekst/hul-advarsel,
  pumpe-tæller og ekstra statusrækker er fjernet fra objective. Gameplay og exit
  er uændrede. Den eksisterende readiness-retry er bevaret med Level 2-gate.
- Objective er 20 % mindre: PC 288 px, touch 192 px, touch-bjælke 32 px,
  trykfelt mindst 44 px og tekst mindst 12 px. Baggrundsfladen er fjernet på
  både PC og telefon. Objective holder fuld opacitet efter sin indgangsanimation.
- SNEAKING og LOUD har ingen baggrundsflade. Deres tekst/prik og øvrige
  markørtilstande er bevaret.
- På telefon åbner fysisk objective-tryk den eksisterende Dev-menu for
  whitelisted devs. Den separate ZYNTRA // DEV-knap er skjult/deaktiveret, når
  det rigtige objective-trykfelt er tilgængeligt. Den vender tilbage uden et
  objective, ved skjulning og ved deaktiveret HUD. Lobbyadgang og PC J består.
  Ordinary-player expansion, ren QA-expansion og Level 4's notehandling består.
- Level 1's Mission Brief-knap/panel er fjernet. Frisk Studio-kontrol bekræfter
  manglende label/panel, afkoblet hjælpetast og fortsat fravalgt automatisk briefing.

## Verifikation

2.110 checks består mod de endelige repo-filer: objective-receivers 183,
fælles RoundHud 382, stamina 74, lokal Round HUD 497, QA-gendannelse 90,
dev-knap/trykfelt 107 og eksisterende ZyntraStore 777. Dev- og modaltestene
bruger det rigtige DevAccess-modul; almindelige/preview/negative bruger-ID'er
afvises. De nye regressionscases fejler på den indfangede gamle kilde.
Store-harnessens eksisterende modalfixture fik kun to manglende fake-API'er;
ingen assertions er fjernet. Fem endelige scripts kompilerer med officiel
Luau 0.737 ved `-O0`. Se `final/tests.json`.

Installationen brugte frisk native drift-audit, exact-source CAS gennem
ScriptEditorService, fuld readback og scoped sync-manifest. Frisk endelig
readback af alle fem ændrede Sources matcher repo; se `final/source-proof.json`.

Native Play gik gennem den normale offentlige Level 2-kø 105 til den faktiske
Poolrooms-map med levende karakter, RoundActive, InRound og controls ready.
PC viste 288 × 51 px, 21 px titel, fuld opacitet og ingen baggrund/ekstra rækker.
Telefon viste 192 × 44 px, 12 px titel, 32 px visuelt kort, fuld opacitet og
ingen baggrund/ekstra rækker. Fysisk tryk på det faktiske Hit åbnede DevPhoneOpen
og den eksisterende Zyntra Dev L4-menu. QA-expand åbnede ikke menuen. Lukning
gendannede objective-ruten; knappen forblev Visible/Active/Selectable=false.
Native visibility/Enabled-toggle bekræftede fallback og gendannelse, og PC J
åbnede den samme menu. Ingen dev-grant/tuning/gameplay-kommandoer blev udført.

Telefonbilledet kommer fra Studio's rigtige **iPhone 13, landscape,
ActualResolution**, device 844 × 390, kamera-viewport 750 × 390. Den endelige
optagelse har native touch-input (Mouse/Keyboard=false), ingen ForceTouchUI
og ingen viewport/inset-fixtures. `phone-level2-final-dev-tap.jpg` er det
endelige billede; ældre phone-optagelser før installation viser den gamle knap.
Se `native/phone-live-objective-final.txt`, `phone-physical-dev-tap.txt`,
`phone-final-dev-touch.txt`, `phone-native-dev-fallback.txt`, `pc-j-opens-dev.txt`.

SNEAKING uden baggrund blev også vist gennem faktisk Ctrl-input. LOUD's
baggrundsfjernelse er dækket af den lokale 497-check suite; sprintforsøget i
den native kørsel viste ikke LOUD og regnes derfor ikke som native LOUD-bevis.
Level 4's særskilte notehandling er testet offline. Den eksisterende udvidede
touch-layout har 8 px overlap mellem nederste kant af header-hit og note-hit;
den fysiske note-prioritet i den kant er ikke målt i denne Level 2-kørsel.

## Afslutning

Play er stoppet. Simulatoren er tilbage på `default`, Edit-viewport 1413 × 556.
ForceTouchUI og QA viewport/inset-attributter er nil; CAS-objektet er væk.
Se `native/restored-edit.txt`. Shop UI's lås er frigivet efter denne kontrol;
andre låseoplysninger og fremmede køposter er bevaret.

Senere samme dag blev objective-header højrejusteret. Det nye scoped Source-readback og de nye screenshots ligger i ../objective-right-align-20261009/QA.md. Ovenstående readback er et snapshot fra før denne efterfølgende layoutændring.
