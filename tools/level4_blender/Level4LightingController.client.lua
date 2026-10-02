-- Level 4 Lighting Controller (LocalScript in StarterPlayerScripts; installed 2026-10-01).
-- Client-side interior grade for the Blender cinema (Workspace."Level 4 Cinema Blender"), modelled on the
-- Level 2 controller: while the local character stands inside the model's stored bounds (BoundsCenter /
-- BoundsSize, set by tools/level4_blender/place.luau) it applies the "Synthwave Grid" grade (owner pick
-- 2026-09-30: deep blacks, magenta/cyan neon that blooms, a slight purple haze), designed for
-- LightingStyle Realistic (the fixtures are real local lights with shadows), and it restores exactly what it
-- found when the character leaves, dies or the model goes away.
-- v3 (2026-10-01, owner: neon is the light, a Rolls-Royce star ceiling, "it should already be dark"): a darker
-- baseline (low ambient, so a neon that blinks off leaves its corner dark) with the neon blooming harder, and the
-- star ceiling twinkles: the pooled star MeshParts carry CollectionService tags L4StarTwinkleA/B/C (place.luau),
-- and while we own the grade each group drifts to a random Transparency 0..TWINKLE_MAX every TWINKLE_SECONDS
-- (a handful of tweens, not one per star). ReduceFlashing (anything but an explicit false) fades them back to
-- their original transparency and holds them still; leaving cancels the tweens and restores their baseline.
-- AMBIENT / EXPOSURE / BLOOM and the twinkle numbers below are the live-tuning knobs.
-- It publishes the client-local player attribute Level4LightingOwned. RoundUI re-applies the lobby grade every
-- 0.5 s and must stand down on it; the block to add at the top of RoundUI's applyPlayerLighting(), right after
-- `local isLevelThree = ...` (no new top-level local: RoundUI sits at the 200-register limit; run the compile
-- probe after):
--  if player:GetAttribute("Level4LightingOwned") == true then
--   lobbyGrade.Enabled = false
--   if mazeGrade then mazeGrade.Enabled = false end
--   return
--  end
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local MODEL_NAME = "Level 4 Cinema Blender"
local OWNED_ATTRIBUTE = "Level4LightingOwned"
local CHECK_INTERVAL = 0.25
local REAPPLY_INTERVAL = 0.75

-- live-tuning knobs. v2 play test 2026-10-01: Ambient (26,20,34) / exposure 0.7 read well with ceiling troffers;
-- (9,6,14) left whole rooms unreadable. v3 lights from neon + a sparse star fill, and a dead neon must leave its
-- corner dark, so the ambient sits between the two.
-- v3 play test 2026-10-02: (15,11,21) / 0.6 left the walls black ("you must be able to see everything"); with the
-- 3x light gains in make_place.py, (46,36,60) / 0.9 reads everywhere while a blinking neon still leaves its corner dim.
local AMBIENT = Color3.fromRGB(46, 36, 60)
local EXPOSURE = 0.9
local TWINKLE_TAGS = { "L4StarTwinkleA", "L4StarTwinkleB", "L4StarTwinkleC" }
local TWINKLE_MAX = 0.6                   -- a group drifts between Transparency 0 and this
local TWINKLE_SECONDS = { 3, 7 }          -- length of one slow drift

-- dark interior lit only by its lights; exposure independent of ClockTime. Ambient is a violet near-black so the
-- dead stretches read as dark but never as a flat void.
local GRADE = {
	ClockTime = 0,
	Brightness = 0,
	Ambient = AMBIENT,
	OutdoorAmbient = Color3.fromRGB(0, 0, 0),
	ColorShift_Top = Color3.fromRGB(0, 0, 0),
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 0.15,
	EnvironmentSpecularScale = 1.0,   -- neon picked up in the lacquer, chrome and wet floor
	ExposureCompensation = EXPOSURE,
	ShadowSoftness = 0.25,
	GlobalShadows = true,
}
local ATMOSPHERE = {
	Density = 0.1,                    -- 0.32 swallowed the far walls in black haze (v3 play test)
	Haze = 1.5,
	Glare = 0,
	Offset = 0,
	Color = Color3.fromRGB(40, 20, 58),
	Decay = Color3.fromRGB(12, 6, 22),
}
local GRADE_EFFECT = { Brightness = -0.03, Contrast = 0.2, Saturation = 0.14, TintColor = Color3.fromRGB(244, 234, 255) }
local BLOOM = { Intensity = 0.85, Size = 30, Threshold = 0.92 }
local DEPTH = { FarIntensity = 0.08, FocusDistance = 14, InFocusRadius = 45, NearIntensity = 0 }

local function effect(className, name, props, parent)
	local e = parent:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	for k, v in props do e[k] = v end
	e.Enabled = false
	e.Parent = parent
	return e
end

local grade = effect("ColorCorrectionEffect", "Level 4 Client Color Grade", GRADE_EFFECT, Lighting)
local bloom = effect("BloomEffect", "Level 4 Client Bloom", BLOOM, Lighting)
local depth = effect("DepthOfFieldEffect", "Level 4 Client Depth", DEPTH, workspace.CurrentCamera or Lighting)
local ours = { [grade] = true, [bloom] = true, [depth] = true }

local saved = nil        -- what the place had when we took over; nil while inactive
local applying = false

