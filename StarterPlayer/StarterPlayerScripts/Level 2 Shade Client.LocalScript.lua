-- Level 2 Shade Client (SHADE_20261010): everything you see and hear of the shadow with no owner.
--
-- The server (ServerScriptService."Level 2 Systems"."Level 2 Shade") decides who is hunted, where the shadow is and
-- when it strikes, and publishes that as attributes of ReplicatedStorage.Level2Shade. This script draws it: the same
-- black meshes are squashed flat against the wall or floor while it is a shadow and given their depth back when it
-- becomes real. It also tells the server when the hunted player (this one) has it on screen, and it makes the harmless
-- glimpses on far walls on its own.
--
-- Test read-outs on the local player: Level2ShadeView (what is drawn), Level2ShadeGlimpses, Level2ShadeSeenSent,
-- Level2ShadeEvent (the last recoil / warn / kill played).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local bank = ReplicatedStorage:WaitForChild("Level2Shade", 60)
if not bank then return end
local meshes = bank:WaitForChild("Meshes", 20)
local remote = ReplicatedStorage:WaitForChild("Level 2 Remotes"):WaitForChild("Level 2 Shade Event", 60)
if not meshes or not remote then return end

local START_DISTANCE, STRIKE_DISTANCE = 46, 4.5      -- the server's numbers, for how near "near" is
local SHADOW_FAR, SHADOW_NEAR = 0.62, 0.3            -- transparency of the flat shadow, far and near
local GLIMPSE_GAP = {18, 42}
local ARMS = 7
local UP = Vector3.yAxis
local random = Random.new()

local function smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-4 and f.Unit or nil
end

local function world()
	local model = workspace:FindFirstChild("Level 2 Generated World")
	return model and model:IsA("Model") and model:GetAttribute("Level2NewMap") == true and model or nil
end

local function inLevel()
	return world() ~= nil and player:GetAttribute("InRound") == true and workspace:GetAttribute("SelectedLevel") == 2
end

-- the same surface test as the server: the map's colliders without guards, pit volumes and pit sheets
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.IgnoreWater, params.RespectCanCollide = true, false
local paramsFor, guards
local function cast(origin, displacement)
	local model = world()
	local collision = model and model:FindFirstChild("Collision")
	if not collision then return nil end
	if paramsFor ~= collision then
		paramsFor, guards = collision, collision:FindFirstChild("Guards")
		params.FilterDescendantsInstances = {collision}
	end
	local length = displacement.Magnitude
	if length < 1e-3 then return nil end
	local unit = displacement / length
	local from, left = origin, length
	for _ = 1, 6 do
		local hit = workspace:Raycast(from, unit * left, params)
		if not hit then return nil end
		local instance = hit.Instance
		if instance.CanCollide and instance.Name ~= "Hazard" and instance.Name ~= "Veil" and instance.Name ~= "A2ReflectorCollider"
			and not (guards and instance:IsDescendantOf(guards)) then
			return hit
		end
		local gone = (hit.Position - from).Magnitude + 0.05
		if gone >= left then return nil end
		from, left = hit.Position + unit * 0.05, left - gone
	end
	return nil
end

-- A shadow on the bottom of a pool cannot be seen through the water from standing height: it lies on the water instead.
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = {workspace.Terrain}
waterParams.IgnoreWater = false
local function onWater(position)
	local hit = workspace:Raycast(position + UP * 8, -UP * 8.5, waterParams)
	if hit and hit.Material == Enum.Material.Water and hit.Position.Y > position.Y + 0.05 then
		return Vector3.new(position.X, hit.Position.Y + 0.1, position.Z)
	end
	return position
end

-- How far the wall goes on to one side of `origin` (a CFrame on it, -Z out of it) at `height`, up to `limit` studs.
local function room(origin, side, height, limit)
	local reached = 0
	for step = 0.5, limit, 0.5 do
		local from = (origin * CFrame.new(side * step, height, -1.5)).Position
		local behind = cast(from, origin.LookVector * -3)
		if not behind or math.abs(behind.Distance - 1.5) > 0.45 then break end
		reached = step
	end
	return reached
end

---------------------------------------------------------------------------------------------------------------------
-- pieces: one black mesh each
---------------------------------------------------------------------------------------------------------------------
local folder
local function home()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "Level 2 Shade (local)"
		folder.Parent = workspace
	end
	return folder
end

local function piece(name)
	local template = meshes:FindFirstChild(name)
	if not (template and template:IsA("MeshPart")) then return nil end
	local part = template:Clone()
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow, part.Massless = true, false, false, false, false, true
	part.Material, part.Color, part.Transparency, part.Reflectance = Enum.Material.Neon, Color3.new(0, 0, 0), 1, 0
	part.Parent = home()
	-- A mesh made from numbers (AssetService:CreateAssetAsync) keeps its own origin: the part's CFrame is the mesh's
	-- (0,0,0), not the middle of its box, and resizing the part scales the mesh about that point. The figures stand on
	-- their origin with their back on the plane Z = 0, so a figure is placed by its feet and flattens against the wall.
	local top = template:GetAttribute("BoxMax")
	return {Part = part, Full = template.Size, Top = typeof(top) == "Vector3" and top.Y or template.Size.Y, Name = name}
end

local function drop(p)
	if p and p.Part then p.Part:Destroy() end
end

