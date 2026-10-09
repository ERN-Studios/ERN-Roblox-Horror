-- Public presentation for the approved Level 2 Poolrooms round.
-- Local grade, water look, lamp flicker and camera collision restore when the player leaves.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local NEW_MAP = "Level 2 Generated World"

local function mapModel()
	local model = workspace:FindFirstChild(NEW_MAP)
	return if model and model:IsA("Model") and model:GetAttribute("Level2NewMap") == true then model else nil
end

local function inNewMap()
	if player:GetAttribute("InRound") ~= true or workspace:GetAttribute("SelectedLevel") ~= 2 then return false end
	local model = mapModel()
	local center = model and model:GetAttribute("BoundsCenter")
	local size = model and model:GetAttribute("BoundsSize")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if typeof(center) ~= "Vector3" or typeof(size) ~= "Vector3" or not root
		or not root:IsDescendantOf(workspace) then return false end
	local d = root.Position - center
	return math.abs(d.X) * 2 <= size.X and math.abs(d.Y) * 2 <= size.Y and math.abs(d.Z) * 2 <= size.Z
end
local REAPPLY = 0.75
local GRADE = { -- {model attribute, target, property, default}
	{"GradeClockTime", "Lighting", "ClockTime", 13}, -- daytime: the sun comes in through the openings...
	{"GradeLatitude", "Lighting", "GeographicLatitude", 0.0}, -- the place's own: A1/A3a's shafts stay put
	{"GradeBrightness", "Lighting", "Brightness", 0.9}, -- ...weakly (owner 2026-10-08: a touch lighter)
	{"GradeAmbient", "Lighting", "Ambient", Color3.fromRGB(20, 24, 25)},
	{"GradeOutdoorAmbient", "Lighting", "OutdoorAmbient", Color3.fromRGB(13, 16, 17)},
	{"GradeColorShiftTop", "Lighting", "ColorShift_Top", Color3.new(0, 0, 0)},
	{"GradeColorShiftBottom", "Lighting", "ColorShift_Bottom", Color3.new(0, 0, 0)},
	{"GradeDiffuse", "Lighting", "EnvironmentDiffuseScale", 0.08}, -- no sky fill indoors
	{"GradeSpecular", "Lighting", "EnvironmentSpecularScale", 0.35}, -- the wet tiles still glint
	{"GradeExposure", "Lighting", "ExposureCompensation", -0.05},
	{"GradeShadows", "Lighting", "GlobalShadows", true}, -- a shaft is the roof's shadow with a hole in it
	{"GradeShadowSoftness", "Lighting", "ShadowSoftness", 0.2},
	{"GradeDensity", "Atmosphere", "Density", 0.3}, -- distance sinks into the dark (Fog is inert under an Atmosphere)
	{"GradeOffset", "Atmosphere", "Offset", 0},
	{"GradeHaze", "Atmosphere", "Haze", 1},
	{"GradeGlare", "Atmosphere", "Glare", 0},
	{"GradeAtmosphereColor", "Atmosphere", "Color", Color3.fromRGB(28, 34, 36)},
	{"GradeDecay", "Atmosphere", "Decay", Color3.fromRGB(10, 13, 14)},
	{"GradeTint", "Grade", "TintColor", Color3.fromRGB(220, 236, 234)}, -- clean but cold
	{"GradeSaturation", "Grade", "Saturation", -0.3},
	{"GradeContrast", "Grade", "Contrast", 0.15},
	{"GradeColorBrightness", "Grade", "Brightness", -0.02},
	{"GradeBloom", "Bloom", "Intensity", 0.5}, -- the few working lamps halo
	{"GradeBloomSize", "Bloom", "Size", 24},
	{"GradeBloomThreshold", "Bloom", "Threshold", 0.95},
	{"GradeWaterColor", "Terrain", "WaterColor", Color3.fromRGB(24, 62, 60)}, -- one dark teal for every room
	{"GradeWaterTransparency", "Terrain", "WaterTransparency", 0.4},
	{"GradeWaterReflectance", "Terrain", "WaterReflectance", 0.06}, -- dark halls must not mirror the sky
	{"GradeWaterWaveSize", "Terrain", "WaterWaveSize", 0.03}, -- A1's 0.43-stud flood keeps its floor covered
	{"GradeWaterWaveSpeed", "Terrain", "WaterWaveSpeed", 1.2},
}
local grade = nil -- while this client owns the map's look: what it saved, wants and suppressed
-- A2, the lion rotunda (owner 2026-10-08: a skylight down onto the gold disc, only there): while the character
-- is inside its drum the sun stands straight over the oculus (ClockTime 12 at latitude 23.5, measured in Play:
-- GetSunDirection().Y > 0.9999), so the oculus's own sun patch lands on the island; the rest of the map keeps
-- 13:00. The server's A2 Skylight adds the visible shaft and the light on the disc. Model attributes
-- A2GradeClockTime / A2GradeLatitude retune it live (the knob convention above).
local A2_AXIS, A2_SUN = Vector3.new(69742.6, 0, 0), {GradeClockTime = 12, GradeLatitude = 23.5}
local function inA2()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local p = root and root.Position
	return p ~= nil and p.Y > 274 and p.Y < 391 and ((p - A2_AXIS) * Vector3.new(1, 0, 1)).Magnitude <= 90
