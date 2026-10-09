# Frisk Studio-kildeaudit

Alle syv live Source/editor-par matcher direkte. Source SHA256 er verificeret fra fuldtekst for alle syv, ved at kombinere fire komplette objekter fra første capture med tre komplette objekter fra scoped re-audit.

**Samtidig repoændring:** seks scripts matcher stadig repo byte-for-byte og efter LF-normalisering. FlashlightController blev ændret af Shop HUD B2-arbejde under rapportskrivningen: live capture 41429 bytes/f0666fe6 mod aktuelt repo 37276 bytes/b1b1322a. Det er fremmed WIP, som skal bevares. Den må ikke overskrives af en mirror-pull. Lys-prefix, mate-loop, warning-blink og toggle-blok er identiske; diffen ændrer LIGHT-cell mount/input/layout/readout og UI-lifecycle. Ingen lystuning/raycast/CFrame-algoritmeændring fundet. Dette er repo/Studio-drift efter capture, ikke en live Source/editor-konflikt.

**Første export var afkortet:** fresh-audit.txt er 100015 UTF-8-bytes og ender midt i L4 Round Client med ... (truncated). Hele dokumentet er ugyldig JSON. Kun de fire komplette scriptobjekter før afkortningen er brugt. De tre sidste er fuldt genlæst fra gyldig remaining-audit.txt; intet manglende indhold er gættet. Separate Edit-captures er ikke ét atomisk place-snapshot.

| Script | Source-bytes | Aktuelt repo | Editor==Source | Source SHA256 |
| --- | ---: | --- | --- | --- |
| StarterPlayer.StarterPlayerScripts.FlashlightController | 41429 | HUD B2 WIP drift | true | f0666fe69f40ecfaa843865aecd432b30830daeeeee8652c480e69b8308d6c04 |
| ServerScriptService.FlashlightSync | 6494 | Exact | true | 6a6dedd4b3de72d8ad729b29c7eb56a1e82b00700913f1ec0d62568b8978d06b |
| ReplicatedStorage.FlashlightProfiles | 3110 | Exact | true | 4c2db65af38dd00092ab2af74d670b22fd5af9a1d3cf1e80af95fd5ffba4a230 |
| StarterPlayer.StarterPlayerScripts.SpectateController | 20374 | Exact | true | 4d9b3a3db6f6357ed3dac228e616ef18744b241c416e6c5c6e4ee17981d2cd92 |
| StarterPlayer.StarterPlayerScripts.Level 4 Round Client | 47349 | Exact | true | 61a901c10210b70fa327cd9f567d971d6c9a7cf150d77961d8fc732e7cfc5e19 |
| StarterPlayer.StarterPlayerScripts.Level 4 Lighting Controller | 14043 | Exact | true | 69fcca821e75670ad2725c326933556a6e7263b4ddbaf4b5b06c6d8acd442975 |
| StarterPlayer.StarterPlayerScripts.Level 2 Lighting Controller | 6312 | Exact | true | ba4a5882c4a266f76bbe96abacee3655e28be023686ef006502516993ac58b66 |

Captured Studio Source canonical SHA256 matcher manifestet for alle syv. Det aktuelle Controllers repo-hash matcher ikke manifestet, fordi fremmed WIP er kommet siden. Ingen mirrors eller manifest er ændret af denne audit.

Place 131311258779917; universe 10559217407. Properties: LightingStyle=Realistic, PrioritizeLightingQuality=true, StreamingEnabled=true. Technology og StreamingMin/TargetRadius er unreadable. Editor-SHA er ikke særskilt eksporteret; editorparitet bygger på direkte live string-sammenligning. Ingen native place-backup og ingen Play/render-pass påstået her.

Råaudit og fulde hash-/capturemetadata ligger i resh-source-audit.json og play/fresh-audit.mcp.json, play/compact-audit.mcp.json, play/remaining-audit.mcp.json.