-- `origin` sits at the mesh's own origin: -Z out of the surface, +Y up the figure. `depth` 0 is a shadow, 1 the body.
local function pose(p, origin, sx, sy, depth, lift)
	local full = p.Full
	depth = math.clamp(depth, 0, 1)
	p.Part.Size = Vector3.new(full.X * sx, full.Y * sy, math.max(0.02, full.Z * sx * depth))
	p.Part.CFrame = origin * CFrame.new(0, 0, -(lift or 0.03))
end

local function real(p, on)
	if p.Real == on then return end
	p.Real = on
	if on then
		p.Part.Material, p.Part.Color, p.Part.Reflectance = Enum.Material.SmoothPlastic, Color3.fromRGB(5, 5, 7), 0.12
	else
		p.Part.Material, p.Part.Color, p.Part.Reflectance = Enum.Material.Neon, Color3.new(0, 0, 0), 0
	end
end

---------------------------------------------------------------------------------------------------------------------
-- sound: every one of its sounds comes from a point in the world
---------------------------------------------------------------------------------------------------------------------
local soundBank = bank:FindFirstChild("Sounds")
local families = {}
local function family(prefix)
	local list = families[prefix]
	if not list then
		list = {}
		if soundBank then
			for _, item in ipairs(soundBank:GetChildren()) do
				if item:IsA("Sound") and item.Name:sub(1, #prefix) == prefix and item.Archivable ~= false then table.insert(list, item) end
			end
			table.sort(list, function(a, b) return a.Name < b.Name end)
		end
		families[prefix] = list
	end
	return list
end
local lastOf = {}
local function choose(prefix)
	local list = family(prefix)
	if #list == 0 then return nil end
	local index = random:NextInteger(1, #list)
	if #list > 1 and list[index] == lastOf[prefix] then index = index % #list + 1 end
	lastOf[prefix] = list[index]
	return list[index]
end

local function spatial(sound)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance, sound.RollOffMaxDistance = 14, 170
end

-- the masters are not equally loud: the installer measured each and left what it takes to level them
local function gain(sound)
	local g = sound:GetAttribute("Gain")
	return type(g) == "number" and math.clamp(g, 0.25, 4) or 1
end

local function emit(position, prefix, volume)
	local template = choose(prefix)
	if not template then return end
	local holder = Instance.new("Part")
	holder.Name = "Shade Sound"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.Transparency = true, false, false, false, 1
	holder.Size, holder.CFrame = Vector3.new(0.2, 0.2, 0.2), CFrame.new(position)
	holder.Parent = home()
	local sound = template:Clone()
	sound.Looped, sound.Volume = false, volume * gain(template)
	spatial(sound)
	sound.Parent = holder
	sound:Play()
	task.delay(math.max(sound.TimeLength, 6) + 1, function() holder:Destroy() end)
end

local function flatSound(prefix, volume)
	local template = choose(prefix)
	if not template then return end
	local sound = template:Clone()
	sound.Looped, sound.Volume = false, volume * gain(template)
	sound.Parent = player:WaitForChild("PlayerGui")
	sound:Play()
	task.delay(10, function() sound:Destroy() end)
end

local voice = {loops = {}}
local function voiceLoop(key)
	local sound = voice.loops[key]
	if sound and sound.Parent then return sound end
	local template = soundBank and soundBank:FindFirstChild(key)
	if not (template and template:IsA("Sound")) then return nil end
	if not voice.part or not voice.part.Parent then
		local part = Instance.new("Part")
		part.Name = "Shade Voice"
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.Transparency = true, false, false, false, 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = home()
		voice.part = part
	end
	sound = template:Clone()
	sound.Looped, sound.Volume = true, 0
	spatial(sound)
	sound.Parent = voice.part
	voice.loops[key] = sound
	return sound
end
local function voiceQuiet(dt)
	for _, sound in pairs(voice.loops) do
		if sound.Parent then
			sound.Volume = math.max(0, sound.Volume - dt * 1.5)
			if sound.Volume <= 0 and sound.IsPlaying then sound:Stop() end
		end
	end
end
local function voiceSet(key, volume, dt)
	local sound = voiceLoop(key)
	if not sound then return end
	volume *= gain(sound)
	if volume > 0.01 and not sound.IsPlaying then sound:Play() end
	sound.Volume += math.clamp(volume - sound.Volume, -dt * 1.5, dt * 1.5)
	if sound.Volume <= 0.005 and volume <= 0.01 and sound.IsPlaying then sound:Stop() end
end

---------------------------------------------------------------------------------------------------------------------
-- the dark at the edge of the screen
---------------------------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Level2ShadeDark"
gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder, gui.Enabled = true, false, 45, false
local edges = {}
local function edge(anchor, position, size, rotation)
	local frame = Instance.new("Frame")
	frame.AnchorPoint, frame.Position, frame.Size = anchor, position, size
	frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = Color3.new(0, 0, 0), 1, 0
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 0.6), NumberSequenceKeypoint.new(1, 1)})
	gradient.Parent = frame
	frame.Parent = gui
	table.insert(edges, frame)
end
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.42, 1), 0)        -- left
edge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.42, 1), 180)      -- right
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.42), 90)       -- top
edge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.42), 270)      -- bottom
local black = Instance.new("Frame")
black.Size, black.BackgroundColor3, black.BackgroundTransparency, black.BorderSizePixel, black.ZIndex =
	UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 1, 0, 5
