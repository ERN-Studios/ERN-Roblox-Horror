# Tabte sikringer og CD'er — samlet arbejdscheckpoint

Trello: https://trello.com/c/IpCKlAsz — nyt kort læst i det komplette 63-korts-inventory 10. september 2026 kl. 11:52 dansk tid. Spillere skal tabe medbragte sikringer og CD'er på gulvet ved dødsstedet, så andre kan finde og samle dem op.

## Afgrænsning og status

Dette er én gameplayrettelse med to eksisterende, adskilte item-systemer. Begge forslag er nu frosset i `fuses/` og `cds/` og har fået **samlet uafhængig kodekritik 9/10**, uden resterende nødvendig koderettelse. Kritikeren genkørte 92 sikringschecks + 387 CD-checks og fem målrettede negative kontroller; begge hele produktionsforslag compiler. Se `independent-review.md` og de to delreviews. **Der er endnu ingen installation, native accept eller publicering af kortet.** Artifactscoren må ikke bruges som en påstand om leveret gameplay.

- Sikringer: `ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua` ejer carried-count, prompts, den fysiske håndvisual og `PuzzleItems`-cleanup. Den nuværende kode bevarer antallet efter død. En forsinket relay-extraction kan også afsluttes efter dødsfaldet.
- CD'er: `ServerScriptService/Level 3 Systems/Level 3 Objective Controller.ModuleScript.lua` ejer de fem konkrete CD-identiteter, state, dropped pickups og cleanup. Death-drop findes allerede; placering, synlighed og karakterbinding efter ventetid kræver rettelser.

GameManager rydder ikke inventory ved almindelig død midt i et level. Den eksisterende runde fortsætter, og Emergency Re-entry kan skabe en ny karakter i samme runde. Derfor skal en tabt genstand blive liggende i den aktive verden, mens den dødes inventory og håndvisual tømmes. Ved rundens afslutning skal systemernes eksisterende cleanup fjerne drops og forbindelser. Dette kræver ingen fælles GameManager-ændring.

## Samlet accept

1. Tab kun det antal/den identitet, som spilleren faktisk bar. Dobbelt Died/CharacterRemoving eller en gammel callback må ikke oprette flere kopier eller påvirke en ny runde/karakter.
2. Brug dødsstedets gulv, når det er tilgængeligt. Et fald i et hul eller et utilgængeligt punkt kræver et bekræftet, tilgængeligt gulv i nærheden; en rå position i luften er ikke et gyldigt recovery-punkt.
3. En anden levende deltager skal kunne se og samle de tabte genstande op med den eksisterende servervaliderede prompt. Samtidige pickup-forsøg skal have én vinder. En død spiller eller en ikke-deltager må ikke samle op.
4. Saml op, dø igen, og genopliv: behold genstandenes antal/identitet uden genoprettelse af tidligere inventory. CD'ernes allerede-indsamlet-progress må ikke øges igen ved recovery. Sikringernes eksisterende entity-objective-target skal fortsat kunne pege på en tilgængelig sikring.
5. Afprøv den forsinkede sikrings-extraction, flere genstande tæt på væg/hjørne, en karakter udskiftet under deferred binding og fuld round-cleanup.

Actual-source tests og helfilskompilering er kodebevis. Synlighed, gulv-/vægplacering og faktisk pickup med en anden spiller kræver separat native kontrol; de må ikke udledes alene af fixtures eller en frisk MCP-require med egen module-cache.

## Installation og publicering

Ejeren har valgt kodearbejde, mens vedkommende bruger computeren. Ingen native input eller Studio-installation udføres i denne forberedelse. Den tidligere Continue-rettelse er allerede installeret, men mangler sin afsluttende test og særskilte mouse-publicering. Den afsluttes først, så dette kort ikke bliver blandet ind i samme release.

Læs derefter de aktuelle Studio-kilder, sammenlign de to frosne baselines og anvend kun de gennemgåede ændringer med den eksisterende `ScriptEditorService:UpdateSourceAsync`-workflow. Bevar øvrige upublicerede/udenforliggende ændringer. Begge item-halvdele hører til én feature og skal accepteres sammen med uafhængig score mindst 8/10 før deres egen mouse-publicering. Trello og den afsluttende Discord-announcement må først beskrive dette som leveret efter observeret publicering.
