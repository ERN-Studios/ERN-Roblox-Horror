-- Each client copies the movement of every visible R15 player into the
-- cosmetic Meshy skeleton. Bone.Transform does not replicate, and this mesh
-- does not share R15 joint names, so neither a server Animator nor Roblox's
-- stock Animate script can drive it directly. The physical R15 rig stays put.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local VISUAL_NAME = "ZyntraHazmatSkinVisual"
local ORIGINAL_ATTRIBUTE = "ZyntraHazmatOriginalTransparency"
local CAMERA_CLEARANCE = 3
local RESCAN_INTERVAL = 0.2

-- The 22 Bones retained by Studio in the canonical Meshy import and the R15
-- segment each should follow. Rest offsets come from the *actual authored R15*
-- attachment/Motor6D bind frames at runtime; no guessed global axis flip or
-- animation translation is introduced.
local BONE_TO_PART = {
	Hips = "LowerTorso",
	Spine02 = "LowerTorso", Spine01 = "UpperTorso", Spine = "UpperTorso",
	neck = "UpperTorso", Head = "Head",
	LeftShoulder = "UpperTorso", LeftArm = "LeftUpperArm",
	LeftForeArm = "LeftLowerArm", LeftHand = "LeftHand",
	RightShoulder = "UpperTorso", RightArm = "RightUpperArm",
	RightForeArm = "RightLowerArm", RightHand = "RightHand",
	LeftUpLeg = "LeftUpperLeg", LeftLeg = "LeftLowerLeg",
	LeftFoot = "LeftFoot", LeftToeBase = "LeftFoot",
	RightUpLeg = "RightUpperLeg", RightLeg = "RightLowerLeg",
	RightFoot = "RightFoot", RightToeBase = "RightFoot",
}

local BODY_PARTS = {
	Head = true, UpperTorso = true, LowerTorso = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
	Mask = true, Torso = true, LeftArm = true, RightArm = true,
	LeftLeg = true, RightLeg = true,
}

local states = {}
local blockedVisuals = setmetatable({}, {__mode = "k"})
local warned = {}

local function warnOnce(key, message)
	if warned[key] then return end
	warned[key] = true
	warn("[HazmatSkinDriver] " .. message)
end

local function sourceParts(character)
	local parts = {}
	for _, name in pairs(BONE_TO_PART) do
		if not parts[name] then
			local part = character:FindFirstChild(name)
			if not part or not part:IsA("BasePart") then return nil end
			parts[name] = part
		end
	end
	return parts
end

local function restFrames(character, root)
	local edges = {}
	local function addEdge(part0, part1, c0, c1)
		if not part0 or not part1 or not part0:IsA("BasePart")
			or not part1:IsA("BasePart") or part0 == part1
			or not part0:IsDescendantOf(character)
			or not part1:IsDescendantOf(character) then return end
		local relative = c0 * c1:Inverse()
		edges[part0] = edges[part0] or {}
		edges[part1] = edges[part1] or {}
		table.insert(edges[part0], {Part = part1, Relative = relative})
		table.insert(edges[part1], {Part = part0, Relative = relative:Inverse()})
	end
	for _, joint in ipairs(character:GetDescendants()) do
		if joint:IsA("Motor6D") then
			addEdge(joint.Part0, joint.Part1, joint.C0, joint.C1)
		elseif joint:IsA("AnimationConstraint") then
			local attachment0, attachment1 = joint.Attachment0, joint.Attachment1
			if attachment0 and attachment1
				and attachment0.Parent:IsA("BasePart")
				and attachment1.Parent:IsA("BasePart") then
				addEdge(attachment0.Parent, attachment1.Parent,
					attachment0.CFrame, attachment1.CFrame)
			end
		end
	end
	local frames = {[root] = root.CFrame}
	local queue = {root}
	local head = 1
	while head <= #queue do
		local part = queue[head]
		head += 1
		for _, edge in ipairs(edges[part] or {}) do
			if not frames[edge.Part] then
				frames[edge.Part] = frames[part] * edge.Relative
				table.insert(queue, edge.Part)
			end
		end
	end
	return frames
end

