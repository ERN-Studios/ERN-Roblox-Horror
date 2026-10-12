-- Lobby Mall Client (2026-10-13, owner requests). MALL_FINISH_20261013.
--   What a player's own client adds to the mall lobby (Workspace.LobbyMallPreview), none of it replicated:
--   LEVEL SIGNS  a sign over every shop front, seen through walls ("LEVEL 1 / OFFICE" ...), in the game's UI style
--                (ShopBinder's palette: tile, line, rail teal, cream; Montserrat and Roboto Mono). They stand down
--                in a round and outside the mall.
--   CRATES       the product crates over the shop's buy rings bob gently, each out of step with the next
--                (LobbyShopDisplay gives every crate its resting pose and phase).
--   DYING LAMPS  the ceiling panels the importer marked `Flicker` stutter like a fluorescent tube on its way out.
--   A player who asked for less flashing (ReduceFlashing, on until they switch it off) gets steady dim lamps and
--   still crates. Nothing here runs while the player is in a round or away from the mall.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local TILE, LINE, TEAL, CREAM = Color3.fromRGB(22, 29, 32), Color3.fromRGB(38, 49, 52), Color3.fromRGB(68, 221, 196), Color3.fromRGB(242, 235, 219)
local TITLE = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local LENS_ON, LENS_OFF = Color3.fromRGB(246, 240, 214), Color3.fromRGB(120, 118, 108)

local function levelSign(host)
	local stale = host:FindFirstChild("MallLevelSign")
	if stale then stale:Destroy() end
	local gui = Instance.new("BillboardGui")
	gui.Name = "MallLevelSign"
	gui.Adornee, gui.AlwaysOnTop, gui.LightInfluence, gui.ResetOnSpawn = host, true, 0, false
	gui.Size, gui.MaxDistance, gui.ClipsDescendants = UDim2.fromOffset(150, 50), 420, false
	local plate = Instance.new("Frame")
	plate.Size, plate.BackgroundColor3, plate.BackgroundTransparency, plate.BorderSizePixel = UDim2.fromScale(1, 1), TILE, 0.08, 0
	Instance.new("UICorner", plate).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = LINE, 2
	stroke.Parent = plate
	local bar = Instance.new("Frame")
	bar.Position, bar.Size, bar.BackgroundColor3, bar.BorderSizePixel = UDim2.fromOffset(10, 10), UDim2.new(0, 4, 1, -20), TEAL, 0
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	bar.Parent = plate
	local function line(text, y, size, font, colour)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency, label.Position, label.Size = 1, UDim2.fromOffset(22, y), UDim2.new(1, -30, 0, size + 4)
		label.FontFace, label.TextSize, label.TextColor3, label.Text = font, size, colour, text
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = plate
	end
	line("LEVEL " .. tostring(host:GetAttribute("LevelNumber")), 6, 21, TITLE, CREAM)
	line(tostring(host:GetAttribute("LevelName") or ""), 30, 11, MONO, TEAL)
	plate.Parent = gui
	gui.Parent = host                   -- on the host itself (this client's copy of it): nothing is replicated
	return gui
end

local mall, crates, lamps, made = nil, {}, {}, {}
local function bind(model)
	mall = model
	table.clear(crates); table.clear(lamps)
	for _, gui in pairs(made) do gui:Destroy() end
	table.clear(made)
	if not mall then return end
	local anchors = mall:FindFirstChild("Anchors")
	local markers = anchors and anchors:FindFirstChild("LevelMarkers")
	for _, host in ipairs(markers and markers:GetChildren() or {}) do
		if host:IsA("BasePart") then made[host] = levelSign(host) end
	end
	local box = anchors and anchors:FindFirstChild("ShopCrates")
	for _, crate in ipairs(box and box:GetChildren() or {}) do
		if crate:IsA("BasePart") and typeof(crate:GetAttribute("MallCrateOrigin")) == "CFrame" then
			table.insert(crates, {part = crate, origin = crate:GetAttribute("MallCrateOrigin"), phase = tonumber(crate:GetAttribute("MallCratePhase")) or 0})
		end
	end
	local lights, ceiling = mall:FindFirstChild("Lights"), mall:FindFirstChild("Parts") and mall.Parts:FindFirstChild("Ceiling")
	for _, host in ipairs(lights and lights:GetChildren() or {}) do
		local light = host:GetAttribute("Flicker") == true and host:FindFirstChildWhichIsA("Light")
		if light then
			table.insert(lamps, {light = light, bright = light.Brightness, lens = ceiling and ceiling:FindFirstChild(tostring(host:GetAttribute("Lens"))),
				on = true, next = 0, burst = 0})
		end
	end
end

local random = Random.new()
local function setLamp(lamp, level)                    -- 1 lit, 0 out, between for a tube that will not quite strike
	lamp.light.Brightness = lamp.bright * level
	if lamp.lens then
		lamp.lens.Material = level > 0.15 and Enum.Material.Neon or Enum.Material.SmoothPlastic
		lamp.lens.Color = LENS_OFF:Lerp(LENS_ON, level)
	end
end

local scanned, elapsed, still = 0, 0, false
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	scanned += dt
	if scanned > 2 or (mall and not mall.Parent) then
		scanned = 0
		local now = workspace:FindFirstChild("LobbyMallPreview")
		-- the model streams in piece by piece: bind again while what it should hold is still arriving
		local anchors = now and now:FindFirstChild("Anchors")
		local count = anchors and (#(anchors:FindFirstChild("ShopCrates") and anchors.ShopCrates:GetChildren() or {})
			+ #(anchors:FindFirstChild("LevelMarkers") and anchors.LevelMarkers:GetChildren() or {})
			+ #(now:FindFirstChild("Lights") and now.Lights:GetChildren() or {})) or 0
		if now ~= mall or count ~= (mall and mall:GetAttribute("ClientBound")) then
			bind(now)
			if now then now:SetAttribute("ClientBound", count) end
		end
	end
	if not mall then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local low, high = mall:GetAttribute("BoundsMin"), mall:GetAttribute("BoundsMax")
	local here = root ~= nil and player:GetAttribute("InRound") ~= true and typeof(low) == "Vector3" and typeof(high) == "Vector3"
		and root.Position.X > low.X - 40 and root.Position.X < high.X + 40 and root.Position.Z > low.Z - 40 and root.Position.Z < high.Z + 40
		and root.Position.Y > low.Y - 20 and root.Position.Y < high.Y + 20
	for _, gui in pairs(made) do
		if gui.Enabled ~= here then gui.Enabled = here end
	end
	if not here then return end
	local calm = player:GetAttribute("ReduceFlashing") ~= false
	if calm ~= still then
		still = calm
		for _, crate in ipairs(crates) do if crate.part.Parent then crate.part.CFrame = crate.origin end end
		for _, lamp in ipairs(lamps) do if lamp.light.Parent then setLamp(lamp, 0.45) end end
	end
	if calm then return end
	for _, crate in ipairs(crates) do
		if crate.part.Parent then
			crate.part.CFrame = crate.origin + Vector3.new(0, 0.32 * math.sin(elapsed * 1.7 + crate.phase), 0)
		end
	end
	-- a dying tube: mostly lit and a little weak, then a burst of quick stutters, now and then out for a second or two
	for _, lamp in ipairs(lamps) do
		if lamp.light.Parent and elapsed >= lamp.next then
			if lamp.burst > 0 then
				lamp.burst -= 1
				lamp.on = not lamp.on
				setLamp(lamp, lamp.on and random:NextNumber(0.55, 1) or random:NextNumber(0, 0.12))
				lamp.next = elapsed + random:NextNumber(0.03, 0.16)
			else
				local roll = random:NextNumber()
				if roll < 0.55 then
					lamp.burst = random:NextInteger(3, 11)
					lamp.next = elapsed
				elseif roll < 0.72 then
					lamp.on = false
					setLamp(lamp, 0)
					lamp.next = elapsed + random:NextNumber(0.8, 2.6)
				else
					lamp.on = true
					setLamp(lamp, random:NextNumber(0.8, 1))
					lamp.next = elapsed + random:NextNumber(1.2, 5.5)
				end
			end
		end
	end
end)
