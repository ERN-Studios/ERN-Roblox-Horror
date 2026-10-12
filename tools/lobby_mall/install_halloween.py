"""Put the Halloween dressing in the mall lobby of the open Studio place (Edit mode).

    /usr/local/bin/python3 tools/lobby_mall/install_halloween.py             # upload what is new, place everything
    /usr/local/bin/python3 tools/lobby_mall/install_halloween.py --remove    # take the dressing out again (after Halloween)

LOBBY_HALLOWEEN_20261013. From artifacts/lobby-halloween-20261013/build/halloween.json (build_halloween.py): each kit
mesh goes up once as a group mesh (AssetService:CreateAssetAsync from an EditableMesh with a colour per vertex, the
creator skin's route; ids and the mesh data's hash are kept in halloween_ids.json beside this file), then one Model,
`Workspace.LobbyMallPreview.Halloween`, is built from MeshParts: props, hanging lines, the lanterns' glowing faces
(a second Neon mesh a hair outside the painted face) and 22 small PointLights, sale banners, standees and price bursts
with their lettering as SurfaceGuis in the mall's sign font. Everything sits inside the mall's model, so the round
servers drop it with the mall and import_mall.py carries it over when the mall is rebuilt. Nothing is sent from this Mac.
"""
import hashlib, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

BUILD = ROOT / 'artifacts' / 'lobby-halloween-20261013' / 'build'
IDS = HERE / 'halloween_ids.json'
OFFSET = (300, 0, 0)                   # the mall's own (import_mall.py)
MALL, NAME = 'LobbyMallPreview', 'Halloween'
J = lambda v: json.dumps(v, separators=(',', ':'))

MESH = '''
local AssetService = game:GetService("AssetService")
local data = game:GetService("HttpService"):JSONDecode([==[%s]==])
local em = AssetService:CreateEditableMesh()
local V, N, C, T = data.verts, data.normals, data.colours, data.tris
local vid, nid, cid = {}, {}, {}
for i = 1, #V, 3 do
	vid[#vid + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]) / 1000)
	nid[#nid + 1] = em:AddNormal(Vector3.new(N[i], N[i + 1], N[i + 2]) / 1000)
	cid[#cid + 1] = em:AddColor(Color3.fromRGB(C[i], C[i + 1], C[i + 2]), 1)
end
for i = 1, #T, 3 do
	local a, b, c = T[i] + 1, T[i + 1] + 1, T[i + 2] + 1
	local f = em:AddTriangle(vid[a], vid[b], vid[c])
	em:SetFaceNormals(f, {nid[a], nid[b], nid[c]})
	em:SetFaceColors(f, {cid[a], cid[b], cid[c]})
end
local ok, result, id = pcall(function()
	return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name = "Halloween_" .. %s, Description = "Mall lobby Halloween kit (tools/lobby_mall)",
		CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
end)
em:Destroy()
if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(id) end
return "OK " .. tostring(id)
'''

REMOVE = '''
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local mall = workspace:FindFirstChild("%s")
local old = mall and mall:FindFirstChild("%s")
local stash = game:GetService("ServerStorage"):FindFirstChild("HalloweenKitTemp")
if stash then stash:Destroy() end
if old then old:Destroy(); return "removed" end
return "nothing to remove"
'''

HEAD = '''
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local AssetService, ServerStorage = game:GetService("AssetService"), game:GetService("ServerStorage")
local mall = assert(workspace:FindFirstChild("%s"), "the mall lobby is not in the place")
local old = mall:FindFirstChild("%s")
if old then old:Destroy() end
local stash = ServerStorage:FindFirstChild("HalloweenKitTemp")
if stash then stash:Destroy() end
stash = Instance.new("Folder"); stash.Name = "HalloweenKitTemp"; stash.Parent = ServerStorage
local kit = game:GetService("HttpService"):JSONDecode([==[%s]==])
local made = 0
for name, k in pairs(kit) do
	local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(k.id), {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise})
	part.Name = name
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Material = Enum.Material[k.material]
	part.Color = Color3.new(1, 1, 1)
	part.DoubleSided = k.double
	part:SetAttribute("BaseSize", part.Size)
	part.Parent = stash
	made += 1
end
local model = Instance.new("Model")
model.Name = "%s"
model:SetAttribute("Build", "LOBBY_HALLOWEEN_20261013")
for _, name in ipairs({"Props", "Signs"}) do
	local f = Instance.new("Folder"); f.Name = name; f.Parent = model
end
model.Parent = mall
return "templates " .. made
'''

