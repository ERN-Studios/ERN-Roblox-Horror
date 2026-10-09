# LE-34: resterende tre afgrænsede lokale kandidater

Status: **afventer test/installation; endnu ikke implementeret**. Root har
reviewet og accepteret de scoped offline-forslag. B11-staging blev afvist før
native write, fordi Studio stod i Play. Root gendannede præcis før-mirrors;
manifest/native er uændret. Ejerens tilbagevenden til Edit, frisk native CAS og
efterport mangler. Dette er ingen implementeret batch eller Studio-rollback.
Forslagets konkrete ændringer i RoomDressing og én session-field-ændring
findes i [candidate-manifest.json](candidate-manifest.json), inklusive før-kilder,
fulde candidate-kilder, præcise hashes, metadata, compile-receipts og diff.

## `safeRect.reservePerimeter`

Kilde: `ServerScriptService/Level 3 Systems/Level 3 Worn Party Room Dressing.ModuleScript.lua:61-62`,
`Dress.Plan:89` og `Dress.Apply` fallback-placering `:404`.
Den private helper har præcis to callers; begge giver den fjerde argumentværdi
`false`. Parameteren kan derfor fjernes med den konstante eksisterende `WALL_INSET`
som inset, og de to false-argumenter fjernes. Boundary-, portal- og obstacle-
kontroller forbliver identiske. Ingen initializer/require/event/Instance fjernes;
beregningen læser kun tal, private konstanter og tabeller.

Afhængigheder: offentligt `Dress.Plan/Apply` via Worn Party Visual Adapter,
layout ServiceVariant/seed, ROOM W/D, eksisterende collider/hiding/CD/nav-exclusion
envelopes, private SERVICE/SIZES, helper.Place. Historiske tool-payloads og
manual authoring-suiten bevares; den private helper eksponeres ikke til dem.
Risiko lav; fjerner én altid-falsk intern gren/parameter, uden påstået målbar gevinst.

## Breaker-positionen, der overskrives straks

Kilde: samme RoomDressing `interactive:252-255`.
Breaker-grenens midlertidige `V(.98,6.70,.42)` bliver straks erstattet af
`V(.98,2.15,.42)`, før den første læsning i `carrier(...)`. Forslaget bruger
den endelige +2.15-vector direkte og fjerner den redundante assignment; den
eksisterende forklarende kommentar beholdes. `V` er uændret `Vector3.new`, en
immutable value-constructor, ikke et objektbygger-/callback-/require-kald.

Afhængigheder: BreakerPanel asset er allerede monteret på y=4.55; carrier/nav/
prompt-parts, +2.15 latch-offset, ProximityPrompt label/distance/hold/LOS,
participant-/generation-checks, SoundIds, noise, busy/cooldown og cleanup beholdes.
Claw/arcade-offsets ændres ikke. Lav risiko; fjerner én ubrugt vectorberegning.
Ingen real-asset visibility/pathfinding-/performancegevinst påstås.

## Privat `session.latchMode`

Kilde: `ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua:1373`.
Kun `latchMode = true` fjernes fra den lokale session-table initializer. Det
er en boolean literal uden sideeffekter. Feltet har ingen aktive/dynamiske
readers, key-reflection, captures eller exports; PuzzleManager holder sessionen
privat. `boxesDone/boxCount`, latchede levers, circuits, player inventory og
de øvrige session-felter/forbindelser forbliver identiske.

Authoring/test-reference: `tools/tests/test_level1_team_prompts.py:139` sætter
et falsk felt i sin egen syntetiske session; det læses aldrig. Den fixture
bevares som historisk udviklingsworkflow. Testporten substituerer den *aktuelle
produktionsinitializer* i hukommelsen for begge versioner og kører de samme
aktuelle fuse-/box-/lever-handlers. Ingen fixture/produktion ændres under prøven.
Risiko lav; én ubrugt boolean field fjernes, ingen multiplayer-/teleport-/dataændring.

## Testport og begrænsning

`verify_additional_locals.py` kører hele aktuelle RoomDressing-module og
`Plan/Apply` med engine services, Instance/Signal, transform og clock som offline
grænser. Før/efter: **1.477 assertions**, herunder 336 seeded variant/W-D/blocked-
cases per version, alle tre servicevariants, fuld authoring-graf/property/attrs/
placements/reports, breaker-inspection, duplicate/busy, generation-reentry,
deaktiveret participant-workflow, beskyttet plads fallback, manglende asset-fejl
og gentaget owner-cleanup/task-/connection-afkobling. Normalgrafen har uændrede
tre pockets/fem interaction-prompts; de eksisterende usynlige carriers/nav-parts
er bevaret. Grænse-fixturens synthetic asset Models gør ingen real-kit- eller
aktiv-round-navigationstest gældende.

Actual PuzzleManager initializer + de tre aktuelle prompt-handlers består
**21 checks før og 21 efter** med identisk output: teamdelivery, refused pickup,
multi-fuse stack, box/circuit updates, tom inventory, sidste box, lever-latch og
duplicate latch. Otte hele-source O0/O1 compile-porte består. Tre uafhængige
semantiske mutanter (forkert wall inset, forkert breaker-højde, inactive session)
fejler på den uændrede kontrakt. Canonical source/manifest er byte-uændrede.

Disse porte godkender de konkrete private locals, ikke en runtimefeature-
fjernelse. Root skal kontrollere frisk native Source/editor, scoped CAS og
metadata/manifest/parity før gennemførelse. Ved ny reader/caller eller source-
drift genvurderes closure. CORE-025/CORE-024 mangler stadig rigtig full-builder/
installer-kit-flow-test og er ikke godkendt af denne fixture.

`--verify-installed` kræver exact canonical/current manifest mod gemte candidate-
hashes og metadata; genkører porten på immutable før/candidate-kilder og skriver
en separat `installed-contract-check.json`. De fem oprindelige proposal-filer
ændres ikke. Denne tilstand skal først køres, når root faktisk har installeret.
