# Objective højrejustering — 2026-10-09

Færdig i repo og Studio. Level-tekst, objective-titel og blå understregning deler
nu højrekant på PC og telefon, med den eksisterende sikre kantafstand.
På telefon ligger den inline tæller i venstre side, så titel og tal har hver
deres plads. Tekstbredder, højder, fontgrænser og 44 px objective-trykfelt består.
Kun RoundHud.Source er ændret; importerede templates er uændrede.

Layoutet sættes ved mount. Eventuelt cached FW_FitSize/FW_FitPosition nulstilles
efter gendannelse af den oprindelige tekstboks, så senere tekstændringer bevarer
den nye placering. Guide/status-rækker og deres handlinger er bevaret.

456 eksisterende checks består (fælles HUD 382, stamina 74), og den ændrede
kandidat kompilerer med officiel Luau 0.737 ved -O0. Ingen nye unit-tests.
Frisk native baseline matchede repo før installation. Installation brugte
exact-source CAS gennem ScriptEditorService og fuld readback. Endelig frisk
Source og scoped sync-manifest er verificeret i source-proof.json.

Native PC og telefon blev testet gennem den normale Level 2-kø 105, med faktisk
Poolrooms-map, levende karakter, controls ready og RoundActive. Teksterne passer
(TextFits=true), og Eyebrow/Title/Underbar flugter inden for 0.01 px:
PC x1382.2, telefon x734 i kamera-viewportets koordinater. Telefonens tællerboks
slutter x593.2, titel starter x598, så bokse har 4.8 px afstand.
Screenshots: native/pc-right-aligned.jpg og native/phone-right-aligned.jpg.

Telefonen var Studio iPhone 13, LandscapeLeft, ActualResolution844×390,
kameraviewport750×390. Endelig optagelse bruger native touch med Mouse og
Keyboard=false, ForceTouchUI=nil og ingen viewport/inset-fixtures.
Fysisk objective-tryk åbnede stadig den eksisterende dev-menu; lukning gendannede
objective. Den separate dev-knap var fortsat skjult/deaktiveret.

Play stoppet; simulator tilbage på default og Edit-viewport1413×556.
QA-attributter er nil, CAS-objektet er væk. Shop UI's lås frigivet.
Ingen publish, commit eller push. Se native/restored-edit.txt.
