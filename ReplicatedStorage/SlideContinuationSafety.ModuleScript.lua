-- Shared by server and owning client. Keeps fast ragdolls within the authored
-- continuation bore and refuses streaming readiness for a partially loaded tube.
local Safety = {}
local function geometry(model)
	if not model or not model.Parent then return nil end
	local mouth, length, rise = model:GetAttribute("Level3_SlideMouthPosition"),
		model:GetAttribute("Level3_SlideLength"), model:GetAttribute("Level3_SlideRise")
	local radius = model:GetAttribute("Level3_SlideBoreRadius")
	if typeof(mouth) ~= "Vector3" or type(length) ~= "number" or length <= 0
		or type(rise) ~= "number" or type(radius) ~= "number" or radius <= 2 then return nil end
	return mouth, length, rise, radius
end

function Safety.Resolve(model, position, engaged)
	local mouth, length, rise, radius = geometry(model)
	if not mouth then return nil, nil, false end
	local alpha = (mouth.X - position.X) / length
	-- The mouth is a real exit. Never pull a player back once they reach it.
	if alpha <= .025 or alpha >= .985 then return nil, nil, false end
	local pathY = mouth.Y + rise * alpha * alpha
	local tangent = Vector3.new(length, -2 * rise * alpha, 0).Unit
	local dy, dz = position.Y - pathY, position.Z - mouth.Z
	local radialDistance = Vector2.new(dy * tangent.X, dz).Magnitude
	if radialDistance > (engaged and 64 or radius) then return nil, nil, false end
	local margin = radius - 2.2
	if radialDistance <= margin then return nil, tangent, true end
	local scale = margin / radialDistance
	return Vector3.new(position.X, pathY + dy * scale, mouth.Z + dz * scale), tangent, true
end

function Safety.Apply(model, character, engaged, serverFallback)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return false end
	local corrected, tangent, riding = Safety.Resolve(model, root.Position, engaged)
	-- The owner corrects its own simulation. Server corrections against a stale
	-- replicated pose otherwise drag a moving client back to the same segment.
	if serverFallback and root:GetNetworkOwner() ~= nil then return riding end
	if corrected and not root.Anchored then
		character:PivotTo(character:GetPivot() + corrected - root.Position)
		root.AssemblyLinearVelocity = tangent * math.clamp(root.AssemblyLinearVelocity:Dot(tangent), 48, 90)
		root.AssemblyAngularVelocity = Vector3.zero
		character:SetAttribute("Level3_SlideContainmentCorrections",
			(character:GetAttribute("Level3_SlideContainmentCorrections") or 0) + 1)
	end
	return riding
end

function Safety.Ready(model, position)
	local mouth, length, rise = geometry(model)
	if not mouth then return false end
	local expected = model:GetAttribute("Level3_SlideCollisionPartCount")
	if type(expected) ~= "number" or expected <= 0 then return false end
	local count = 0
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") and object.CanCollide
			and object:GetAttribute("Level3_ProgressionSlide") == true then count += 1 end
	end
	if count ~= expected then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {model}
	params.RespectCanCollide = true
	for _, offset in ipairs({-12, 0, 12}) do
		local x = position.X + offset
		local alpha = (mouth.X - x) / length
		local center = Vector3.new(x, mouth.Y + rise * alpha * alpha, mouth.Z)
		local floor = workspace:Raycast(center, -Vector3.yAxis * 18, params)
		if not floor or floor.Normal.Y < .5
			or floor.Instance:GetAttribute("Level3_ProgressionSlide") ~= true then return false end
	end
	return true
end
return table.freeze(Safety)
