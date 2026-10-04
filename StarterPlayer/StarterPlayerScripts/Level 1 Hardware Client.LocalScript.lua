-- Level 1 relay and lever motion. PuzzleManager owns every state change and every final pose;
-- this script only animates them locally so they read as physical objects:
--   * holding E on a relay unlatches its door so it stands ajar and works the fuse loose; letting
--     go eases everything back
--   * "relayextract" swings the door fully open and pulls the fuse out to whoever took it
--   * "leverpull" throws the lever from up to down: a short lift off the latch, a firm throw, a
--     rebound off the bottom stop and a settle
-- Geometry comes from attributes PuzzleManager publishes on each model (DoorHinge, LeverHinge ...).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local status = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("PuzzleStatus")
local player = Players.LocalPlayer

local HOLD_DOOR = .3 -- the door stands ajar while E is held; the full swing waits for the extraction
local LEVER_THROW = { -- {degrees, seconds, style, direction}; nil degrees = the server's down pose
	{-18, .10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out},
	{-160, .24, Enum.EasingStyle.Quad, Enum.EasingDirection.In},
	{-150, .08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out},
	{nil, .12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut},
}

local function ease(alpha, style, direction)
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out)
end

-- One RenderStepped job per object; starting a new job replaces the running one. The step gets the
-- elapsed time (summed frame deltas, not os.clock) and returns false when it is done.
local jobs = {}
local function run(key, step)
	if jobs[key] then jobs[key]:Disconnect() end
	local elapsed, connection = 0, nil
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local ok, more = pcall(step, elapsed)
		if not ok or more == false then
			connection:Disconnect()
			if jobs[key] == connection then jobs[key] = nil end
			if not ok then warn("[Level 1 Hardware Client] " .. tostring(more)) end
		end
	end)
	jobs[key] = connection
end

-- Relays -------------------------------------------------------------------------------------

local relays = setmetatable({}, { __mode = "k" })

