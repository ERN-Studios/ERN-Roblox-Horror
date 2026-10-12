-- JumpscareUI: first-person capture direction and matching cancellation.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local BLACK_FADE, BLACK_HOLD, REVEAL, DIED_GRACE = 0.16, 1.65, 0.65, 0.35
local CAMERA_BIND = "EntityKillCamera"
local dying, capturing = false, false
local controls, overlay = nil, nil
local captureRecord, fadeRecord, lastCaptureId = nil, nil, nil


local function getControls()
	if controls then return controls end
	pcall(function()
		controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	end)
	return controls
end

local function makeOverlay()
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	if overlay then overlay:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder = "JumpscareGui", true, false, 1000
	gui.Parent = playerGui
	local black = Instance.new("Frame")
	black.Name, black.Size = "Black", UDim2.fromScale(1, 1)
	black.BackgroundColor3, black.BackgroundTransparency = Color3.new(0, 0, 0), 1
	black.BorderSizePixel, black.ZIndex, black.Parent = 0, 20, gui      -- over the narrowing rings of the stranglehold
	overlay = gui
	return black
end

-- KILL_CHOKE_20261011 (owner: "den loefter dig i struben med en arm, saa dine foedder slipper gulvet. Kameraet ryster,
-- synet snaevrer ind fra kanterne, den vipper hovedet paa skraa som et nysgerrigt dyr, og saa slipper lyset").
-- The server names the style with the capture; the camera then rides the clip's own `grip` track (the throat in the
-- Entity's hand) and looks at its `eyes` track, both in the Entity's root space, so the view is smooth whatever the
-- replication of the carried body does. Vision closes in through a soft-edged hole; the black at the end is the
-- ordinary death fade.
local HttpService = game:GetService("HttpService")
local function chokeTracks(clipName, required)
	local owner = RS:FindFirstChild("Level1EntityMotion")
	local folder = owner and owner:FindFirstChild("Clips")
	local value = folder and folder:FindFirstChild(clipName)
	if not (value and value:IsA("StringValue")) then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(value.Value) end)
	if not ok or type(data) ~= "table" or type(data.tracks) ~= "table" or type(data.marks) ~= "table" then return nil end
	local frames, seconds, marks = tonumber(data.frames), tonumber(data.seconds), data.marks
	if not frames or frames < 2 or not seconds or seconds <= 0 then return nil end
	local function points(flat)
		if type(flat) ~= "table" or #flat ~= frames * 3 then return nil end
		local out = table.create(frames)
		for f = 0, frames - 1 do
			local x, y, z = flat[f * 3 + 1], flat[f * 3 + 2], flat[f * 3 + 3]
			if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
			out[f + 1] = Vector3.new(x, y, z) / 1000
		end
		return out
	end
	local grip, eyes = points(data.tracks.grip), points(data.tracks.eyes)
	for _, name in ipairs(required) do
		if type(marks[name]) ~= "number" then return nil end
	end
	if not grip or not eyes then return nil end
	-- KILL_SLAM_20261011: the slam also carries the striking fist and the victim's attitude (unit vectors x 1000)
	return {frames = frames, seconds = seconds, grip = grip, eyes = eyes, marks = marks,
		fist = points(data.tracks.fist), vup = points(data.tracks.vup), vfront = points(data.tracks.vfront)}
end
local function chokePoint(clip, track, t)
	local f = math.clamp(t / clip.seconds, 0, 1) * (clip.frames - 1)
	local i = math.floor(f)
	return track[i + 1]:Lerp(track[math.min(i + 2, clip.frames)], f - i)