end

local function same(a, b)
	return a == b or (type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-4)
end

local function gradeEffect(className, name)
	local e = Lighting:FindFirstChild(name)
	if not e or not e:IsA(className) then
		e = Instance.new(className)
		e.Name = name
		e.Enabled = false
		e.Parent = Lighting
	end
	return e
end

local function takeGrade()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local created = nil
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "Level 2 New Map Atmosphere"
		atmosphere.Parent = Lighting
		created = atmosphere
	end
	grade = {created = created, saved = {}, want = {}, effects = {}, connections = {}, applied = 0, objects = {
		Lighting = Lighting, Atmosphere = atmosphere, Terrain = workspace.Terrain,
		Grade = gradeEffect("ColorCorrectionEffect", "Level 2 New Map Grade"),
		Bloom = gradeEffect("BloomEffect", "Level 2 New Map Bloom"),
	}}
	for _, row in ipairs(GRADE) do
		local object = grade.objects[row[2]]
		grade.want[object] = grade.want[object] or {}
		if row[2] ~= "Grade" and row[2] ~= "Bloom" then
			grade.saved[object] = grade.saved[object] or {}
			grade.saved[object][row[3]] = object[row[3]]
		end
	end
	for object in pairs(grade.saved) do
		table.insert(grade.connections, object.Changed:Connect(function(property)
			local want = grade and grade.want[object][property]
			if want == nil or same(object[property], want) then return end
			grade.saved[object][property] = object[property]
			object[property] = want
		end))
	end
end

local function applyGrade()
	local model = mapModel()
	local a2 = inA2()
	for _, row in ipairs(GRADE) do
		local object = grade.objects[row[2]]
		local value = model and model:GetAttribute(row[1])
		if a2 and A2_SUN[row[1]] ~= nil then value = (model and model:GetAttribute("A2" .. row[1])) or A2_SUN[row[1]] end
		if typeof(value) ~= typeof(row[4]) then value = row[4] end
		if row[2] == "Bloom" and row[3] == "Intensity" then value *= .8 end
		grade.want[object][row[3]] = value
		if object.Parent and not same(object[row[3]], value) then object[row[3]] = value end
	end
	for _, e in ipairs(Lighting:GetChildren()) do
		if e ~= grade.objects.Grade and e ~= grade.objects.Bloom and (e:IsA("BloomEffect")
			or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") or e:IsA("DepthOfFieldEffect")) then
			if grade.effects[e] == nil then grade.effects[e] = e.Enabled end
			e.Enabled = false
		end
	end
	grade.objects.Grade.Enabled, grade.objects.Bloom.Enabled = true, true
	grade.applied, grade.a2 = os.clock(), a2
end

local function releaseGrade()
	local previous = grade
	grade = nil
	for _, connection in ipairs(previous.connections) do connection:Disconnect() end
	previous.objects.Grade.Enabled, previous.objects.Bloom.Enabled = false, false
	for object, properties in pairs(previous.saved) do
		if object.Parent then
			for property, value in pairs(properties) do object[property] = value end
		end
	end
	if previous.created then previous.created:Destroy() end
	for e, enabled in pairs(previous.effects) do
		if e.Parent then e.Enabled = enabled end
	end
end

local function faceArrival()
	local deadline = os.clock() + 3
	while not inNewMap() and os.clock() < deadline do task.wait(0.05) end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not inNewMap() or not camera or camera.CameraType ~= Enum.CameraType.Custom then return end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	local distance = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, .5, 12)
	camera.CFrame = CFrame.lookAt(focus - look * distance + Vector3.new(0, distance * .2, 0), focus)
	camera.Focus = CFrame.new(focus)
end

local function refresh()
	local inside = inNewMap()
	if inside and not grade then
		takeGrade()
		applyGrade()
		task.spawn(faceArrival)
	elseif not inside and grade then
		releaseGrade()
	elseif grade and (os.clock() - grade.applied >= REAPPLY or inA2() ~= grade.a2) then
		applyGrade()
	end
	if player:GetAttribute("Level2NewMapLightingOwned") ~= inside then
		player:SetAttribute("Level2NewMapLightingOwned", inside)
	end
end

local FLICKER_FADE = 1.5
local flickering = {} -- holder -> {thread, tweens, base}

local function flickerReduced()
	return player:GetAttribute("ReduceFlashing") ~= false
end

local function flickerSet(holder, state, on, fade)
	local base = tonumber(holder:GetAttribute("BaseBrightness"))
	for _, light in ipairs(holder:GetChildren()) do
		if light:IsA("Light") then
			state.base[light] = state.base[light] or light.Brightness
			local goal = if on then base or state.base[light] else 0
			if fade then
				local tween = TweenService:Create(light, TweenInfo.new(FLICKER_FADE, Enum.EasingStyle.Sine),
					{Brightness = goal})
				table.insert(state.tweens, tween)
				tween:Play()
			else
				light.Brightness = goal
			end
		end
	end
	if fade then
		task.wait(FLICKER_FADE)
		table.clear(state.tweens)
	end