local function inside()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.Health > 0 and humanoid.RootPart
	local model = workspace:FindFirstChild(MODEL_NAME)
	local centre = model and model:GetAttribute("BoundsCenter")
	local size = model and model:GetAttribute("BoundsSize")
	if not (root and typeof(centre) == "Vector3" and typeof(size) == "Vector3") then return false end
	local d = root.Position - centre
	return math.abs(d.X) <= size.X / 2 and math.abs(d.Y) <= size.Y / 2 and math.abs(d.Z) <= size.Z / 2
end

local function inheritedEffects()
	local list = {}
	for _, e in Lighting:GetChildren() do
		if not ours[e] and (e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect")
			or e:IsA("DepthOfFieldEffect")) then
			table.insert(list, e)
		end
	end
	return list
end

local function take()
	saved = { lighting = {}, effects = {} }
	for k in GRADE do saved.lighting[k] = Lighting[k] end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		saved.atmosphere = atmosphere
		saved.atmosphereProps = {}
		for k in ATMOSPHERE do saved.atmosphereProps[k] = atmosphere[k] end
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "Level 4 Client Atmosphere"
		saved.createdAtmosphere = atmosphere
		atmosphere.Parent = Lighting
	end
end

local function apply()
	applying = true
	for k, v in GRADE do Lighting[k] = v end
	local atmosphere = saved.atmosphere or saved.createdAtmosphere
	if atmosphere and atmosphere.Parent then
		for k, v in ATMOSPHERE do atmosphere[k] = v end
	end
	for _, e in inheritedEffects() do                  -- inherited Bloom / SunRays / grades (LobbyLocalGrade) are suppressed
		if saved.effects[e] == nil then saved.effects[e] = e.Enabled end
		e.Enabled = false
	end
	if workspace.CurrentCamera and depth.Parent ~= workspace.CurrentCamera then depth.Parent = workspace.CurrentCamera end
	grade.Enabled, bloom.Enabled, depth.Enabled = true, true, true
	applying = false
end

local function release()
	local previous = saved
	saved = nil                             -- restoration must not trigger our Lighting.Changed enforcement
	grade.Enabled, bloom.Enabled, depth.Enabled = false, false, false
	for k, v in previous.lighting do Lighting[k] = v end
	if previous.atmosphere and previous.atmosphere.Parent then
		for k, v in previous.atmosphereProps do previous.atmosphere[k] = v end
	end
	if previous.createdAtmosphere then previous.createdAtmosphere:Destroy() end
	for e, enabled in previous.effects do
		if e.Parent then e.Enabled = enabled end
	end
end

-- the star ceiling: each twinkle group drifts as one (a few pooled MeshParts per group), client-side only
local rng = Random.new()
local twinkleNext = {}                    -- tag -> time the current drift ends
local starState = {}                      -- pooled MeshPart -> original transparency + cancellable tween
local twinkleModel = nil

local function stars(tag, model)
	local list = {}
	for _, p in CollectionService:GetTagged(tag) do
		if p:IsA("MeshPart") and p:IsDescendantOf(model) then table.insert(list, p) end
	end
	return list
end

local function settleStars(fade)
	for p, state in starState do
		if state.tween then state.tween:Cancel(); state.tween = nil end
		if p.Parent then
			if fade then
				state.tween = TweenService:Create(p, TweenInfo.new(1.5), { Transparency = state.original })
				state.tween:Play()
			else
				p.Transparency = state.original
			end
		end
	end
	table.clear(twinkleNext)
	if not fade then table.clear(starState); twinkleModel = nil end
end

local function twinkle(now)
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not model then return end
	if model ~= twinkleModel then settleStars(false); twinkleModel = model end
	for p, state in starState do
		if not p:IsDescendantOf(model) then
			if state.tween then state.tween:Cancel() end
			if p.Parent then p.Transparency = state.original end
			starState[p] = nil
		end
	end
	if player:GetAttribute("ReduceFlashing") ~= false then
		if next(twinkleNext) then settleStars(true) end
		return
	end
	for _, tag in TWINKLE_TAGS do
		if now >= (twinkleNext[tag] or 0) then
			local seconds = rng:NextNumber(TWINKLE_SECONDS[1], TWINKLE_SECONDS[2])
			local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local goal = { Transparency = rng:NextNumber(0, TWINKLE_MAX) }
			for _, p in stars(tag, model) do
				local state = starState[p] or { original = p.Transparency }
				if state.tween then state.tween:Cancel() end
				state.tween = TweenService:Create(p, info, goal)
				state.tween:Play()
				starState[p] = state
			end
			twinkleNext[tag] = now + seconds
		end
	end
end

-- a server Lighting write that lands while we own the grade is put back at once (not on the next pass)
Lighting.Changed:Connect(function(prop)
	local want = GRADE[prop]
	if saved and not applying and want ~= nil and Lighting[prop] ~= want then
		if typeof(want) == "number" and math.abs(Lighting[prop] - want) < 1e-4 then return end
		Lighting[prop] = want
	end
end)

local lastCheck, lastApply = 0, 0
local function step()
	local now = time()
	if now - lastCheck < CHECK_INTERVAL then return end
	lastCheck = now
	local want = inside()
	if want and not saved then
		take()
		apply()
		lastApply = now
		player:SetAttribute(OWNED_ATTRIBUTE, true)
	elseif not want and saved then
		release()
		settleStars()
		player:SetAttribute(OWNED_ATTRIBUTE, false)
	elseif want and now - lastApply >= REAPPLY_INTERVAL then
		apply()
		lastApply = now
	end
	if saved then twinkle(now) end
end

RunService.Heartbeat:Connect(step)
player.CharacterRemoving:Connect(function()
	if saved then
		release()
		settleStars()
		player:SetAttribute(OWNED_ATTRIBUTE, false)
	end
end)
