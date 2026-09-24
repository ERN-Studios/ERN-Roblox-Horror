# Signal Architect and False Sun VFX art handoff

This folder contains new art for [developer-only suit card 141](https://trello.com/c/SYUaXHKQ) and [skin effects card 142](https://trello.com/c/IRLeRBcN). It does **not** contain game code or a Studio import. Both cards stay open until their game integration, live tests, and publication are verified.

## Signal Architect developer suit

`signal-architect-color.png` is the 2048 × 2048 RGB color map to apply to the existing `ServerStorage.HazmatSkin_*_20260924` canonical skinned body. `signal-architect.glb` is Meshy's unrigged retexture result for reference; **do not replace the canonical 24-bone rig with this unrigged GLB**. `signal-architect-preview.png` is the inspected Meshy front render: teal fabric, dark respirator and hardware, small copper shoulder details. The brief specified a practical premium engineer suit, not armor or a gameplay power.

Roblox group-owned Image ID **`137400739559825`** is the approved color map; use `rbxassetid://137400739559825` as its `SurfaceAppearance.ColorMap`. The Open Cloud [upload receipt](upload-receipt.json) records the exact SHA-256, creator group `1039373905`, and approval. Uploading the Image did not insert it into Studio.

The new color map uses the original UVs. The retexture GLB and existing `baseline-yellow.glb` each have 14,446 UV vertices and byte-identical UV accessors (SHA-256 `baacd178e7532b5a16b52440ba743897b06d3f6bb53c712806b8eeaf44662d33`). The canonical `baseline-rigged.glb` has 14,463 UV vertices because rigging split some vertices, but its set of 14,402 unique UV coordinates is **identical** to the new retexture. This checks UV compatibility; it does not prove a Studio import or in-game appearance.

Meshy `retexture` task `01a0d37a-86f5-73bc-9e67-82cb2cf1b3e2`, source remesh task `01a0d056-45f0-71ae-b756-f5ddbf80bb54`, `enable_original_uv=true`, 2K map, PBR on. Consumed **10 credits**. The local project record is under `meshy_output/` and is gitignored because its snapshot carries expiring signed URLs. No new rigging or remesh credits were spent.

Integration contract for Claude: add a cosmetic-only skin ID such as `SignalArchitect`; authorize every ownership/equip path on the **server** with `DevAccess.IsAllowed(player)`. No Token, wheel, Robux, gift, or client-supplied ownership path may grant it. A developer can select and equip it at no cost; a non-developer should not see an actionable offer and must be rejected if a forged request reaches the server. Use the existing cosmetic clone and native R15 movement. On developer access removal, fall back to Baseline Yellow on load and on equip. Test developer and ordinary player, rejoin, two-client visibility, and mobile rendering. Keep existing colliders, footsteps/noise, light, camera, and detection unchanged.

## False Sun: quiet solar motes

The existing False Sun topper has a warm center window. Add a small halo of drifting embers around **that topper only**, never across the full suit. `false-sun-mote.png` is a transparent 256 × 256 sprite; `false-sun-mote.svg` is its editable radial-gradient source. Roblox group-owned Image ID **`128661548525607`** is approved; use `rbxassetid://128661548525607` as the emitter texture. Avoid a `PointLight`, full-body emission, dynamic shadows, high-frequency flashes, or particles that obscure the player or entity silhouettes.

Suggested single `ParticleEmitter` on an `Attachment` immediately in front of the topper window, positioned after checking the current topper orientation in Studio:

| Property | Initial desktop target | Mobile/low graphics |
| --- | --- | --- |
| Texture | `rbxassetid://128661548525607` | Same |
| Rate | 2.5/s | 1/s |
| Lifetime | 0.45–0.75 s | Same |
| Speed | 0.12–0.28 studs/s, drifting upward | Same |
| Size | 0.12 → 0.24 → 0 over lifetime | 0.10 → 0.18 → 0 |
| Transparency | 0.58 → 0.42 → 1 | 0.67 → 0.55 → 1 |
| LightEmission | 0.25 | 0.15 |
| SpreadAngle | ±16° each axis | Same |

At 2.5/s and 0.75 s maximum lifetime, the expected live count is under two motes per wearer. Bind to the currently equipped False Sun visual, including the shop's standing preview; remove it with the visual on unequip, death, lobby return, or character replacement. Cull by distance (suggest 40 studs) and avoid creation for unseen players when practical. Other clients should see the effect in a two-client round. No effect may alter gameplay light radius, line of sight, hitboxes, noise, speed, or purchase entitlements.

Acceptance: inspect front/back and shop preview in Studio; verify the effect is visible but does not light nearby geometry; compare desktop and phone/tablet frame time and particle counts with at least two wearers; verify cleanup across equip/death/rejoin; test Roblox purchase ownership separately; publish and record place version only after those checks. These values are art direction and starting parameters, not a claim of live validation.
