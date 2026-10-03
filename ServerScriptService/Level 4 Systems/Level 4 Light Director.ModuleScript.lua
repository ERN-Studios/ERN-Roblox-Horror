-- Level 4 Light Director: the server's single authority over light in the cinema round.
-- The Usher may only stand in the dark, so "dark" must mean the same thing for every player and for the AI: this
-- module owns it. Light zones are spatial clusters exported from Blender: every light holder and every pooled neon
-- MeshPart carries attribute L4Zone, and one L4LightZone marker per zone gives its floor centre and Radius.
--   Preview     no round: everything on, the client's cosmetic flicker runs (walk-in preview).
--   Off         round start: every zone dark, stars off (only exit signs).
--   PoweringUp  the "woooow": zones switch on in a wave ordered by distance from the service room.
--   On          everything lit for a while.
--   Failing     blinks escalate with each reel loaded; a few dead zones stay dark (the Usher's homes).
--   Finale      everything dark except the three screens.
-- Transitions are announced to clients (Level 4 Remotes.ClientEvent {Type="Zones"}) a moment before the server
-- applies them, so each client can stutter its own lights locally (or fade them with ReduceFlashing) and the final
-- replicated state is identical for everyone.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))

local LightDirector = {}

local STUTTER_LEAD = 0.45        -- seconds between the announcement and the authoritative switch
local STAR_TAGS = { "L4StarTwinkleA", "L4StarTwinkleB", "L4StarTwinkleC" }

local session = 0
local model, stateFolder, clientEvent
local zones = {}                 -- array of zone records
local zoneById = {}
local power = "Preview"
local escalation = 0
local deadZones = {}
local blinkThread, waveThread
local originals = {}             -- instance -> saved properties (restored on Stop)
local screenLights = {}
local epoch = 0                  -- bumped on every power-phase change; queued transitions of an older phase are void
local emergencyLights = {}       -- zone id -> the mount of the dim red light that burns while the power is off

local function now()
	return workspace:GetServerTimeNow()
end

local function remember(inst, props)
	if originals[inst] then return end
	local saved = {}
	for _, k in ipairs(props) do saved[k] = inst[k] end
	originals[inst] = saved
end

