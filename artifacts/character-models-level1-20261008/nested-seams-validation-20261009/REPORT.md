Udvidet kun den isolerede `collision-candidate/test_collision.py`; ingen delt test eller production-source ændret i denne delopgave.

Fixturen placerer nu alle tre seam-navne både direkte på karakteren, i den faktiske `SuitGapFix`-folder og i en dybere folder med duplikerede navne. Den kontrollerer desuden sen nested replikering (inklusive to NeckSeamLiner), oprindelig transparens, oprydning og posefejlens fallback. Lignende navne, objekter uden BasePart-klassen og en uvedkommende nested UpperTorso skal være uberørte. De tidligere direct-body/fallback-checks er bevaret.

Regressionsbevis mod frosne kilder før nested-rettelsen:

- Server fejler check 26: nested/duplikerede seams bliver ikke fjernet.
- Klient fejler check 21: nested LeftShoulderSeamLiner forbliver synlig.
- Begge har exit-kode 1; logs er gemt.

Efter rettelsen:

- Final collision: 49 serverchecks + 61 klientchecks = 110 passer.
- Final marker/loading: 40 checks passer; 5/5 mutationer fanges.
- Final tint/helper/cache: 15 checks passer.
- Final feedback: 104 checks passer.
- Faktisk delt feedback-suite: 104 checks passer.
- Faktisk delt round-loading-host-suite: 98 checks passer.
- Alle tre endelige kandidater kompilerer med Luau `--null -O0`.

269 fokuserede Luau-checks passer på final-candidate. `validation.json` indeholder alle kommandoer og logs samt de forventede før-fejl. Rootens installerede mirror-hashes og de tilsvarende final-candidate-filer matcher før og efter testkørslerne:

- Visuals: `f279e4816d991f37b336c381a25feccc0b6dfc829d683a9a97841f70d615e156`
- Driver: `9ea59afae58b5bddfc9bf672af8a98303d6b8a7261d28701b97c5eb0359232cf`

Ingen Studio-adgang; ingen ændring af source, manifest eller kø/lås. Denne offlinekontrol supplerer rootens egentlige Play-QA.