local function relayState(model)
	if typeof(model) ~= "Instance" or not model:IsDescendantOf(workspace) then return nil end
	local s = relays[model]
	if s then return s end
	local door, core = model:FindFirstChild("RelayDoor"), model:FindFirstChild("Fuse")
	local hinge, offset = model:GetAttribute("DoorHinge"), model:GetAttribute("DoorHingeOffset")
	if not (door and core and typeof(hinge) == "CFrame" and type(offset) == "number") then return nil end -- streamed out
	local parts = { core }
	for _, child in ipairs(model:GetChildren()) do
		if child.Name == "FuseCap" and child:IsA("BasePart") then parts[#parts + 1] = child end
	end
	s = { model = model, door = door, parts = parts, hinge = hinge, offset = offset,
		open = math.rad(model:GetAttribute("DoorOpenDegrees") or 86), angle = 0, token = 0 }
	relays[model] = s
	return s
end

-- The door leaf and everything welded to it (label, lamp, handle, Blender art).
local function doorPieces(s)
	if not s.pieces then
		s.pieces = {}
		for _, part in ipairs(s.door:GetConnectedParts(false)) do
			s.pieces[#s.pieces + 1] = part
			for _, item in ipairs(part:GetDescendants()) do
				if item:IsA("BasePart") then s.pieces[#s.pieces + 1] = item end
			end
		end
	end
	return s.pieces
end

local function setDoor(s, amount)
	s.angle = amount
	if not s.door.Parent then return end
	s.door.CFrame = s.hinge * CFrame.Angles(0, s.open * amount, 0) * CFrame.new(s.offset, 0, 0)
	-- A centred first-person camera stands inside the full swing; let the leaf ghost out while it
	-- passes through the view instead of flashing a dark panel across the screen.
	local camera, fade = workspace.CurrentCamera, 0
	if camera then
		local eye = s.hinge:PointToObjectSpace(camera.CFrame.Position)
		if math.abs(eye.Y) < 3.4 and eye.X * eye.X + eye.Z * eye.Z < 5.4 * 5.4 then
			fade = math.clamp(1 - math.abs(math.atan2(-eye.Z, eye.X) - s.open * amount) / .3, 0, 1)
		end
	end
	for _, piece in ipairs(doorPieces(s)) do piece.LocalTransparencyModifier = fade end
end

local function hideOriginal(s, hidden)
	for _, part in ipairs(s.parts) do
		if part.Parent then
			part.LocalTransparencyModifier = hidden and 1 or 0
			for _, item in ipairs(part:GetDescendants()) do
				if item:IsA("BasePart") then
					item.LocalTransparencyModifier = hidden and 1 or 0
				elseif item:IsA("Light") then
					item.Enabled = not hidden
				end
			end
		end
	end
end

-- A local copy of the fuse (core + caps, with their Blender art) that can leave the cabinet while
-- the server keeps the real parts until it confirms the extraction.
local function ghostOf(s)
	if s.ghost and s.ghost.Parent then return s.ghost end
	local ghost = Instance.new("Model")
	ghost.Name = "RelayFuseGhost"
	for _, part in ipairs(s.parts) do
		if part.Parent then
			local copy = part:Clone()
			copy.Anchored = true
			copy.Parent = ghost
		end
	end
	ghost.PrimaryPart = ghost:FindFirstChild("Fuse")
	ghost.Parent = workspace.CurrentCamera -- local only
	s.ghost, s.seat = ghost, ghost:GetPivot()
	hideOriginal(s, true)
	return ghost
end

local function dropGhost(s)
	if s.ghost then s.ghost:Destroy() end
	s.ghost = nil
end

local function alive(s)
	if s.model:IsDescendantOf(workspace) then return true end
	dropGhost(s) -- round torn down mid-animation
	return false
end

-- Ease the door shut and the fuse back into its seat, then hand the real parts back.
local function settle(s)
	local from, ghost = s.angle, s.ghost
	local start = ghost and ghost.Parent and ghost:GetPivot()
	if start then -- a refused extraction can arrive mid-flight: full size and opaque again
		ghost:ScaleTo(1)
		for _, item in ipairs(ghost:GetDescendants()) do
			if item:IsA("BasePart") then item.LocalTransparencyModifier = 0 end
		end
	end
	run(s, function(t)
		if not alive(s) then return false end
		local k = ease(t / .35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		setDoor(s, from * (1 - k))
		if start then ghost:PivotTo(start:Lerp(s.seat, k)) end
		if k < 1 then return true end
		dropGhost(s)
		hideOriginal(s, false)
		return false
	end)
end

local function flightTarget(who)
	if who == player then
		local camera = workspace.CurrentCamera
		return camera and camera.CFrame * CFrame.new(.9, -1.25, -1.7) -- into your hands, bottom right of view
	end
	local character = who and who.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	return hand and hand.CFrame * CFrame.new(0, -.72, -.12) -- the carried-fuse grip PuzzleManager welds
end

local function extract(model, who)
	local s = relayState(model)
	if not s or s.extracting then return end
	s.extracting, s.holding = true, false
	s.token += 1
	local ghost = ghostOf(s)
	local from, start = s.angle, ghost:GetPivot()
	local out = s.seat * CFrame.new(0, 0, -1.3) -- clear of the cabinet, straight out of the socket
	local pieces = {}
	for _, item in ipairs(ghost:GetDescendants()) do
		if item:IsA("BasePart") then pieces[#pieces + 1] = item end
	end
	run(s, function(t)
		if not alive(s) then return false end
		setDoor(s, from + (1 - from) * ease(t / .32, Enum.EasingStyle.Back))
		if t < .14 then -- a sharp pull out of the clips
			ghost:PivotTo(start:Lerp(out, ease(t / .14)))
			return true
		end
		local k = ease((t - .14) / .5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local target = flightTarget(who) or out
		local lift = out.Position:Lerp(target.Position, .5) + Vector3.new(0, .7, 0)
		local position = out.Position:Lerp(lift, k):Lerp(lift:Lerp(target.Position, k), k)
		ghost:PivotTo(CFrame.new(position) * out.Rotation:Lerp(target.Rotation, k))
		ghost:ScaleTo(1 - .5 * k)
		local fade = math.clamp((k - .7) / .3, 0, 1)
		for _, piece in ipairs(pieces) do piece.LocalTransparencyModifier = fade end
		if t < .64 then return true end
		dropGhost(s)
		setDoor(s, 1)
		return false
	end)
end

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	local model = prompt:FindFirstAncestor("FuseRelay")
	local s = model and model:GetAttribute("ContainsFuse") == true and relayState(model)
	if not s or s.extracting then return end
	s.holding, s.triggered = true, false
	s.token += 1
	local hold = math.max(prompt.HoldDuration, .1)
	local from = s.angle
	local ghost = ghostOf(s)
	run(s, function(t)
		if not s.holding or not alive(s) then return false end
		local progress = t / hold
		-- unlatch with a small kick so the door stands ajar
		setDoor(s, from + (HOLD_DOOR - from) * ease(progress / .45, Enum.EasingStyle.Back))
		-- then work the fuse loose: a tightening wobble while it creeps out of the clips
		local loose = math.clamp((progress - .4) / .6, 0, 1)
		local wobble = loose > 0 and math.sin(t * 38) * .03 * (1 - loose * .5) or 0
		ghost:PivotTo(s.seat * CFrame.new(wobble, 0, -.45 * loose * loose) * CFrame.Angles(0, 0, wobble * 1.5))
		return true
	end)
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local model = prompt:FindFirstAncestor("FuseRelay")
	local s = model and relays[model]
	if s then s.triggered = true end
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	local model = prompt:FindFirstAncestor("FuseRelay")
	local s = model and relays[model]
	if not s or not s.holding then return end
	s.holding = false
	local token = s.token
	-- A completed hold also ends here. Wait for the server's "relayextract" before closing; a
	-- refused trigger (dead, out of range) closes after a moment.
	task.delay(.2, function()
		if s.token ~= token or s.extracting then return end
		if s.triggered then
			task.delay(1.3, function()
				if s.token == token and not s.extracting then settle(s) end
			end)
		else
			settle(s)
		end
	end)
end)

-- Levers -------------------------------------------------------------------------------------

local function throwLever(model)
	if typeof(model) ~= "Instance" or not model:IsDescendantOf(workspace) then return end
	local handle, knob = model:FindFirstChild("Handle"), model:FindFirstChild("Knob")
	local hinge, up, down = model:GetAttribute("LeverHinge"), model:GetAttribute("LeverUp"), model:GetAttribute("LeverDown")
	if not (handle and knob and typeof(hinge) == "CFrame" and type(up) == "number" and type(down) == "number") then return end
	local rod = CFrame.new(0, handle.Size.Y * .5, 0)
	local knobOffset = CFrame.new(0, 1.25, 0)
	local function pose(degrees)
		handle.CFrame = hinge * CFrame.Angles(math.rad(degrees), 0, 0) * rod
		knob.CFrame = handle.CFrame * knobOffset
	end
	pose(up)
	local from, index, stepStart = up, 1, 0
	run(model, function(t)
		if not handle.Parent or not knob.Parent then return false end
		while true do
			local step = LEVER_THROW[index]
			if not step then
				pose(down) -- exactly the server's final pose
				return false
			end
			local to = step[1] or down
			local alpha = (t - stepStart) / step[2]
			if alpha < 1 then
				pose(from + (to - from) * ease(alpha, step[3], step[4]))
				return true
			end
			from, stepStart, index = to, stepStart + step[2], index + 1
		end
	end)
end

status.OnClientEvent:Connect(function(event, model, who)
	if event == "relayextract" then
		extract(model, who)
	elseif event == "relayrestore" then
		local s = typeof(model) == "Instance" and relays[model]
		if s then
			s.extracting = false
			settle(s)
		end
	elseif event == "leverpull" then
		throwLever(model)
	end
end)
