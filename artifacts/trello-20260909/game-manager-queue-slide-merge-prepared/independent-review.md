# Uafhængigt integrationsreview

**9/10 for den forberedte kildekodekomposition. Ingen resterende mergeblocker fundet. Dette er ikke native accept eller publicering.**

De særskilte forslag til længere slide og fuld lobbycirkel har hver fået 9/10 prepared-review. Jeg har nu også læst hele `prepare_merges.py`, de præcise frosne inputs, samtlige variant-hashes samt begge `validation-merged.json`-rapporter mod den endelige GameManager. Baseline er den allerede installerede, men endnu upublicerede Continue-revision `3615b6a3ca5eb8dde3acdcc7c4f03ed674b5cc84641bce6ed07670e67c3e5d58`.

Rootens algoritme kræver entydige kontekstblokke, frosne fulde inputhashes og uændret faktisk baseline. Alle otte kombinationer og 15 anvendelsesrækkefølger giver samme bytes for samme kombination. Den omvendte anvendelse genskaber hele Continue-baseline. Scriptet skriver kun integrationsartifacts.

Jeg udførte desuden en selvstændig kontrol i `independent_verify.py`, som ikke bruger denne hunk-/SequenceMatcher-algoritme: den anvender de to featureejeres smalle transforms og indsætter den nøjagtige oprindelige ESP-commandbranch fra det første ESP-forslag. Alle otte varianter og 15 rækkefølger matcher de gemte outputs. Fjernelse af den oprindelige ESP-branch fra hver relevant variant giver præcis den tilsvarende variant uden ESP. Det bevarer den tidligere reviewede developer-gate, svar til kun forespørgeren og de nye Continue-, slide- og circle-områder byte for byte. Både `slide-circle` og `slide-circle-esp` er genkompileret som hele scripts; faktisk runtime er stadig uændret.

Den endelige kombination er:

| Del | SHA-256 |
|---|---|
| Kun slide over Continue | `241d8ad4c2ccb70a7d3f62c7ef3a05b7909500723725019a52ac44a067df0219` |
| Slide + circle over Continue | `d6b71c1c69fc0d7f9836ccc577192b408232e6e8a7c33601a27fc823ca8a46db` |
| Slide + circle + ESP over Continue | `f006dda5f63464af3c3f7a69925a4276bcbfa19c4d8ad57ced514db6663f152d` |
| Separat slide-WorldBuilder | `a3a41d76f6dc6d13d782cb5dab5595757a5cd9b1d1b440f6605f310c56bf983d` |

Begge gemte override-rapporter angiver nøjagtig f006…-hash: 433 actual GameManager-checks, 7.787 geometrikontroller, 61.269 aperture-checks og to slide-negative kontroller; 257 circle-checks og tre negative kontroller. Disse root-udførte kombinationstests er læst og matchet mod den aktuelle fil. Jeg har tidligere i dette review selv genkørt begge standalone-suiter. Den uændrede Builder-geometri er derfor ikke gentestet endnu en gang under merge-reviewet. Kildebevarelsen erstatter ikke de særskilte gameplaytests eller de stadig udestående native observationer.

Store-kompositionen er også gennemgået: rootens `store-proof.json` viser, at ESP og de to korte upgrade-tekstrettelser kan anvendes i begge rækkefølger. Min uafhængige kontrol erstatter direkte de præcis to aftalte tekstlitteraler i både nuværende Store og ESP-Store; resultatet matcher hver frossen copy-variant byte for byte. Efter copy skal ESP derfor bruge Store `88f25ffed330b3786c2638a437332e3a4cff68a53475a4ae115a15dae30dcbb6`, ikke den ældre 1ca…-variant, som ville gendanne den fjernede tekst. ESP's DevCheats forbliver `f16d6fc3f23fbd314f77498788eae3a08fb4698ba5160166064846f3eabd5aeb`.

## Særskilte release-trin

1. Afslut native accept og publicér den allerede installerede Continue først. Kontrollér den faktiske baseline efter dette trin; eventuelle nye kildeændringer kræver ny komposition, ikke blind kopiering af et helt ældre script.
2. Installér kun slidevarianten 241d… sammen med dens reviewede WorldBuilder a3a…; udfør kortets native entry/ride/cleanup, kildeaudit og særskilt publicering.
3. Installér derefter GameManager d6b… til cirkelkortet; bevar den accepterede slide og Continue. Kontrollér faktisk fysisk afvisning, fri plads/udgang/cancel og launch, og publicér kortet særskilt.
4. Når de øvrige foranstående kort, herunder upgrade-copy, er leveret, installeres ESP med GameManager f006…, Store 88f… og DevCheats f16…. Gentag kun relevante native ESP-kontroller, audit og dets særskilte publicering. Hvis rækkefølgen eller kilderne ændrer sig, vælg den dokumenterede tilsvarende kombination og verificér dens nye baseline først.

Ingen Studio-/UI-handling, produktionsændring eller Trello-mutation blev udført af dette review. Native begrænsninger fra begge feature-reviewnotater gælder fortsat, herunder circle's sikre afvisning af en helt blokeret kandidatliste og manglende faktisk flerpersoners slide-accept.
