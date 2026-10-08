-- Lobby Tunnel Reach Client (2026-10-06). TUNNEL_REACH_20261006.
--   Draws the thing behind the fence at the DJ end of the lobby. The server (`Lobby Tunnel Reach`) decides who is
--   over the fence, where each hand is and who is taken, and publishes it on ReplicatedStorage.LobbyTunnelReach:
--   Awake, Eyes (how far down the tunnel they are), Gaze, and per arm T<n> (the middle of the palm), S<n> (rest,
--   creep, windup, strike, miss, hold, drag, wait, retreat), At<n>, V<n> (the UserId in that hand), Shoulder<n>.
--   Everything here is local parts in workspace.LobbyTunnelReachLocal; nothing is drawn while it sleeps.
--
--   AN ARM is eight long bones folded between a shoulder nobody sees and the wrist, a knob on every elbow. The fold
--   is worked out, not simulated: the joints lie along the straight line from shoulder to wrist and are pushed off
--   it alternately to either side by as much as the spare length allows, so a hand that is close to the dark has
--   its arm folded up like a ruler and a hand at the fence has it nearly straight.
--   A HAND is a palm and six digits of three joints (four fingers, a thumb on either side). The poses and the roots
--   of the digits come from the Blender build (attribute `Hand`); `poseHand` is build_reach.py's `digit_frames`.
--   THE PIECES are MeshPart templates in ReplicatedStorage.LobbyTunnelReach.Meshes, baked by the server. Each looks
--   down its own -Z (the far end) and carries `Offset`: its own origin measured from the middle of its box.
--
--   For the player it takes: the picture closes in while they are pulled and is black by the time they are in the
--   dark; it stays black until the lobby has stood them up again. `ReduceCameraShake` leaves the camera alone;
--   nothing here flashes.
--
--   REACH_DARK_20261007 (owner, with two pictures: "you can see the built monster and that it's not complete, make
--   sure it is dark all the way down to the entity" and, of the eyes shown to the victim after the kill, "no kill
--   cam like that looking at the entity please, just black screen and then respawn in lobby"). It is eyes and arms
--   and nothing else, so nothing of it may be seen where there is no light: every piece is blacked out by how far
--   behind the wall it is (`DARK`; the Builder takes the tunnel itself to black over the same stretch), the eyes
--   light nothing, and the shot of the eyes after the kill is gone.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local root = ReplicatedStorage:WaitForChild("LobbyTunnelReach")
local kit = root:WaitForChild("Meshes")
while root:GetAttribute("Ready") ~= true do root:GetAttributeChangedSignal("Ready"):Wait() end   -- never, on a round server

local PIECES = {"bone_a", "bone_b", "bone_c", "elbow", "palm", "finger", "thumb", "claw", "eye"}
for _, name in ipairs(PIECES) do
	if not kit:WaitForChild(name, 60) then return end
end
local frame = root:GetAttribute("Frame")
local hand = HttpService:JSONDecode(root:GetAttribute("Hand"))
local ARMS = root:GetAttribute("Arms")
local POSES = hand.poses
POSES.reach = {12, -30, -24}                 -- a hand in the air, groping

local BONES, BONE = 8, 24.5                  -- bones in an arm, and how long one is when the arm is straight
local GRIP_DROP = 3.6                        -- the server's CONFIG.GripDrop
local LOOK = {                               -- per arm: thickness, size of the hand, which way its elbows fold
	{thick = 1.3, size = 1.0, plane = 0.5, seed = 0.0},
	{thick = 1.42, size = 1.06, plane = -0.65, seed = 2.3},
	{thick = 1.18, size = 0.94, plane = 2.9, seed = 4.1},
	{thick = 1.3, size = 1.0, plane = 1.0, seed = 5.6},
}
local EYES = {{x = -9.4, y = 21.4, size = 10.0}, {x = 8.0, y = 22.6, size = 11.2}}   -- not a matched pair
local SKIN_REFLECTANCE = 0.1
local EYE_GLOW = 0.55
-- How much of its colour a piece keeps. By depth: all of it up to `Lit` studs behind the wall, none from `Black` on
-- (the tunnel's lamps are out at 70). And by nearness: a piece close to the camera keeps a little wherever it is,
-- so a hand that has come right up to somebody standing in the dark is a shape and not nothing.
local DARK = {Lit = 34, Black = 72, Near = 14, Far = 30, NearKeeps = 0.7, Steps = 16}

local holder = Instance.new("Folder")
holder.Name = "LobbyTunnelReachLocal"
local parts, frames = {}, {}                 -- every piece and where it goes this frame, for one BulkMoveTo
local items = {}                             -- the same pieces, with what each needs to be shaded
local function piece(name, size)
	local template = kit[name]
	local part = template:Clone()
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Material, part.Reflectance, part.Color = Enum.Material.SmoothPlastic, SKIN_REFLECTANCE, Color3.new(1, 1, 1)
	local native = template.Size
	local offset = template:GetAttribute("Offset") or Vector3.zero
	local item = {part = part, native = native, centre = -offset, slot = #parts + 1, shift = CFrame.new(), shade = DARK.Steps}
	items[item.slot] = item
	if size then
		part.Size = Vector3.new(native.X * size.X, native.Y * size.Y, native.Z * size.Z)
		item.shift = CFrame.new(item.centre * size)
	end
	parts[item.slot] = part
	frames[item.slot] = CFrame.new()
	part.Parent = holder
	return item
end

local arms = {}
for i = 1, ARMS do
	local look = LOOK[(i - 1) % #LOOK + 1]
	local arm = {index = i, look = look, bones = {}, elbows = {}, digits = {}, joints = {}, walk = look.seed, pose = "crawl", splay = 1}
	for b = 1, BONES do
		local thick = look.thick * (1.5 - 0.72 * (b - 1) / (BONES - 1))
		local bone = piece(({"bone_a", "bone_b", "bone_c"})[(b + i) % 3 + 1])
		bone.thick, bone.roll, bone.length = thick, CFrame.Angles(0, 0, b * 2.1 + i), -1
		arm.bones[b] = bone
		if b < BONES then
			local k = 0.5 + 0.34 * thick
			local elbow = piece("elbow", Vector3.new(k, k, k))
			elbow.turn = CFrame.Angles(b * 1.3 + i, b * 2.9, i * 0.7)
			arm.elbows[b] = elbow
		end
	end
	local s = look.size
	arm.palm = piece("palm", Vector3.new(s, s, s))
	for n, digit in ipairs(hand.digits) do
		local entry = {root = Vector3.new(digit.root[1], digit.root[2], digit.root[3]) * s, yaw = digit.yaw, joints = {}, curl = {0, 0, 0}}
		for j = 1, 3 do
			local key = j == 3 and "claw" or digit.kind
			local length = digit.lengths[j] * s
			local thick = digit.thick * (1 - 0.12 * (j - 1)) / 0.74 * s
			local native = kit[key].Size
			local joint = piece(key, Vector3.new(thick, thick, length * 1.06 / native.Z))
			joint.length = length
			entry.joints[j] = joint
			entry.curl[j] = POSES.crawl[j]
		end
		arm.digits[n] = entry
	end
	arms[i] = arm
end

local eyes = {}
for i, spec in ipairs(EYES) do
	local iris = kit.eye:Clone()
	iris.Anchored, iris.CanCollide, iris.CanTouch, iris.CanQuery, iris.CastShadow = true, false, false, false, false
	-- (at full colour the game's bloom turned each eye into a ball of light with no iris and no slit: seen in the
	-- live game at full graphics quality, not in Studio's default quality. EYE_GLOW is how much of it they keep.)
	iris.Material, iris.Color = Enum.Material.Neon, Color3.new(EYE_GLOW, EYE_GLOW, EYE_GLOW)
	iris.Parent = holder
	local pupil = Instance.new("Part")
	pupil.Name = "pupil"
	pupil.Anchored, pupil.CanCollide, pupil.CanTouch, pupil.CanQuery, pupil.CastShadow = true, false, false, false, false
	pupil.Material, pupil.Color, pupil.Reflectance = Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), 0   -- a reflecting pupil showed the sky's stars
	local ball = Instance.new("SpecialMesh")
	ball.MeshType = Enum.MeshType.Sphere
	ball.Parent = pupil
	pupil.Parent = holder
	eyes[i] = {spec = spec, iris = iris, pupil = pupil, native = kit.eye.Size}
end

local function deg(v) return math.rad(v) end
local function ease(u) u = math.clamp(u, 0, 1); return u * u * (3 - 2 * u) end

-- the palm's frame looks down -Z at the fingertips with +Y out of the back of the hand
local function poseHand(arm, palm, dt, rate)
	local s = arm.look.size
	local k = 1 - math.exp(-dt * rate)
	frames[arm.palm.slot] = palm * arm.palm.shift
	local target = POSES[arm.pose]
	for n, digit in ipairs(arm.digits) do
		local at = palm * CFrame.new(digit.root) * CFrame.Angles(0, deg(digit.yaw * arm.splay), 0)
		local wave = arm.walk + n * 2.1
		for j, joint in ipairs(digit.joints) do
			local want = target[j]
			if arm.pose == "crawl" then                        -- each finger steps in its own time
				want += (j == 1 and 15 * math.sin(wave)) or (j == 2 and -16 * math.sin(wave + 1.2)) or 9 * math.sin(wave + 2.2)
			elseif arm.pose == "reach" then
				want += 9 * math.sin(wave * 0.6 + j)
			end
			digit.curl[j] += (want - digit.curl[j]) * k
			at *= CFrame.Angles(deg(digit.curl[j]), 0, 0)
			frames[joint.slot] = at * CFrame.new(0, 0, -joint.length / 2) * joint.shift
			at *= CFrame.new(0, 0, -joint.length)
		end
	end
	local length = hand.palm[3] * s
	return palm * Vector3.new(0, 0.15 * s, length / 2 - 0.35 * s)            -- the wrist
end

local function poseArm(arm, shoulder, wrist, t)
	local look = arm.look
	local span = wrist - shoulder
	local reach = span.Magnitude
	local along = span / reach
	local each = reach / BONES
	local fold = math.min(math.sqrt(math.max(BONE * BONE - each * each, 0)) * 0.5, 12)
	local side = along:Cross(Vector3.yAxis)
	side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
	local up = side:Cross(along).Unit
	local joints = arm.joints
	for i = 0, BONES do
		local u = i / BONES
		local point = shoulder + along * (reach * u)
		if i > 0 and i < BONES then
			local sign = i % 2 == 0 and -1 or 1
			local turn = look.plane + 0.45 * math.sin(t * 0.31 + i * 1.3 + look.seed)
			local amount = fold * sign * (0.72 + 0.28 * math.sin(i * 2.4 + look.seed)) + 0.6 * math.sin(t * 0.8 + i * 0.9 + look.seed)
			point += (up * math.cos(turn) + side * math.sin(turn)) * amount
			local at = frame:PointToObjectSpace(point)           -- an elbow rests on the road, it does not go through it
			local floor = 0.8 + 0.9 * look.thick
			if at.Y < floor or math.abs(at.X) > 31 or at.Y > 35 then
				point = frame:PointToWorldSpace(Vector3.new(math.clamp(at.X, -31, 31), math.clamp(at.Y, floor, 35), at.Z))
			end
		end
		joints[i] = point
	end
	for b, bone in ipairs(arm.bones) do
		local a, z = joints[b - 1], joints[b]
		local length = (z - a).Magnitude
		if math.abs(length - bone.length) > 0.15 then
			bone.length = length
			bone.part.Size = Vector3.new(bone.native.X * bone.thick, bone.native.Y * bone.thick, length + 0.7)
		end
		frames[bone.slot] = CFrame.lookAt((a + z) / 2, z) * bone.roll * CFrame.new(bone.centre.X * bone.thick, bone.centre.Y * bone.thick, 0)
		local elbow = arm.elbows[b]
		if elbow then frames[elbow.slot] = CFrame.new(z) * elbow.turn * elbow.shift end
	end
end

-- ---- the player it takes ------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "TunnelReachCover"
gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder, gui.Enabled = true, false, 940, false
local black = Instance.new("Frame")
black.Size, black.BackgroundColor3, black.BorderSizePixel, black.BackgroundTransparency = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0, 1
black.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local taken
local eyeOpen, eyeOut, eyeWide, blinkAt, blink = 0, root:GetAttribute("Eyes") or 148, 0, 0, 0
local function depthOf(character)            -- studs behind the wall
	local body = character and character:FindFirstChild("HumanoidRootPart")
	return body and frame:PointToObjectSpace(body.Position).Z or nil
end
local SHAKE = "TunnelReachShake"

-- The lobby's own screens (the left rail, Friend Boost, the daily chips) have no place over this: they are switched
-- off for as long as it lasts and put back exactly as they were. One that switches itself on again is put out again.
local hidden = {}
local function hideScreens()
	for _, screen in ipairs(player.PlayerGui:GetChildren()) do
		if screen:IsA("ScreenGui") and screen ~= gui and screen.Enabled then
			hidden[screen] = true
			screen.Enabled = false
		end
	end
end
local function showScreens()
	for screen in pairs(hidden) do
		if screen.Parent then screen.Enabled = true end
	end
	table.clear(hidden)
end

local function endTaken()
	RunService:UnbindFromRenderStep(SHAKE)
	showScreens()
	local camera = workspace.CurrentCamera
	if taken and camera then camera.FieldOfView = taken.fov end
	taken = nil
	player:SetAttribute("TunnelReachPhase", nil)
	black.BackgroundTransparency = 1
	gui.Enabled = false
end

-- The camera is written AFTER the default camera has had its turn (a RenderStepped connection runs before it and
-- loses).
local function cameraStep()
	local camera = workspace.CurrentCamera
	if not (taken and camera) then return end
	local e = os.clock() - taken.since
	if taken.phase == "pull" then
		if player:GetAttribute("ReduceCameraShake") ~= true then
			local whole = os.clock() - taken.at
			local a = 0.012 + 0.03 * math.clamp(whole / 1.2, 0, 1)
			camera.CFrame *= CFrame.Angles(math.noise(whole * 23, 1.7) * 2 * a, math.noise(whole * 19, 9.1) * 2 * a, math.noise(whole * 17, 4.3) * 1.2 * a)
			camera.FieldOfView = taken.fov + 20 * ease(whole / 0.7)
		end
	elseif taken.phase == "back" and taken.view and e < 0.35 then
		camera.CFrame = taken.view                                 -- the default camera takes its direction from this
	end
end

local function beginTaken()
	local camera = workspace.CurrentCamera
	taken = {at = os.clock(), fov = camera.FieldOfView, phase = "pull", since = os.clock(), character = player.Character,
		from = depthOf(player.Character) or 0}
	player:SetAttribute("TunnelReachPhase", "pull")
	gui.Enabled = true
	RunService:BindToRenderStep(SHAKE, Enum.RenderPriority.Camera.Value + 2, cameraStep)
end

player:GetAttributeChangedSignal("TunnelReachHeld"):Connect(function()
	if player:GetAttribute("TunnelReachHeld") == true and not taken then beginTaken() end
end)

local function stepTaken(dt)
	local camera = workspace.CurrentCamera
	if taken.phase ~= "back" then hideScreens() end
	local e = os.clock() - taken.since
	local function go(phase)
		taken.phase, taken.since = phase, os.clock()
		player:SetAttribute("TunnelReachPhase", phase)             -- client-local; a play test reads it
	end
	if taken.phase == "pull" then
		-- it closes in from the moment the hand shuts, and it is black thirty studs into the pull, wherever the hand
		-- took them: the eyes are never nearer than that, so nothing of what is down there is seen from close by
		local deep = depthOf(taken.character) or taken.deep or taken.from
		taken.deep = deep
		taken.cover = math.max(taken.cover or 0, 0.55 * ease((os.clock() - taken.at) / 2.2), ease((deep - taken.from - 4) / 26))
		black.BackgroundTransparency = 1 - taken.cover
		local humanoid = taken.character and taken.character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or e > 5 then go("wait") end
	elseif taken.phase == "wait" then
		-- black, and it stays black until the lobby has stood them up again
		black.BackgroundTransparency = math.max(0, black.BackgroundTransparency - dt * 9)
		local character = player.Character
		local humanoid = character and character ~= taken.character and character:FindFirstChildOfClass("Humanoid")
		local body = humanoid and character:FindFirstChild("HumanoidRootPart")
		if body or e > 7 then
			-- back to the player, under the cover, looking the way the lobby's own spawn view looks: down the tunnel
			camera.CameraType = Enum.CameraType.Custom
			if humanoid then camera.CameraSubject = humanoid end
			camera.FieldOfView = taken.fov
			local lobby = workspace:FindFirstChild("LobbyReimaginedPreview")
			local toward = body and lobby and (lobby:GetPivot().Position - body.Position) * Vector3.new(1, 0, 1)
			if toward and toward.Magnitude > 1 then
				toward = toward.Unit
				local head = body.Position + Vector3.new(0, 2, 0)
				taken.view = CFrame.lookAt(head - toward * 12 + Vector3.new(0, 3.5, 0), head + toward * 30)
			end
			go("back")
		end
	elseif taken.phase == "back" then
		if next(hidden) then showScreens() end                  -- under the cover, so they are simply there when it lifts
		black.BackgroundTransparency = e < 0.5 and 0 or ease((e - 0.5) / 0.9)
		if e > 1.4 then endTaken() end
	end
end

-- ---- every frame ---------------------------------------------------------------------------------------------------
local shown = false
local function show(on)
	if shown == on then return end
	shown = on
	holder.Parent = on and workspace or nil
end

for _, arm in ipairs(arms) do
	arm.tip = frame:PointToWorldSpace(root:GetAttribute("T" .. arm.index))
	arm.heading = frame:VectorToWorldSpace(Vector3.new(0, 0, -1))    -- toward the lobby
	arm.pitch = 0
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.1)
	if taken then stepTaken(dt) end
	local awake = root:GetAttribute("Awake") == true
	local busy = awake or taken ~= nil
	for _, arm in ipairs(arms) do
		arm.state = root:GetAttribute("S" .. arm.index) or "rest"
		if arm.state ~= "rest" then busy = true end
	end
	local want = awake and 1 or 0
	eyeOpen += (want - eyeOpen) * (1 - math.exp(-dt * (want > eyeOpen and 3.2 or 1.1)))
	if not busy and eyeOpen < 0.02 then
		eyeOpen = 0
		show(false)
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - frame.Position).Magnitude > 750 then
		show(false)
		return
	end
	show(true)
	local t = os.clock()
	local now = workspace:GetServerTimeNow()
	local striking = false

	for _, arm in ipairs(arms) do
		local state = arm.state
		local since = now - (root:GetAttribute("At" .. arm.index) or now)
		local goal = frame:PointToWorldSpace(root:GetAttribute("T" .. arm.index))
		local held
		if state == "hold" or state == "drag" then               -- glued to the body it holds, wherever that really is
			local victim = Players:GetPlayerByUserId(root:GetAttribute("V" .. arm.index) or 0)
			local body = victim and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
			if body then
				held = body.Position + Vector3.new(0, GRIP_DROP, 0)
				goal = held
			end
		end
		local before = arm.tip
		local quick = (state == "strike" or state == "windup") and 45 or (held and 60 or 12)
		arm.tip = held and (state == "drag" and held or arm.tip:Lerp(held, 1 - math.exp(-dt * quick))) or arm.tip:Lerp(goal, 1 - math.exp(-dt * quick))
		local moved = arm.tip - before
		local flat = Vector3.new(moved.X, 0, moved.Z)
		if state == "creep" and flat.Magnitude > 0.02 then
			arm.heading = arm.heading:Lerp(flat.Unit, 1 - math.exp(-dt * 2.5)).Unit
		end
		arm.walk += flat.Magnitude * 1.75 + dt * ((state == "wait" or state == "miss") and 5.5 or 0.9)

		local high = (root:GetAttribute("T" .. arm.index).Y > 5.2) and (state == "creep" or state == "wait" or state == "retreat" or state == "rest")
		local pitch, rate = -6, 9
		arm.pose, arm.splay = high and "reach" or "crawl", 1
		if high then pitch = -34 end
		if state == "windup" then
			arm.pose, arm.splay, pitch, rate = "open", 1.5, 52 * ease(since / 0.4), 16
			striking = true
		elseif state == "strike" then
			arm.pose, arm.splay, pitch, rate = "cage", 1.2, 52 * (1 - ease(since / 0.18)), 40
			striking = true
		elseif state == "miss" then
			arm.pose, arm.splay, pitch, rate = since < 0.35 and "cage" or "crawl", 1.1, 0, 14
		elseif state == "hold" then
			arm.pose, arm.splay, pitch, rate = "grip", 0.92, 0, 34
			striking = true
		elseif state == "drag" then
			arm.pose, arm.splay, pitch, rate = "grip", 0.92, 14, 34
		end
		arm.pitch += (pitch - arm.pitch) * (1 - math.exp(-dt * 14))
		local sway = (state == "hold" and 0.05 or 0.035) * math.sin(t * (state == "hold" and 38 or 1.3) + arm.look.seed)
		local palm = CFrame.lookAt(arm.tip, arm.tip + arm.heading) * CFrame.Angles(deg(arm.pitch) + sway, 0, sway * 1.4)
		local wrist = poseHand(arm, palm, dt, rate)
		poseArm(arm, frame:PointToWorldSpace(root:GetAttribute("Shoulder" .. arm.index)), wrist, t)
	end
	-- no piece is seen where there is no light to see it by (DARK)
	local eyeAt = camera.CFrame.Position
	for slot, item in ipairs(items) do
		local at = frames[slot].Position
		local depth = frame:PointToObjectSpace(at).Z
		local keep = math.clamp((DARK.Black - depth) / (DARK.Black - DARK.Lit), 0, 1)
		keep = math.max(keep * keep, DARK.NearKeeps * math.clamp((DARK.Far - (at - eyeAt).Magnitude) / (DARK.Far - DARK.Near), 0, 1))
		local step = math.floor(keep * DARK.Steps + 0.5)
		if step ~= item.shade then
			item.shade = step
			local v = step / DARK.Steps
			item.part.Color = Color3.new(v, v, v)
			item.part.Reflectance = SKIN_REFLECTANCE * v
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)

	-- the eyes: they open when it wakes, come nearer as the hands go out, and blink now and then
	eyeOut += ((root:GetAttribute("Eyes") or eyeOut) - eyeOut) * (1 - math.exp(-dt * 0.7))
	eyeWide += ((striking and 1 or 0) - eyeWide) * (1 - math.exp(-dt * 7))
	if t >= blinkAt then
		blink = t
		blinkAt = t + 3.2 + math.random() * 5.5
	end
	local lid = 1 - math.clamp(1 - math.abs((t - blink) / 0.09 - 1), 0, 1)       -- shut for an instant, 0.18 s in all
	local gaze = frame:PointToWorldSpace(root:GetAttribute("Gaze") or Vector3.new(0, 4, 0))
	for i, eye in ipairs(eyes) do
		local spec = eye.spec
		local size = spec.size * (1 + 0.14 * eyeWide)
		local open = math.max(0.015, eyeOpen * lid)
		local at = frame:PointToWorldSpace(Vector3.new(spec.x + 0.7 * math.sin(t * 0.42), spec.y + 0.35 * math.sin(t * 0.6 + i), eyeOut))
		local face = CFrame.lookAt(at, gaze)
		eye.iris.Size = Vector3.new(size, size * open, size * eye.native.Z)
		eye.iris.CFrame = face
		-- a slit that widens when it is about to strike; it slides a little toward what it watches
		local slit = size * (0.11 + 0.2 * eyeWide)
		eye.pupil.Size = Vector3.new(slit, size * 0.78 * open, size * 0.05)
		local aside = math.clamp(frame:PointToObjectSpace(gaze).X - spec.x, -30, 30) / 30
		eye.pupil.CFrame = face * CFrame.new(-aside * size * 0.1, 0, -size * (eye.native.Z * 0.5 + 0.03))
		local visible = eyeOpen > 0.02 and 0 or 1
		eye.iris.Transparency, eye.pupil.Transparency = visible, visible
	end
end)

