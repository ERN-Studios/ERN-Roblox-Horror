-- Shop Display Client
-- The player's half of the lobby SHOP wall (ServerScriptService.LobbyShopDisplay).
--
-- Two jobs, both lobby-only:
--   1. THE CARD. The server publishes which item this player is standing in
--      front of as the player attribute ZyntraShopFocus. This draws that item's
--      detail card -- name, what you get, live price, owned/used state -- and
--      nothing else. Opening a card NEVER prompts a purchase. Only BUY does,
--      and BUY does not prompt anything here either: it fires
--      PlayerScripts.ZyntraShopBuy, which ZyntraStore answers by running the
--      SAME product-card purchase path its own terminal button runs. One
--      purchase entry point in the game, not two.
--   2. THE MOTION. The hologram boxes bob, locally, so no CFrame of this
--      replicates and the server does no per-frame work at all. One calm
--      continuous sine per box, phase-offset by the server's ShopBobPhase so
--      the row never pumps in unison. It stops the moment a round starts and
--      under ReduceFlashing / ReduceCameraShake, and every pose it moved is put
--      back. The boxes do NOT turn (Trello #105) -- the product art is on all
--      six faces now, but a turning box still reads as a spinning pickup rather
--      than as merchandise, and the shop's whole point is that it is legible
--      from the road. The overhead sign it used to breathe with was deleted
--      with the rest of the shopfront in v4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local Profiles = require(ReplicatedStorage:WaitForChild("FlashlightProfiles"))

local FOCUS_ATTRIBUTE = "ZyntraShopFocus"
local BUY_EVENT_NAME = "ZyntraShopBuy"
local TOUCH_TAP = 44

-- ANALYTICS_20260921. The server cannot see a card open or a demo start, so
-- the client reports those two facts and nothing else, fire-and-forget, on
-- the existing ZyntraAction remote. The server validates the key against the
-- catalogue and ignores everything else; a missing remote is simply silence.
local function reportShop(key, demo)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local action = remotes and remotes:FindFirstChild("ZyntraAction")
	if action and action:IsA("RemoteEvent") then
		action:FireServer("ShopView", {Key = key, Demo = demo})
	end
end

-- ANALYTICS_20260921. The PC / phone / tablet split the ads decision needs is a
-- client fact. It is reported once, as one of three fixed words; the server
-- keeps it only as an analytics segment, so a client that lies mislabels
-- nothing but its own row. ponytail: no console class -- UIDevice has none;
-- add it there first if console ever matters.
task.delay(4, function()
	-- The server drops every ZyntraAction until the profile has loaded.
	local localPlayer = game:GetService("Players").LocalPlayer
	for _ = 1, 60 do
		if localPlayer:GetAttribute("ZyntraProfileLoaded") == true then break end
		task.wait(1)
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local action = remotes and remotes:FindFirstChild("ZyntraAction")
	local ok, class = pcall(function() return UIDevice.Layout().Class end)
	local names = {desktop = "PC", phone = "Phone", tablet = "Tablet"}
	if action and action:IsA("RemoteEvent") and ok and names[class] then
		action:FireServer("DeviceClass", {Class = names[class]})
	end
end)

local COLORS = {
	panel = Color3.fromRGB(14, 21, 24),
	card = Color3.fromRGB(20, 29, 33),
	line = Color3.fromRGB(75, 94, 83),
	text = Color3.fromRGB(231, 238, 233),
	muted = Color3.fromRGB(144, 164, 165),
	accent = Color3.fromRGB(68, 221, 196),
	accent2 = Color3.fromRGB(255, 203, 79),
}

-- ── the catalogue entry behind a focus key ──────────────────────────────────
local function lookup(key)
	local pass = Config.Passes and Config.Passes[key]
	if pass then return pass, "Pass" end
	local product = Config.Products and Config.Products[key]
	if product then return product, "Product" end
	local item = Config.Items and Config.Items[key]
	if item then return item, "Item" end
	return nil, nil
end

-- Live prices, fetched once per key per session exactly the way the terminal's
-- own cards do. The configured price is what shows until the fetch answers, so
-- the card always states a number.
local livePrices = {}
local function requestPrice(key, item, kind, apply)
	if livePrices[key] then apply(livePrices[key]) return end
	apply(math.max(0, math.floor(tonumber(item.Price) or 0)))
	local id = tonumber(item.Id)
	if not id or id <= 0 then return end
	task.spawn(function()
		local infoType = kind == "Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
		local price = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
		if price and price >= 0 then
			livePrices[key] = math.floor(price)
			apply(livePrices[key])
		end
	end)
end

-- ── the card ────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "ZyntraShopDisplayCard"
gui.ResetOnSpawn = false
gui.DisplayOrder = 65 -- product detail stays above the lobby rail and friend chip
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent, radius)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
	return object
