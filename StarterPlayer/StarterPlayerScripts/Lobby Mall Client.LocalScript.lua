-- Lobby Mall Client (2026-10-13, owner requests). MALL_FINISH_20261013.
--   What a player's own client adds to the mall lobby (Workspace.LobbyMallPreview), none of it replicated:
--   (The level signs seen through walls that this script first drew were removed on the owner's word, 2026-10-13.)
--   CRATES       the product crates over the shop's buy rings bob gently, each out of step with the next
--                (LobbyShopDisplay gives every crate its resting pose and phase).
--   RECORDS      the two discs on the DJ console turn.
--   DYING LAMPS  the ceiling panels the importer marked `Flicker` stutter like a fluorescent tube on its way out.
--   A player who asked for less flashing (ReduceFlashing, on until they switch it off) gets steady dim lamps and
--   still crates. Nothing here runs while the player is in a round or away from the mall.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local LENS_ON, LENS_OFF = Color3.fromRGB(246, 240, 214), Color3.fromRGB(120, 118, 108)
-- cool and low, so that the lanterns' orange is the warm thing in the room (a first try with warm panels turned
-- the whole hall amber and the lanterns disappeared in it)
local DUSK_PANEL, DUSK_SHEEN = 0.3, 0.25
local DUSK_LIGHT, DUSK_LENS = Color3.fromRGB(196, 200, 236), Color3.fromRGB(150, 152, 178)

local mall, crates, lamps, discs, suits = nil, {}, {}, {}, {}
local SUIT_TURN = math.rad(360 / 26)             -- one turn in 26 seconds
local function bind(model)
	mall = model
	table.clear(crates); table.clear(lamps); table.clear(discs); table.clear(suits)
	if not mall then return end
	local anchors = mall:FindFirstChild("Anchors")
	local box = anchors and anchors:FindFirstChild("ShopCrates")
	for _, crate in ipairs(box and box:GetChildren() or {}) do
		if crate:IsA("BasePart") and typeof(crate:GetAttribute("MallCrateOrigin")) == "CFrame" then
			table.insert(crates, {part = crate, origin = crate:GetAttribute("MallCrateOrigin"), phase = tonumber(crate:GetAttribute("MallCratePhase")) or 0})
		end
	end
	-- SKINS_AT_EASE_20261013 (owner: the suits on show "spinner stille og roligt på den runde plade de står på")
	local plinths = anchors and anchors:FindFirstChild("SkinPlinths")
	for _, suit in ipairs(plinths and plinths:GetChildren() or {}) do
		if suit:IsA("Model") and typeof(suit:GetAttribute("MallSkinOrigin")) == "CFrame" and typeof(suit:GetAttribute("MallSkinAxis")) == "Vector3" then
			table.insert(suits, {model = suit, origin = suit:GetAttribute("MallSkinOrigin"), axis = suit:GetAttribute("MallSkinAxis")})
		end
	end
	-- BOOTH_FROM_TUNNEL_20261013: the two records on the DJ console turn, as they did in the tunnel lobby
	local stage = mall:FindFirstChild("Parts") and mall.Parts:FindFirstChild("Stage")
	for _, disc in ipairs(stage and stage:GetChildren() or {}) do
		if typeof(disc:GetAttribute("RecordPivot")) == "CFrame" then
			table.insert(discs, {part = disc, pivot = disc:GetAttribute("RecordPivot"), offset = disc:GetAttribute("RecordMeshOffset")})
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
	-- HALLOWEEN_DUSK_20261013 (owner: "a bit darker in the lobby to give it that spooky, cozy halloween vibe so the
	-- jack o lanterns pop"). While the Halloween dressing stands in the mall, the hall's own ceiling panels burn low
	-- and cool on this client (their light, their lenses and the sheen they lay on the floor); RoundUI lowers the
	-- ambient light to a dusk. Nothing is changed on the server, so taking the dressing out puts the light back.
	-- The wing's dying lamps are left alone. Safe to run again: every regular value is remembered on the instance.
	if mall:FindFirstChild("Halloween") then
		for _, host in ipairs(lights and lights:GetChildren() or {}) do
			local light = host:FindFirstChildWhichIsA("Light")
			if light and host.Name:sub(1, 10) == "PanelLight" and host.Name:sub(1, 14) ~= "PanelLightWing" and host:GetAttribute("Flicker") ~= true then
				local regular = light:GetAttribute("RegularBrightness") or light.Brightness
				light:SetAttribute("RegularBrightness", regular)
				light.Brightness = regular * DUSK_PANEL
				light.Color = DUSK_LIGHT
				local lens = ceiling and ceiling:FindFirstChild((host.Name:gsub("PanelLight", "PanelLens")))
				if lens and lens.Material == Enum.Material.Neon then lens.Color = DUSK_LENS end
			end
			for _, d in ipairs(host:GetDescendants()) do
				if d:IsA("SurfaceGui") and d.Name == "Sheen" then d.Brightness = DUSK_SHEEN end
			end
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
			+ #(now:FindFirstChild("Lights") and now.Lights:GetChildren() or {})
			+ #(anchors:FindFirstChild("SkinPlinths") and anchors.SkinPlinths:GetChildren() or {})
			+ #(now:FindFirstChild("Parts") and now.Parts:FindFirstChild("Stage") and now.Parts.Stage:GetChildren() or {})) or 0
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
	if not here then return end
	-- a slow turn is no flashing: the suits turn for everybody
	for _, suit in ipairs(suits) do
		if suit.model.Parent then
			suit.model:PivotTo(CFrame.new(suit.axis) * CFrame.Angles(0, elapsed * SUIT_TURN, 0) * CFrame.new(-suit.axis) * suit.origin)
		end
	end
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
	for _, disc in ipairs(discs) do
		if disc.part.Parent then disc.part.CFrame = disc.pivot * CFrame.Angles(0, elapsed * math.rad(12), 0) * disc.offset end
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