black.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

-- The face in the dark (owner, 2026-10-10: "et meget klamt shadow figure ansigt, som vises når man er blevet trukket
-- ned i det shadow realm ... omridset af hovedet og hvide lysende øjne og ingen mund"). A Blender animation played as a
-- flipbook over the black: sheets of FaceGrid x FaceGrid frames, their asset ids in the folder's attribute FaceSheets
-- (tools/level2_shade/install_shade.py). Until the pictures exist two eyes open in the dark instead.
local faceHolder = Instance.new("Frame")
faceHolder.AnchorPoint, faceHolder.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
-- a third larger than the screen is high: the head sits small in its black frame, and the frame's edges are black
faceHolder.Size, faceHolder.SizeConstraint = UDim2.fromScale(1.3, 1.3), Enum.SizeConstraint.RelativeYY
faceHolder.BackgroundTransparency, faceHolder.BorderSizePixel, faceHolder.ZIndex, faceHolder.Visible = 1, 0, 6, false
faceHolder.Parent = gui
local face = {labels = {}, eyes = {}, source = nil, frames = 0, fps = 12, grid = 3, size = 340}
for index = 1, 2 do
	local eye = Instance.new("Frame")
	eye.AnchorPoint, eye.BackgroundColor3, eye.BorderSizePixel, eye.ZIndex, eye.Visible = Vector2.new(0.5, 0.5), Color3.new(1, 1, 1), 0, 7, false
	eye.Position = UDim2.fromScale(index == 1 and 0.41 or 0.6, 0.44)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = eye
	eye.Parent = faceHolder
	face.eyes[index] = eye
end
local function faceSetup()
	local sheets = bank:GetAttribute("FaceSheets")
	if type(sheets) ~= "string" or sheets == face.source then return end
	face.source = sheets
	for _, label in ipairs(face.labels) do label:Destroy() end
	face.labels = {}
	face.grid = math.max(1, tonumber(bank:GetAttribute("FaceGrid")) or 3)
	face.size = tonumber(bank:GetAttribute("FaceFrame")) or 340
	face.fps = tonumber(bank:GetAttribute("FaceFps")) or 12
	for id in sheets:gmatch("%d+") do
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency, label.BorderSizePixel, label.ZIndex, label.Visible = 1, 0, 6, false
		label.Size, label.Image = UDim2.fromScale(1, 1), "rbxassetid://" .. id
		label.ImageRectSize = Vector2.new(face.size, face.size)
		label.Parent = faceHolder
		table.insert(face.labels, label)
	end
	face.frames = math.min(tonumber(bank:GetAttribute("FaceFrames")) or math.huge, #face.labels * face.grid * face.grid)
	task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync(face.labels) end) end)
