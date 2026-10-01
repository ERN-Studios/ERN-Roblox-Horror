# Level 6 ceiling lighting review

Read-only Codex review of the complete live Studio Level 6 Lighting Controller and the newly captured World Builder/Visual Adapter. This is source analysis, not a gameplay test.

The live controller applies a local grade only when `Level6SelectedLevel == 6`, `Level6LightingOwnedByController == true`, and the local player's `Level6InRound == true`. It captures and immediately restores the prior Lighting properties on exit. Normal indoor ambient is `(18,17,16)`; exposure is zero, external ambient and environment-derived fill are zero. The ordinary ceiling SurfaceLights emit downward; authored gateway PointLights already emit in all directions.

The smallest candidate is a normal Level 6 ambient lift of about 3–5 RGB units, with all grade, exposure, colors, fog, fixture settings, blackout and completion branches unchanged. That also lifts other unlit surfaces slightly, so it must be judged using matched normal-player room/corridor screenshots. If it visibly flattens wall/floor contrast, reject it and trial tiny upward fixture spill instead.

Upward spill could be created alongside each working fixture with its existing color and a low brightness/short range. The adapter transfers all light children from the legacy diffuser to the authored carrier. The controller's blackout/fade captures all descendant Lights, including late-streamed fixtures. Added lights must not be put on dead fixtures. This approach has extra light-render cost, potential ceiling hot spots near flush mounting, and changes to blackout light-list indices; source inspection does not establish acceptable performance or appearance.

Keep source writes against the fresh live Source/editor baseline. Do not change server/global Lighting defaults or Level 3 Sources.

Roblox's official documentation describes Ambient as affecting indoor/outdoor hue, exposure as camera exposure, and environment diffuse as environment-derived ambient. These support caution around broad grade adjustments; they do not prove the visual outcome of either candidate. [Roblox global lighting documentation](https://create.roblox.com/docs/environment/lighting). SurfaceLight has independent Face, Angle and Range controls. [SurfaceLight reference](https://create.roblox.com/docs/reference/engine/classes/SurfaceLight).

Required actual Play checks: matched representative party, service, kitchen, arcade and corridor views; ceiling tile/beam visibility at normal camera height; unchanged saturated wall/carpet colors; stable lighting without additional glare; ordinary blackout, recovery/completion suppression; returning to lobby restores its grade. Broader checks are only required if the implementation changes those paths.