end

local function stroke(parent, color, transparency, thickness)
	local object = Instance.new("UIStroke")
	object.Color = color
	object.Transparency = transparency or 0.28
	object.Thickness = thickness or 1
	object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	object.Parent = parent
	return object
end

local card = Instance.new("Frame")
card.Name = "ShopDetailCard"
card.BackgroundColor3 = COLORS.panel
card.BackgroundTransparency = 0.04
card.BorderSizePixel = 0
card.ClipsDescendants = true
card.Parent = gui
corner(card, 10)
stroke(card, COLORS.accent, 0.35, 1.5)

local icon = Instance.new("ImageLabel")
icon.Name = "ItemIcon"
icon.BackgroundColor3 = COLORS.card
icon.BorderSizePixel = 0
icon.ScaleType = Enum.ScaleType.Crop
icon.Parent = card
corner(icon, 8)
stroke(icon, COLORS.accent, 0.4, 1.5)

local monogram = Instance.new("TextLabel")
monogram.Name = "ItemMonogram"
monogram.Size = UDim2.fromScale(1, 1)
monogram.BackgroundTransparency = 1
monogram.Font = Enum.Font.GothamBlack
monogram.Text = "Z//"
monogram.TextColor3 = COLORS.accent
monogram.TextScaled = true
monogram.Visible = false
monogram.Parent = icon

local function makeLabel(name, font, color, xAlign)
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.Font = font
	object.Text = ""
	object.TextColor3 = color
	object.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Top
	object.TextWrapped = true
	object.Parent = card
	return object
end

-- The ONE place the word SHOP is written anywhere in the game world or on this
-- card: v4 deleted the overhead sign and the kiosk fascia, so the eyebrow on
-- the card a hologram opens is what tells the player what they have walked into.
local shopTitle = makeLabel("ShopTitle", Enum.Font.GothamBlack, COLORS.accent)
shopTitle.Text = "SHOP"
local title = makeLabel("ItemName", Enum.Font.GothamBold, COLORS.text)
local kindTag = makeLabel("ItemKind", Enum.Font.Code, COLORS.accent)
local description = makeLabel("ItemDescription", Enum.Font.GothamMedium, COLORS.muted)
local descriptionScroll=Instance.new("ScrollingFrame")
descriptionScroll.Name="ProductContents"
descriptionScroll.BackgroundTransparency=1
descriptionScroll.BorderSizePixel=0
descriptionScroll.ScrollBarThickness=3
descriptionScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
descriptionScroll.CanvasSize=UDim2.new()
descriptionScroll.ScrollingDirection=Enum.ScrollingDirection.Y
descriptionScroll.Parent=card
description.Parent=descriptionScroll
description.AutomaticSize=Enum.AutomaticSize.Y
local state = makeLabel("ItemState", Enum.Font.Code, COLORS.accent2)
-- How to get rid of the card, on the kind row's right so it costs no height.
-- The plate is invisible now, so this line is the only place that says the
-- floor is what opened this; proportional Gotham rather than the kind tag's
-- monospace, because 27 characters of Code does not fit 168px on a phone.
local hintTag = makeLabel("CloseHint", Enum.Font.GothamMedium, COLORS.muted, Enum.TextXAlignment.Right)
hintTag.TextTruncate = Enum.TextTruncate.AtEnd

local function makeButton(name, text, color)
	local object = Instance.new("TextButton")
	object.Name = name
	object.AutoButtonColor = false
	object.BackgroundColor3 = COLORS.card
	object.Font = Enum.Font.GothamBold
	object.Text = text
	object.TextColor3 = color
	object.TextScaled = false
	object.Parent = card
	corner(object, 8)
	stroke(object, COLORS.line, 0.25, 1)
	return object