-- REACH_WARNING_20261008 (owner: "when players hop over the fence and the eyes start shining, a couple of seconds
-- go by and a text prompt appears on their screen: 'You are in danger, get back to safezone', blinking in red but
-- not in a big font"). Only on the screen of a player who is over the fence, from WARN_AFTER seconds after they
-- stand there with the eyes open, until they are back on the lobby's side or it has them (the taking blacks the
-- screen itself). The test is the server's own for "over the fence". A line in a ScreenGui of its own: the cover
-- above is only enabled for a taking. Under ReduceFlashing it stands still instead of blinking.
do
	local WARN_AFTER = 2.5
	local screen = Instance.new("ScreenGui")
	screen.Name = "TunnelReachWarning"
	screen.ResetOnSpawn, screen.IgnoreGuiInset, screen.DisplayOrder, screen.Enabled = false, false, 930, false
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.AnchorPoint, line.Position, line.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.16, 0), UDim2.new(0.9, 0, 0, 24)
	line.BackgroundTransparency = 1
	line.Font, line.TextSize = Enum.Font.GothamMedium, 16
	line.TextColor3 = Color3.fromRGB(255, 64, 56)
	line.TextStrokeColor3, line.TextStrokeTransparency = Color3.new(0, 0, 0), 0.45
	line.Text = "You are in danger, get back to the safe zone"
	line.Parent = screen
	screen.Parent = player:WaitForChild("PlayerGui")
	local overSince = nil
	RunService.Heartbeat:Connect(function()
		local fence = root:GetAttribute("Fence")
		local body = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = body and frame:PointToObjectSpace(body.Position)
		local over = at ~= nil and type(fence) == "number" and at.Z > -(fence - 0.9) and math.abs(at.X) < 37
			and at.Y > -4 and at.Y < 42 and player:GetAttribute("InRound") ~= true
			and player:GetAttribute("Level6PlaygroundPreview") ~= true
		if over and not taken and root:GetAttribute("Awake") == true and eyeOpen > 0.5 then
			overSince = overSince or os.clock()
		else
			overSince = nil
		end
		local on = overSince ~= nil and os.clock() - overSince >= WARN_AFTER
		if screen.Enabled ~= on then screen.Enabled = on end
		if on then
			-- a blink a second, lit for a little over half of it
			local dim = player:GetAttribute("ReduceFlashing") ~= true and (os.clock() - overSince) % 1 >= 0.58
			line.TextTransparency = dim and 0.85 or 0
			line.TextStrokeTransparency = dim and 0.92 or 0.45
		end
	end)