end
-- Vision narrowing: rings of black around one round hole, each a little wider than the last, so the edge is soft
-- (25 of them: 13 showed as bands on a bright ceiling; the outermost is solid). `open` is the hole's diameter against
-- the screen's WIDTH: 1.2 clears the corners.
local function makeNarrowing(gui)
	local holder = Instance.new("Frame")
	holder.Name, holder.Size, holder.BackgroundTransparency, holder.BorderSizePixel = "Narrowing", UDim2.fromScale(1, 1), 1, 0
	holder.ClipsDescendants, holder.Parent = true, gui
	local rings = {}
	for index = 1, 25 do
		local ring = Instance.new("Frame")
		ring.Name, ring.AnchorPoint, ring.Position = "Ring" .. index, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency, ring.BorderSizePixel, ring.SizeConstraint, ring.Parent = 1, 0, Enum.SizeConstraint.RelativeXX, holder
		Instance.new("UICorner", ring).CornerRadius = UDim.new(0.5, 0)
		local stroke = Instance.new("UIStroke", ring)
		stroke.Color, stroke.Thickness, stroke.Transparency = Color3.new(0, 0, 0), 2400, index == 25 and 0 or 0.87
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rings[index] = ring
	end
	return function(open)
		holder.Visible = open < 1.2
		for index, ring in ipairs(rings) do
			local size = math.max(0, open) * (1 + 0.027 * (index - 1))
			ring.Size = UDim2.fromScale(size, size)
		end
	end
end

local function stopCapture(restoreCamera)
	local record = captureRecord
	if not capturing and not record then return end
	capturing, captureRecord = false, nil
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	if record and record.Hidden then                    -- the victim's own body, hidden for the stranglehold's view
		for _, part in ipairs(record.Hidden) do if part.Parent then part.LocalTransparencyModifier = 0 end end
	end
	if record and record.Effects then                   -- the slam's panic vision
		for _, effect in ipairs(record.Effects) do effect:Destroy() end
		record.Effects = nil
	end
	if record and record.Crunch then                    -- let a crunch that has started ring out behind the black
		local sound = record.Crunch
		record.Crunch = nil
		if sound.IsPlaying then task.delay(4, function() sound:Destroy() end) else sound:Destroy() end
	end
	if controls then controls:Enable() end
	if restoreCamera and record and player.Character == record.Character
		and workspace.CurrentCamera == record.Camera then
		record.Camera.CameraType = record.CameraType
		record.Camera.CameraSubject = record.CameraSubject
		record.Camera.FieldOfView = record.FieldOfView
		record.Camera.CFrame = record.CFrame
	end
end

local function clearFade()
	local record = fadeRecord
	fadeRecord = nil
	if record and record.Tween then record.Tween:Cancel() end
	if overlay then overlay:Destroy(); overlay = nil end
end

local function cancelCapture(id, character)
	local record = captureRecord
	if not record or record.Id ~= id or record.Character ~= character then return end
	clearFade()
	stopCapture(true)
	dying = false
end