end

local buyButton = makeButton("Buy", "BUY", COLORS.accent2)
local closeButton = makeButton("Close", "CLOSE", COLORS.muted)

-- ── layout ──────────────────────────────────────────────────────────────────
-- THE SAME THREE TIERS the terminal's Shop cards use -- phone / tablet /
-- pointer -- and the same two touch icon sizes (52 / 64), so a hologram's card
-- and its card in the terminal are recognisably the same object. `compact` is
-- read from the VIEWPORT rather than from this card's own width: the terminal's
-- compact means "the 840x610 panel had to shrink", and a 560px card would
-- otherwise report itself compact on every screen there is.
--
-- The POINTER tier grew with the shop (#105): 560 wide and a 112px icon, which
-- is the product art at a size worth looking at on a desktop screen that has
-- the room. The two touch tiers are unchanged -- a phone does not.
local CARD_DESIGN_WIDTH = 560

local function cardFace()
	local layout = UIDevice.Layout()
	local area = layout.ModalViewport
	local touch = layout.IsTouch
	local compact = area.Width < 640 or area.Height < 430
	local face = ({
		{Pad = 10, Icon = 52, Title = 14, Kind = 11, Desc = 11, State = 11, Button = 38, Width = 300},
		{Pad = 14, Icon = 64, Title = 16, Kind = 12, Desc = 12, State = 12, Button = 38, Width = 380},
		{Pad = 16, Icon = 112, Title = 20, Kind = 12, Desc = 13, State = 13, Button = 40, Width = 560},
	})[(compact and touch) and 1 or (touch and 2 or 3)]
	return face, (touch and TOUCH_TAP or 32), touch
end

-- WHERE THE CARD SITS: bottom centre of the true safe area, not a HUD corner.
-- The top right is the player list's on desktop, the left rail is the store's
-- rail buttons, and the card is about the hologram the player is standing
-- in front of, so it belongs near the bottom of the screen they are looking
-- through. On touch it is lifted above the movement cluster -- walking off the
-- plate is how the card is meant to close, and a card over the thumbstick would
-- take that away.
local function cardArea(width, height)
	local layout = UIDevice.Layout()
	local safe = layout.Safe
 if layout.IsTouch and safe.Height>safe.Width then
  -- Portrait needs a readable card across the centre; the side lane can be
  -- narrower than its two 44px actions. Leave the bottom movement band free.
  width=math.min(width,safe.Width-24)
  height=math.min(height,math.max(180,safe.Height-220))
  return {Left=math.floor((safe.Left+safe.Right-width)/2),
   Top=math.max(safe.Top+12,safe.Bottom-200-height),Width=width,Height=height}
 end
	if layout.IsTouch and layout.ModalArea then
		-- The free lane excludes BOTH the thumbstick and the right-hand controls.
		-- Centring over the whole screen covered the stick on short landscape phones.
		local area = layout.ModalArea
		width = math.min(width, math.max(1, area.Right - area.Left))
		height = math.min(height, math.max(1, area.Bottom - area.Top))
		return {Left = math.floor((area.Left + area.Right - width) / 2),
			Top = math.floor(area.Bottom - height), Width = math.floor(width),
			Height = math.floor(height)}
	end
	local margin = layout.IsTouch and 12 or 18
	width = math.min(width, math.max(120, safe.Right - safe.Left - margin * 2))
	local bottom = safe.Bottom - margin
	if layout.IsTouch and layout.Zones and layout.Zones.Controls then
		bottom = math.min(bottom, layout.Zones.Controls.Top - 10)
	end
	height = math.min(height, math.max(80, bottom - (safe.Top + margin)))
	return {
		Left = math.floor((safe.Left + safe.Right - width) / 2),
		Top = math.floor(bottom - height),
		Width = math.floor(width),
		Height = math.floor(height),
	}
end

-- The icon and description stand side by side in ONE row, and that row is the
-- first thing that gives way on a short screen -- never the type size, never the
-- tap target. 28px is the floor below which the row is not a row any more; at
-- that point the state line goes, and below that the SHOP eyebrow goes too. The
-- same ordered give-way the terminal's own panel uses, with three rungs instead
-- of four. The eyebrow is last because a card with no room for it still has the
-- product name, the price and BUY, which is the whole transaction.
local MIN_BODY_HEIGHT = 28

local function applyLayout()
	if not gui.Enabled then return end
	local face, tap, touch = cardFace()
	local buttonHeight = math.max(tap, face.Button)
	local eyebrowHeight = face.Kind + 6
	local titleHeight = face.Title + 12
	local kindHeight = face.Kind + 6
	local stateHeight = face.State + 8
	local function fixedHeight(withState, withEyebrow)
		return face.Pad + (withEyebrow and eyebrowHeight or 0) + titleHeight + kindHeight + 4 + 8
			+ (withState and (stateHeight + 10) or 0)
			+ buttonHeight + face.Pad
	end

	local wanted = fixedHeight(true, true) + face.Icon
	local column = cardArea(math.min(face.Width, CARD_DESIGN_WIDTH), wanted)
	local withState = column.Height >= fixedHeight(true, true) + MIN_BODY_HEIGHT
	local withEyebrow = column.Height >= fixedHeight(withState, true) + MIN_BODY_HEIGHT
	local fixed = fixedHeight(withState, withEyebrow)
	local bodyHeight = math.clamp(column.Height - fixed, MIN_BODY_HEIGHT, face.Icon)
	local height = fixed + bodyHeight
	local titleTop = face.Pad + (withEyebrow and eyebrowHeight or 0)
	local bodyTop = titleTop + titleHeight + kindHeight + 4
	local stateTop = bodyTop + bodyHeight + 8
	local buttonTop = withState and (stateTop + stateHeight + 10) or stateTop

	card.Size = UDim2.fromOffset(column.Width, height)
	-- Bottom-aligned inside the band, but never drawn above the safe top: on a
	-- screen too short for even the floor composition, the honest answer is a
	-- card that overlaps the reserved control band -- where that device's
	-- cluster is laid along the bottom edge anyway -- not one running off it.
	card.Position = UIDevice.LocalPosition(gui, column.Left,
		math.max(column.Top, column.Top + column.Height - height))

	local inner = column.Width - face.Pad * 2
	shopTitle.Visible = withEyebrow
	shopTitle.Position = UDim2.fromOffset(face.Pad, face.Pad)
	shopTitle.Size = UDim2.fromOffset(inner, eyebrowHeight)
	shopTitle.TextSize = face.Kind
	title.Position = UDim2.fromOffset(face.Pad, titleTop)
	title.Size = UDim2.fromOffset(inner, titleHeight)
	title.TextSize = face.Title
	-- Kind on the left, how-to-close on the right, one row. 38% is what fits
	-- "PERMANENT PASS" in monospace at the phone tier's 11px and still leaves
	-- the hint its 27 characters.
	local kindWidth = math.floor(inner * 0.38)
	kindTag.Position = UDim2.fromOffset(face.Pad, titleTop + titleHeight)
	kindTag.Size = UDim2.fromOffset(kindWidth, kindHeight)
	kindTag.TextSize = face.Kind
	hintTag.Position = UDim2.fromOffset(face.Pad + kindWidth + 6, titleTop + titleHeight)
	hintTag.Size = UDim2.fromOffset(math.max(40, inner - kindWidth - 6), kindHeight)
	hintTag.TextSize = face.Kind
	-- The trigger is invisible, so "the plate" names nothing a player can see;
	-- the card closes on distance, and walking is true on every device.
	hintTag.Text = "Walk away to close"

	icon.Position = UDim2.fromOffset(face.Pad, bodyTop)
	icon.Size = UDim2.fromOffset(bodyHeight, bodyHeight)

	local copyLeft = face.Pad * 2 + bodyHeight
	descriptionScroll.Position = UDim2.fromOffset(copyLeft, bodyTop)
	description.Position = UDim2.new()
	descriptionScroll.Size = UDim2.fromOffset(math.max(40, column.Width - copyLeft - face.Pad), bodyHeight)
	description.Size = UDim2.new(1,-5,0,0)
	description.TextSize = face.Desc
	description.TextTruncate = Enum.TextTruncate.None

	state.Visible = withState
	state.Position = UDim2.fromOffset(face.Pad, stateTop)
	state.Size = UDim2.fromOffset(inner, stateHeight)
	state.TextSize = face.State

	-- BUY takes the room; CLOSE is deliberately the smaller of the two, because
	-- stepping off the plate closes the card anyway.
	local closeWidth = math.max(72, math.floor(inner * 0.3))
	buyButton.Position = UDim2.fromOffset(face.Pad, buttonTop)
	buyButton.Size = UDim2.fromOffset(inner - closeWidth - 8, buttonHeight)
	buyButton.TextSize = math.max(12, face.Title - 2)
	closeButton.Position = UDim2.fromOffset(face.Pad + inner - closeWidth, buttonTop)
	closeButton.Size = UDim2.fromOffset(closeWidth, buttonHeight)
	closeButton.TextSize = math.max(11, face.Kind)
end

-- ── what the card says ──────────────────────────────────────────────────────
local shownKey = nil
local dismissedKey = nil

local function ownedState(key, kind, item)
	if kind == "Item" then
		local attribute = key == "SpeedPotion" and "ZyntraSpeedPotions" or "ZyntraRouteMarkers"
		return ("%d STORED"):format(tonumber(player:GetAttribute(attribute)) or 0), true
	end
	if kind == "Pass" then
		if player:GetAttribute("ZyntraOwns" .. key) == true then return "OWNED", false end
		return "PERMANENT -- BOUGHT ONCE", true
	end
	if key == "EmergencyReentry" then
		local credits = tonumber(player:GetAttribute("ZyntraReentryCredits")) or 0
		return ("STORED CREDITS  %d"):format(credits), true
	end
	if tonumber(item.TokenGrant) then
		return ("ADDS %d RESEARCH TOKENS"):format(item.TokenGrant), true
	end
	return "", true
end

local function refresh()
	local key = shownKey
	if not key then return end
	local item, kind = lookup(key)
	if not item then return end
	title.Text = tostring(item.Name or key)
	closeButton.Text = (key == "AdvancedEquipment" or key == "CosmeticEquipment" or key == "EntityDetector") and "TRY DEMO" or "CLOSE"
	-- What you are actually buying with, in three words: a pass you keep, a thing
	-- bought with research tokens, a thing bought with Robux.
	kindTag.Text = kind == "Pass" and "PERMANENT PASS" or (kind == "Item" and "TOKEN ITEM" or "ROBUX PRODUCT")
	description.Text = tostring(item.PreviewDescription or item.Description or "")

	local iconId = tonumber(item.IconId) or 0
	icon.Image = iconId > 0 and ("rbxassetid://" .. tostring(iconId)) or ""
	monogram.Visible = iconId <= 0
	monogram.Text = type(item.IconText) == "string" and item.IconText or "Z//"

	local stateText, purchasable = ownedState(key, kind, item)
	state.Text = stateText
	if not purchasable then
		-- "OWNED" is a stated reason, not silence: UIRegression's
		-- Fit.ZyntraDisabledCaptions already recognises it.
		buyButton.Text = "OWNED"
		UIDevice.SetEnabled(buyButton, false)
	elseif kind == "Item" then
		buyButton.Text = tostring(item.TokenCost) .. " TOKENS  //  BUY"
		UIDevice.SetEnabled(buyButton, true)
	elseif not tonumber(item.Id) or item.Id <= 0 then
		buyButton.Text = "UNAVAILABLE"
		UIDevice.SetEnabled(buyButton, false)
	else
		UIDevice.SetEnabled(buyButton, true)
		requestPrice(key, item, kind, function(price)
			if shownKey == key then buyButton.Text = tostring(price) .. " R$" end
		end)
	end
end

local demoMount, demoConnection, detectorDemo
local startCosmeticDemo
local DetectorVisual=require(ReplicatedStorage:WaitForChild("ZyntraDetectorVisual"))
local function stopDemo()
	if detectorDemo then detectorDemo:Destroy(); detectorDemo=nil end
	card.Visible=true
	if demoConnection then demoConnection:Disconnect(); demoConnection = nil end
	if demoMount then demoMount:Destroy(); demoMount = nil end
	icon.Visible=true
	if shownKey then refresh() end
end
local function startFocusDemo()
	stopDemo()
	if shownKey ~= "AdvancedEquipment" or player:GetAttribute("InRound") == true then return end
	-- Local-only six-second comparison on the world in front of the camera.
	-- It changes no equipment, battery, ownership, inventory or purchase state.
	local part = Instance.new("Part")
	part.Name = "ZyntraLocalFlashlightDemo"
	part.Size = Vector3.new(.1, .1, .1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	local core = Instance.new("SpotLight")
	core.Face = Enum.NormalId.Front
	core.Shadows = true
	core.Color = Color3.fromRGB(255, 244, 214)
	core.Parent = part
	local spill = core:Clone()
	spill.Shadows = false
	spill.Parent = part
	part.Parent = workspace
	demoMount = part
	local began, previous = os.clock(), nil
	demoConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - began
		if not gui.Enabled or player:GetAttribute("InRound") == true then stopDemo(); return end
  if elapsed >= 6 then stopDemo(); startCosmeticDemo("AdvancedEquipment"); return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		part.CFrame = camera.CFrame * CFrame.new(.25, -.25, -.3)
		local focused = elapsed >= 3
		if previous ~= focused then
			Profiles.Apply(Profiles.Own, "BASE", core, spill, focused)
			previous = focused
			state.Text = focused and "DEMO: FOCUSED — +45% RANGE, SAME DRAIN" or "DEMO: NORMAL WIDE BEAM"
			closeButton.Text = focused and "FOCUSED" or "WIDE"
		end
	end)
end


-- Preview a disposable clone; never recolor the live character or save settings.
startCosmeticDemo=function(key)
 stopDemo()
 if shownKey~=key or player:GetAttribute("InRound")==true then return end
 local character=player.Character
 if not character then return end
 local previous=character.Archivable
 character.Archivable=true
 local ok,clone=pcall(function() return character:Clone() end)
 character.Archivable=previous
 if not ok or not clone then state.Text="AVATAR PREVIEW UNAVAILABLE" return end
 local viewport=Instance.new("ViewportFrame")
 viewport.Name="CosmeticPreview"
 viewport.BackgroundColor3=Color3.fromRGB(12,25,23)
 viewport.Size=icon.Size viewport.Position=icon.Position viewport.Parent=card
 viewport.Ambient=Color3.fromRGB(200,200,200)
 viewport.LightColor=Color3.new(1,1,1)
 viewport.LightDirection=Vector3.new(-1,-1,-2)
 demoMount=viewport icon.Visible=false
 local world=Instance.new("WorldModel") world.Parent=viewport
 for _,object in ipairs(clone:GetDescendants()) do
  if object:IsA("LuaSourceContainer") then object:Destroy()
  elseif object:IsA("BasePart") then object.Anchored=true object.CanCollide=false end
 end
 clone.Parent=world clone:PivotTo(CFrame.new())
 local cf,size=clone:GetBoundingBox()
 local camera=Instance.new("Camera") camera.FieldOfView=35 camera.Parent=viewport
 camera.CFrame=CFrame.lookAt(cf.Position+Vector3.new(0,.25,-math.max(size.Y,size.X)*1.9),cf.Position)
 viewport.CurrentCamera=camera
 local glow
 if key=="CosmeticEquipment" then
  local hand=clone:FindFirstChild("RightHand") or clone:FindFirstChild("Right Arm")
  glow=Instance.new("Part") glow.Name="PreviewGlowstick" glow.Size=Vector3.new(.22,1.5,.22)
  glow.Anchored=true glow.CanCollide=false glow.Material=Enum.Material.Neon
  glow.CFrame=(hand and hand.CFrame or cf)*CFrame.new(0,-.3,-.2) glow.Parent=world
 end
 local palette={Color3.fromRGB(73,245,204),Color3.fromRGB(245,151,61),Color3.fromRGB(165,115,255)}
 local began,last=os.clock(),0
 demoConnection=RunService.RenderStepped:Connect(function()
  local elapsed=os.clock()-began
  if elapsed>=6 or not gui.Enabled or player:GetAttribute("InRound")==true then stopDemo() return end
  viewport.Position=icon.Position viewport.Size=icon.Size
  local step=math.min(3,math.floor(elapsed/2)+1)
  if step~=last then
   last=step local color=palette[step]
   if glow then glow.Color=color else
    for _,object in ipairs(clone:GetDescendants()) do
     if object:IsA("SurfaceAppearance") then object.Color=color
     elseif object:IsA("BasePart") and object.Name~="HumanoidRootPart" then object.Color=color end
    end
   end
   state.Text=glow and "DEMO: YOUR AVATAR · GLOWSTICK COLORS" or "DEMO: YOUR AVATAR · HAZMAT COLORS"
   closeButton.Text="PREVIEW"
  end
 end)
end

local function startDetectorDemo()
 stopDemo()
 if shownKey~="EntityDetector" or player:GetAttribute("InRound")==true then return end
 card.Visible=false
 local demoCharacter=player.Character
 detectorDemo=DetectorVisual.Demo(player:WaitForChild("PlayerGui"),function()
  detectorDemo=nil
  stopDemo()
 end)
 demoConnection=RunService.Heartbeat:Connect(function()
  if not gui.Enabled or shownKey~="EntityDetector" or player:GetAttribute("InRound")==true or player.Character~=demoCharacter then stopDemo() end
 end)
end

local function setShown(key)
	if shownKey == key then return end
	stopDemo()
	shownKey = key
	descriptionScroll.CanvasPosition=Vector2.zero
	gui.Enabled = key ~= nil
	-- Yield the dispatch caption without suppressing movement: stepping off the
	-- pressure plate remains a way to close this nonmodal card.
	player:SetAttribute("ZyntraShopDetailOpen", key ~= nil)
	if key then
		refresh()
		applyLayout()
		reportShop(key, false)
	end
end

-- WHY THIS CANNOT LOOP. evaluate runs on an attribute CHANGE, never on a
-- timer, so after CLOSE a player who stands perfectly still gets no further
-- call and the card stays down. dismissedKey survives exactly as long as the
-- focus does not move: any other key, or nil, clears it on the line below,
-- which is what lets stepping off and back on -- or on to the next hologram --
-- open the card again. There is no second path that can raise it.
local function evaluate()
	local key = player:GetAttribute(FOCUS_ATTRIBUTE)
	if type(key) ~= "string" or key == "" or not lookup(key) then key = nil end
	if key ~= dismissedKey then dismissedKey = nil end
	if key == nil
		or key == dismissedKey
		or player:GetAttribute("InRound") == true
		or UIDevice.ScreenOwningModalOpen() then
		setShown(nil)
		return
	end
	setShown(key)
end

local function startShownDemo()
 local key=shownKey
 if key=="AdvancedEquipment" then startFocusDemo()
 elseif key=="CosmeticEquipment" then startCosmeticDemo(key)
 elseif key=="EntityDetector" then startDetectorDemo()
 else return false end
 reportShop(key,true)
 return true
end
-- Studio-only probe invokes the same entry point as the visible demo button.
if RunService:IsStudio() then
 local probe=Instance.new("BindableFunction")
 probe.Name="UIRegressionShopDemoProbe"
 probe.OnInvoke=function(action)
  if action=="start" then return startShownDemo() end
  if action=="stop" then stopDemo() return true end
  return shownKey
 end
 probe.Parent=gui
end
closeButton.Activated:Connect(function()
 if startShownDemo() then return end
	-- CLOSE dismisses THIS focus. Stepping off the plate and back on, or
	-- walking to the next hologram, brings the card back.
	dismissedKey = shownKey
	setShown(nil)
end)

buyButton.Activated:Connect(function()
	if not shownKey or not buyButton.Active then return end
	local event = player:FindFirstChild("PlayerScripts")
	event = event and event:FindFirstChild(BUY_EVENT_NAME)
	if event and event:IsA("BindableEvent") then
		-- ZyntraStore owns the purchase. This is a request to run its button.
		event:Fire(shownKey)
	else
		state.Text = "STILL LOADING -- TRY AGAIN"
	end
end)

player:GetAttributeChangedSignal(FOCUS_ATTRIBUTE):Connect(evaluate)
player:GetAttributeChangedSignal("InRound"):Connect(evaluate)
player:GetAttributeChangedSignal("ZyntraReentryCredits"):Connect(refresh)
player:GetAttributeChangedSignal("ZyntraSpeedPotions"):Connect(refresh)
player:GetAttributeChangedSignal("ZyntraRouteMarkers"):Connect(refresh)
for _, key in ipairs({"Supporter", "AdvancedEquipment", "CosmeticEquipment", "EntityDetector"}) do
	player:GetAttributeChangedSignal("ZyntraOwns" .. key):Connect(refresh)
end
UIDevice.OnScreenOwningModalChanged(evaluate)
UIDevice.Changed:Connect(applyLayout)
-- Enabling a previously hidden ScreenGui can update its inset origin one
-- render later. Relayout against the engine's settled origin; otherwise the
-- first card can sit one topbar too low and crop BUY/CLOSE off the screen.
gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(applyLayout)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

-- ── the wall's own motion ───────────────────────────────────────────────────
-- Local only: these are anchored server parts and nothing written here leaves
-- this client, so the server does no per-frame work for the shop at all. Stops
-- dead outside the lobby, and restores every pose it moved.
--
-- The amplitude is the number the SERVER's envelope was solved against: a box
-- top at 8.70 resting and 9.05 at the peak, which is 0.15 inside the rib arch.
-- Changing BOB_HEIGHT here moves geometry that LobbyShopDisplay measured.
local BOB_HEIGHT = 0.35
local BOB_PERIOD = 3.4

local shopModel = nil
local boxes = {}
local animating = false

local function restoreMotion()
	for _, record in ipairs(boxes) do
		if record.Part.Parent then record.Part.CFrame = record.Origin end
	end
	animating = false
end

local function collect(model)
	boxes = {}
	if not model then return end
	for _, node in ipairs(model:GetDescendants()) do
		if node:IsA("BasePart") then
			local origin = node:GetAttribute("ShopBobOrigin")
			if typeof(origin) == "CFrame" then
				table.insert(boxes, {
					Part = node,
					Origin = origin,
					Phase = tonumber(node:GetAttribute("ShopBobPhase")) or 0,
				})
			end
		end
	end
end

local function lobbyShop()
	local lobby = workspace:FindFirstChild("ServerLobby")
	return lobby and lobby:FindFirstChild("ZyntraShopDisplay") or nil
end

-- Rounds stop it because nothing in the lobby should run while the player is
-- somewhere else; the two accessibility flags stop it because a player who has
-- asked for less motion has asked for less motion, and the boxes are readable
-- standing still -- the art is on all six faces.
local function motionAllowed()
	return shopModel ~= nil
		and player:GetAttribute("InRound") ~= true
		and workspace:GetAttribute("RoundActive") ~= true
		and player:GetAttribute("ReduceFlashing") ~= true
		and player:GetAttribute("ReduceCameraShake") ~= true
end

local elapsed = 0
RunService.Heartbeat:Connect(function(delta)
	elapsed += delta
	local current = (shopModel and shopModel.Parent) and shopModel or lobbyShop()
	if current ~= shopModel then
		restoreMotion()
		shopModel = current
		collect(shopModel)
	end
	-- Replication hands a client the model BEFORE its boxes: measured in Studio
	-- Play on 2026-09-16, the first collect found the model and none of the
	-- eight boxes, and the row then stood still for the whole session. The
	-- server stamps ShopItemCount on the model once every box is built, so
	-- until this client holds that many it keeps collecting.
	if shopModel and #boxes < (tonumber(shopModel:GetAttribute("ShopItemCount")) or 0) then
		collect(shopModel)
	end
	if not motionAllowed() then
		if animating then restoreMotion() end
		return
	end
	animating = true
	-- Bob only, never yaw: a turning box reads as a spinning pickup, and the
	-- server's envelope is solved for a box that only ever moves up and down.
	-- The phase comes from the server so every client sees the same row.
	for _, record in ipairs(boxes) do
		local phase = elapsed * (math.pi * 2 / BOB_PERIOD) + record.Phase
		record.Part.CFrame = record.Origin * CFrame.new(0, math.sin(phase) * BOB_HEIGHT, 0)
	end
end)

script.Destroying:Connect(function() stopDemo(); restoreMotion() end)
evaluate()