local function newZone(id)
	local zone = { Id = id, Lights = {}, Neon = {}, Units = {}, On = true, Center = nil, Radius = 30, Players = 0 }
	zones[#zones + 1] = zone
	zoneById[id] = zone
	return zone
end

local function zoneFor(id)
	return zoneById[id] or newZone(id)
end

local function isStar(part)
	for _, tag in ipairs(STAR_TAGS) do
		if CollectionService:HasTag(part, tag) then return true end
	end
	return false
end

local function collect(root)
	table.clear(zones); table.clear(zoneById)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Light") then
			local holder = d.Parent
			local id = holder and holder:GetAttribute("L4Zone")
			if id then
				local zone = zoneFor(id)
				remember(d, { "Enabled", "Brightness" })
				-- clients stutter zone lights through Brightness; they need the authored value
				if d:GetAttribute("L4Brightness") == nil then d:SetAttribute("L4Brightness", d.Brightness) end
				table.insert(zone.Lights, d)
			end
		elseif d:IsA("BasePart") then
			local id = d:GetAttribute("L4Zone")
			if id and d.Material == Enum.Material.Neon then
				remember(d, { "Material", "Color" })
				-- clients render zone changes themselves; they need the lit colour even while it is dark
				if d:GetAttribute("L4OnColor") == nil then d:SetAttribute("L4OnColor", d.Color) end
				table.insert(zoneFor(id).Neon, d)
			end
			if CollectionService:HasTag(d, "L4LightZone") then
				local zid = d:GetAttribute("Zone")
				if zid then
					local zone = zoneFor(zid)
					zone.Center = d.Position
					zone.Radius = d:GetAttribute("Radius") or math.max(d.Size.X, d.Size.Z) * 0.5
				end
			end
		end
	end
	-- a zone without a marker gets the centre of its lights
	for _, zone in ipairs(zones) do
		if not zone.Center then
			local sum, n = Vector3.zero, 0
			for _, l in ipairs(zone.Lights) do
				if l.Parent and l.Parent:IsA("BasePart") then sum += l.Parent.Position; n += 1 end
			end
			zone.Center = n > 0 and sum / n or Vector3.zero
		end
	end
	table.sort(zones, function(a, b) return a.Id < b.Id end)
end

local function publish()
	if not stateFolder then return end
	local bits = table.create(#zones)
	for i, zone in ipairs(zones) do bits[i] = zone.On and "1" or "0" end
	stateFolder:SetAttribute("Level4_PowerState", power)
	stateFolder:SetAttribute("Level4_ZoneStates", table.concat(bits))
	stateFolder:SetAttribute("Level4_ZoneSerial", (stateFolder:GetAttribute("Level4_ZoneSerial") or 0) + 1)
end

-- authoritative switch of one zone (lights + neon)
local function applyZone(zone, on)
	local changed = zone.On ~= on
	zone.On = on
	if changed and LightDirector.OnZoneChanged then task.spawn(LightDirector.OnZoneChanged, zone.Id, on) end
	for _, l in ipairs(zone.Lights) do
		if l.Parent then
			local o = originals[l]
			l.Enabled = on and (o and o.Enabled ~= false)
		end
	end
	for _, p in ipairs(zone.Neon) do
		if p.Parent then
			local o = originals[p]
			if on then
				p.Material = o and o.Material or Enum.Material.Neon
				p.Color = o and o.Color or p.Color
			else
				p.Material = Enum.Material.SmoothPlastic
				p.Color = (o and o.Color or p.Color):Lerp(Color3.new(0, 0, 0), 0.82)
			end
		end
	end
end

local function setStars(on)
	if not model then return end
	for _, tag in ipairs(STAR_TAGS) do
		for _, part in ipairs(CollectionService:GetTagged(tag)) do
			if part:IsA("BasePart") and part:IsDescendantOf(model) then
				remember(part, { "Transparency" })
				part.Transparency = on and (originals[part].Transparency or 0) or 1
			end
		end
	end
	if stateFolder then stateFolder:SetAttribute("Level4_StarsOn", on) end
end

-- announce, then switch: changes = { {zone, on}, ... }
local function transition(changes, lead)
	if #changes == 0 then return end
	local mySession, myEpoch = session, epoch
	local at = now() + (lead or STUTTER_LEAD)
	local payload = {}
	for _, c in ipairs(changes) do payload[#payload + 1] = { c[1].Id, c[2] } end
	if clientEvent then clientEvent:FireAllClients({ Type = "Zones", Changes = payload, At = at }) end
	task.delay(lead or STUTTER_LEAD, function()
		if session ~= mySession or epoch ~= myEpoch then return end
		for _, c in ipairs(changes) do applyZone(c[1], c[2]) end
		publish()
	end)
end

local function allZones(on, lead)
	local changes = {}
	for _, zone in ipairs(zones) do
		if zone.On ~= on then changes[#changes + 1] = { zone, on } end
	end
	if lead == 0 then
		for _, c in ipairs(changes) do applyZone(c[1], c[2]) end
		publish()
	else
		transition(changes, lead)
	end
end

local function cancelThreads()
	if blinkThread then task.cancel(blinkThread); blinkThread = nil end
	if waveThread then task.cancel(waveThread); waveThread = nil end
end

local function playerZones()
	local counts = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then
			local _, zid = LightDirector.ZoneAt(root.Position)
			if zid then counts[zid] = (counts[zid] or 0) + 1 end
		end
	end
	return counts
end

local function darkFraction()
	if #zones == 0 then return 0 end
	local dark = 0
	for _, zone in ipairs(zones) do if not zone.On then dark += 1 end end
	return dark / #zones
end

local function blinkLoop(mySession)
	local rng = Random.new()
	while session == mySession and power == "Failing" do
		local level = math.clamp(escalation + 1, 1, 4)
		task.wait(Configuration.Failing.BlinkEvery[level] * rng:NextNumber(0.7, 1.3))
		if session ~= mySession or power ~= "Failing" then break end
		if darkFraction() < Configuration.Failing.MaxDarkFraction[level] then
			local occupied = playerZones()
			local candidates = {}
			for _, zone in ipairs(zones) do
				if zone.On and not deadZones[zone.Id] then
					local weight = (occupied[zone.Id] and rng:NextNumber() < Configuration.Failing.AvoidPlayerZoneChance)
						and 0.35 or 1
					candidates[#candidates + 1] = { zone, weight * (1 + escalation * 0.5 * (occupied[zone.Id] and 1 or 0)) }
				end
			end
			local total = 0
			for _, c in ipairs(candidates) do total += c[2] end
			if total > 0 then
				local pick, acc = rng:NextNumber(0, total), 0
				for _, c in ipairs(candidates) do
					acc += c[2]
					if pick <= acc then
						local zone = c[1]
						local range = Configuration.Failing.OffSeconds[level]
						local off = rng:NextNumber(range[1], range[2])
						transition({ { zone, false } })
						task.delay(STUTTER_LEAD + off, function()
							if session == mySession and power == "Failing" and not deadZones[zone.Id] then
								transition({ { zone, true } })
							end
						end)
						break
					end
				end
			end
		end
	end
end

local function chooseDeadZones(avoid)
	table.clear(deadZones)
	local rng = Random.new()
	local pool = {}
	for _, zone in ipairs(zones) do
		local blocked = false
		for _, p in ipairs(avoid or {}) do
			if (zone.Center - p).Magnitude <= zone.Radius + 6 then blocked = true; break end
		end
		if not blocked then pool[#pool + 1] = zone end
	end
	for _ = 1, math.min(Configuration.Failing.DeadZones, #pool) do
		local i = rng:NextInteger(1, #pool)
		deadZones[pool[i].Id] = true
		table.remove(pool, i)
	end
end

-- ---------------------------------------------------------------- public API

-- EMERGENCY_LIGHTS_20261002 (owner: "so dark before the power you can't see anything"): while the power is Off,
-- one dim red-amber battery light per zone burns at the zone's lowest light holder, so rooms and silhouettes read
-- and the flashlight is still the main light. They are server lights with no L4Brightness attribute, so the round
-- client's zone renderer never touches them; each goes out when the power-up wave reaches its zone.
-- MaxHeight: a zone's lowest holder can still hang high (auditorium star fills, hanging fixtures), so the glow sits
-- on an attachment at most this far above the floor under the holder.
local EMERGENCY = { Color = Color3.fromRGB(255, 86, 48), Brightness = 1.2, Range = 30, MaxHeight = 12 }
local function createEmergencyLights()
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	for _, zone in ipairs(zones) do
		local best, bestY
		for _, l in ipairs(zone.Lights) do
			local holder = l.Parent
			if holder and holder:IsA("BasePart") and (not bestY or holder.Position.Y < bestY) then
				best, bestY = holder, holder.Position.Y
			end
		end
		if best then
			local mount = Instance.new("Attachment")
			mount.Name = "L4EmergencyMount"
			mount.Parent = best
			local floor = workspace:Raycast(best.Position, Vector3.new(0, -80, 0), params)
			if floor then
				mount.WorldPosition = Vector3.new(best.Position.X,
					math.min(best.Position.Y, floor.Position.Y + EMERGENCY.MaxHeight), best.Position.Z)
			end
			local light = Instance.new("PointLight")
			light.Name = "L4EmergencyLight"
			light.Color = EMERGENCY.Color
			light.Brightness = EMERGENCY.Brightness
			light.Range = EMERGENCY.Range
			light.Shadows = false
			light.Parent = mount
			emergencyLights[zone.Id] = mount
		end
	end
end

local function emergencyOff(zoneId)
	local light = emergencyLights[zoneId]
	if light then
		emergencyLights[zoneId] = nil
		light:Destroy()
	end
end

local function clearEmergencyLights()
	for id in pairs(emergencyLights) do emergencyOff(id) end
end

function LightDirector.Start(manifest, generation)
	LightDirector.Stop()
	session += 1
	model = manifest.World
	stateFolder = manifest.State
	clientEvent = manifest.ClientEvent
	collect(model)
	LightDirector.ProtectedPoints = manifest.ProtectedLightPoints or {}
	power = "Off"
	escalation = 0
	allZones(false, 0)
	setStars(false)
	createEmergencyLights()
	publish()
	return #zones
end

function LightDirector.Stop()
	session += 1
	cancelThreads()
	clearEmergencyLights()
	for _, l in ipairs(screenLights) do if l.Parent then l:Destroy() end end
	table.clear(screenLights)
	for inst, saved in pairs(originals) do
		if inst.Parent then
			for k, v in pairs(saved) do pcall(function() inst[k] = v end) end
		end
	end
	table.clear(originals)
	for _, zone in ipairs(zones) do zone.On = true end
	power = "Preview"
	escalation = 0
	table.clear(deadZones)
	if stateFolder then
		publish()
		stateFolder:SetAttribute("Level4_StarsOn", true)
	end
end

function LightDirector.PowerState()
	return power
end

function LightDirector.ZoneCount()
	return #zones
end

function LightDirector.SetEscalation(level)
	escalation = math.clamp(math.floor(level or 0), 0, 3)
	if stateFolder then stateFolder:SetAttribute("Level4_Escalation", escalation) end
end

-- the power comes back: the wave from the service room, then fully lit, then Failing
function LightDirector.PowerUp(origin, onFailing)
	if power ~= "Off" then return end
	cancelThreads()
	epoch += 1
	power = "PoweringUp"
	publish()
	local mySession = session
	local ordered = table.clone(zones)
	table.sort(ordered, function(a, b)
		return (a.Center - origin).Magnitude < (b.Center - origin).Magnitude
	end)
	local wave = Configuration.Sequence.PowerUpWaveSeconds
	local startAt = now() + 0.6
	if stateFolder then stateFolder:SetAttribute("Level4_PowerUpStartedAt", startAt) end
	if clientEvent then clientEvent:FireAllClients({ Type = "PowerUp", At = startAt, Wave = wave, Origin = origin }) end
	waveThread = task.spawn(function()
		task.wait(0.6)
		local step = wave / math.max(#ordered, 1)
		for _, zone in ipairs(ordered) do
			if session ~= mySession then return end
			transition({ { zone, true } }, 0.25)
			task.delay(0.25, function() if session == mySession then emergencyOff(zone.Id) end end)
			task.wait(step)
		end
		task.wait(0.3)
		if session ~= mySession then return end
		setStars(true)
		power = "On"
		publish()
		task.wait(Configuration.Sequence.FullyLitSeconds)
		if session ~= mySession then return end
		chooseDeadZones(LightDirector.ProtectedPoints)
		local dead = {}
		for _, zone in ipairs(zones) do
			if deadZones[zone.Id] then dead[#dead + 1] = { zone, false } end
		end
		transition(dead)
		power = "Failing"
		publish()
		if onFailing then task.spawn(onFailing) end
		waveThread = nil
		blinkThread = task.spawn(blinkLoop, mySession)
	end)
end

-- everything dark except the screens
function LightDirector.Finale(screens)
	cancelThreads()
	epoch += 1
	power = "Finale"
	allZones(false, STUTTER_LEAD)
	setStars(true)
	for _, screen in ipairs(screens or {}) do
		local light = Instance.new("SurfaceLight")
		light.Name = "L4FinaleScreenGlow"
		light.Face = Enum.NormalId.Front
		light.Range = 40
		light.Angle = 120
		light.Brightness = 2.2
		light.Color = Color3.fromRGB(235, 240, 255)
		light.Parent = screen
		screenLights[#screenLights + 1] = light
		-- both faces: the marker's front may face either way
		local back = light:Clone()
		back.Face = Enum.NormalId.Back
		back.Parent = screen
		screenLights[#screenLights + 1] = back
	end
	publish()
end

-- which zone covers a point (nearest covering centre), and whether it is on
function LightDirector.ZoneAt(position)
	local best, bestD
	for _, zone in ipairs(zones) do
		local d = Vector3.new(position.X - zone.Center.X, 0, position.Z - zone.Center.Z).Magnitude
		if d <= zone.Radius and math.abs(position.Y - zone.Center.Y) < 24 and (not bestD or d < bestD) then
			best, bestD = zone, d
		end
	end
	return best, best and best.Id or nil
end

function LightDirector.IsZoneOn(id)
	local zone = zoneById[id]
	return zone ~= nil and zone.On
end

-- the AI's question: may the Usher stand here?
function LightDirector.IsLit(position)
	if power == "Preview" then return true end
	if power == "Off" or power == "Finale" then return false end
	local zone = LightDirector.ZoneAt(position)
	return zone ~= nil and zone.On
end

function LightDirector.IsDark(position)
	return not LightDirector.IsLit(position)
end

return LightDirector