end

-- REACH_SOUNDS_20261008 (owner: "give the lobby monster sounds behind the fence. Use ElevenLabs and remember to
-- sound engineer the ai static out"). Its own sounds, made for it and for nothing else (no level lends another its
-- sounds): assets/lobby-reach-20261008 has the brief, every raw take and `clean_reach.py`, which takes the
-- generator's hiss out of them; tools/lobby_reach/README.md says what plays when.
--   deep in the tunnel, where the eyes are:  WAKE once when they open, a slow BREATHING for as long as they are
--     open, KILL when a hand comes back from the dark with nobody in it, RETREAT when it gives up and the eyes close
--   at each hand:  a wet CRAWL that is louder and quicker the faster the hand goes, WINDUP when it rears, SLAM when
--     it comes down on nothing, GRAB when it closes on somebody, DRAG all the way into the dark
-- Everything is a local Sound on a local part, driven by the same replicated attributes the arms are drawn from, so
-- every player near the fence hears the same thing at the same moment. Distances: somebody just over the fence is
-- about 145 studs from the eyes, the middle of the lobby 290, the spawn 430. The deep emitter is whole to 120 studs
-- and gone at 400 (a faint breath from the stage, nothing at the spawn); a hand is whole at 16 and gone at 150 to
-- 190, so it is heard coming for the last hundred studs of its way. The lobby's music plays at 0.12.
do
	-- REACH_SOUND_IDS_BEGIN (written by tools/lobby_reach/install_sounds.py from sound_ids.json)
	local IDS = {
		wake = {117940189058779, 72164714595964},
		windup = {128917156313141, 121233909593277},
		slam = {97896736900807, 124069536656370},
		grab = {140068430266389},
		kill = {139492757172415, 78029580675374},
		retreat = {121505714120825, 118016938051269},
		presence = 114751129400744,
		creep = 95645845470090,
		drag = 75840869369188,
	}
	-- REACH_SOUND_IDS_END
	local stage = Instance.new("Folder")       -- its own folder: `holder` leaves the workspace when nothing is awake
	stage.Name = "LobbyTunnelReachSound"
	stage.Parent = workspace
	local all = {}
	local function emitter(name)
		local part = Instance.new("Part")
		part.Name, part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = name, true, false, false, false
		part.Transparency, part.CastShadow, part.Size = 1, false, Vector3.one
		part.Parent = stage
		return part
	end
	local function sound(parent, name, id, volume, near, far, looped)
		if type(id) ~= "number" or id <= 0 then return nil end
		local item = Instance.new("Sound")
		item.Name, item.SoundId, item.Volume, item.Looped = name, "rbxassetid://" .. string.format("%.0f", id), volume, looped == true
		item.RollOffMode, item.RollOffMinDistance, item.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, near, far
		item.Parent = parent
		table.insert(all, item)
		return item
	end
	local function takes(parent, name, ids, volume, near, far)
		local list = {}
		for i, id in ipairs(ids) do
			table.insert(list, sound(parent, name .. i, id, volume, near, far))
		end
		return list
	end
	local function playOne(list)
		if #list == 0 then return end
		local ready = {}                       -- a take that has not loaded would be a silence: one that has, if any
		for _, item in ipairs(list) do
			if item.IsLoaded then table.insert(ready, item) end
		end
		local from = #ready > 0 and ready or list
		local item = from[math.random(#from)]
		item.PlaybackSpeed = 0.95 + math.random() * 0.1
		item.TimePosition = 0
		item:Play()
	end
	-- a loop follows a wanted volume: it starts when that is above nothing and stops when it has faded out
	local function follow(item, want, dt, quick, startAt)
		if not item then return end
		item.Volume += (want - item.Volume) * math.min(1, dt * quick)
		if item.Volume > 0.012 then
			if not item.IsPlaying then
				item.TimePosition = startAt or 0
				item:Play()
			end
		elseif item.IsPlaying and want <= 0 then
			item:Stop()
		end
	end

	local deep = emitter("Deep")
	local presence = sound(deep, "Breathing", IDS.presence, 0, 120, 400, true)
	local wake = takes(deep, "Wake", IDS.wake, 1, 120, 400)
	local retreat = takes(deep, "Retreat", IDS.retreat, 0.9, 120, 400)
	local kill = takes(deep, "Kill", IDS.kill, 1, 120, 400)
	-- the one who is taken hears it whole, wherever the lobby stands them up meanwhile: a Sound in a Folder has no place
	local killOwn = takes(stage, "KillOwn", IDS.kill, 0.8, 120, 400)
	local hands = {}
	for _, arm in ipairs(arms) do
		local at = emitter("Hand" .. arm.index)
		hands[arm.index] = {part = at, last = "rest", was = arm.tip, speed = 0,
			creep = sound(at, "Crawl", IDS.creep, 0, 16, 150, true),
			drag = sound(at, "Drag", IDS.drag, 0, 16, 190, true),
			-- (the cracks and the slaps are all peak: the limiter left them 5 and 3 dB under the rest)
			windup = takes(at, "Windup", IDS.windup, 1.6, 16, 170),
			slam = takes(at, "Slam", IDS.slam, 1.25, 16, 170),
			grab = takes(at, "Grab", IDS.grab, 1, 16, 170)}
	end
	task.spawn(function()
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(all) end)
	end)

	local wasAwake, lastKill = false, -math.huge
	RunService.Heartbeat:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local near = camera ~= nil and (camera.CFrame.Position - frame.Position).Magnitude < 620
		local awake = near and root:GetAttribute("Awake") == true
		deep.CFrame = CFrame.new(frame:PointToWorldSpace(Vector3.new(0, 21, eyeOut)))
		if awake and not wasAwake then playOne(wake) end
		-- (not after a taking: what is heard then is the kill, and a groan of giving up would be the wrong end)
		if wasAwake and not awake and near and os.clock() - lastKill > 9 then playOne(retreat) end
		wasAwake = awake
		follow(presence, near and eyeOpen * 0.85 or 0, dt, 2.5)
		for _, arm in ipairs(arms) do
			local h = hands[arm.index]
			local state = near and arm.state or "rest"
			h.part.CFrame = CFrame.new(arm.tip)
			h.speed += ((arm.tip - h.was).Magnitude / math.max(dt, 1 / 240) - h.speed) * math.min(1, dt * 6)
			h.was = arm.tip
			if state ~= h.last then
				if state == "windup" then
					playOne(h.windup)
				elseif state == "miss" then
					playOne(h.slam)
				elseif state == "hold" then
					playOne(h.grab)
				elseif h.last == "drag" then
					lastKill = os.clock()
					playOne(taken and killOwn or kill)
				end
				h.last = state
			end
			-- four hands on one loop would beat against each other: each has its own place in it and its own pace
			-- (a hand that is waiting where it stopped is still: it is heard only for as long as it really moves)
			local crawling = state == "creep" or state == "retreat"
			local moving = math.clamp(h.speed / 22, 0, 0.64)          -- it sets out at 4.5 studs a second and ends near 18
			follow(h.creep, crawling and 0.16 + moving or state == "wait" and moving or 0, dt, 5, arm.index * 2.3)
			if h.creep then h.creep.PlaybackSpeed = 0.84 + 0.07 * arm.index + math.clamp(h.speed / 40, 0, 0.25) end
			follow(h.drag, state == "drag" and 0.95 or 0, dt, 8)
		end
	end)
end
