**Offline candidate. Nothing has been written.** Studio, the native builder and LIVE Level3 remain authoritative. `ASSUMED` marks items to verify at write time.

### 1. Palette candidate (per-key replacements, no grading)

```json
{
 "cells":{
  "beige_wall":[220,213,187],"orange_wall":[183,78,35],"red_wall":[145,58,48],
  "ceiling":[188,182,158],"linoleum":[150,146,126],"linoleum_grout":[84,82,70],
  "laminate":[204,196,168],
  "hold":["carpet_beige","carpet_confetti","carpet_red"],
  "keep":["black_wall","wood_worn","metal_worn","cardboard","paper_worn","service_door"]
 },
 "palette":{
  "blue_plastic":[38,153,165],"green_plastic":[55,130,87],"red_plastic":[151,49,59],
  "orange_plastic":[192,112,35],"yellow_plastic":[210,159,37],
  "balloon_red":[187,42,52],"balloon_blue":[40,104,169],
  "balloon_green":[55,139,91],"balloon_yellow":[210,159,37],
  "pink_plastic":[214,96,142],"purple":[104,60,140],"ivory_plastic":[212,202,168],
  "screen_cyan":[52,188,204],"screen_magenta":[204,56,138],"screen_green":[84,186,82]
 },
 "renameInPlace":{
  "orange_wall":{"balloon_purple":[119,61,151]},
  "red_wall":{"balloon_orange":[215,94,38]},
  "beige_wall":{"chair_indigo":[71,72,137]}
 },
 "chairs":{"ChairBlue":"blue_plastic","ChairRed":"red_plastic","ChairGreen":"green_plastic",
  "ChairYellow":"yellow_plastic; strict L3 parity = re-UV to orange_plastic",
  "ChairIndigo":"chair_indigo (optional new mesh; append to chairNames)"}
}
```

- **Exact Level3:** walls, chairs, balloons.
- **Proposals:** ceiling, linoleum, laminate, pink, purple, ivory, screens.
- **Unchanged:** all unlisted keys.
- **Carpet cells are held.** Room floors move to native Level3 Textures, so these cells become a corridor fallback only. Don't tune them into lookalikes.

**Slot constraint:**
- The palette grid is full (36 × 85 px). A 37th key would land at y=510, off-canvas.
- Swatches 32–34 are orphaned because `CELLS` overwrites their mapping. Renaming them *at the same dict position* keeps every existing UV rect stable.
- Move wall RGBs into a `WALL` dict. Use it for both the tile literals and the exported `colors`; they currently drift (166,77,29 vs 159,75,32).
- The seeded rng draw order is unchanged, so only colors differ.
- ASSUMED: purple/orange balloons will be new per-color mesh variants UV'd to slots 32–33, and nothing hard-codes rects 32–34.

### 2. Luau helper (insert above the room loop)

```lua
-- Filled at write time from LIVE Level3 {Texture, StudsPerTileU/V, Color3}; nil keeps native values.
local L3Floor = Configuration.Level3FloorTextures -- ASSUMED field

local function floorFinish(room) -- explicit fields only (ASSUMED names); never Id
    return room.FloorFinish or (room.Kitchen == true and "Tile") or "Carpet"
end

local function exposeNativeFloor(model, w, d, y, key)
    for _, part in ipairs(model:GetChildren()) do
        if part:IsA("BasePart") and part.Position.Y < y + .5
            and part.Size.X * part.Size.Z >= .9 * w * d then
            for _, tex in ipairs(part:GetChildren()) do
                if tex:IsA("Texture") and tex.Face == Enum.NormalId.Top then
                    local src = L3Floor and L3Floor[key]
                    if src and src.Texture and src.Texture ~= ""
                        and src.StudsPerTileU and src.StudsPerTileV then -- ID + repeat as a unit
                        tex.Texture, tex.StudsPerTileU, tex.StudsPerTileV =
                            src.Texture, src.StudsPerTileU, src.StudsPerTileV
                        tex.Color3 = src.Color3 or tex.Color3
                    end
                    part.Transparency, tex.Transparency = 0, 0 -- ASSUMED native values
                    return true -- collision/query/material/size untouched
                end
            end
        end
    end
    return false
end
```

Room loop: replace the `"Floor" .. palette` Place with:

```lua
local native = floorFinish(room) == "Carpet"
    and exposeNativeFloor(model, room.W, room.D, base.Y, palette)
if not native then -- no native floor, or Tile opt-in (asset TBD): today's path
    helper.Place("Floor" .. palette, CFrame.new(base), visuals,
        {Scale=Vector3.new(room.W/80, 1, room.D/64)})
end
```

Corridor loop: compute `native` before the section loop, then guard the floor Place:

```lua
local native = palette ~= "Service" and exposeNativeFloor(corridor.Model,
    corridor.Width, corridor.Length, corridor.Center.Y, palette)
-- inside the section loop:
if not native then
    helper.Place("Floor"..palette, panel, folder, {Scale=Vector3.new(corridor.Width/80, 1, (length+.02)/64)})
end
```

**Pockets:**
- The Service 18×24 `FloorService` pockets and the MaintenanceWorkshop linoleum pocket stay Blender meshes.
- Select them by explicit fields or an exact `MaintenanceWorkshop` match. Never use `:find("Maintenance")` and never match Janitor.
- BudgetArcade and PartySupplyStore get no pocket.
- Pocket tops must sit at least 0.03 above the native top to avoid Texture z-fighting.

### 3. Optional wallpaper/plaster overlay

For each wall/lintel proxy, add a Part:
- Place it in the visuals folder, with a name outside the `Level 6 … Wall` pattern.
- Set Anchored; CanCollide/CanQuery/CanTouch false; CastShadow false; Transparency 1.
- Use the proxy's CFrame, with thickness +0.04.

Then:
- Parent Textures to its two broad faces, copying the Level3 ID, StudsPerTile and Color3 at write time.
- Derive per-face `OffsetStudsU/V` from world position so segments, lintels and jambs stay continuous.

Textures still render on invisible parts, so Blender geometry is untouched. Blender caps and trims stay atlas-colored, which is why the atlas walls use exact Level3 RGB.

**Limitations:**
- The flat plane hides Blender relief and baked wear.
- Mesh bounds include trims, so the plane may float off the flat face or let baseboards poke through. Limit it to the band between baseboard and cornice.
- Too small an offset shimmers; too large shows lips at jambs.
- Shared walls need a per-face room lookup, because wallSkin uses one palette per proxy.
- T-junctions overlap.
- Texture shading won't match the atlas roughness.
- Each proxy gains two Textures.

### 4. Review

- **Collision and AI:**
  - Only Transparency and Level3 Texture fields change. Collision, Material and `Humanoid.FloorMaterial` stay native.
  - ASSUMED: Blender floors are CanCollide=false. If they have CanQuery=true, removing them changes which instances rays hit.
  - Search AI vision code for Transparency filters, since the floor becomes opaque.
- **Hide site:** the better fix is to exempt floors where they are currently hidden, so native values are never overwritten. The `0` restore is ASSUMED.
- **Geometry checks:**
  - Confirm exactly one full-footprint floor per room/corridor; split floors fall back safely.
  - Confirm the Blender floor top equals the native top, or furniture and pockets will float or sink.
- **Lighting:** the match is by source RGB. If Level6 lighting differs from Level3, compare screenshots rather than adding ColorCorrection.
- **Thresholds:** check carpet continuity where rooms meet corridors.