end

local function flickerEpisode(holder, state, rng)
	local function outage()
		return if rng:NextNumber() < .12 then rng:NextNumber(6, 15) else rng:NextNumber(.3, 4)
	end
	local function slow()
		flickerSet(holder, state, false, true)
		task.wait(outage())
		flickerSet(holder, state, true, true)
	end
	local function blink(on, shortest, longest) -- false once the player asks for less flashing
		if flickerReduced() then return false end
		flickerSet(holder, state, on, false)
		task.wait(rng:NextNumber(shortest, longest))
		return true
	end
	if flickerReduced() then slow(); return end
	for _ = 1, rng:NextInteger(1, 4) do -- the stutter
		if not (blink(false, .04, .16) and blink(true, .03, .25)) then slow(); return end
	end
	if rng:NextNumber() < .7 then -- and usually it gives out for a while
		flickerSet(holder, state, false, false)
		task.wait(outage())
		for _ = 1, rng:NextInteger(0, 2) do -- a catch or two on the way back
			if not (blink(true, .04, .12) and blink(false, .05, .2)) then slow(); return end
		end
	end
	flickerSet(holder, state, true, flickerReduced())
end

local function watchFlicker(holder)
	if flickering[holder] or not holder:IsA("BasePart") or holder:GetAttribute("L2NFlicker") ~= true then return end
	local model = mapModel()
	local lights = model and model:FindFirstChild("Lights")
	if not lights or not holder:IsDescendantOf(lights) then return end
	local state = {tweens = {}, base = {}}
	flickering[holder] = state
	state.thread = task.spawn(function()
		local rng = Random.new()
		local dying = rng:NextNumber() < .25
		local shortest, longest = if dying then 2 else 6, if dying then 6 else 20
		task.wait(rng:NextNumber(0, longest))
		while flickering[holder] == state do
			if grade then flickerEpisode(holder, state, rng) end -- only while this client is in the map
			task.wait(rng:NextNumber(shortest, longest))
		end
	end)
end

local function stopFlicker(holder)
	local state = flickering[holder]
	if not state then return end
	flickering[holder] = nil
	task.cancel(state.thread)
	for _, tween in ipairs(state.tweens) do tween:Cancel() end
	local base = tonumber(holder:GetAttribute("BaseBrightness"))
	for light, brightness in pairs(state.base) do light.Brightness = base or brightness end
end

-- Third person inside the map: Poppercam stops only at opaque parts and every
-- collider here is invisible, so the camera saw through every wall. One step after the camera module, a
-- sphere cast from the focus out to the camera pulls the camera in front of the first real surface: a
-- colliding part, in practice the map's Collision (and the exit slide's tube). Characters, invisible fall
-- guards (the Collision's Guards sub-model, or a part named Barrier), non-colliding parts (kill boxes,
-- veils, sensors) and water are not walls.
local CAMERA_RADIUS = 0.5
local cameraParams = RaycastParams.new()
cameraParams.FilterType = Enum.RaycastFilterType.Exclude
cameraParams.IgnoreWater = true
cameraParams.RespectCanCollide = true
RunService:BindToRenderStep("Level2NewMapCameraClamp", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = workspace.CurrentCamera
	local model = grade and mapModel()
	if not model or not camera or camera.CameraType ~= Enum.CameraType.Custom then return end
	local focus = camera.Focus.Position
	local offset = camera.CFrame.Position - focus
	local distance = offset.Magnitude
	if distance < 1 then return end -- first person: the head is the camera
	local direction = offset / distance
	local collision = model:FindFirstChild("Collision")
	local ignore = {}
	local guards = collision and collision:FindFirstChild("Guards")
	if guards then table.insert(ignore, guards) end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then table.insert(ignore, other.Character) end
	end
	cameraParams.FilterDescendantsInstances = ignore
	for _ = 1, 4 do
		local hit = workspace:Spherecast(focus, CAMERA_RADIUS, offset, cameraParams)
		if not hit then return end
		if hit.Instance.Name ~= "Barrier" then
			camera.CFrame -= direction * (distance - hit.Distance) -- the sphere's centre where it touched
			return
		end
		cameraParams:AddToFilter(hit.Instance)
	end
end)

player:GetAttributeChangedSignal("InRound"):Connect(refresh)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(refresh)
workspace.DescendantRemoving:Connect(stopFlicker)
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed >= 0.2 then elapsed = 0; refresh() end
end)
workspace.DescendantAdded:Connect(watchFlicker)
for _, instance in ipairs(workspace:GetDescendants()) do watchFlicker(instance) end
player.CharacterRemoving:Connect(function()
	if grade then releaseGrade() end
	if player:GetAttribute("Level2NewMapLightingOwned") == true then
		player:SetAttribute("Level2NewMapLightingOwned", false)
	end
end)
refresh()
