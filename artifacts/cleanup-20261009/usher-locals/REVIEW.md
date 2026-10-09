# LE-32: tre private Usher-state-rester

Status: **afventer test/installation**. Offline-forslaget er afgrænset og består,
men root skal have ejerens tilbagevenden til Edit, frisk native Source/editor-CAS
og efterport. Ingen af disse tre locals er fjernet i Studio eller canonical repo.

Kilde: `ServerScriptService/Level 4 Systems/Level 4 Usher Controller.ModuleScript.lua`.
Præcis diff, immutable før/candidate-kilder, hashes og metadata findes i
[candidate-manifest.json](candidate-manifest.json).

- `targetReason` er privat declaration + én write ved :41/:676, aldrig read/capture/export. Fjern kun bindingen og assignment. **`local newTarget, reason = chooseTarget()` og reason-baseret Chase/Stalk-logik beholdes.**
- `nextThinkAt` forekommer kun i den private nul-initializer ved :43. Fjern bindingen og dens tilsvarende nul; den virkelige `Usher.Start`-Heartbeat accumulator, `C.ThinkSeconds`, `nextHopAt` og `nextReplanAt` beholdes.
- `stunUntil` forekommer kun i nul-initializer :44 og Stop-reset :927. Fjern begge binding/writes og deres respektive nuller. **Aktivt `beamTime`, `stunCooldownUntil`, hold-stun, 50-stud retreat og Stun-payload beholdes.**

Alle fjernede expressions er nil/nul literals eller et ubrugt lokalt copy af
reason; ingen initializer-kald, Instance/property-/attribute-/remote-sideeffekt
eller callback fjernes. Der er ingen refleksion over disse lokale bindings.
Risiko lav; reducerer misvisende privat state og unødvendige writes. Ingen
målt FPS-/memory-/navgevinst påstås.

Callers/closure: `Level4RoundGenerator` kræver Usher og bruger Start/Stop sammen
med LightDirector/Objectives. Objective Controller bruger Activate/Finale.
Usher's faktiske Start/Heartbeat, nav-graph, NoiseRegistry, PlayerProtection,
DeathAdvice, `UsherMotion`/ClientEvent/Jumpscare, beamer/battery-attributter,
proxy diagnostics og sessions/capture-leases er uændrede. DevCheats/debug-
placeringsworkflow og Level 4 Test Suite bevares.

`verify_usher_locals.py` kører verbatim actual state declarations,
`chooseTarget`, `think`, `setState`, `setBeamers` og `Usher.Stop` ved kontrollerede
service/private-helper-grænser. **59 assertions** før/efter har identiske state/
attribute/event/path/hop-requests. Holder/sight/noise/finale target modes,
recent noise search, windup/capture-request, flashlight held-stun/cooldown,
retreat-request, invalid round, Stop/capture-cancel/connection teardown og
Stop-reentry indgår. Fire hele-source O0/O1 compile-porte består. To semantiske
mutanter (mistet reason-baseret target-mode og fjernet aktiv cooldown) afvises
af uændrede assertions.

Testen er en **actual-function offline contract**; body/perception/nav/physical
hop og capture-lease-implementering er eksplicit kontrollerede grænser. Den
påstår ikke fuldt live-round-flow, native multiplayer/streaming eller real
capture/respawn-test. Der er ikke ændret gameplaykode i disse grænser, men
root skal stadig gennemføre frisk native/metadata/parity/efterport ved install.

`--verify-installed` kræver præcis installed candidate + current manifest,
genkører samme immutable før/candidate-port og skriver en særskilt
`installed-contract-check.json`; oprindelige tre proposal-filer bevares.