local function bindJointPosition(character, frames, partA, partB)
	-- The authored StarterCharacter uses AnimationConstraints; ordinary R15
	-- avatars may use Motor6Ds instead. Both expose their joint bind offsets.
	for _, joint in ipairs(character:GetDescendants()) do
		if joint:IsA("AnimationConstraint") then
			local attachment0, attachment1 = joint.Attachment0, joint.Attachment1
			if attachment0 and attachment1 then
				local parent0, parent1 = attachment0.Parent, attachment1.Parent
				if parent0 == partA and parent1 == partB then
					return (frames[partA] * attachment0.CFrame).Position
				elseif parent0 == partB and parent1 == partA then
					return (frames[partA] * attachment1.CFrame).Position
				end
			end
		elseif joint:IsA("Motor6D") then
			if joint.Part0 == partA and joint.Part1 == partB then
				return (frames[partA] * joint.C0).Position
			elseif joint.Part0 == partB and joint.Part1 == partA then
				return (frames[partA] * joint.C1).Position
			end
		end
	end
	return nil
end

local function alignDirections(from, to)
	if from.Magnitude < 0.001 or to.Magnitude < 0.001 then return nil end
	local fromUnit, toUnit = from.Unit, to.Unit
	local dot = math.clamp(fromUnit:Dot(toUnit), -1, 1)
	if dot > 0.99999 then return CFrame.identity end
	local axis = fromUnit:Cross(toUnit)
	if axis.Magnitude < 0.00001 then
		axis = fromUnit:Cross(Vector3.zAxis)
		if axis.Magnitude < 0.00001 then
			axis = fromUnit:Cross(Vector3.xAxis)
		end
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function correctedArmBind(character, parts, frames, byName)
	local corrected = {}
	for _, side in ipairs({"Left", "Right"}) do
		local upperPart = parts[side .. "UpperArm"]
		local lowerPart = parts[side .. "LowerArm"]
		local handPart = parts[side .. "Hand"]
		local upperBone = byName[side .. "Arm"]
		local lowerBone = byName[side .. "ForeArm"]
		local handBone = byName[side .. "Hand"]
		local shoulder = bindJointPosition(character, frames,
			parts.UpperTorso, upperPart)
		local elbow = bindJointPosition(character, frames,
			upperPart, lowerPart)
		local wrist = bindJointPosition(character, frames,
			lowerPart, handPart)
		if not shoulder or not elbow or not wrist then return nil end

		-- Meshy was imported in a horizontal T-pose, while the authored R15
		-- bind has arms at the sides. Match upper/lower limb directions once in
		-- bind space; the normal per-frame R15 deltas then preserve walks, idle,
		-- equipment actions and ragdoll without a separate Meshy AnimationId.
		local upperRest = upperBone.WorldCFrame
		local lowerRest = lowerBone.WorldCFrame
		local handRest = handBone.WorldCFrame
		local shoulderRotation = alignDirections(
			lowerRest.Position - upperRest.Position, elbow - shoulder)
		if not shoulderRotation then return nil end
		local upperPivot = upperRest.Position
		local shoulderTransform = CFrame.new(upperPivot)
			* shoulderRotation * CFrame.new(-upperPivot)
		local rotatedLower = shoulderTransform * lowerRest
		local lowerDirection = shoulderRotation:VectorToWorldSpace(
			handRest.Position - lowerRest.Position)
		local elbowRotation = alignDirections(lowerDirection, wrist - elbow)
		if not elbowRotation then return nil end
		local elbowPivot = rotatedLower.Position
		local elbowTransform = CFrame.new(elbowPivot)
			* elbowRotation * CFrame.new(-elbowPivot)
		corrected[upperBone] = shoulderTransform * upperRest
		corrected[lowerBone] = elbowTransform * rotatedLower
		corrected[handBone] = elbowTransform * shoulderTransform * handRest
	end
	return corrected
end

local function orderedBones(mesh)
	local byName = {}
	local total = 0
	for _, object in ipairs(mesh:GetDescendants()) do
		if object:IsA("Bone") then
			total += 1
			if not BONE_TO_PART[object.Name] or byName[object.Name] then
				return nil
			end
			byName[object.Name] = object
		end
	end
	if total ~= 22 then return nil end
	for name in pairs(BONE_TO_PART) do
		if not byName[name] then return nil end
	end
	local ordered = {}
	local function visit(bone)
		table.insert(ordered, bone)
		for _, child in ipairs(bone:GetChildren()) do
			if child:IsA("Bone") then visit(child) end
		end
	end
	for _, bone in pairs(byName) do
		if not bone.Parent:IsA("Bone") then visit(bone) end
	end
	if #ordered ~= 22 then return nil end
	return ordered
end

local function captureBody(character, originals)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and BODY_PARTS[child.Name] then
			if originals[child] == nil then originals[child] = child.Transparency end
			for _, descendant in ipairs(child:GetDescendants()) do
				if (descendant:IsA("Decal") or descendant:IsA("Texture"))
					and originals[descendant] == nil then
					originals[descendant] = descendant.Transparency
				end
			end
		end
	end
end