PROPS = '''
local HttpService, ServerStorage = game:GetService("HttpService"), game:GetService("ServerStorage")
local stash = ServerStorage.HalloweenKitTemp
local model = workspace["%s"]["%s"]
local OFFSET, TAPE_Z, FIRST = Vector3.new(%s), %s, %d
local kit = HttpService:JSONDecode([==[%s]==])
local GLOW = Color3.fromRGB(255, 176, 56)
local function frame(item)
	local p = Vector3.new(item.pos[1], item.pos[2], item.pos[3]) + OFFSET
	return CFrame.lookAt(p, p + Vector3.new(item.face[1], 0, item.face[2])) * CFrame.Angles(math.rad(item.tilt or 0), 0, 0)
end
local function place(name, item, cf)
	local k = kit[name]
	local s = Vector3.new(item.scale[1], item.scale[2], item.scale[3])
	local part = stash[name]:Clone()
	part.Size = part:GetAttribute("BaseSize") * s
	part:SetAttribute("BaseSize", nil)
	part.CFrame = cf * CFrame.new(Vector3.new(k.centre[1], k.centre[2], k.centre[3]) * s)
	return part
end
local n = 0
for i, item in ipairs(HttpService:JSONDecode([==[%s]==])) do
	local cf = frame(item)
	local part = place(item.kind, item, cf)
	part.Name = string.format("%%s_%%03d", item.kind, FIRST + i)
	if item.collide ~= nil then part.CanCollide = item.collide else part.CanCollide = kit[item.kind].collide end
	if item.tint then part.Color = Color3.fromRGB(item.tint[1], item.tint[2], item.tint[3]) end
	if item.transparency then part.Transparency = item.transparency end
	-- past the tape the hall goes dark, as the mall's own parts do (import_mall.py): the lanterns' faces are what is left
	local z = item.pos[3]
	if z > TAPE_Z then
		local shade = math.max(0.03, (1 - math.clamp((z - TAPE_Z) / 150, 0, 1)) ^ 1.5)
		part.Color = Color3.new(part.Color.R * shade, part.Color.G * shade, part.Color.B * shade)
	end
	part.Parent = model.Props
	n += 1
	if item.kind == "pumpkin" and item.lit then
		local face = place("pumpkin_face", item, cf)
		face.Name, face.Color, face.CanCollide = part.Name .. "_Face", GLOW, false
		if item.light then
			local light = Instance.new("PointLight")
			light.Name, light.Color, light.Shadows = "Lantern", Color3.fromRGB(255, 150, 60), false
			light.Brightness, light.Range = (z > TAPE_Z) and 1.6 or 1.5, 8 + 4 * item.scale[1]      -- HALLOWEEN_DUSK_20261013: the hall is dim now, the lanterns carry it
			light.Parent = face
		end
		face.Parent = model.Props
		n += 1
	end
	if item.line then
		local top = Vector3.new(item.pos[1], item.pos[2], item.pos[3]) + OFFSET
		local length = item.line - item.pos[2]
		local cord = Instance.new("Part")
		cord.Name, cord.Size = part.Name .. "_Line", Vector3.new(0.06, length, 0.06)
		cord.CFrame = CFrame.new(top + Vector3.new(0, length / 2, 0))
		cord.Anchored, cord.CanCollide, cord.CanTouch, cord.CanQuery, cord.CastShadow = true, false, false, false, false
		cord.Material, cord.Color = Enum.Material.SmoothPlastic, Color3.fromRGB(34, 32, 30)
		cord.Parent = model.Props
		n += 1
	end
end
return n
'''

