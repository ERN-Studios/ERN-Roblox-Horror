# Forslag: 20 % mindre bloom i lobby og alle levels

Kun offline-kortlægning, ingen runtime-/Studio-ændring. Ejerens nye instruktion autoriserer en lille generel bloom-reduktion eller sammenlignelige screenshots. Forslaget ændrer kun `BloomEffect.Intensity`; Size, Threshold, Lighting exposure/ambient og håndlygtens lys holdes som de er. Graphify blev brugt som kort; kildehenvisninger er fra aktuelt checkout.

## Writers og mindste permanente ændring

| Område | Writer/effect | Baseline → 80 % | Lifecycle og patchsted |
| --- | --- | --- | --- |
| Lobby, Level 1, sandsynligvis Level 5 | Ingen runtime-kildewriter til Bloom intensity fundet i RoundUI, GameManager eller Level5PreviewAccess; arver place-data i Lighting/evt camera | **Live native Intensity × .8**, nuværende værdi ukendt | Frisk Edit-audit skal først opliste alle BloomEffects i Lighting og camera: exact path/class/Enabled/Intensity/Size/Threshold. Patch kun de identificerede baseeffekter med frisk property-CAS; registrér før/efter. Repoets kildefiler er ikke en mirror af native Lighting-properties. Level 5 skal bekræftes live. |
| Level 2 gamle round | `Level 2 Client Bloom` i Level 2 Lighting Controller | NORMAL .085→.068; EXIT_OPEN .11→.088 | Direkte writes 113/123, reapply .75 s. Inherited `Lighting.Bloom` undertrykkes ved entry og Enabled restaureres ved exit; ingen Intensity-restoration. Source ændres ved begge targets. |
| Level 2 new-map preview | `Level 2 New Map Bloom` i Level2BlenderPreviewButton | Resolved `GradeBloom` × .8; default .5 giver .4 | GRADE-row 86; `applyGrade` 144–151 læser **modelattr først**, fallback default. Skaler kun den resolved Bloom/Intensity-række efter typekontrol. At ændre default .5→.4 alene overser en eksisterende GradeBloom-override. Grade reapply .75 s; egne Grade/Bloom deaktiveres ved exit og inherited effects' Enabled restaureres. |
| Level 3 | `Level3ClientBloom` i Level 3 Lighting Controller | Locked .08→.064; unlocked .11→.088 | `tween(bloom,.48,{Intensity=...})` 874–878; blackout/completion kan disable Bloom. Exit tween til0 (923) forbliver0, og inherited Enabled restaureres. |
| Level 4 | `Level 4 Client Bloom` i Level 4 Lighting Controller | Preview/On/Failing .85→.68; Off .5→.4; PoweringUp1.6→1.28; Finale1.1→.88 | Mindst to ændringer: initial `BLOOM.Intensity` .85→.68 (109), og final writer `bloom.Intensity = current.Bloom * .8` (292). **Behold rå POWER_GRADES/current.Bloom** for at undgå dobbelt skalering. Dette dæmper alle dynamiske power-state transitions, ikke kun Preview. Follow hvert .25 s; inherited effects undertrykkes/reapply .75 s og Enabled restaureres ved exit. |
| Level 6 | `Level6ClientBloom` i Level 6 Lighting Controller | Locked .08→.064; unlocked .11→.088 | `tween(bloom,.48,{Intensity=...})` 1009–1013. Blackout/completion disable; exit restoreInheritedEffects og eget Bloom disabled (1025–1058). |

L3/L6 init opretter/genbruger BloomEffect og sætter kun `Enabled=false` (75–83); intensity før første tween kommer derfor fra native eksisterende instance eller engine-default. En 20 % targetændring giver ikke nødvendigvis præcis 20 % forskel i den første .48 s af allerførste entry. Aflæs før entry; hvis en streng proportionel transition også skal dæmpes, skal den verificerede initværdi skaleres én gang. Et ukendt default-tal må ikke antages eller gentagne gange multipliceres ved entry.

Level 4 tools/level4_blender/Level4LightingController.client.lua er et historisk installationstemplate, ikke en ekstra live writer. Skift ikke dette eller builder-assets blot for at patche den aktive Studio LocalScript; eventuel template-paritet kan registreres separat.

## Eksempler på de to dynamiske patchpunkter

L4, existing final-write-linje:

```lua
bloom.Intensity = current.Bloom * .8
```

L2 new-map, lige efter resolved-value/typecheck i `applyGrade`:

```lua
if row[2] == "Bloom" and row[3] == "Intensity" then value *= .8 end
```

Det respekterer aktuelle og senere GradeBloom-modeltargets og ændrer ikke fx atmosphere glare eller lysenes Brightness.

## Frisk audit før senere write

Udvid scoped Source/editor-audit til **Level2BlenderPreviewButton**, **Level 3 Lighting Controller** og **Level 6 Lighting Controller** (ikke med i første 7-script audit). L2 legacy/L4 Lighting var med og matcher det tidligere capture; de skal stadig genlæses ved CAS-write efter næste grant. Oplist alle native BloomEffects i både Edit og Client, med exact path/class/properties og hvilke der er aktive i lobby/L1/L5. Læs new-map modelens GradeBloom-override; modelattrs findes ikke nødvendigvis i source-only mirror.

Brug eksisterende writers fremfor en ny per-frame global Bloom-loop: ellers konkurrerer den med deres tweens/ownership/restoration eller kan nedskalere samme value flere gange. Ingen Bloom-fix må beskrives som bevist løsning på torch-flicker, før den konkrete før/efter-sweep viser årsagssammenhæng.

## Sammenlignelige screenshots

### Allerede observerede Play-værdier og Level 5-usikkerhed

`play/L1-high-bloom-on-valid.txt` registrerede `Lighting.Bloom` Enabled=true og Intensity=1 i alle 25 Bloom-observationer (0–1.46667 s): den konkrete 80 %-variant er 0.8. `play/L4-high-bloom-on.txt` registrerede eget L4 Bloom Enabled=true og Intensity=0.5 i alle 98 Bloom-observationer (0–5.93333 s): Off-state-varianten er 0.4. Dette er de faktisk fangede Play-states, ikke en frisk Edit-/lobby-baseline. Bloom-observationernes tidsvindue er forskelligt fra frame-probens 90 frames; det må ikke rapporteres som samme målevarighed.

`RoundUI` 442–450 læser `Level5LightingOwned`, men checkout indeholder ingen Level 5 Lighting Controller. Det er evidens for en mulig live-only L5-owner, ikke bevis for at L5 blot arver native Bloom. Næste grant skal opliste live Script/LocalScript/ModuleScript-navne og læse eventuel L5-owner Source/editor før en påstand om alle levels eller et L5-patch. GameManager, MazeGenerator, RoundUI og Level5PreviewAccess har ingen fundne Bloom-intensity-writes i den aktuelle source; deres globale lighting-grades skal ikke ændres for denne bloom-opgave.

Først current baseline og 0.8× med præcis samme kamera, viewport, device/quality, level/power-state og lysbestand. Giv dynamiske transitions tid til at falde til ro og log faktisk Bloom intensity ved hvert billede; især L4 PoweringUp er højere end On. En valgfri 0.9× variant er en endnu mildere ejerbeslutning, ikke ekstra implementering. Alle midlertidige runtime overrides skal restaureres samme kald eller ved Stop. Permanent CAS først efter frisk source/property-baseline og efter næste tildelte lås.