local function setVisible(state, visible)
	if state.Visible == visible then return end
	state.Visible = visible
	for object, original in pairs(state.Originals) do
		if object.Parent then
			object:SetAttribute(ORIGINAL_ATTRIBUTE, visible and original or nil)
			object.Transparency = visible and 1 or original
		end
	end
	for _, part in ipairs(state.VisualParts) do
		if part.Parent then part.Transparency = visible and 0 or 1 end
	end
end

local function clearState(player)
	local state = states[player]
	if not state then return end
	states[player] = nil
	if state.Motes then state.Motes.Parent:Destroy() end
	for object, original in pairs(state.Originals) do
		if object.Parent then
			object:SetAttribute(ORIGINAL_ATTRIBUTE, nil)
			object.Transparency = original
		end
	end
	for _, part in ipairs(state.VisualParts) do
		if part.Parent then
			part.Transparency = 1
			part.LocalTransparencyModifier = 0
		end
	end
	for _, record in ipairs(state.Bones) do
		if record.Bone.Parent then record.Bone.Transform = CFrame.identity end
	end
end

-- FALSE_SUN_MOTES_20260924 (Trello IRLeRBcN). A quiet halo of embers off the
-- False Sun topper only (Codex's art brief: assets/hazmat/developer-signal-
-- architect/README.md). Client-local on every viewer, so each honours its own
-- ReduceFlashing and nothing replicates. A ParticleEmitter lights no geometry;
-- LightInfluence 1 lets the motes dim with the scene instead of marking a
-- player in the dark. No Light instances, ever.
local function falseSunMotes(topperPart, character)
	local torso = character:FindFirstChild("UpperTorso")
	local back = torso and -torso.CFrame.LookVector or Vector3.zero
	-- How far the topper reaches along `back`, so the motes start just OUTSIDE
	-- its back face (inside, the closed mesh hides them).
	local c, half = topperPart.CFrame, topperPart.Size / 2
	local reach = math.abs(back:Dot(c.RightVector)) * half.X + math.abs(back:Dot(c.UpVector)) * half.Y
		+ math.abs(back:Dot(c.LookVector)) * half.Z
	local attachment = Instance.new("Attachment")
	attachment.Name = "ZyntraFalseSunMotes"
	-- World-up, just behind the window; the weld keeps it riding the torso.
	attachment.CFrame = c:ToObjectSpace(CFrame.new(topperPart.Position + back * (reach + 0.15)))
	local touch = UserInputService.TouchEnabled
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://128661548525607"
	emitter.Rate = touch and 1 or 2.5
	emitter.Lifetime = NumberRange.new(0.45, 0.75)
	emitter.Speed = NumberRange.new(0.12, 0.28)
	emitter.SpreadAngle = Vector2.new(16, 16)
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, touch and 0.10 or 0.12),
		NumberSequenceKeypoint.new(0.5, touch and 0.18 or 0.24), NumberSequenceKeypoint.new(1, 0)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, touch and 0.67 or 0.58),
		NumberSequenceKeypoint.new(0.5, touch and 0.55 or 0.42), NumberSequenceKeypoint.new(1, 1)})
	emitter.LightEmission = touch and 0.15 or 0.25
	emitter.LightInfluence = 1
	emitter.Enabled = false
	emitter.Parent = attachment
	attachment.Parent = topperPart
	return emitter
end

local function buildState(character, visual)
	local root = character:FindFirstChild("HumanoidRootPart")
	local mesh = visual:FindFirstChild("char1", true)
	if not root or not root:IsA("BasePart")
		or not mesh or not mesh:IsA("MeshPart") then return nil end
	local parts = sourceParts(character)
	local bones = orderedBones(mesh)
	if not parts or not bones then return nil end
	local visualParts = {mesh}
	if visual:GetAttribute("RequiresTopper") == true then
		local topper = visual:FindFirstChild("ZyntraPremiumTopper")
		if not topper then return nil end
		local topperCount = 0
		for _, object in ipairs(topper:GetDescendants()) do
			if object:IsA("BasePart") then
				topperCount += 1
				table.insert(visualParts, object)
			end
		end
		if topperCount ~= 1 then return nil end
	end
	local frames = restFrames(character, root)
	for _, part in pairs(parts) do
		if not frames[part] then return nil end
	end
	local byName = {}
	for _, bone in ipairs(bones) do byName[bone.Name] = bone end
	local armBind = correctedArmBind(character, parts, frames, byName)
	if not armBind then return nil end
	local records = {}
	for _, bone in ipairs(bones) do
		local part = parts[BONE_TO_PART[bone.Name]]
		table.insert(records, {
			Bone = bone, Part = part,
			BindOffset = frames[part]:ToObjectSpace(
				armBind[bone] or bone.WorldCFrame),
		})
	end
	local state = {
		Character = character, Visual = visual, Mesh = mesh,
		Bones = records, Originals = {}, Visible = false,
		VisualParts = visualParts, TargetByBone = {}, PoseFrames = 0,
		-- Built last, so a calibration that bails out above leaves nothing behind.
		Motes = visual:GetAttribute("SkinId") == "FalseSun" and visualParts[2]
			and falseSunMotes(visualParts[2], character) or nil,
	}
	captureBody(character, state.Originals)
	return state