SIGNS = '''
local HttpService, ServerStorage = game:GetService("HttpService"), game:GetService("ServerStorage")
local stash = ServerStorage.HalloweenKitTemp
local model = workspace["%s"]["%s"]
local OFFSET = Vector3.new(%s)
local star = HttpService:JSONDecode([==[%s]==])
local FACE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
-- GLOWING_SIGNS_20261013 (owner, from the live game: "Make all discount signs text glow a nice halloween deep orange so
-- its visible the text"). The signs were orange boards with near-black lettering, lit by the room; in the Halloween
-- dusk both went dark red and the words could not be read. Now every sign is a dark board whose lettering and
-- frame are self-lit deep orange (LightInfluence 0, a brightness over 1 so the bloom catches it).
local INK = Color3.fromRGB(255, 118, 20)
local BOARD = Color3.fromRGB(26, 17, 12)
local function plain(name, size, cf, colour)
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame = name, size, cf
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Material, part.Color = Enum.Material.SmoothPlastic, colour
	part.Parent = model.Signs
	return part
end
-- lines stacked on one face; the first is the headline. `inset`: the share of the face the lettering may use
local function write(part, face, lines, w, h, inset, far, weights, border)
	local tallest = 0
	local total = 0
	for i = 1, #lines do total += weights[i] or 1 end
	for i = 1, #lines do tallest = math.max(tallest, (weights[i] or 1) / total * h * inset) end
	local g = Instance.new("SurfaceGui")
	g.Name, g.Face, g.SizingMode = "SaleSign", face, Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = math.clamp(math.floor(110 / tallest), 10, 160)      -- TextScaled stops at 100 px
	g.LightInfluence, g.Brightness, g.MaxDistance, g.ClipsDescendants = 0, 2.2, far, true
	if border then
		local edge = Instance.new("Frame")
		edge.Name, edge.BackgroundTransparency, edge.Size, edge.Position = "Edge", 1, UDim2.fromScale(0.94, 0.94), UDim2.fromScale(0.03, 0.03)
		local stroke = Instance.new("UIStroke")
		stroke.Color, stroke.Thickness = INK, math.max(2, math.floor(g.PixelsPerStud * 0.07))
		stroke.Parent = edge
		edge.Parent = g
	end
	local at = (1 - inset) / 2
	for i, text in ipairs(lines) do
		local share = (weights[i] or 1) / total * inset
		local label = Instance.new("TextLabel")
		label.Name, label.BackgroundTransparency, label.FontFace, label.TextColor3 = "Line" .. i, 1, FACE, INK
		label.Position, label.Size = UDim2.fromScale((1 - inset) / 2, at), UDim2.fromScale(inset, share)
		label.TextScaled, label.Text = true, (text:gsub(" ", utf8.char(160)))
		label.Parent = g
		at += share
	end
	g.Parent = part
end
local function cord(name, a, top)
	local length = top - a.Y
	local c = plain(name, Vector3.new(0.07, length, 0.07), CFrame.new(a + Vector3.new(0, length / 2, 0)), Color3.fromRGB(34, 32, 30))
	return c
end
local n = 0
for _, sign in ipairs(HttpService:JSONDecode([==[%s]==])) do
	local p = Vector3.new(sign.pos[1], sign.pos[2], sign.pos[3]) + OFFSET
	local look = Vector3.new(sign.face[1], 0, sign.face[2]).Unit
	local cf = CFrame.lookAt(p, p + look)
	local w, h = sign.size[1], sign.size[2]
	if sign.kind == "banner" then
		local colour = Color3.fromRGB(sign.colour[1], sign.colour[2], sign.colour[3])
		local part = plain(sign.name, Vector3.new(w, h, 0.1), cf, BOARD)
		local weights = #sign.lines == 2 and {1.25, 0.85} or {1}
		write(part, Enum.NormalId.Front, sign.lines, w, h, 0.84, w > 20 and 260 or 150, weights, true)
		if sign.two then write(part, Enum.NormalId.Back, sign.lines, w, h, 0.84, w > 20 and 260 or 150, weights, true) end
		if sign.line then
			for _, side in ipairs({-1, 1}) do
				cord(sign.name .. "_Line", (cf * CFrame.new(side * (w / 2 - 0.4), h / 2, 0)).Position, sign.line)
				n += 1
			end
		end
		n += 1
	elseif sign.kind == "aframe" then
		-- two boards leaning on each other; each reads from its own side
		for _, side in ipairs({1, -1}) do
			local turn = cf * CFrame.Angles(0, side == 1 and 0 or math.pi, 0)
			local board = plain(sign.name .. (side == 1 and "_Front" or "_Back"), Vector3.new(w, h, 0.12),
				turn * CFrame.new(0, h / 2 * math.cos(math.rad(11)), -0.46) * CFrame.Angles(math.rad(11), 0, 0), BOARD)
			write(board, Enum.NormalId.Front, sign.lines, w, h, 0.8, 95, {0.9, 1.5, 0.6}, true)
			n += 1
		end
	elseif sign.kind == "burst" then
		local r = w / 2
		for _, side in ipairs(sign.two and {1, -1} or {1}) do
			local turn = cf * CFrame.Angles(0, side == 1 and 0 or math.pi, 0) * CFrame.new(0, 0, sign.two and -0.03 or 0)
			local part = stash.starburst:Clone()
			part.Name = sign.name .. (side == 1 and "" or "_Back")
			part.Size = part:GetAttribute("BaseSize") * Vector3.new(r, r, 1)
			part:SetAttribute("BaseSize", nil)
			part.CFrame = turn * CFrame.new(Vector3.new(star.centre[1] * r, star.centre[2] * r, star.centre[3]))
			part.Color = Color3.fromRGB(70, 44, 36)          -- the star itself goes dark red-brown; its words are the light
			part.Parent = model.Signs
			write(part, Enum.NormalId.Front, sign.lines, 2 * r, 2 * r, 0.56, r > 1.5 and 150 or 60, {1.2, 0.8}, false)
			n += 1
		end
		if sign.line then cord(sign.name .. "_Line", p + Vector3.new(0, r, 0), sign.line); n += 1 end
	end
end
return n
'''

