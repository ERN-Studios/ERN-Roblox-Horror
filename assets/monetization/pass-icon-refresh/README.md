# Circular Game Pass icon refresh — 24 September 2026

Roblox displays Game Pass thumbnails in a circle. This package replaces four
live icons whose original 150 px Roblox circle preview either showed a tiny
T-pose, clipped its product title, or reduced the premium 20K donation pass to
a plain gray ticket. The new PNGs are 512 × 512 RGBA with transparent corners.
The main face, device screen/button, and donor ticket-heart stay within the
central ~80–85% of the diameter. `all-four-128-preview.jpg` is the pre-upload
circle check. Order: Static Wraith, False Sun, Entity Detector, 20K donation.

| Game Pass | Pass ID | Before icon asset | New file | After icon asset |
| --- | ---: | ---: | --- | ---: |
| Static Wraith | `1994666374` | `101066368280251` | `static-wraith-round-v2.png` | `138340341615487` |
| False Sun | `1994816385` | `90694693019242` | `false-sun-round-v2.png` | `124426104310134` |
| Zyntra Entity Detector | `1982715834` | `134413710349950` | `entity-detector-round-v2.png` | `95155166160730` |
| ZYNTRA Support — 20K | `1978617781` | `133448903949274` | `donation-20k-round-v2.png` | `99653124666776` |

`refresh_live_icons.py before` captured each original Open Cloud pass record
and both square and circular official Roblox thumbnails in `before/` and
`before-state.json`. `refresh_live_icons.py apply` submitted only the
`imageFile` field in four separate PATCH requests, then GET-read each pass.
The receipt is `apply-receipt.json`. Name, description, price information,
sale status, and managed-pricing flag matched their pre-change values after
every update. Open Cloud Assets reports all four new Image assets Approved.
Official thumbnails are asynchronous; `refresh_live_icons.py after` captures
their processed state and previews in `after/` and `after-state.json`.
All four after-thumbnails now report `Completed`, and the circular thumbnail
hash changed for every pass. [Roblox's actual 128 px before/after sheet](roblox-before-after-128-preview.png)
shows the visible improvement. `before-state.json` and `after-state.json`
confirm the four pass names, descriptions, Robux prices, sale states and
managed-pricing flags are identical; only iconAssetId changed.

The complete Open Cloud list returned **13 passes** in this universe with no
next page, and all 13 official circular thumbnails reported `Completed` on
24 September. [Current 128 px contact sheet](all-live-pass-icons-128-preview.png)
and [machine-readable inventory](pass-inventory-20260924.json) cover all 13:

| Passes inspected without icon replacement | Pass IDs | Finding |
| --- | --- | --- |
| Zyntra Supporter, Advanced Equipment, Glowstick Customizer | `1941938256`, `1945402536`, `1946086261` | Central symbols remain readable inside Roblox's circle. |
| Token Earner direct 2×, 3×, 5× | `1995218405`, `1995716395`, `1994654411` | Approved, Completed, legible numerals. |
| Token Earner upgrades 2→3, 3→5, 2→5 | `1994282418`, `1995812369`, `1994252411` | Approved, Completed, same target-tier art as matching direct pass. |

The six new Token Earner pass icons were already circular and readable in
`assets/monetization/booster-passes/`. Their six icon assets are Approved and
the official Roblox pass and asset thumbnails now all report Completed. The
first `Pending` result immediately after creation was transient thumbnail
processing, not a moderation rejection. Other live pass icons (Supporter,
Advanced Equipment, Glowstick) fit the circle. Local developer-product art
under `assets/monetization/icons-512/` was previously composed for a circular
safe area; this refresh changed no Developer Product icon.

The suit portraits and Entity Detector are deterministic crops of the exact
project images. `make_icons.py` rebuilds all four final PNGs. The 20K image was
generated with the built-in imagegen tool using the existing donation medallion
and live plain-ticket thumbnail as style/motif references; its original is
`source-donation-20k.png`. Final generation prompt:

> Use case: stylized-concept. Asset type: 512 x 512 Roblox Game Pass icon for
> the BACKROOMS: STAY QUIET one-time 20K voluntary studio-support pass. Input
> Image 1 is the game's existing premium donation medallion art and defines
> exact gold/teal/graphite rendering style, lighting, and polished material
> quality. Input Image 2 is the current plain ticket pass icon; use the ticket
> shape as motif only. Create a distinctive NEW centered premium support
> medallion: a short beveled gold ticket silhouette with an embossed warm gold
> heart in its center, contained inside a dark graphite circular frame with
> teal edge glow and restrained gold rays. Strong readable heart-and-ticket
> silhouette at 64 px. Product art only, no interface, no human, no text, no
> numerals, no Robux symbol, no logos, no watermark, no extra objects.
> Critical subject and frame must fit inside the inscribed circular safe area
> with generous margin; Roblox automatically crops Game Pass icons to a
> circle. Square full-bleed source image.

API references: [Roblox Game Pass Cloud API](https://create.roblox.com/docs/cloud/reference/features/game-passes),
[Roblox circular-crop guidance](https://create.roblox.com/docs/production/publishing/badges).
