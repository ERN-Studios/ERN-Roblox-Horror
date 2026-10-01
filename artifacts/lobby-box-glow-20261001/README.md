# Lobby purchase-box artwork lighting

The owner requested subtle glow because the newly replaced purchase images were
too dark on the ten lobby boxes. The live Studio ModuleScript was the baseline.
Only `ServerScriptService.LobbyShopDisplay` changed: one static artwork helper
and one call in the existing six-face loop.

Each face now has a noninteractive SurfaceGui with `LightInfluence = 0`,
`Brightness = 1.25`, `AlwaysOnTop = false`, a 256-square fixed canvas, and a
90-stud maximum distance. Its opaque ImageLabel uses the exact existing image
URL. Existing decals, cube geometry, accent lights, bobbing, product layout,
purchase IDs and purchase logic remain intact. No frame loop or new world light
was added; the existing accent lights provide the surrounding glow.

Actual Play checks found ten boxes and sixty artwork faces. All ten front
images were loaded and readable in the lobby. The initial image-load sample
had twenty-three loaded and thirty-seven pending hidden faces; it does not
establish simultaneous rendering of all sixty. Close, wide and oblique views
showed clear symbols, dark backgrounds and no visible face artifacts. Moving
the test player onto the existing Tokens20 plate opened its actual product
card; stepping away closed it. No purchase was invoked. Existing bobbing
remained active. Play was stopped afterward.

`native-scope-verification.json` proves that the exact approved two-span edit
is the only Source change, with Source/editor parity for all 205 scripts.
The 204 other Sources, 181 native roots and captured native properties/service
settings are unchanged after comparison-only normalization of that one Source.
The full before/after native snapshots remain local; reconstruction limitations
are recorded and reconstructed places were never uploaded or restored.

Creator Dashboard Version History confirms published version 2453 on October 1,
2026 at 11:14 AM local time. The open Studio's loaded `game.PlaceVersion` remained
2450; that value and the absence of a publish line in MCP Output are not proof
of a failed cloud publication. The authoritative receipt is under
`publication/`. Dashboard version history does not independently expose the
published ModuleScript Source hash; the exact Source hash was verified in Edit
and in the native capture before the publish action.

The Play log also contained animation-access and Level6 WaitForChild warnings
from unchanged components. This task does not claim multiplayer, broad
performance, other-level gameplay or asset-permission verification.

Git had no configured remote. Local task commits are separate from Studio
publication; there was no GitHub push. Unrelated repository files, including
the existing modified cathedral Blender file, were preserved.

Rendering evidence: `preview/before.png`, `preview/after.png`,
`preview/after-wide.png`, and `preview/after-oblique-interaction.png`.
