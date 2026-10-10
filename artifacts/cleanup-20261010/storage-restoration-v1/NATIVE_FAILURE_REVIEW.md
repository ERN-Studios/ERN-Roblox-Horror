# Native V4 fejlede sikkert ved den første setter

**S19 forbliver afventende; V4-opskriften består ikke.** Den faktiske Studio-rapport fra 08:18:37Z afviser den første testejede `Bone.CFrame` setter-verifikation. Den rå historiske recovery-port forbliver også fejlet. Dette er ingen godkendelse til native packagefjernelse.

Reviewet følger SHA-kæden fra de frosne Lua-kilder gennem den faktiske MCP-response, Roots uændrede completion-bytes og receiverens `recipePassed=false`. Baseline bestod med 213 friske Source/editor-/identity-/metadata-pins, 52 ServerStorage-rødder og 416284 live descendants. Frosne kilder og fem historiske inddata er stadig byte-eksakte.

Setter-kaldet returnerede, hvorefter den kombinerede assertion `copy.CFrame == wanted AND after12 == spec12` fejlede. Der var ét forsøg og én returneret assignment; det betyder ikke, at værdien blev gendannet eksakt. Den native completion registrerer hverken after-komponenterne eller de to predicates hver for sig. Vi kan derfor ikke udpege komponent/delta eller fastslå normalisering som årsag. Første target kan udledes fra den pinnede arrays rækkefølge som `TEMP_PipeEntityValidation.PipeEntity_LocalPreview.RootPart.Root.Hips.LeftUpperLeg`; receiptet registrerede ikke selv target. De gamle DS R21-forskelle må ikke præsenteres som dette forsøgs after-setter-tal.

Alle 23 skabte/adopterede testrødder blev destrueret, nul var tilbage, og egen lease blev frigivet. De afsluttende guards bekræfter uændret original native archive samt alle 213 Source-pins; Source-/original Parent-/mode-writes er nul. Der er ingen autoritativ regression observeret af disse guards og ingen original rollback at anvende. Der blev ikke gennemført fire setters, fuld efter-supplement-verifikation, anden genåbning eller native transfer. De 3.167.424 checks og testens varighed er ikke en gameplay-/performance- eller recovery-pass.

Bevar alle held-originaler, raw archive/facts, det tidligere raw-only FAIL, frosset V4, denne faktiske fejl og receiverens FAIL. Ændr ikke tolerance, baseline eller setterlisten; prøv ikke native V4 igen. Fortsæt uafhængige afklarede oprydningskandidater. S04's fem pakker har fortsat deres egne manglende gameplay-/multiplayer-/streaming-porte.

En mulig senere årsagsdiagnostik er kun et forslag: højst én ny, uparentet Bone, fire pinnede wanted-værdier, alle 12 expected/wanted/after-tal med `%.17g`, separate equality-predicates og præcise differing indices. Den må hverken bruge DS, originale Bones, levende parents eller originale setters og skal have friske originale guards samt cleanup på success/throw. En fejl dér kan afgrænse setter-stien; et match beviser ikke den deserialiserede hierarkis recovery. Ingen diagnostikkode er oprettet eller eksekveret her.

Maskinlæsbar kontrol, præcise inddatahashes og native evidence findes i `NATIVE_FAILURE_REVIEW.json`. Reviewet foretog nul Studio-kald og ændrede ingen originaler, frosne kilder, tidligere kvitteringer, manifest, index eller commits.