TAIL = '''
local stash = game:GetService("ServerStorage"):FindFirstChild("HalloweenKitTemp")
if stash then stash:Destroy() end
local model = workspace["%s"]["%s"]
local parts, lights, guis, tris = 0, 0, 0, 0
for _, d in ipairs(model:GetDescendants()) do
	if d:IsA("BasePart") then parts += 1 elseif d:IsA("PointLight") then lights += 1 elseif d:IsA("SurfaceGui") then guis += 1 end
end
return string.format("Halloween dressing: %%d parts, %%d lights, %%d sign faces", parts, lights, guis)
'''


def main():
    studio = Studio()
    if '--remove' in sys.argv:
        print(studio.luau(REMOVE % (MALL, NAME)))
        return
    data = json.loads((BUILD / 'halloween.json').read_text())
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    for name, mesh in data['kit'].items():
        body = {k: mesh[k] for k in ('verts', 'normals', 'colours', 'tris')}
        digest = hashlib.sha256(J(body).encode()).hexdigest()
        if ids.get(name, {}).get('sha256') == digest:
            continue
        answer = studio.luau(MESH % (J(body), json.dumps(name)))
        print(f'{name:16s} {mesh["triangles"]:5d} triangles -> {answer}', flush=True)
        if not answer.startswith('OK '):
            raise SystemExit('stopped: ' + answer)
        ids[name] = {'id': int(answer.split()[1]), 'sha256': digest}
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    kit = {name: {'id': ids[name]['id'], 'centre': m['centre'], 'double': m['double'], 'collide': m['collide'], 'material': m['material']} for name, m in data['kit'].items()}
    print(studio.luau(HEAD % (MALL, NAME, J(kit), NAME)))
    placed = 0
    for i in range(0, len(data['items']), 120):
        placed += int(float(studio.luau(PROPS % (MALL, NAME, ', '.join(map(str, OFFSET)), data['tape_z'], i, J(kit), J(data['items'][i:i + 120])))))
    signs = int(float(studio.luau(SIGNS % (MALL, NAME, ', '.join(map(str, OFFSET)), J(kit['starburst']), J(data['signs'])))))
    print(f'props and lines {placed}, sign parts {signs}')
    print(studio.luau(TAIL % (MALL, NAME)))


if __name__ == '__main__':
    main()
