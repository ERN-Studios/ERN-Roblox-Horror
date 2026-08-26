local TweenService = game:GetService("TweenService")

local PARTY_DURATION = 10
local STEP_DURATION = 0.75
local RESTORE_DURATION = 0.9

local PALETTE = {
	Color3.fromRGB(73, 245, 204), -- Zyntra cyan
	Color3.fromRGB(52, 153, 255), -- electric blue
	Color3.fromRGB(126, 83, 255), -- deep violet
	Color3.fromRGB(211, 78, 255), -- neon purple
	Color3.fromRGB(255, 75, 190), -- magenta
	Color3.fromRGB(255, 126, 38), -- neon orange
	Color3.fromRGB(91, 255, 139), -- acid green
}

local active = false
local boundPrompts = setmetatable({}, { __mode = "k" })

local function collectCeilingLights()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local lighting = lobby and lobby:FindFirstChild("TunnelLighting")
	local targets = {}
	if not lighting then
		return lobby, targets
	end

	for _, descendant in ipairs(lighting:GetDescendants()) do
		if descendant:IsA("BasePart")
			and (descendant:GetAttribute("PartyCeilingLight") == true or descendant.Name == "WarmTunnelLight") then
			table.insert(targets, descendant)
		end
	end
	table.sort(targets, function(a, b)
		if math.abs(a.Position.Z - b.Position.Z) > 0.01 then
			return a.Position.Z < b.Position.Z
		end
		return a.Position.X < b.Position.X
	end)
	return lobby, targets
end

local function tween(instance, duration, properties)
	if not instance or not instance.Parent then return end
	local animation = TweenService:Create(
		instance,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		properties
	)
	animation:Play()
end

local function realNow()
	return DateTime.now().UnixTimestampMillis / 1000
end

local function runParty(prompt)
	if active then return end
	active = true

	local endsAt = realNow() + PARTY_DURATION
	script:SetAttribute("PartyModeActive", true)
	script:SetAttribute("PartyModeEndsAt", endsAt)

	local saved = {}
	local savedByPart = setmetatable({}, { __mode = "k" })
	local savedButtons = {}
	local savedByButton = setmetatable({}, { __mode = "k" })
	local lobbiesSeen = setmetatable({}, { __mode = "k" })

	local function rememberLight(part)
		local item = savedByPart[part]
		if item then return item end
		local light = part:FindFirstChildWhichIsA("Light")
		item = {
			part = part,
			partColor = part.Color,
			light = light,
			lightColor = light and light.Color or nil,
			brightness = light and light.Brightness or nil,
		}
		savedByPart[part] = item
		table.insert(saved, item)
		return item
	end

	local function rememberButton(button)
		local item = savedByButton[button]
		if item then return item end
		local glow = button:FindFirstChild("ButtonGlow")
		item = {
			button = button,
			color = button.Color,
			glow = glow,
			glowColor = glow and glow:IsA("Light") and glow.Color or nil,
		}
		savedByButton[button] = item
		table.insert(savedButtons, item)
		return item
	end

	local function setCurrentPrompts(enabled, partyColor, duration)
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") and descendant.Name == "ZyntraPartyPrompt" then
				descendant.Enabled = enabled
				local button = descendant.Parent
				if button and button:IsA("BasePart") then
					local item = rememberButton(button)
					button:SetAttribute("PartyModeActive", not enabled)
					if partyColor then
						tween(button, duration, { Color = partyColor })
						if item.glow and item.glow:IsA("Light") then
							tween(item.glow, duration, { Color = partyColor })
						end
					end
				end
			end
		end
	end

	setCurrentPrompts(false)
	local step = 0
	local nextStepAt = realNow()
	local foundAnyLights = false

	while realNow() < endsAt do
		local now = realNow()
		local lobby, parts = collectCeilingLights()
		if lobby then
			lobbiesSeen[lobby] = true
			lobby:SetAttribute("PartyModeActive", true)
			lobby:SetAttribute("PartyModeEndsAt", endsAt)
		end

		if now >= nextStepAt then
			local duration = math.min(STEP_DURATION, math.max(0.1, endsAt - now))
			for index, part in ipairs(parts) do
				foundAnyLights = true
				local item = rememberLight(part)
				local phase = math.floor((index - 1) / 4)
				local color = PALETTE[((step + phase) % #PALETTE) + 1]
				tween(item.part, duration, { Color = color })
				if item.light then
					tween(item.light, duration, {
						Color = color,
						Brightness = math.max(item.brightness or 0, 1.55),
					})
				end
			end
			local buttonColor = PALETTE[(step % #PALETTE) + 1]
			setCurrentPrompts(false, buttonColor, duration)
			step += 1
			nextStepAt = now + STEP_DURATION
		end
		task.wait(0.05)
	end

	if not foundAnyLights then
		warn("[LobbyPartyMode] No tunnel ceiling lights were available")
	end

	-- Include any fixtures created during the final transition, then restore
	-- every surviving generation to its exact original appearance.
	local finalLobby, finalParts = collectCeilingLights()
	if finalLobby then lobbiesSeen[finalLobby] = true end
	for _, part in ipairs(finalParts) do rememberLight(part) end

	for _, item in ipairs(saved) do
		tween(item.part, RESTORE_DURATION, { Color = item.partColor })
		if item.light then
			tween(item.light, RESTORE_DURATION, {
				Color = item.lightColor,
				Brightness = item.brightness,
			})
		end
	end
	for _, item in ipairs(savedButtons) do
		tween(item.button, RESTORE_DURATION, { Color = item.color })
		if item.glow and item.glow:IsA("Light") and item.glowColor then
			tween(item.glow, RESTORE_DURATION, { Color = item.glowColor })
		end
	end
	task.wait(RESTORE_DURATION)

	for _, item in ipairs(saved) do
		if item.part.Parent then item.part.Color = item.partColor end
		if item.light and item.light.Parent then
			item.light.Color = item.lightColor
			item.light.Brightness = item.brightness
		end
	end
	for _, item in ipairs(savedButtons) do
		if item.button.Parent then
			item.button.Color = item.color
			item.button:SetAttribute("PartyModeActive", false)
		end
		if item.glow and item.glow.Parent and item.glowColor then item.glow.Color = item.glowColor end
	end
	for lobby in pairs(lobbiesSeen) do
		if lobby.Parent then
			lobby:SetAttribute("PartyModeActive", false)
			lobby:SetAttribute("PartyModeEndsAt", nil)
		end
	end
	setCurrentPrompts(true)
	script:SetAttribute("PartyModeActive", false)
	script:SetAttribute("PartyModeEndsAt", nil)
	active = false
end

local function bindPrompt(instance)
	if not instance:IsA("ProximityPrompt")
		or instance.Name ~= "ZyntraPartyPrompt"
		or boundPrompts[instance] then
		return
	end
	boundPrompts[instance] = true
	if active then instance.Enabled = false end
	instance.Triggered:Connect(function()
		task.spawn(runParty, instance)
	end)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	bindPrompt(descendant)
end
workspace.DescendantAdded:Connect(bindPrompt)