local function fadeDeath(character)
	if player.Character ~= character or fadeRecord then return end
	local black = overlay and overlay:FindFirstChild("Black") or makeOverlay()
	if not black then return end
	local record = {Character = character, Overlay = overlay}
	fadeRecord = record
	local function current() return fadeRecord == record and player.Character == character end
	record.Tween = TweenService:Create(black, TweenInfo.new(BLACK_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
	record.Tween:Play()
	task.wait(BLACK_FADE)
	if not current() then return end
	black.BackgroundTransparency = 0
	stopCapture() -- SpectateController takes over behind the black frame.
	task.wait(BLACK_HOLD)
	if not current() then return end
	record.Tween = TweenService:Create(black, TweenInfo.new(REVEAL), {BackgroundTransparency = 1})
	record.Tween:Play()
	task.wait(REVEAL)
	if not current() then return end
	if overlay == record.Overlay then overlay:Destroy(); overlay = nil end
	fadeRecord = nil
end

local function beginCapture(entity, duration, deathAt, id, character, style)
	if capturing or typeof(entity) ~= "Instance" or type(id) ~= "string" or id == lastCaptureId
		or player.Character ~= character then return end
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	camera = workspace.CurrentCamera
	local record = {Id = id, Character = character, Camera = camera,
		CameraType = camera.CameraType, CameraSubject = camera.CameraSubject,
		FieldOfView = camera.FieldOfView, CFrame = camera.CFrame}
	captureRecord, lastCaptureId = record, id
	dying, capturing = true, true
	if not makeOverlay() then cancelCapture(id, character); return end
	local c = getControls()
	-- PlayerModule loading can yield. A cancel/respawn owns the state now if
	-- this record changed while it loaded; never disable that newer character.
	if captureRecord ~= record then return end
	if player.Character ~= character or hum.Health <= 0 then cancelCapture(id, character); return end
	if c then c:Disable() end
	camera.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	local head = character:FindFirstChild("Head")
	local entityHead = entity:FindFirstChild("Head", true)
	local entityRoot = entity:FindFirstChild("HumanoidRootPart", true)
	-- KILL_SLAM_20261011 (owner: "tager fat, smasher ned i jorden og loader haand op og smadrer ind i ansigtet ... de
	-- skal have panik syn imens det sker og isaer naar de ligger paa jorden ... et skull crunch lyd naar den smasker
	-- dem i ansigtet"). The camera is the victim's own eyes all the way: carried up, thrown onto its back, looking up
	-- its body at the thing over it, and at the fist for the last quarter second. Panic vision is a heartbeat: each
	-- beat closes the edges in, blurs and drains the picture and kicks the lens; it runs faster and much harder once
	-- the victim is on the floor, where the slam itself whites the head out for a moment. The crunch (the group's
	-- sound named by Level1EntityMotion.KillCrunchSound) plays on the frame of the blow, as the screen goes black.
	local slam = style == "Slam" and entityRoot and chokeTracks("Kill_Slam", {"grab", "lifted", "slam", "windup", "strike"}) or nil
	if slam and not (slam.fist and slam.vup and slam.vfront) then slam = nil end
	if slam then
		local narrow = makeNarrowing(overlay)
		narrow(1.25)
		local black = overlay:FindFirstChild("Black")
		record.Hidden = {}
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("Decal") then table.insert(record.Hidden, part) end
		end
		local blur = Instance.new("BlurEffect")
		blur.Name, blur.Size, blur.Parent = "KillPanicBlur", 0, camera
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name, grade.Parent = "KillPanicGrade", camera
		record.Effects = {blur, grade}
		local crunch = nil
		do
			local owner = RS:FindFirstChild("Level1EntityMotion")
			local id = owner and owner:GetAttribute("KillCrunchSound")
			if type(id) == "string" and id ~= "" then
				crunch = Instance.new("Sound")
				crunch.Name, crunch.SoundId, crunch.Volume = "KillCrunch", id, 1.6          -- the master is -15.5 LUFS
				crunch.Parent = game:GetService("SoundService")            -- 2D: the victim's own head
				record.Crunch = crunch
			end
		end
		local marks = slam.marks
		local function ease(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
		local beat, last, struck = 0, nil, false
		RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
			if captureRecord ~= record or player.Character ~= character
				or not (capturing and entity.Parent and entityRoot.Parent and head and head.Parent) then return end
			local startedAt = workspace:GetAttribute("EntityKillStartedAt")
			local elapsed = os.clock() - started
			if type(startedAt) == "number" then
				local synced = workspace:GetServerTimeNow() - startedAt
				if synced == synced and synced >= 0 and synced < 30 then elapsed = synced end
			end
			local dt = last and math.clamp(elapsed - last, 0, 0.1) or 0
			last = elapsed
			for _, part in ipairs(record.Hidden) do part.LocalTransparencyModifier = 1 end
			local base = entityRoot.CFrame
			local grip = base:PointToWorldSpace(chokePoint(slam, slam.grip, elapsed))
			local eyes = base:PointToWorldSpace(chokePoint(slam, slam.eyes, elapsed))
			local fist = base:PointToWorldSpace(chokePoint(slam, slam.fist, elapsed))
			local up = base:VectorToWorldSpace(chokePoint(slam, slam.vup, elapsed))
			local front = base:VectorToWorldSpace(chokePoint(slam, slam.vfront, elapsed))
			up = up.Magnitude > 0.01 and up.Unit or Vector3.yAxis
			front = front.Magnitude > 0.01 and front.Unit or Vector3.zAxis
			local held = grip + up * 0.55 + front * 0.35
			local eye = (head.Position + Vector3.new(0, 0.12, 0)):Lerp(held, ease((elapsed - marks.grab + 0.08) / 0.16))
			-- while the hand is loaded the view is drawn half way to it, so the face and the raised fist are both in frame
			local raise = 0.45 * ease((elapsed - (marks.windup - 0.9)) / 0.6)
			local aim = eyes:Lerp(fist, math.max(raise, ease((elapsed - (marks.strike - 0.25)) / 0.2)))
			-- how hard the panic is: some from the grab, more in the air, all of it on the floor
			local down = elapsed >= marks.slam
			local k = down and 1 or (0.3 * ease((elapsed - marks.grab) / 0.2) + 0.3 * ease((elapsed - marks.grab) / math.max(marks.lifted - marks.grab, 0.1)))
			local calm = player:GetAttribute("ReduceCameraShake") == true
			beat += dt * (down and (3.1 + 1.2 * ease((elapsed - marks.windup) / math.max(marks.strike - marks.windup, 0.1))) or 2.3)
			local pulse = math.exp(-(beat % 1) * 5.5)
			local sinceSlam = elapsed - marks.slam
			local hit = down and math.exp(-sinceSlam * 6) or 0                       -- the slam itself, fading
			local shake = (math.sin(elapsed * 31) * 0.6 + math.sin(elapsed * 47.3) * 0.4) * (0.005 + 0.018 * k)
			local jolt = elapsed - marks.grab
			if jolt >= 0 and jolt < 0.3 then shake += math.sin(jolt * 110) * (1 - jolt / 0.3) * 0.07 end
			shake += math.sin(sinceSlam * 85) * hit * 0.17
			if calm then shake = 0 end
			if (aim - eye).Magnitude > 0.05 and math.abs((aim - eye).Unit:Dot(up)) < 0.98 then
				camera.CFrame = CFrame.lookAt(eye, aim, up) * CFrame.Angles(shake * 0.6, shake, shake * 0.8 + (calm and 0 or math.sin(elapsed * 2.1) * 0.05 * (down and 1 or 0)))
			end
			camera.FieldOfView = 70 + (calm and 2 or 5) * pulse * k + (calm and 4 or 14) * hit
			blur.Size = (calm and 0.4 or 1) * (2 * k + 11 * pulse * k + 26 * hit)
			grade.Saturation = -0.25 * k - 0.25 * pulse * k
			grade.Contrast = 0.12 * k + 0.16 * pulse * k
			grade.Brightness = -0.04 * k + 0.25 * hit
			grade.TintColor = Color3.new(1, 1 - 0.2 * pulse * k, 1 - 0.24 * pulse * k)
			local open = 1.25 - 0.3 * ease((elapsed - marks.grab) / math.max(marks.lifted - marks.grab, 0.1))
				- 0.27 * ease(sinceSlam / 0.25) - 0.14 * ease((elapsed - marks.windup) / math.max(marks.strike - marks.windup, 0.1))
			narrow(open - 0.2 * pulse * k)
			-- two blinks on the floor: the head hitting it, and one more as it comes back
			if black and not record.Death then
				local blink = 0
				if down then
					blink = math.max(0.85 * math.exp(-sinceSlam * 11), 0.7 * math.max(0, 1 - math.abs(sinceSlam - 0.62) / 0.07))
				end
				black.BackgroundTransparency = 1 - blink
			end
			if crunch and not struck and elapsed >= marks.strike - 0.03 then
				struck = true
				crunch:Play()
			end
		end)
		return
	end
	local choke = style == "Choke" and entityRoot and chokeTracks("Kill_Choke", {"grab", "lifted", "squeeze", "dark"}) or nil
	if choke then
		local narrow = makeNarrowing(overlay)
		narrow(1.25)
		record.Hidden = {}
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("Decal") then table.insert(record.Hidden, part) end
		end
		local marks = choke.marks
		local function ease(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
		RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
			if captureRecord ~= record or player.Character ~= character
				or not (capturing and entity.Parent and entityRoot.Parent and head and head.Parent) then return end
			local startedAt = workspace:GetAttribute("EntityKillStartedAt")
			local elapsed = os.clock() - started
			if type(startedAt) == "number" then
				local synced = workspace:GetServerTimeNow() - startedAt
				if synced == synced and synced >= 0 and synced < 30 then elapsed = synced end
			end
			for _, part in ipairs(record.Hidden) do part.LocalTransparencyModifier = 1 end
			local base = entityRoot.CFrame
			local grip = base:PointToWorldSpace(chokePoint(choke, choke.grip, elapsed))
			local eyes = base:PointToWorldSpace(chokePoint(choke, choke.eyes, elapsed))
			local back = (grip - eyes) * Vector3.new(1, 0, 1)
			local held = grip + Vector3.new(0, 0.5, 0) + (back.Magnitude > 0.05 and back.Unit * 0.25 or Vector3.zero)
			-- its own eyes until the hand has closed, then the held head
			local eye = (head.Position + Vector3.new(0, 0.12, 0)):Lerp(held, ease((elapsed - marks.grab + 0.08) / 0.16))
			local strain = ease((elapsed - marks.lifted) / math.max(marks.dark - marks.lifted, 0.1))
			local shake = math.sin(elapsed * 23) * (0.004 + 0.016 * strain) + math.sin(elapsed * 37.3) * 0.008 * strain
			local jolt = elapsed - marks.grab
			if jolt >= 0 and jolt < 0.3 then shake += math.sin(jolt * 110) * (1 - jolt / 0.3) * 0.07 end
			if player:GetAttribute("ReduceCameraShake") == true then shake = 0 end
			if (eyes - eye).Magnitude > 0.05 then
				camera.CFrame = CFrame.lookAt(eye, eyes) * CFrame.Angles(shake * 0.6, shake, shake * 0.45)
			end
			camera.FieldOfView = 70 - 6 * strain
			-- clear until it has you up; closing slowly through the hold, fast in the squeeze
			local hold = ease((elapsed - marks.lifted) / math.max(marks.squeeze - marks.lifted, 0.1))
			local final = ease((elapsed - marks.squeeze) / math.max(marks.dark - marks.squeeze, 0.1))
			narrow(1.25 - 0.75 * hold - 0.36 * final)      -- 0.5 of the width at the squeeze: a tunnel on any screen; 0.14 at the dark
		end)
		return
	end
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		if captureRecord ~= record or player.Character ~= character
			or not (capturing and entity.Parent and head and head.Parent) then return end
		local elapsed = os.clock() - started
		local target = entityHead and entityHead:IsA("BasePart") and entityHead.Position
			or entityHead and (entityHead:IsA("Bone") or entityHead:IsA("Attachment")) and entityHead.WorldPosition
			or (entityRoot and entityRoot.Position + Vector3.new(0, 2.7, 0))
		if not target then return end
		local shake = math.sin(elapsed * 19) * 0.008
		local d = elapsed - (deathAt or (124 / 30))
		if d >= 0 and d < 0.24 then shake += math.sin(d * 125) * (1 - d / 0.24) * 0.095 end
		if player:GetAttribute("ReduceCameraShake") == true then shake = 0 end
		local floorBlend = math.clamp((elapsed - 1.35) / 0.8, 0, 1)
		floorBlend = floorBlend * floorBlend * (3 - 2 * floorBlend)
		local eye = head.Position + Vector3.new(0, 0.12, 0)
		local away = eye - target
		if away.Magnitude > 0.05 then eye += away.Unit * (0.85 * floorBlend) end
		camera.CFrame = CFrame.lookAt(eye, target) * CFrame.Angles(shake * 0.55, shake, math.rad(-9) * floorBlend + shake * 0.35)
		camera.FieldOfView = 70 + math.clamp(elapsed / math.max(duration or 5, 0.1), 0, 1) * 4
	end)
end

remote.OnClientEvent:Connect(function(eventName, entity, duration, deathAt, id, character, style)
	if eventName == "capture" then
		beginCapture(entity, duration, deathAt, id, character, style)
	elseif eventName == "cancel" then
		cancelCapture(id, character)
	elseif eventName == "death" then
		local record = captureRecord
		if record and record.Id == id and record.Character == character and not record.Death then
			record.Death = true
			task.spawn(fadeDeath, character)
		end
	end
end)

local function hookChar(char)
	clearFade()
	stopCapture()
	dying = false
	camera = workspace.CurrentCamera
	camera.CameraType, camera.FieldOfView = Enum.CameraType.Custom, 70
	local hum = char:WaitForChild("Humanoid")
	if player.Character ~= char then return end
	hum.Died:Connect(function()
		task.wait(DIED_GRACE)
		if player.Character ~= char or dying then return end
		dying = true
		makeOverlay()
		task.spawn(fadeDeath, char)
	end)
end
if player.Character then hookChar(player.Character) end
player.CharacterAdded:Connect(hookChar)
