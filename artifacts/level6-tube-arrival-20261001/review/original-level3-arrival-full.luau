local function makeArrivalElevator(parent: Instance, room: {[string]: any}): (Model, BasePart, BasePart)
	local p = worldPosition(room)
	local visual = Instance.new("Model")
	visual.Name = "Level 2 Exit Slide Continuation"
	visual.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	visual:SetAttribute("Level3_Level2ExitTube", true)
	visual:SetAttribute("Level3_ProgressionLandmark", true)
	visual.Parent = parent

	-- LEVEL2_EXIT_TRANSITION_20260828
	-- This is the far end of Level 2's exit flume, not a decorative stub. A
	-- player who chose to continue resumes near the REAR of this bore, still
	-- moving, and physically slides the rest of the way out into the mall. That
	-- requires a real run: enough length for the arrival to read as the tail of
	-- one long ride, and enough rise that the resume point is genuinely downhill.
	-- The bore still finishes level with the landing-room floor so the outlet is
	-- a slide mouth rather than a drop.
	local tubeLength, rise, radius = 400, 115, 8
	local shellThickness, runoutThickness = .30 * 1.5, .60 * 1.5
	local shellRadius = radius + (shellThickness - .30) * .5
	visual:SetAttribute("Level3_SlideBoreRadius", radius)
	visual:SetAttribute("Level3_SlideWallThickness", shellThickness)
	-- A longer run leaves room for six riders, spaced uphill before the rear cap.
	-- The gentle curve still uses 32 sections (panels shorter than 14.6 studs) and the
	-- same 20-sided bore, preserving the existing shell/collision part budget.
	local pathSections, shellSegments = 32, 20
	local wallX = p.X - room.W * .5
	local mouthX = wallX + Configuration.WallThickness * .5 + .12
	local centerY = p.Y + radius + .05
	visual:SetAttribute("Level3_SlideMouthPosition", Vector3.new(mouthX, centerY, p.Z))
	visual:SetAttribute("Level3_DirectMallArrival", true)
	local signPosition = Vector3.new(mouthX + .16, centerY + radius + 2.3, p.Z)
	local arrivalSign = part(visual, "Arrival Only Sign",
		CFrame.lookAt(signPosition, signPosition + Vector3.xAxis),
		Vector3.new(14, 3.6, .2), Color3.fromRGB(223, 197, 115), Enum.Material.SmoothPlastic)
	decorative(arrivalSign)
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "Arrival Only Notice"
	signGui.Face = Enum.NormalId.Front
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	signGui.CanvasSize = Vector2.new(840, 216)
	signGui.LightInfluence = .15
	signGui.AlwaysOnTop = false
	signGui.Parent = arrivalSign
	local signTitle = Instance.new("TextLabel")
	signTitle.Name = "NoExit"
	signTitle.BackgroundTransparency = 1
	signTitle.Size = UDim2.new(1, 0, .62, 0)
	signTitle.Font = Enum.Font.GothamBold
	signTitle.TextSize = 78
	signTitle.TextColor3 = Color3.fromRGB(37, 33, 23)
	signTitle.Text = "NO EXIT"
	signTitle.Parent = signGui
	local signDetail = Instance.new("TextLabel")
	signDetail.Name = "ArrivalOnly"
	signDetail.BackgroundTransparency = 1
	signDetail.Position = UDim2.new(0, 0, .62, 0)
	signDetail.Size = UDim2.new(1, 0, .3, 0)
	signDetail.Font = Enum.Font.GothamMedium
	signDetail.TextSize = 36
	signDetail.TextColor3 = signTitle.TextColor3
	signDetail.Text = "ONE-WAY ARRIVAL"
	signDetail.Parent = signGui
	local shellColor = Color3.fromRGB(218, 226, 211)
	local shellShadow = Color3.fromRGB(193, 207, 197)
	local slipperyPhysics = PhysicalProperties.new(.7, .02, 0, 100, 1)
	local pathPoints: {Vector3} = {}
	for section = 0, pathSections do
		local alpha = section / pathSections
		table.insert(pathPoints, Vector3.new(
			mouthX - tubeLength * alpha,
			centerY + rise * alpha * alpha,
			p.Z
		))
	end
	for section = 1, pathSections do
		local a, b = pathPoints[section], pathPoints[section + 1]
		local segmentAxis = (b - a).Unit
		local segmentCenter = (a + b) * .5
		local segmentLength = (b - a).Magnitude
		local radialZero = Vector3.zAxis
		for shellIndex = 0, shellSegments - 1 do
			local angle = (shellIndex + .5) / shellSegments * math.pi * 2
			local radial = CFrame.fromAxisAngle(segmentAxis, angle)
				:VectorToWorldSpace(radialZero).Unit
			local tangent = segmentAxis:Cross(radial).Unit
			local panel = part(visual, "Level 2 Exit Slide Fiberglass Shell",
				CFrame.fromMatrix(segmentCenter + radial * shellRadius, segmentAxis, radial, tangent),
				Vector3.new(segmentLength + 1, shellThickness,
					2 * shellRadius * math.tan(math.pi / shellSegments) + .06),
				shellColor, Enum.Material.SmoothPlastic)
			panel.CanCollide = true
			panel.CanTouch = false
			panel.CastShadow = false
			panel.Reflectance = .025
			panel.CustomPhysicalProperties = slipperyPhysics
			panel:SetAttribute("Level3_ProgressionSlide", true)
		end

		local downSeed = -Vector3.yAxis
		local radialDown = (downSeed - segmentAxis * downSeed:Dot(segmentAxis)).Unit
		local floorTangent = segmentAxis:Cross(radialDown).Unit
		local runout = part(visual, "Level 2 Exit Slide Runout",
			CFrame.fromMatrix(segmentCenter + radialDown * (radius + runoutThickness * .5),
				segmentAxis, radialDown, floorTangent),
			Vector3.new(segmentLength + 1, runoutThickness, 11.8),
			shellShadow, Enum.Material.SmoothPlastic)
		runout.CanCollide = true
		runout.CastShadow = false
		runout.Reflectance = .02
		runout.CustomPhysicalProperties = slipperyPhysics
		runout:SetAttribute("Level3_ProgressionSlide", true)
		-- Keep the mouth visually clean; the wear rails begin one section inside.
		if section > 1 then
			for _, zOffset in ipairs({-3.7, 3.7}) do
				local guide = part(visual, "Level 2 Exit Slide Wear Guide",
					CFrame.fromMatrix(segmentCenter + radialDown * (radius - .10)
						+ floorTangent * zOffset, segmentAxis, radialDown, floorTangent),
					Vector3.new(segmentLength + .10, .10, .30),
					Color3.fromRGB(71, 88, 85), Enum.Material.SmoothPlastic, .05)
				decorative(guide)
			end
		end
	end
	visual:SetAttribute("Level3_SlideCollisionPartCount", pathSections * (shellSegments + 1))
	visual:SetAttribute("Level3_SlideRise", rise)
	visual:SetAttribute("Level3_SlideSlipback", true)
	visual:SetAttribute("Level3_SlideLength", tubeLength)

	-- The resume frame: where a continuing Level 2 rider re-enters the world.
	-- It leaves room uphill for the remaining five riders, all on the bore axis,
	-- with tangents pointing down toward the mall. GameManager places the
	-- character here and gives it this velocity, so the ride continues instead
	-- of restarting as a stand-up spawn somewhere else.
	local RESUME_ALPHA = .80
	local RESUME_SPEED = 62
	local resumePosition = Vector3.new(
		mouthX - tubeLength * RESUME_ALPHA,
		centerY + rise * RESUME_ALPHA * RESUME_ALPHA,
		p.Z)
	-- Direction of TRAVEL, which is -d/dalpha: the path is
	-- x = mouthX - tubeLength*alpha, so riding toward the mouth means alpha
	-- decreasing and x increasing. Negating only the Y term (as an earlier
	-- version did) points the rider back up the bore; the slip loop then
	-- silently corrected their velocity while they faced the wrong way.
	local resumeTangent = Vector3.new(tubeLength, -2 * rise * RESUME_ALPHA, 0).Unit
	visual:SetAttribute("Level3_SlideResumePosition", resumePosition)
	visual:SetAttribute("Level3_SlideResumeTangent", resumeTangent)
	visual:SetAttribute("Level3_SlideResumeVelocity", resumeTangent * RESUME_SPEED)
	visual:SetAttribute("Level3_SlideResumeSpeed", RESUME_SPEED)
	local rearPoint = pathPoints[#pathPoints]
	local rearAxis = (rearPoint - pathPoints[#pathPoints - 1]).Unit

	-- Match the twenty flat shell panels, not a stepped approximation of a circle.
	-- Each band is a rectangle plus a wedge: a continuous plaster face with the
	-- same forty-part budget. Its inner edge meets the middle of the fiberglass.
	-- Project the first tube segment onto the wall so its slight rise cannot
	-- expose a seam. Across the wall depth the edge stays within the .30 shell.
	local sealSlope = (pathPoints[2].Y - pathPoints[1].Y)
		/ (pathPoints[1].X - pathPoints[2].X)
	local sealYScale = math.sqrt(1 + sealSlope * sealSlope)
	local sealCenter = Vector3.new(wallX, centerY + (mouthX - wallX) * sealSlope, p.Z)
	local sealVertexRadius = radius / math.cos(math.pi / shellSegments)
	local sealOuterZ = radius + .30
	local sealDepth = Configuration.WallThickness + .02
	for bandIndex = 0, shellSegments / 2 - 1 do
		local angle0 = -math.pi * .5 + bandIndex * math.pi * 2 / shellSegments
		local angle1 = angle0 + math.pi * 2 / shellSegments
		local y0 = math.sin(angle0) * sealVertexRadius * sealYScale
		local y1 = math.sin(angle1) * sealVertexRadius * sealYScale
		local z0 = math.cos(angle0) * sealVertexRadius
		local z1 = math.cos(angle1) * sealVertexRadius
		local outerEdge = math.max(z0, z1)
		local wedgeUp = Vector3.yAxis * (if z1 > z0 then 1 else -1)
		for _, side in ipairs({-1, 1}) do
			local sideName = side < 0 and "Left" or "Right"
			local fill = Instance.new("Part")
			fill.Name = "Level 3 West Wall Circular Aperture Fill " .. sideName
			fill.CFrame = CFrame.new(sealCenter
				+ Vector3.new(0, (y0 + y1) * .5, side * (outerEdge + sealOuterZ) * .5))
			fill.Size = Vector3.new(sealDepth, y1 - y0, sealOuterZ - outerEdge)
			local wedge = Instance.new("WedgePart")
			wedge.Name = "Level 3 West Wall Circular Aperture Wedge " .. sideName
			local wedgeBack = Vector3.zAxis * side
			wedge.CFrame = CFrame.fromMatrix(sealCenter
				+ Vector3.new(0, (y0 + y1) * .5, side * (z0 + z1) * .5),
				wedgeUp:Cross(wedgeBack), wedgeUp, wedgeBack)
			wedge.Size = Vector3.new(sealDepth, y1 - y0, math.abs(z1 - z0))
			for _, seal in ipairs({fill, wedge}) do
				seal.Anchored = true
				seal.Color = wallColor(room)
				seal.Material = Enum.Material.Plaster
				seal.TopSurface = Enum.SurfaceType.Smooth
				seal.BottomSurface = Enum.SurfaceType.Smooth
				decorative(seal)
				seal:SetAttribute("Level3_TransitionWallSeal", true)
				seal.Parent = visual
			end
		end
	end

	-- The physical safety stop sits far beyond the upward bend. A muted pale
	-- shadow cap prevents outdoor sky from leaking through without reading as a portal.
	local rearUp = (Vector3.yAxis - rearAxis * Vector3.yAxis:Dot(rearAxis)).Unit
	local rearTangent = rearAxis:Cross(rearUp).Unit
	local field = part(visual, "One Way Pool Exit Field",
		CFrame.fromMatrix(rearPoint, rearAxis, rearUp, rearTangent),
		Vector3.new(.42, 14.8, 14.8),
		Color3.fromRGB(142, 153, 147), Enum.Material.SmoothPlastic, .02)
	field.CanCollide = true
	field.CastShadow = true
	field:SetAttribute("Level3_ReturnPathSealed", true)

	local mouthLightAnchor = part(visual, "Poolrooms Slide Mouth Light Anchor",
		CFrame.new(mouthX + 1.2, centerY + 1.0, p.Z),
		Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(mouthLightAnchor)
	local mouthGlow = Instance.new("PointLight")
	mouthGlow.Name = "Poolrooms Slide Mouth Fill"
	mouthGlow.Color = Color3.fromRGB(226, 235, 214)
	mouthGlow.Brightness = .82
	mouthGlow.Range = 30
	mouthGlow.Shadows = false
	mouthGlow.Parent = mouthLightAnchor

	local depthLightAnchor = part(visual, "Poolrooms Slide Depth Light Anchor",
		CFrame.new(pathPoints[math.floor(#pathPoints * .56)]),
		Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(depthLightAnchor)
	local depthGlow = Instance.new("PointLight")
	depthGlow.Name = "Poolrooms Slide Indirect Depth Fill"
	depthGlow.Color = Color3.fromRGB(194, 210, 201)
	depthGlow.Brightness = .48
	depthGlow.Range = 38
	depthGlow.Shadows = false
	depthGlow.Parent = depthLightAnchor

	-- Low-friction parts communicate the material; this lightweight server loop
	-- makes the one-way behavior deterministic for every avatar controller.
	-- Fast enough to read as the tail of a long slide; slow enough that the
	-- arrival into the mall is survivable and controllable.
	local SLIDE_MINIMUM_SPEED = 48
	local riders = setmetatable({}, {__mode = "k"})
	local slipAccumulator = 0
	local slipConnection: RBXScriptConnection?
	slipConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not visual:IsDescendantOf(workspace) then
			if slipConnection then slipConnection:Disconnect() end
			-- The world can be torn down with a rider still in the bore. Release
			-- every PlatformStand this loop set, or that player stays a ragdoll
			-- for the rest of their session.
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and character:GetAttribute("Level3_ProgressionSliding") == true then
					humanoid.PlatformStand = false
					character:SetAttribute("Level3_ProgressionSliding", nil)
				end
			end
			return
		end
		slipAccumulator += deltaTime
		if slipAccumulator < .08 then return end
		slipAccumulator = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				if player:GetAttribute("InRound") == true and workspace:GetAttribute("SelectedLevel") == 3 then
					riders[character] = SlideSafety.Apply(visual, character, riders[character], true) or nil
				end
				local alpha = (mouthX - root.Position.X) / tubeLength
				local pathY = centerY + rise * alpha * alpha
				local insideBore = alpha > .025 and alpha < .99
					and math.abs(root.Position.Z - p.Z) < radius - .8
					and math.abs(root.Position.Y - pathY) < radius + 2
				if insideBore then
					-- LEVEL2_EXIT_TRANSITION_20260828
					-- This is the tail of Level 2's flume, so it has to ride like
					-- one. PlatformStand takes the humanoid controller out of the
					-- way: without it the character stays in Running, resists the
					-- imposed velocity and WALKS the bore at about 16 studs/s,
					-- which reads as a corridor rather than the end of a slide.
					if not humanoid.PlatformStand then
						humanoid.PlatformStand = true
						character:SetAttribute("Level3_ProgressionSliding", true)
					end
					-- Push along the live path tangent rather than world +X, so
					-- the steep rear section drives the rider forward instead of
					-- straight down into the shell.
					local tangent = Vector3.new(tubeLength, -2 * rise * alpha, 0).Unit
					-- The shared slide controller owns production client physics and
					-- releases the actual body joints. Keep this velocity write only as
					-- a server fallback until its replicated ragdoll session is live.
					if character:GetAttribute("Level2_RagdollServerActive") ~= true then
						local velocity = root.AssemblyLinearVelocity
						local along = velocity:Dot(tangent)
						local lateral = velocity - tangent * along
						root.AssemblyLinearVelocity = tangent * math.max(along, SLIDE_MINIMUM_SPEED)
							+ lateral * .35
					end
				elseif character:GetAttribute("Level3_ProgressionSliding") == true then
					-- Out of the bore: hand control straight back. Leaving
					-- PlatformStand set would drop the arriving player onto the
					-- mall floor as an inert ragdoll.
					-- If the shared ragdoll service is still live, let its client End
					-- restore joints and humanoid state atomically instead of racing it.
					if character:GetAttribute("Level2_RagdollServerActive") ~= true then
						humanoid.PlatformStand = false
						character:SetAttribute("Level3_ProgressionSliding", nil)
					end
				end
			end
		end
	end)

	-- Invisible compatibility elevator retained for GameManager choreography.
	local model = Instance.new("Model")
	model.Name = "Elevator"
	model.Parent = workspace
	local compatibilityCF = CFrame.new(rearPoint)
	local doorL = part(model, "DoorL", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	local doorR = part(model, "DoorR", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(doorL)
	decorative(doorR)
	model.PrimaryPart = doorL

	-- Twenty-six studs of reveal distance frame the clean tube mouth on narrow
	-- mobile screens while the forward vector still leads naturally into Level 3.
	local spawnPosition = p + Vector3.new(-room.W * .5 + 26, .25, 0)
	local spawnCF = CFrame.lookAt(spawnPosition, p + Vector3.new(2, .25, 0))
	local spawn = part(parent, "ElevatorSpawn", spawnCF, Vector3.new(10, .5, 10),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	spawn.CanCollide = true
	spawn:SetAttribute("Level3_CompatibilityMarker", true)
	spawn.Parent = workspace
	local mazeStart = part(parent, "MazeStart", spawn.CFrame, Vector3.new(2, .3, 2),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	mazeStart.CanCollide = false
	mazeStart:SetAttribute("Level3_CompatibilityMarker", true)
	mazeStart.Parent = workspace
	model:SetAttribute("Level3_CompatibilityMarker", true)
	return model, spawn, mazeStart
end
