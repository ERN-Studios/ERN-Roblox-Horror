-- Shop terminal SKINS tab. Purchases and equip requests are server-authoritative.
-- PreviewImageId is a verified render; ImageId is the separate UV texture map.
-- This page never uses a preview as a character ColorMap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Skins = require(ReplicatedStorage:WaitForChild("ZyntraSkins"))
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))

local Page = {}
local PREVIEW_FOLDER_NAME = "HazmatSkinPreviewTemplates"

local function allowedRobuxPass(item)
	local id = tonumber(item.PassId)
	if not id or id <= 0 or id % 1 ~= 0 then return false end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService,
		id, Enum.InfoType.GamePass)
	return ok and type(info) == "table" and info.IsForSale == true
		and info.PriceInRobux == item.RobuxPrice
end

function Page.mount(page, ctx)
	local colors = ctx.COLORS
	local accent = colors.accent or Color3.fromRGB(77, 219, 204)
	local muted = colors.muted or Color3.fromRGB(146, 169, 166)
	local ink = colors.text or Color3.fromRGB(235, 245, 242)
	local cardColor = colors.card or Color3.fromRGB(16, 29, 31)
	local gold = colors.accent2 or Color3.fromRGB(232, 186, 97)
	local pageName = ctx.pageName or "Skins"
	local contract = ctx.contract or {}

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Skins"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = accent
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = page
	if contract.scroll then contract.scroll(pageName, scroll) end

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 9)
	list.Parent = scroll

	local heading = Instance.new("Frame")
	heading.Name = "SkinHeading"
	heading.LayoutOrder = 0
	heading.Size = UDim2.new(1, -8, 0, 60)
	heading.BackgroundTransparency = 1
	heading.Parent = scroll
	local headingTitle = ctx.label(heading, "HAZMAT SKINS", UDim2.new(1, 0, 0, 28),
		UDim2.fromOffset(0, 0), 20, accent, Enum.Font.GothamBlack)
	headingTitle.Name = "HeadingTitle"
	local headingNote = ctx.label(heading,
		"Cosmetic only · owned suits stay unlocked · 5% skin prize on the wheel",
		UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 28), 12, muted,
		Enum.Font.GothamMedium)
	headingNote.Name = "HeadingNote"
	headingNote.TextWrapped = true
	headingNote.TextYAlignment = Enum.TextYAlignment.Top

	-- One live 3D model at a time. The replicated templates are cloned from
	-- the same canonical suits used on players, including premium toppers.
	local previewPanel = Instance.new("Frame")
	previewPanel.Name = "SkinPreview"
	previewPanel.LayoutOrder = 1
	previewPanel.Size = UDim2.new(1, -8, 0, 220)
	previewPanel.BackgroundColor3 = cardColor
	previewPanel.BorderSizePixel = 0
	previewPanel.Parent = scroll
	ctx.corner(previewPanel, 10)
	ctx.outline(previewPanel, colors.line or accent, 0.45)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "SuitViewport"
	viewport.Size = UDim2.new(1, -16, 1, -48)
	viewport.Position = UDim2.fromOffset(8, 30)
	viewport.BackgroundColor3 = Color3.fromRGB(35, 49, 53)
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(209, 215, 217)
	viewport.LightColor = Color3.fromRGB(255, 255, 247)
	viewport.LightDirection = Vector3.new(-0.6, -0.8, -1)
	viewport.Parent = previewPanel
	ctx.corner(viewport, 7)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local previewTitle = ctx.label(previewPanel, "BASELINE YELLOW",
		UDim2.new(1, -20, 0, 25), UDim2.fromOffset(10, 3), 14, accent,
		Enum.Font.GothamBold)
	previewTitle.Name = "PreviewTitle"
	previewTitle.TextTruncate = Enum.TextTruncate.AtEnd
	local previewDescription = ctx.label(previewPanel,
		Skins.ById[Skins.DefaultId].Description,
		UDim2.new(), UDim2.new(), 15, ink, Enum.Font.GothamMedium)
	previewDescription.Name = "PreviewDescription"
	previewDescription.TextWrapped = true
	previewDescription.TextYAlignment = Enum.TextYAlignment.Top
	local previewStatus = ctx.label(previewPanel, "OWNED · EQUIPPED",
		UDim2.new(), UDim2.new(), 13, gold, Enum.Font.GothamBold)
	previewStatus.Name = "PreviewStatus"
	previewStatus.TextWrapped = true
	local previewHint = ctx.label(previewPanel, "3D PREVIEW LOADING",
		UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 1, -20), 10, muted,
		Enum.Font.Code)
	previewHint.Name = "PreviewHint"
	previewHint.TextWrapped = true

	local selectedSkinId = Skins.DefaultId
	local loadedSkinId, previewModel, previewPivot, previewSize
	local previewAngle = 0
	local previewHold = 0
	local function frameCamera()
		if not previewSize then return end
		local size = viewport.AbsoluteSize
		local aspect = math.max(0.5, size.X / math.max(1, size.Y))
		local tangent = math.tan(math.rad(camera.FieldOfView) * 0.5)
		local distance = math.max(previewSize.Y / (2 * tangent),
			previewSize.X / (2 * tangent * aspect), previewSize.Z * 1.5) * 1.12
		camera.CFrame = CFrame.lookAt(Vector3.new(0, previewSize.Y * 0.02,
			-distance), Vector3.zero)
	end
	-- ViewportFrames render no ParticleEmitter, so preview the two topper effects
	-- as sparse 2D sprites. The rigid models remain visible with reduced flashing.
	local motes, moteClock = {}, 0
	local function clearMotes()
		for _, mote in ipairs(motes) do mote.Label:Destroy() end
		table.clear(motes)
	end
	local function stepMotes(deltaTime)
		for index = #motes, 1, -1 do
			local mote = motes[index]
			mote.Age += deltaTime
			local t = mote.Age / mote.Life
			if t >= 1 then
				mote.Label:Destroy()
				table.remove(motes, index)
			else
				mote.Label.Position = UDim2.fromOffset(mote.X + mote.Drift * t,
					mote.Y - mote.Rise * t)
				mote.Label.ImageTransparency = mote.StartTransparency
					+ (1 - mote.StartTransparency) * t
			end
		end
		local signal = selectedSkinId == "SignalArchitect"
		local topper = previewModel and (selectedSkinId == "FalseSun" or signal)
			and previewModel:FindFirstChild("ZyntraPremiumTopper")
		local part = topper and topper:FindFirstChildWhichIsA("BasePart", true)
		moteClock += deltaTime
		if not part or moteClock < (signal and 0.65 or 0.4)
			or #motes >= (signal and 2 or 3)
			or ctx.player:GetAttribute("ReduceFlashing") == true then return end
		moteClock = 0
		local position = part.Position + (signal and Vector3.yAxis * (part.Size.Y * 0.2)
			or Vector3.zero)
		local at = camera.CFrame:PointToObjectSpace(position)
		local centre = camera.CFrame:PointToObjectSpace(previewModel:GetPivot().Position)
		local depth = -at.Z
		if depth <= 0.1 or (not signal and at.Z <= centre.Z) then return end
		local size = viewport.AbsoluteSize
		local tangent = math.tan(math.rad(camera.FieldOfView) * 0.5)
		local label = Instance.new("ImageLabel")
		label.Name = signal and "SignalArchitectMote" or "FalseSunMote"
		label.BackgroundTransparency = 1
		label.Image = signal and "rbxassetid://124315518046326"
			or "rbxassetid://128661548525607"
		label.ImageTransparency = signal and 0.32 or 0.42
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromOffset(signal and 10 or 12, signal and 10 or 12)
		label.ZIndex = viewport.ZIndex + 1
		label.Parent = viewport
		table.insert(motes, {Label = label, Age = 0, Life = 0.45 + math.random() * 0.3,
			Drift = (math.random() - 0.5) * (signal and 12 or 10),
			Rise = signal and 14 or 22, StartTransparency = label.ImageTransparency,
			X = (at.X / depth / (tangent * size.X / math.max(1, size.Y)) + 1) / 2 * size.X,
			Y = (1 - at.Y / depth / tangent) / 2 * size.Y})
	end
	local function releasePreview()
		if previewModel then previewModel:Destroy() end
		clearMotes()
		previewModel, previewPivot, previewSize, loadedSkinId = nil, nil, nil, nil
	end
	local function loadPreview()
		local folder = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER_NAME)
		local source = folder and folder:FindFirstChild(selectedSkinId)
		if not source or not source:IsA("Model") then
			previewHint.Text = "3D PREVIEW LOADING"
			return
		end
		releasePreview()
		local model = source:Clone()
		local bounds, size = model:GetBoundingBox()
		model:PivotTo(CFrame.new(-bounds.Position) * model:GetPivot())
		model.Parent = world
		previewModel, previewPivot, previewSize = model, model:GetPivot(), size
		loadedSkinId = selectedSkinId
		-- Native Play confirmed this yaw shows the mask/front on first reveal.
		previewAngle = math.rad(295)
		previewHold = 3
		previewHint.Text = "TAP SUIT IMAGE · AUTO-ROTATING 3D"
		frameCamera()
	end
	local previewStep = RunService.RenderStepped:Connect(function(deltaTime)
		if not ctx.isVisible() then
			if previewModel then releasePreview() end
			return
		end
		if loadedSkinId ~= selectedSkinId then loadPreview() end
		if previewModel and previewPivot then
			if previewHold > 0 then
				previewHold -= deltaTime
			else
				previewAngle += math.min(deltaTime, 0.1) * 0.24
			end
			previewModel:PivotTo(CFrame.Angles(0, previewAngle, 0) * previewPivot)
		end
		stepMotes(deltaTime)
	end)
	viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(frameCamera)

	local entries = {}
	local paidVerified = {}
	for order, skinId in ipairs(Skins.Order) do
		local item = Skins.ById[skinId]
		-- DEV_SUIT_20260924: a Developer suit has no card for anyone else.
		if item.Kind == "Developer" and not DevAccess.IsAllowed(ctx.player) then continue end
		local card = Instance.new("Frame")
		card.Name = skinId
		card.LayoutOrder = order + 1
		card.BackgroundColor3 = cardColor
		card.BorderSizePixel = 0
		card.Parent = scroll
		ctx.corner(card, 10)
		ctx.outline(card, colors.line or accent, 0.45)

		local sample = Instance.new("ImageButton")
		sample.Name = "SuitSample"
		sample.AutoButtonColor = true
		sample.BackgroundColor3 = colors.bg or Color3.fromRGB(9, 18, 21)
		sample.BorderSizePixel = 0
		sample.Image = "rbxassetid://" .. tostring(item.PreviewImageId or item.ImageId)
		sample.ScaleType = Enum.ScaleType.Fit
		sample.Parent = card
		ctx.corner(sample, 7)
		local sampleCaption = ctx.label(card,
			skinId == selectedSkinId and "VIEWING" or "VIEW 3D",
			UDim2.new(), UDim2.new(), 10, muted, Enum.Font.Code)
		sampleCaption.Name = "SampleCaption"
		sampleCaption.TextXAlignment = Enum.TextXAlignment.Center

		local title = ctx.label(card, string.upper(item.Name), UDim2.new(), UDim2.new(),
			16, ink, Enum.Font.GothamBold)
		title.Name = "SkinName"
		title.TextWrapped = true
		title.TextYAlignment = Enum.TextYAlignment.Top
		local desc = ctx.label(card, item.Description, UDim2.new(), UDim2.new(),
			12, muted, Enum.Font.GothamMedium)
		desc.Name = "SkinDescription"
		desc.TextWrapped = true
		desc.TextYAlignment = Enum.TextYAlignment.Top
		local meta = ctx.label(card, "", UDim2.new(), UDim2.new(),
			12, gold, Enum.Font.GothamBold)
		meta.Name = "SkinPrice"
		meta.TextWrapped = true
		meta.TextYAlignment = Enum.TextYAlignment.Top
		local action = ctx.button(card, "", UDim2.new(), UDim2.new())
		action.Name = "SkinAction"
		if contract.card then contract.card(pageName, skinId, card, action) end

		entries[skinId] = {Card = card, Sample = sample, Caption = sampleCaption,
			Title = title, Desc = desc, Meta = meta, Action = action}
		sample.Activated:Connect(function()
			selectedSkinId = skinId
			previewHint.Text = "3D PREVIEW LOADING"
			previewTitle.Text = string.upper(item.Name)
			previewDescription.Text = item.Description
			for id, entry in pairs(entries) do
				entry.Caption.Text = id == skinId and "VIEWING" or "VIEW 3D"
			end
			previewStatus.Text = entries[skinId].Meta.Text .. " · "
				.. entries[skinId].Action.Text
			scroll.CanvasPosition = Vector2.new(scroll.CanvasPosition.X, 0)
		end)
		action.Activated:Connect(function()
			local profile = ctx.profile()
			if type(profile) ~= "table" then return end
			local owned = type(profile.Skins) == "table"
				and type(profile.Skins.Owned) == "table"
				and profile.Skins.Owned[skinId] == true
			if owned then
				if profile.Skins.Equipped ~= skinId then ctx.action("EquipSkin", skinId) end
			elseif item.Kind == "Tokens" then
				ctx.action("BuySkin", skinId)
			elseif item.Kind == "Robux" and paidVerified[skinId] == true then
				MarketplaceService:PromptGamePassPurchase(ctx.player, item.PassId)
			end
		end)
	end

	local function render()
		local profile = ctx.profile()
		profile = type(profile) == "table" and profile or {}
		local state = type(profile.Skins) == "table" and profile.Skins or {}
		local owned = type(state.Owned) == "table" and state.Owned or {}
		local tokens = tonumber(profile.Tokens) or 0
		local clears = math.max(0, math.floor(tonumber(profile.CompletedLevels) or 0))
		for _, skinId in ipairs(Skins.Order) do
			local item = Skins.ById[skinId]
			local entry = entries[skinId]
			if not entry then continue end
			local button = entry.Action
			local canAct = false
			if owned[skinId] == true or skinId == Skins.DefaultId then
				entry.Meta.Text = "OWNED"
				if state.Equipped == skinId or (state.Equipped == nil and skinId == Skins.DefaultId) then
					button.Text = "EQUIPPED"
				else
					button.Text = "EQUIP"
					canAct = true
				end
			elseif item.Kind == "Tokens" then
				if item.RequiredClears then
					entry.Meta.Text = ("%d TOKENS · %d/%d CLEARS"):format(item.TokenCost,
						clears, item.RequiredClears)
				else
					entry.Meta.Text = ("%d TOKENS"):format(item.TokenCost)
				end
				button.Text = tokens >= item.TokenCost and "UNLOCK" or "NEED TOKENS"
				canAct = tokens >= item.TokenCost and clears >= (item.RequiredClears or 0)
				if clears < (item.RequiredClears or 0) then button.Text = "LOCKED" end
			elseif item.Kind == "Developer" then
				-- Only while the server's grant is still on its way.
				entry.Meta.Text = "DEVELOPER ONLY"
				button.Text = "UNAVAILABLE"
			else
				entry.Meta.Text = ("%d R$"):format(item.RobuxPrice)
				canAct = paidVerified[skinId] == true
				button.Text = canAct and "BUY" or "UNAVAILABLE"
			end
			ctx.UIDevice.SetEnabled(button, canAct)
			button.TextColor3 = canAct and ink or muted
		end
		previewStatus.Text = entries[selectedSkinId].Meta.Text .. " · "
			.. entries[selectedSkinId].Action.Text
	end

	local function layout(fit)
		local width = math.max(120, math.floor(tonumber(fit.ContentWidth) or 320)) - 8
		-- Studio's phone simulator can report fit.Touch=false while the real
		-- client is touch-enabled. The terminal's measured height is the reliable
		-- layout signal for short landscape viewports.
		local shallowTouch = UserInputService.TouchEnabled
			and (fit.Height < 500 or fit.ContentHeight < 220)
		local tiny = width < 210
		local narrow = width < 340 or (fit.Compact == true and fit.Touch == true)
		local wide = width >= 550 and (fit.Touch ~= true or shallowTouch)
		local height = tiny and 420 or (narrow and 258 or (wide and 185 or 228))
		local sampleSize = narrow and 78 or (wide and 104 or 96)
		local pad = narrow and 10 or 14
		local rightX = tiny and pad or (pad + sampleSize + pad)
		local rightWidth = tiny and (width - pad * 2) or math.max(44, width - rightX - pad)
		local buttonHeight = math.max(44, math.floor(tonumber(fit.Tap) or 0))
		local previewWide = wide and not shallowTouch
		local previewLandscape = shallowTouch and width >= 480
		local previewHeight = previewLandscape
			and math.clamp(fit.ContentHeight - 2, 132, 190)
			or (previewWide and 300 or (tiny and 250 or (narrow and 240 or 270)))
		local viewportWidth = previewLandscape
			and math.clamp(math.floor(width * 0.38), 170, 255)
			or (previewWide and math.min(440, math.floor(width * 0.47))
				or width - 16)
		previewPanel.Size = UDim2.new(1, -8, 0, previewHeight)
		viewport.Size = UDim2.fromOffset(viewportWidth,
			previewLandscape and previewHeight - 8
				or (previewWide and previewHeight - 16 or previewHeight - 48))
		viewport.Position = UDim2.fromOffset(8,
			(previewWide or previewLandscape) and 8 or 30)
		local sideBySide = previewWide or previewLandscape
		local detailX = viewportWidth + (previewLandscape and 18 or 24)
		previewTitle.Position = UDim2.fromOffset(sideBySide and detailX or 10,
			previewWide and 34 or (previewLandscape and 7 or 3))
		previewTitle.Size = UDim2.new(1, -(sideBySide and detailX + 12 or 20),
			0, previewWide and 42 or 25)
		previewTitle.TextSize = previewWide and 22 or (previewLandscape and 16
			or (narrow and 12 or 14))
		previewDescription.Visible = sideBySide
		previewStatus.Visible = sideBySide
		if sideBySide then
			local detailWidth = width - detailX - 12
			previewDescription.Position = UDim2.fromOffset(detailX,
				previewWide and 94 or 42)
			previewDescription.Size = UDim2.fromOffset(detailWidth,
				previewWide and 95 or 43)
			previewStatus.Position = UDim2.fromOffset(detailX,
				previewWide and 205 or 91)
			previewStatus.Size = UDim2.fromOffset(detailWidth,
				previewWide and 38 or 25)
			previewHint.Position = UDim2.fromOffset(detailX,
				previewWide and previewHeight - 45 or previewHeight - 21)
			previewHint.Size = UDim2.fromOffset(detailWidth,
				previewWide and 28 or 18)
		else
			previewHint.Position = UDim2.new(0, 10, 1, -20)
			previewHint.Size = UDim2.new(1, -20, 0, 20)
		end
		previewHint.TextSize = narrow and 9 or 10
		task.defer(frameCamera)
		heading.Visible = not shallowTouch
		heading.Size = UDim2.new(1, -8, 0, narrow and 72 or 60)
		headingNote.Size = UDim2.new(1, 0, 0, narrow and 40 or 30)
		for _, entry in pairs(entries) do
			entry.Card.Size = UDim2.new(1, -8, 0, height)
			entry.Sample.Position = UDim2.fromOffset(pad, pad)
			entry.Sample.Size = UDim2.fromOffset(sampleSize, sampleSize)
			entry.Caption.Position = UDim2.fromOffset(pad, pad + sampleSize + 5)
			entry.Caption.Size = UDim2.fromOffset(sampleSize, 18)
			entry.Title.Position = UDim2.fromOffset(rightX, tiny and 124 or pad)
			entry.Title.Size = UDim2.fromOffset(rightWidth, narrow and 44 or 34)
			entry.Desc.Position = UDim2.fromOffset(rightX, tiny and 176 or (narrow and 58 or 50))
			entry.Desc.Size = UDim2.fromOffset(rightWidth, tiny and 120 or (narrow and 85 or (wide and 42 or 65)))
			entry.Meta.Position = UDim2.fromOffset(rightX, tiny and 310 or (narrow and 148 or (wide and 96 or 132)))
			entry.Meta.Size = UDim2.fromOffset(rightWidth, tiny and 46 or (narrow and 40 or 30))
			entry.Action.Position = UDim2.fromOffset(rightX, height - buttonHeight - pad)
			entry.Action.Size = UDim2.fromOffset(rightWidth, buttonHeight)
			entry.Action.TextSize = narrow and 12 or 14
		end
	end

	local stopProfile = ctx.onProfile(render)
	ctx.registerLayoutHook(layout)
	render()
	-- Price and availability are checked with Roblox before a paid prompt can
	-- open. A missing ID, network error, or price mismatch leaves it disabled.
	for _, skinId in ipairs(Skins.Order) do
		local item = Skins.ById[skinId]
		if item.Kind == "Robux" and item.PassId > 0 then
			task.spawn(function()
				paidVerified[skinId] = allowedRobuxPass(item)
				render()
			end)
		end
	end
	return {
		refresh = render,
		destroy = function()
			previewStep:Disconnect()
			releasePreview()
			if type(stopProfile) == "function" then stopProfile() end
			scroll:Destroy()
		end,
	}
end

return Page