end
-- `elapsed` seconds into the face; nil puts it away. `steady` (ReduceFlashing) stops before the white fills the screen.
local function faceShow(elapsed, steady)
	if not elapsed then
		faceHolder.Visible = false
		return
	end
	faceHolder.Visible = true
	if #face.labels == 0 or face.frames < 1 then
		local open = smooth(elapsed / 0.9)
		local near = 1 + (steady and 0.6 or 2.4) * smooth((elapsed - 2.3) / 0.7)
		for index, eye in ipairs(face.eyes) do
			local wide = (index == 1 and 0.034 or 0.028) * near
			eye.Size = UDim2.fromScale(wide, wide * open * (0.55 + 0.1 * math.noise(elapsed * 7, index)))
			eye.Visible = open > 0.02 and elapsed < 3
		end
		return
	end
	local index = math.floor(elapsed * face.fps) + 1
	local last = steady and math.max(1, face.frames - 6) or face.frames
	local over = index > face.frames
	index = math.clamp(index, 1, last)
	local per = face.grid * face.grid
	local sheet, cell = (index - 1) // per + 1, (index - 1) % per
	for i, label in ipairs(face.labels) do
		label.Visible = i == sheet and not over
		if i == sheet then label.ImageRectOffset = Vector2.new((cell % face.grid) * face.size, (cell // face.grid) * face.size) end
	end
	for _, eye in ipairs(face.eyes) do eye.Visible = false end
end

local busy = false     -- a recoil, the warning or the kill owns the screen
local dark = {edge = 0, black = 0, pulse = 0}
local function showDark()
	local strength = math.clamp(math.max(dark.edge, dark.pulse), 0, 1)
	for _, frame in ipairs(edges) do frame.BackgroundTransparency = 1 - strength end
	black.BackgroundTransparency = 1 - math.clamp(dark.black, 0, 1)
	-- while it has the victim (the kill and the dark after it) the black is over every other HUD; the death card that
	-- follows is another script's and must not be under it
	gui.DisplayOrder = (busy and dark.black > 0.5) and 2000 or 45   -- ProtectionHUD (the item keys) sits at 1001
	gui.Enabled = strength > 0.01 or dark.black > 0.01
end

---------------------------------------------------------------------------------------------------------------------
-- the stalk: the shadow behind somebody
---------------------------------------------------------------------------------------------------------------------
local view = {pieces = {}, name = nil, alpha = 0, cf = nil, surface = nil, serial = -1, whisperAt = 0, supportAt = 0,
	supported = true, unsupportedUntil = 0, reportAt = 0, seenSent = 0}

local function viewPiece(name)
	local p = view.pieces[name]
	if not p or not p.Part.Parent then
		p = piece(name)
		view.pieces[name] = p
	end
	return p
end

local function hideView(dt)
	view.alpha = math.max(0, view.alpha - dt / 0.2)
	for _, p in pairs(view.pieces) do
		if p.Part.Parent and p.Part.Transparency < 1 then p.Part.Transparency = math.min(1, p.Part.Transparency + dt / 0.2) end
	end
	if view.alpha <= 0 then view.name = nil end
end

local function onScreen(point)
	local camera = workspace.CurrentCamera
	if not camera then return false end
	local v, on = camera:WorldToViewportPoint(point)
	if not on or v.Z <= 0 then return false end
	local size = camera.ViewportSize
	if v.X < size.X * 0.04 or v.X > size.X * 0.96 or v.Y < size.Y * 0.04 or v.Y > size.Y * 0.96 then return false end
	local from = camera.CFrame.Position
	local to = point - from
	local length = to.Magnitude
	if length < 1.2 then return true end
	return cast(from, to.Unit * (length - 0.9)) == nil
end

local function drawStalk(dt, anchor, surface, distance, serial, target)
	local now = os.clock()
	local near = 1 - math.clamp((distance - STRIKE_DISTANCE) / (START_DISTANCE - STRIKE_DISTANCE), 0, 1)
	local name
	if surface == "wall" then
		if now >= view.supportAt then
			-- a pillar face is narrower than its arm is long: it reaches only where there is wall to reach along, and
			-- it stands in the middle of a face too narrow for it
			view.supportAt = now + 0.25
			local left, right = room(anchor, -1, 4, 6), room(anchor, 1, 4, 6)
			view.reachFits = right >= 5.6 and room(anchor, 1, 8, 6) >= 5.6
			view.shift = (left < 2.3 or right < 2.3) and math.clamp((right - left) / 2, -2.3, 2.3) or 0
		end
		name = (distance < 18 and view.reachFits) and "Shade_Reach" or "Shade_Stand"
		anchor *= CFrame.new(view.shift or 0, 0, 0)
	else
		anchor = anchor.Rotation + onWater(anchor.Position)
		if now >= view.supportAt then
			-- the long body needs floor under its far end too, or it would hang over a pool like a sheet of card
			view.supportAt = now + 0.2
			local full = meshes:FindFirstChild("Shade_Crawl")
			local tail = anchor.Position - anchor.UpVector * ((full and full.Size.Y or 15) * 0.9)
			local under = cast(tail + UP * 1.5, -UP * 3.5)
			if under ~= nil and math.abs(under.Position.Y - anchor.Position.Y) < 0.6 then
				view.supported = now >= view.unsupportedUntil
			else
				view.supported, view.unsupportedUntil = false, now + 3   -- no flipping between the two figures at an edge
			end
		end
		name = (distance < 14 or not view.supported) and "Shade_Hands" or "Shade_Crawl"
	end
	local p = viewPiece(name)
	if not p then return end
	if view.serial ~= serial or view.name ~= name or view.surface ~= surface or not view.cf
		or (view.cf.Position - anchor.Position).Magnitude > 7 then
		view.serial, view.name, view.surface, view.cf, view.alpha = serial, name, surface, anchor, 0
	else
		view.cf = view.cf:Lerp(anchor, 1 - math.exp(-12 * dt))
	end
	view.alpha = math.min(1, view.alpha + dt / 0.18)
	local flicker = math.noise(now * 9, serial * 0.37) * 0.07
	local transparency = SHADOW_FAR + (SHADOW_NEAR - SHADOW_FAR) * near + flicker
	local breathe = 1 + math.sin(now * 2.1) * 0.015
	real(p, false)
	if surface == "wall" then
		local scale = 0.9 + 0.3 * near
		pose(p, view.cf, scale * breathe, scale, 0)
	else
		local reach = 1 + math.sin(now * 5.3) * 0.02 * (1 + near)
		pose(p, view.cf * CFrame.new(0, -p.Top * reach, 0), breathe, reach, 0)
	end
	p.Part.Transparency = 1 - (1 - math.clamp(transparency, 0.05, 0.95)) * view.alpha
	for other, q in pairs(view.pieces) do
		if other ~= name and q.Part.Parent then q.Part.Transparency = 1 end
	end

	-- its voice is where it is
	local out = view.cf.LookVector
	local mouth = surface == "wall" and view.cf.Position + UP * 6 + out * 0.8 or view.cf.Position + UP * 1.2
	local hunted = target == player.UserId
	local share = hunted and 1 or 0.6
	local presence = voiceLoop("shade_presence")
	if voice.part then voice.part.CFrame = CFrame.new(mouth) end
	if presence then voiceSet("shade_presence", (0.22 + 0.7 * near) * share, dt) end
	voiceSet("shade_hands", (surface == "floor" and distance < 16) and (0.25 + 0.5 * (1 - distance / 16)) * share or 0, dt)
	if now >= view.whisperAt then
		view.whisperAt = now + (5 - 3.5 * near) * random:NextNumber(0.7, 1.3)
		emit(mouth, (near > 0.72 and random:NextNumber() < 0.45) and "shade_near_" or "shade_whisper_", (0.45 + 0.55 * near) * share)
	end

	if hunted then
		dark.edge = near * near * 0.5
		if now >= view.reportAt and view.alpha > 0.5 then
			local a, b
			if surface == "wall" then
				local height = p.Full.Y * (0.9 + 0.3 * near)
				a, b = view.cf * CFrame.new(0, height * 0.75, -0.5), view.cf * CFrame.new(0, height * 0.35, -0.5)
			else
				a, b = view.cf * CFrame.new(0, 0, -0.4), view.cf * CFrame.new(0, -3.5, -0.4)
			end
			if onScreen(a.Position) or onScreen(b.Position) then
				view.reportAt = now + 0.1
				view.seenSent += 1
				player:SetAttribute("Level2ShadeSeenSent", view.seenSent)
				remote:FireServer("seen", serial)
			end
		end
	else
		dark.edge = 0
	end
	player:SetAttribute("Level2ShadeView", string.format("%s %s %.0f", surface, name, distance))
end

---------------------------------------------------------------------------------------------------------------------
-- animations that run on their own for a moment
---------------------------------------------------------------------------------------------------------------------
local running = {}
local function run(seconds, during, after)
	local t0 = os.clock()
	local entry
	entry = {step = function()
		local t = os.clock() - t0
		if t >= seconds then
			running[entry] = nil
			during(seconds, 1)
			if after then after() end
		else
			during(t, t / seconds)
		end
	end}
	running[entry] = true
	return entry
end

local function playRecoil(anchor, surface)
	local name = view.name or (surface == "wall" and "Shade_Stand" or "Shade_Hands")
	local p = piece(name)
	if not p then return end
	local start = view.cf or anchor
	local from = 1 - math.clamp(SHADOW_NEAR, 0, 1)
	view.alpha, view.name = 0, nil
	for _, q in pairs(view.pieces) do if q.Part.Parent then q.Part.Transparency = 1 end end
	local camera = workspace.CurrentCamera
	local side = 1
	if camera and surface == "wall" then
		side = (start.Position - camera.CFrame.Position):Dot(start.RightVector) >= 0 and 1 or -1   -- away from the middle of the view
	end
	emit(anchor.Position + UP * 3, "shade_recoil_", 0.9)
	emit(anchor.Position + UP * 3, "shade_slide_", 0.7)
	player:SetAttribute("Level2ShadeEvent", "recoil")
	run(0.45, function(_, u)
		local e = u * u
		if surface == "wall" then
			pose(p, start * CFrame.new(side * 14 * e, 0, 0), 1 + 0.6 * e, 1 - 0.15 * e, 0)
		else
			pose(p, start * CFrame.new(0, -p.Top - 18 * e, 0), 1 - 0.3 * e, 1 + 0.5 * e, 0)
		end
		p.Part.Transparency = 1 - from * (1 - u)
	end, function() drop(p) end)
end

local function playWarn(userId, floorPoint, direction)
	local p = piece("Shade_Hands")
	if not p then return end
	floorPoint = onWater(floorPoint)
	local mine = userId == player.UserId
	local calm = player:GetAttribute("ReduceCameraShake") == true
	player:SetAttribute("Level2ShadeEvent", "warn")
	emit(floorPoint + UP, "shade_near_", 1)
	emit(floorPoint + UP, "shade_whisper_e", 1)
	local length = p.Top
	local function at(reach)   -- fingertips `reach` studs from the feet, on the shadow's side
		local tip = floorPoint + direction * reach + UP * 0.02
		return CFrame.lookAt(tip, tip + UP, -direction) * CFrame.new(0, -length, 0)
	end
	run(0.16, function(_, u)
		pose(p, at(5.5 - 6.3 * smooth(u)), 1, 1, 0)
		p.Part.Transparency = 0.5 - 0.35 * u
	end, function()
		run(0.6, function(t)
			local shake = calm and 0 or math.noise(t * 31, 0.3) * 0.12
			pose(p, at(-0.8 + shake), 1.05, 1, 0)
			p.Part.Transparency = 0.15
			if mine then dark.pulse = 0.85 end
		end, function()
			emit(floorPoint + direction * 4 + UP, "shade_slide_", 0.8)
			run(0.4, function(_, u)
				pose(p, at(-0.8 + 20 * u * u), 1 - 0.3 * u, 1 + 0.4 * u, 0)
				p.Part.Transparency = 0.15 + 0.85 * u
				if mine then dark.pulse = 0.85 * (1 - u) end
			end, function()
				drop(p)
				dark.pulse = 0
			end)
		end)
	end)
end

local HUSHED = {"RoundExitGui", "FoundFootageHUD", "FlashlightPopup"}
local function playKill(userId, floorPoint, direction, seconds, realm)
	local mine = userId == player.UserId
	local riser, pool = piece("Shade_Rise"), piece("Shade_Pool")
	if not riser or not pool then return end
	floorPoint = onWater(floorPoint) - UP * 0.1   -- in water it all comes up through the surface
	busy = true
	player:SetAttribute("Level2ShadeEvent", "kill")
	local calm = player:GetAttribute("ReduceCameraShake") == true
	local SINK_FROM, SINK = 1.5, 7
	local GRAB = 1.3
	-- it rises behind the victim, nearer when a wall is in the way
	local back = 4.2
	local wall = cast(floorPoint + UP * 3, direction * (back + 1.4))
	if wall then back = math.max(1.6, wall.Distance - 1.4) end
	local riseAt = floorPoint + direction * back
	local riseCF = CFrame.lookAt(riseAt, riseAt - direction)
	local riserScale = 1.12
	local poolYaw = random:NextNumber(0, math.pi * 2)
	local poolAt = floorPoint + UP * 0.15
	local arms = {}
	for i = 1, ARMS do
		local angle = (i - 0.5) / ARMS * math.pi * 2 + random:NextNumber(-0.25, 0.25)
		local at = floorPoint + Vector3.new(math.sin(angle), 0, math.cos(angle)) * random:NextNumber(2.3, 3.3)
		local open, grip = piece("Shade_Arm"), piece("Shade_ArmGrip")
		if open and grip then
			real(open, true); real(grip, true)
			table.insert(arms, {open = open, grip = grip, at = at, delay = 0.55 + (i - 1) * 0.07 + random:NextNumber(0, 0.04),
				scale = random:NextNumber(0.55, 0.8), lean = random:NextNumber(8, 16)})
		end
	end
	emit(floorPoint + UP * 2, "shade_emerge", 1)
	task.delay(GRAB - 0.02, function() emit(floorPoint + UP * 3, "shade_grab", 1) end)
	task.delay(SINK_FROM, function() emit(floorPoint + UP * 2, "shade_drag", 1) end)
	if mine then flatSound("shade_sting", 0.8) end

	local camera = workspace.CurrentCamera
	local startCF, startFov = camera and camera.CFrame, camera and camera.FieldOfView
	local hushed = {}
	local realmSounds = {}
	if mine then faceSetup() end
	if mine and camera then camera.CameraType = Enum.CameraType.Scriptable end
	local t0 = os.clock()
	-- a play test can stretch the whole sequence to look at it (the server's own clock has to be stretched to match)
	local slow = math.clamp(tonumber(player:GetAttribute("Level2ShadeTestSlow")) or 1, 1, 20)

	local function frame()
		local t = (os.clock() - t0) / slow
		local sunk = math.clamp((t - SINK_FROM) / (seconds - SINK_FROM), 0, 1)
		sunk = sunk * sunk * SINK
		-- the dark spreads under their feet
		local spread = 0.3 + 3.9 * smooth(t / 0.9)   -- the blot is 3 studs across: about 13 at its widest
		pool.Part.Size = Vector3.new(pool.Full.X * spread, math.max(0.04, pool.Full.Y), pool.Full.Z * spread)
		pool.Part.CFrame = CFrame.new(poolAt) * CFrame.Angles(0, poolYaw, 0)
		pool.Part.Transparency = 0.06
		-- the shadow gets its depth back and comes up out of the floor
		local up = smooth((t - 0.1) / 1.0)
		local depth = 0.03 + 0.97 * smooth((t - 0.1) / 0.6)
		real(riser, t > 0.3)
		pose(riser, riseCF * CFrame.new(0, -riser.Full.Y * riserScale * (1 - up) - sunk * 0.5, 0), riserScale, riserScale, depth, 0)
		riser.Part.Transparency = t > 0.3 and 0 or 0.15
		-- its hands
		for _, arm in ipairs(arms) do
			local out = smooth((t - arm.delay) / 0.26)
			local closed = t >= GRAB
			local lean = arm.lean + (closed and 22 * smooth((t - GRAB) / 0.12) or 0)
			local length = arm.open.Full.Y * arm.scale
			local base = arm.at - UP * (length * (1 - out) + sunk)
			local cf = CFrame.lookAt(base, Vector3.new(floorPoint.X, base.Y, floorPoint.Z)) * CFrame.Angles(-math.rad(lean), 0, 0)
			local shown, hidden = closed and arm.grip or arm.open, closed and arm.open or arm.grip
			pose(shown, cf, arm.scale, arm.scale, 1, 0)
			shown.Part.Transparency = out > 0 and 0 or 1
			hidden.Part.Transparency = 1
		end
		if not (mine and camera and startCF) then return end
		if t >= seconds + 0.25 then
			-- down in the dark: nothing but black, and then its face
			local inDark = t - seconds - 0.25
			dark.black, dark.edge = 1, 0
			faceShow(inDark, player:GetAttribute("ReduceFlashing") == true)
			if not realmSounds[1] then realmSounds[1] = true; flatSound("shade_whisper_f", 0.9) end
			if inDark > 1.0 and not realmSounds[2] then realmSounds[2] = true; flatSound("shade_near_a", 1) end
			if inDark > 2.45 and not realmSounds[3] then realmSounds[3] = true; flatSound("shade_whisper_e", 1) end
			return
		end
		-- the victim: turned to face it, held, and taken down as the dark closes
		for _, name in ipairs(HUSHED) do
			local other = player.PlayerGui:FindFirstChild(name)
			if other and other:IsA("ScreenGui") and other.Enabled then other.Enabled = false; hushed[other] = true end
		end
		local own = player.Character
		if own then
			for _, part in ipairs(own:GetDescendants()) do
				if part:IsA("BasePart") or part:IsA("Decal") then part.LocalTransparencyModifier = 1 end
			end
		end
		local eye = startCF.Position.Y - floorPoint.Y
		local pulled = math.clamp((t - SINK_FROM) / (seconds - 0.3 - SINK_FROM), 0, 1)
		local position = startCF.Position - UP * (pulled * pulled * math.max(eye - 0.5, 0.5))
		local tremble = (0.02 + 0.06 * pulled) * (calm and 0.2 or 1)
		position += Vector3.new(math.noise(t * 17, 0.5) * tremble, math.noise(0.5, t * 19) * tremble, 0)
		local head = riseAt + UP * (riser.Full.Y * riserScale * up * 0.86)
		local gaze = head:Lerp(riseAt + UP * 8.5, pulled * 0.8)
		local aim = CFrame.lookAt(position, gaze) * CFrame.Angles(0, 0, math.rad((calm and 1 or 4) * math.sin(t * 2.6) * pulled))
		camera.CFrame = CFrame.new(position) * startCF.Rotation:Lerp(aim.Rotation, smooth(t / 0.5))
		local roll = tonumber(player:GetAttribute("Level2ShadeTestRoll"))   -- a play test on a letterbox viewport
		if roll then camera.CFrame *= CFrame.Angles(0, 0, math.rad(roll)) end
		local outside = player:GetAttribute("Level2ShadeTestCamera")        -- or watching it from where a friend would stand
		if typeof(outside) == "CFrame" then
			camera.CFrame = outside
			dark.edge, dark.black = 0, 0
			if own then
				for _, part in ipairs(own:GetDescendants()) do
					if part:IsA("BasePart") or part:IsA("Decal") then part.LocalTransparencyModifier = 0 end
				end
			end
		end
		camera.FieldOfView = startFov + 8 * smooth((t - GRAB) / 0.4)
		dark.edge = 0.6 * smooth(t / 1.2) + 0.4 * pulled
		dark.black = smooth((t - 2.2) / 0.8)
	end

	local function finish()
		drop(riser); drop(pool)
		for _, arm in ipairs(arms) do drop(arm.open); drop(arm.grip) end
		busy = false
		if not mine then return end
		dark.black, dark.edge = 1, 0
		faceShow(nil)
		task.spawn(function()
			-- dead in the level: the black holds until the spectate view owns the screen (or the body turned out to live)
			local held = os.clock()
			while os.clock() - held < 2.5 and player:GetAttribute("Spectating") ~= true do
				local own = player.Character
				local humanoid = own and own:FindFirstChildOfClass("Humanoid")
				if os.clock() - held > 1.2 and humanoid and humanoid.Health > 0 then break end
				task.wait(0.1)
			end
			task.wait(0.3)
			if camera then
				camera.FieldOfView = startFov
				if player:GetAttribute("Spectating") ~= true then camera.CameraType = Enum.CameraType.Custom end
			end
			for other in pairs(hushed) do if other.Parent then other.Enabled = true end end
			local faded = os.clock()
			while os.clock() - faded < 1.2 do
				dark.black = 1 - (os.clock() - faded) / 1.2
				task.wait()
			end
			dark.black = 0
		end)
	end

	run((seconds + 0.25 + (mine and realm or 0)) * slow, frame, finish)
end

-- A play test can look at the face alone: player attribute Level2ShadeTestFace = true plays it once on black.
local function playFaceAlone()
	faceSetup()
	local slow = math.clamp(tonumber(player:GetAttribute("Level2ShadeTestSlow")) or 1, 1, 20)
	busy = true
	run(3.4 * slow, function(t)
		dark.black = 1
		faceShow(t / slow, false)
		player:SetAttribute("Level2ShadeView", string.format("face %.2f, %d sheets, %d frames", t / slow, #face.labels, face.frames))
	end, function()
		faceShow(nil)
		dark.black = 0
		busy = false
	end)
end

remote.OnClientEvent:Connect(function(what, _serial, a, b, c, d, e)
	if not inLevel() then return end
	if what == "recoil" and typeof(a) == "CFrame" then
		playRecoil(a, b)
	elseif what == "warn" and typeof(b) == "Vector3" and typeof(c) == "Vector3" then
		playWarn(a, b, c)
	elseif what == "kill" and typeof(b) == "Vector3" and typeof(c) == "Vector3" then
		playKill(a, b, c, type(d) == "number" and d or 3.6, type(e) == "number" and e or 0)
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- glimpses: a shadow on a far wall or pillar, at the edge of what you see, for less than a second. Nobody's but yours.
---------------------------------------------------------------------------------------------------------------------
local glimpse = {nextAt = os.clock() + random:NextNumber(25, 45), count = 0, live = nil}

local function findWall()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local cf = camera.CFrame
	local look = flat(cf.LookVector)
	if not look then return nil end
	for _ = 1, 10 do
		local yaw = math.rad(random:NextNumber(26, 58)) * (random:NextNumber() < 0.5 and -1 or 1)
		local direction = CFrame.fromAxisAngle(UP, yaw):VectorToWorldSpace(look)
		local hit = cast(cf.Position, direction * 95)
		local normal = hit and math.abs(hit.Normal.Y) < 0.3 and flat(hit.Normal)
		if normal and hit.Distance > 22 and normal:Dot(-direction) > 0.35 then
			local foot = cast(hit.Position + normal * 0.35, -UP * 18)
			if foot and foot.Normal.Y > 0.7 then
				local feet = Vector3.new(hit.Position.X, foot.Position.Y, hit.Position.Z)
				local tangent = normal:Cross(UP)
				local whole = true
				-- the wall has to be there behind its head and behind both shoulders
				for _, probe in ipairs({UP * 8, UP * 5 + tangent * 1.6, UP * 5 - tangent * 1.6, UP * 1.5}) do
					local behind = cast(feet + normal * 1.5 + probe, -normal * 3)
					if not behind or math.abs(behind.Distance - 1.5) > 0.6 then whole = false; break end
				end
				if whole and onScreen(feet + UP * 5 + normal * 0.6) then return CFrame.lookAt(feet, feet + normal), hit.Distance end
			end
		end
	end
	return nil
end

local function startGlimpse()
	local origin, distance = findWall()
	if not origin then return false end
	local roll = random:NextNumber()
	local name = roll < 0.55 and "Shade_Stand" or roll < 0.85 and "Shade_Reach" or "Shade_Claw"
	if name == "Shade_Reach" and (room(origin, 1, 8, 7) < 6.5 or room(origin, 1, 4, 7) < 6.5) then name = "Shade_Stand" end
	if name == "Shade_Claw" and (room(origin, 1, 6, 3.5) < 3 or room(origin, -1, 6, 3.5) < 3) then name = "Shade_Stand" end
	local p = piece(name)
	if not p then return false end
	if name == "Shade_Claw" then origin *= CFrame.new(0, random:NextNumber(1.5, 4), 0) end
	local scale = random:NextNumber(0.85, 1.15) * (1 + math.clamp((distance - 40) / 110, 0, 0.35))
	local hold = random:NextNumber(0.35, 0.9)
	local side = random:NextNumber() < 0.5 and -1 or 1
	local centre = (origin * CFrame.new(0, p.Full.Y * scale * 0.5, -0.5)).Position
	local t0 = os.clock()
	local leaving
	glimpse.count += 1
	player:SetAttribute("Level2ShadeGlimpses", glimpse.count)
	player:SetAttribute("Level2ShadeView", "glimpse " .. name)
	if random:NextNumber() < 0.5 then emit(centre, "shade_glimpse_", 0.5) end
	glimpse.live = function()
		local t = os.clock() - t0
		local camera = workspace.CurrentCamera
		if not leaving then
			-- it does not wait to be looked at
			local stared = camera and t > 0.15 and camera.CFrame.LookVector:Dot((centre - camera.CFrame.Position).Unit) > math.cos(math.rad(11))
			if t >= 0.1 + hold or stared then
				leaving = t
				if stared then emit(centre, "shade_slide_", 0.45) end
			end
		end
		if leaving then
			local u = (t - leaving) / 0.25
			if u >= 1 then
				drop(p)
				glimpse.live = nil
				return
			end
			pose(p, origin * CFrame.new(side * 5 * u * u, 0, 0), scale * (1 + 0.4 * u), scale, 0)
			p.Part.Transparency = 0.5 + 0.5 * u
		else
			pose(p, origin, scale, scale, 0)
			p.Part.Transparency = 1 - 0.5 * math.clamp(t / 0.1, 0, 1)
		end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
local wasIn = false
RunService.RenderStepped:Connect(function(dt)
	local here = inLevel()
	if not here then
		if wasIn then
			wasIn = false
			table.clear(running)
			glimpse.live = nil
			view.pieces, view.name, view.cf, view.alpha = {}, nil, nil, 0
			voice.loops, voice.part = {}, nil
			if folder then folder:Destroy(); folder = nil end
			if not busy then
				dark.edge, dark.pulse, dark.black = 0, 0, 0
			end
			busy = false
			showDark()
			player:SetAttribute("Level2ShadeView", nil)
		end
		return
	end
	if not wasIn then
		wasIn = true
		faceSetup()   -- its pictures are fetched now, not in the second they are needed
		glimpse.nextAt = os.clock() + random:NextNumber(25, 45)
	end
	local turn = {}
	for entry in pairs(running) do table.insert(turn, entry) end   -- a step may end its entry and start the next
	for _, entry in ipairs(turn) do entry.step() end
	local phase = bank:GetAttribute("ShadePhase")
	local anchor = bank:GetAttribute("ShadeAnchor")
	if phase == "stalk" and typeof(anchor) == "CFrame" and not busy then
		drawStalk(dt, anchor, bank:GetAttribute("ShadeSurface") or "floor", bank:GetAttribute("ShadeDistance") or START_DISTANCE,
			bank:GetAttribute("ShadeSerial") or 0, bank:GetAttribute("ShadeTarget") or 0)
	else
		if view.name then glimpse.nextAt = math.max(glimpse.nextAt, os.clock() + 12) end   -- no glimpse on the heels of a stalk
		hideView(dt)
		voiceQuiet(dt)
		if not busy then dark.edge = math.max(0, dark.edge - dt * 1.5) end
		if phase == "idle" then player:SetAttribute("Level2ShadeView", glimpse.live and player:GetAttribute("Level2ShadeView") or "none") end
	end
	if player:GetAttribute("Level2ShadeTestFace") == true then
		player:SetAttribute("Level2ShadeTestFace", "playing")
		playFaceAlone()
	end
	if glimpse.live then
		glimpse.live()
	elseif player:GetAttribute("Level2ShadeTestGlimpse") == true then
		-- a play test asks for one now, whatever the timers say
		player:SetAttribute("Level2ShadeTestGlimpse", startGlimpse() and "made" or "no wall")
	elseif phase == "idle" and not busy and bank:GetAttribute("ShadeLive") == true and os.clock() >= glimpse.nextAt then
		glimpse.nextAt = os.clock() + (startGlimpse() and random:NextNumber(GLIMPSE_GAP[1], GLIMPSE_GAP[2]) or 3)
	end
	showDark()
end)