end

local function pose(state)
	local targetByBone = state.TargetByBone
	for _, record in ipairs(state.Bones) do
		local bone = record.Bone
		local parent = bone.Parent
		local parentWorld = parent:IsA("Bone") and targetByBone[parent]
			or parent:IsA("BasePart") and parent.CFrame or nil
		if not parentWorld then error("unmapped cosmetic Bone parent") end
		local target = record.Part.CFrame * record.BindOffset
		bone.Transform = (parentWorld * bone.CFrame):ToObjectSpace(target)
		targetByBone[bone] = target
	end
end

local function reconcile()
	local seen = {}
	for _, player in ipairs(Players:GetPlayers()) do
		seen[player] = true
		local character = player.Character
		local visual = character and character:FindFirstChild(VISUAL_NAME)
		if player:GetAttribute("InRound") ~= true
			or workspace:GetAttribute("RoundActive") ~= true then
			visual = nil
		end
		local state = states[player]
		if state and (state.Character ~= character or state.Visual ~= visual
			or not state.Mesh.Parent) then
			clearState(player)
			state = nil
		end
		if visual and not state and not blockedVisuals[visual] then
			local ok, candidate = pcall(buildState, character, visual)
			if not ok then
				blockedVisuals[visual] = true
				warnOnce("build", "R15 bind calibration failed: " .. tostring(candidate))
			elseif candidate then
				states[player] = candidate
			end
		end
		state = states[player]
		if state then
			local previousCount = 0
			for _ in pairs(state.Originals) do previousCount += 1 end
			captureBody(state.Character, state.Originals)
			if state.Visible then
				local afterCount = 0
				for _ in pairs(state.Originals) do afterCount += 1 end
				if afterCount ~= previousCount then
					-- A late body part must not appear through the fitted suit.
					for object, original in pairs(state.Originals) do
						if object.Parent and object.Transparency ~= 1 then
							object:SetAttribute(ORIGINAL_ATTRIBUTE, original)
							object.Transparency = 1
						end
					end
				end
			end
		end
	end
	for player in pairs(states) do
		if not seen[player] then clearState(player) end
	end
end

local elapsed = RESCAN_INTERVAL
RunService:BindToRenderStep("ZyntraHazmatR15Retarget",
	Enum.RenderPriority.Character.Value + 1, function(deltaTime)
		elapsed += deltaTime
		if elapsed >= RESCAN_INTERVAL then
			elapsed = 0
			reconcile()
		end
		local camera = workspace.CurrentCamera
		for player, state in pairs(states) do
			if not state.Visual.Parent or player.Character ~= state.Character then
				clearState(player)
			else
				local ok, problem = pcall(pose, state)
				if not ok then
					blockedVisuals[state.Visual] = true
					warnOnce("pose", "R15 pose transfer failed: " .. tostring(problem))
					clearState(player)
				else
					-- Keep the native body visible for one extra frame so the
					-- renderer can consume the first Bone.Transform writes.
					state.PoseFrames += 1
					if state.PoseFrames >= 2 then setVisible(state, true) end
					local head = state.Character:FindFirstChild("Head")
					local nearHead = camera and head and head:IsA("BasePart")
						and (camera.CFrame.Position - head.Position).Magnitude < CAMERA_CLEARANCE
					for _, part in ipairs(state.VisualParts) do
						if part.Parent then
							part.LocalTransparencyModifier = nearHead and 1 or 0
						end
					end
					if state.Motes then
						-- Only on a shown suit, off the wearer's own face, not from
						-- under a Level 3 table, within 40 studs, and never for a
						-- viewer who asked for less flashing.
						state.Motes.Enabled = state.Visible and not nearHead
							and Players.LocalPlayer:GetAttribute("ReduceFlashing") ~= true
							and player:GetAttribute("Level3_Hiding") ~= true
							and camera ~= nil and head ~= nil
							and (camera.CFrame.Position - head.Position).Magnitude < 40
					end
				end
			end
		end
	end)
