"""Dress the Level 6 arena in its PBR materials (make_pbr.py made the maps; pbr_ids.json says where they are).

    python3 tools/level6_playground/pbr/apply_pbr.py --check      # are all the pictures there and usable? changes nothing
    python3 tools/level6_playground/pbr/apply_pbr.py --play       # dress the level in a running play session only (a look, not saved)
    python3 tools/level6_playground/pbr/apply_pbr.py              # dress the saved place (Edit, play stopped): only after --check said every picture is usable
    python3 tools/level6_playground/pbr/apply_pbr.py --dry        # count what would change

What it does, to the model as import_arena.py leaves it (run it again after every re-import; it can be run twice):

  MaterialService     one MaterialVariant per set (`L6 Foam Floor`, `L6 Vinyl Quilt`, `L6 Vinyl Plain`, `L6 Vinyl Filthy`,
                      `L6 Block Wall`, `L6 Roof Deck`, `L6 Slide Plastic`): colour, normal and roughness map, the
                      repeat in studs. A part wears one by Material = the set's base material + MaterialVariant = its name.
  floors              the hall floor, the court's tiles, the lid over the hole and EVERY deck of the frame become the
                      foam mat. The mat's blue and green check is in its colour map, so these parts turn white
                      (a little uneven from part to part).
  under every deck    a deck is one slab: floor on top, the gallery below's ceiling underneath. A material is the
                      same on every face, so each deck above the ground gets a thin unseen-to-physics pad on its
                      underside, in the deck's old colour, in quilted vinyl (folder `Frame_DeckPads`).
  padding             panels, soft blocks, the tunnel, the gate, the rim and the shaft: quilted vinyl in their own
                      colour. Posts, beams, steps, punch bags and rails: the same skin without seams.
  the exit room       its pads go to the mouldy quilt, the room behind the door to ceramic tile (a built-in).
  walls, roof         painted block, ribbed steel deck.
  slides, balls       scuffed moulded plastic (meshes keep their painted vertex colours under it).
  nets                keep their see-through Textures; only the picture is swapped for the knotted cord.
  overlays            the flat seam pictures the materials replace are deleted (about ten thousand Textures).

Why nothing is saved until the pictures are usable: a MaterialVariant whose pictures the experience may not load
draws as its plain base material, and the floors would be white plastic. `--check` loads every picture in a play
session first.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
from import_to_studio import Studio   # noqa: E402

SETS = json.loads((ROOT / 'assets' / 'level6-pbr-20261006' / 'sets.json').read_text())
IDS = HERE / 'pbr_ids.json'
ORGANIC = ('vinyl_plain', 'slide_plastic')               # no pattern to keep straight: let the engine hide the repeat

LUAU = r'''
local MODE = "%(mode)s"                                    -- "apply" | "dry"
local SPEC = game:GetService("HttpService"):JSONDecode([==[%(spec)s]==])
local model = workspace:FindFirstChild("Level 6 Indoor Playground")
assert(model and model:GetAttribute("Arena") ~= nil, "the arena is not in this place")
local origin = model:GetAttribute("Origin")
local MaterialService = game:GetService("MaterialService")
local dry = MODE == "dry"
local count = {}
local function tally(key, n) count[key] = (count[key] or 0) + (n or 1) end

-- 1. the variants
local NAME = {}
for key, set in pairs(SPEC.sets) do
	NAME[key] = set.variant
	if not dry then
		local v = MaterialService:FindFirstChild(set.variant)
		if not v then
			v = Instance.new("MaterialVariant")
			v.Name = set.variant
			v.Parent = MaterialService
		end
		v.BaseMaterial = Enum.Material[set.base]
		v.StudsPerTile = set.studs
		v.MaterialPattern = set.organic and Enum.MaterialPattern.Organic or Enum.MaterialPattern.Regular
		v.ColorMap, v.NormalMap, v.RoughnessMap = "rbxassetid://" .. set.color, "rbxassetid://" .. set.normal, "rbxassetid://" .. set.roughness
	end
	tally("variants")
end

-- 2. the parts
local STRIP = {}                                          -- overlay pictures a material replaces
for _, id in ipairs(SPEC.strip) do STRIP[id] = true end
local VINYL = SPEC.vinylOverlay
local function overlays(part)
	local vinyl, list = false, {}
	for _, t in ipairs(part:GetChildren()) do
		if t:IsA("Texture") then
			local id = tonumber(string.match(t.Texture, "%%d+"))
			if id == VINYL then vinyl = true end
			if id and STRIP[id] then list[#list + 1] = t end
		end
	end
	return vinyl, list
end
local function wear(part, key, colour, base)
	tally(key)
	if dry then return end
	part.Material = base or Enum.Material[SPEC.sets[key].base]
	part.MaterialVariant = NAME[key]
	if colour then part.Color = colour end
	part:SetAttribute("L6PBR", key)
end
local function strip(list)
	tally("overlays removed", #list)
	if dry then return end
	for _, t in ipairs(list) do t:Destroy() end
end
-- a steady small unevenness from where the part is, so a floor of white parts is not one flat white
local function uneven(part, lo)
	local p = part.Position
	local h = (math.sin(p.X * 12.9898 + p.Y * 37.719 + p.Z * 78.233) * 43758.5453) %% 1
	local v = lo + (1 - lo) * h
	return Color3.new(v, v, v * 0.985)
end

local FOAM_GROUPS = {Floor_Concrete = true, Floor_FoamTiles = true, Finale_Lid = true, Frame_Decks = true, Frame_DecksDeep = true}
local DECKS = {Frame_Decks = true, Frame_DecksDeep = true}
local PLAIN_GROUPS = {Frame_Posts = true, Frame_Beams = true, Frame_SoftSteps = true, Frame_PlayFeatures = true, Frame_Bridges = true, Finale_Post = true}
local QUILT_GROUPS = {Frame_Panels = true, Hall_SoftBlocks = true, Tunnel = true, Finale_Shaft = true, Finale_Rim = true, Frame_Entrances = true, Gate = true}
local pads = model:FindFirstChild("Frame_DeckPads")
if not dry then
	if pads then pads:Destroy() end
	pads = Instance.new("Folder")
	pads.Name = "Frame_DeckPads"
end
local batch = 0
for _, group in ipairs(model:GetChildren()) do
	local g = group.Name
	if g ~= "Frame_DeckPads" then
		for _, part in ipairs(group:IsA("BasePart") and {group} or group:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 0.05 then
				local smooth = part.Material == Enum.Material.SmoothPlastic
				local round = part:IsA("Part") and part.Shape ~= Enum.PartType.Block
				local vinyl, list = overlays(part)
				if FOAM_GROUPS[g] then
					local low = part.Position.Y - origin.Y < -40                     -- the exit room's own floor: darker, dirtier
					if DECKS[g] then
						local was = part:GetAttribute("L6PadColor") or part.Color
						if not dry then part:SetAttribute("L6PadColor", was) end
						if part.Position.Y - origin.Y > 2 then                       -- a ground deck has nothing under it to look up at
							tally("deck pads")
							if not dry then
								local pad = Instance.new("Part")
								pad.Name = part.Name
								pad.Size = Vector3.new(part.Size.X, 0.14, part.Size.Z)
								pad.CFrame = part.CFrame * CFrame.new(0, -(part.Size.Y / 2 + 0.06), 0)
								pad.Anchored, pad.CanCollide, pad.CanTouch, pad.CanQuery, pad.CastShadow = true, false, false, false, false
								pad.TopSurface, pad.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
								pad.Material, pad.MaterialVariant, pad.Color = Enum.Material[SPEC.sets.vinyl_quilt.base], NAME.vinyl_quilt, was
								pad:SetAttribute("L6PBR", "vinyl_quilt")
								pad.Parent = pads
							end
						end
					end
					wear(part, "foam_floor", low and Color3.fromRGB(196, 194, 180) or uneven(part, 0.88))
					strip(list)
				elseif g == "Walls" then
					wear(part, "block_wall")
					strip(list)
				elseif g == "Ceiling_Structure" and part.Name == "deck" then
					wear(part, "roof_deck")
					strip(list)
				elseif g == "Slides" or g == "Arena_SlideSurfaces" or g == "Hall_Balls" or (g == "Props" and part.Name == "tube_window_panel")
					or (g == "ExitRoom" and smooth and round and part.Shape == Enum.PartType.Ball) then
					wear(part, "slide_plastic")
				elseif g == "ExitRoom" then
					-- (on a second run the overlay that marked a pad is gone: the mark the first run left says it)
					if smooth and (vinyl or round or part:GetAttribute("L6PBR") == "vinyl_filthy") then
						wear(part, "vinyl_filthy")
						strip(list)
					elseif part.Name == "white" then
						tally("ceramic")
						if not dry then part.Material, part.MaterialVariant = Enum.Material.CeramicTiles, "" end
					end
				elseif PLAIN_GROUPS[g] and smooth and part.Name ~= "black" then
					wear(part, "vinyl_plain")
					strip(list)
				elseif QUILT_GROUPS[g] and smooth then
					wear(part, round and "vinyl_plain" or "vinyl_quilt")
					strip(list)
				end
			end
			batch += 1
			if batch %% 1500 == 0 then task.wait() end
		end
	end
end
if not dry then pads.Parent = model end

-- 3. the nets: the same Textures, a better picture
if SPEC.net then
	for _, d in ipairs(model:GetDescendants()) do
		local id = d:IsA("Texture") and tonumber(string.match(d.Texture, "%%d+"))
		if id and (id == SPEC.netOld or SPEC.netWas[tostring(id)]) and d.Parent:IsA("BasePart") then
			tally("net textures")
			if not dry then
				d.Texture = "rbxassetid://" .. SPEC.net
				-- the old picture was black cord; this one is pale and takes its colour from the net it hangs on
				local c = d.Parent.Color
				d.Color3 = (c.R + c.G + c.B < 0.3) and Color3.fromRGB(26, 26, 28) or c
			end
		end
	end
end
if not dry then model:SetAttribute("PBR", SPEC.stamp) end

local keys = {}
for k in pairs(count) do keys[#keys + 1] = k end
table.sort(keys)
local out = {}
for _, k in ipairs(keys) do out[#out + 1] = k .. " " .. count[k] end
local parts, textures = 0, 0
for _, d in ipairs(model:GetDescendants()) do
	if d:IsA("BasePart") then parts += 1 elseif d:IsA("Texture") then textures += 1 end
end
return (dry and "WOULD: " or "DONE: ") .. table.concat(out, ", ") .. " | the model now holds " .. parts .. " parts and " .. textures .. " Textures"
'''

CHECK = r'''
local ids = game:GetService("HttpService"):JSONDecode([==[%s]==])
local ContentProvider = game:GetService("ContentProvider")
local bad, good = {}, 0
for name, id in pairs(ids) do
	local label = Instance.new("ImageLabel")
	label.Image = "rbxassetid://" .. id
	local status
	ContentProvider:PreloadAsync({label}, function(_, s) status = s end)
	label:Destroy()
	if status == Enum.AssetFetchStatus.Success then good += 1 else bad[#bad + 1] = name .. " (" .. id .. "): " .. tostring(status) end
end
table.sort(bad)
return good .. " usable, " .. #bad .. " not" .. (#bad > 0 and ("\n" .. table.concat(bad, "\n")) or "")
'''

TEXTURES = json.loads((HERE.parent / 'textures.json').read_text())


def digits(ref):
    return int(''.join(c for c in str(ref) if c.isdigit()))


def spec(ids):
    sets = {}
    for key, info in SETS.items():
        maps = ids[key]
        sets[key] = {'variant': info['variant'], 'base': info['base'], 'studs': info['studs'], 'organic': key in ORGANIC,
                     'color': maps['color'], 'normal': maps['normal'], 'roughness': maps['roughness']}
    return {
        'sets': sets, 'stamp': 'PBR_20261006',
        'vinylOverlay': digits(TEXTURES['vinyl_pad']),
        'strip': [digits(TEXTURES[k]) for k in ('vinyl_pad', 'foam_mat', 'block_wall', 'roof_deck')],
        'netOld': digits(TEXTURES['net']), 'net': ids.get('net_knotted'),
        'netWas': {str(n): True for n in ids.get('_net_earlier', []) + ([ids['net_knotted']] if ids.get('net_knotted') else [])},
    }


def flat(ids):
    out = {}
    for key, value in ids.items():
        if key.startswith('_'):                           # bookkeeping, not a picture
            continue
        if isinstance(value, dict):
            for kind, number in value.items():
                out[f'{key}_{kind}'] = number
        else:
            out[key] = value
    return out


def call(studio, datamodel, code):
    return studio.call('execute_luau', {'studio_id': studio.studio_id, 'datamodel_type': datamodel, 'code': code})


def main():
    args = sys.argv[1:]
    if '--dry' in args and not IDS.exists():                # counting needs no pictures
        ids = {key: {'color': 0, 'normal': 0, 'roughness': 0} for key in SETS}
    elif not IDS.exists():
        raise SystemExit(f'{IDS.name} is missing: the pictures are not uploaded yet (see README.md, "Getting the pictures into Roblox")')
    else:
        ids = json.loads(IDS.read_text())
    missing = [k for k in SETS if k not in ids or any(m not in ids[k] for m in ('color', 'normal', 'roughness'))]
    if missing:
        raise SystemExit(f'pbr_ids.json has no complete entry for: {", ".join(missing)}')
    studio = Studio()
    if '--check' in args:
        print(call(studio, 'Client', CHECK % json.dumps(flat(ids))))
        return
    mode = 'dry' if '--dry' in args else 'apply'
    datamodel = 'Server' if '--play' in args else 'Edit'
    code = LUAU % {'mode': mode, 'spec': json.dumps(spec(ids))}
    print(call(studio, datamodel, code))


if __name__ == '__main__':
    main()
