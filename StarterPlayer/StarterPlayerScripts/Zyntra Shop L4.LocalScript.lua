-- Zyntra Shop L4  (StarterPlayerScripts, SHOP_UI_L4_20261005)
--
-- The L4 "Bento Home" shop window, built from the Framewisp import in
-- ReplicatedStorage.ZyntraShopUI.ZyntraShop_L4 (L4-ROBLOX-PLAN.md section 2.4).
--
-- WHO OWNS WHAT.
--   * ShopData owns every read and the ONE purchase dispatcher, and the one
--     settings send. This file never prompts, never fires a remote and never
--     decides ownership or a price.
--   * ShopBinder owns the name contract (tag-tolerant lookup, class tolerance).
--   * ZyntraStore keeps the rail (and MUSIC's own switch), the re-entry modal,
--     PARTY DOWN and the wall card's ZyntraShopBuy bridge. There is no other
--     shop: when this window cannot bind it says why (warn) and stays shut.
--
-- PAGES. Page_Shop is required. Any other Page_<Tab> binds when the import has
-- it; the 2026-10-07 bundle (Framewisp_Live_ZyntraBundle_L4) has all five. A
-- page an import lacks hides its dock tab and is warned once; the other pages
-- keep working. RECORDS and SETTINGS (owner-approved Figma, 2026-10-07) are
-- pages too, opened by the header buttons rather than a dock tab: a header page
-- the import lacks, or cannot bind, hides its button, warned once. Only the
-- chosen page is ever shown; any other Page_* (one this file does not know)
-- stays hidden.
--
-- TEXT. Framewisp writes fixed TextSizes solved for the editor viewport;
-- Binder.scaleText (a port of FramewispTextScaler) re-solves them for the
-- window's on-screen size, here and on every graft.
--
-- OPENING. The shop is live for everyone (go-live 2026-10-07; the old
-- ShopUIVersion switch is gone). ZyntraStore's rail and routes, and its
-- PlayerScripts.ZyntraOpenTerminal router, ask
-- PlayerScripts.ZyntraShopUIOpen:Invoke(tab); this answers true only when it
-- really opened (never yields). Invoke("close") closes the window and answers
-- false: the rail's window switch (2026-10-07). "Records" and "Settings" are
-- pages here; the legacy terminal they used to open is deleted.
--
-- DEVELOPERS (DevAccess, cosmetic: the server re-checks every dev remote and
-- EquipSkin) also get a DEV header button, one slot left of RECORDS, which
-- closes this window and asks PlayerScripts.ZyntraDevUIOpen:Invoke(true): the
-- lobby's dev-menu route on touch and gamepad, where there is no J. And the
-- Skins page grows a Signal Architect card, the developer suit's only equip
-- route since the legacy SKINS tab went.
--
-- MODAL CONTRACT. While open it publishes ZyntraStoreOpen (the name RoundUI,
-- FlashlightController, NoiseReporter, ProtectionHUD and UIDevice already
-- read), re-asserts it if another script clears it, suppresses touch movement
-- through the shared modal set, binds ButtonB, and never writes
-- ScreenGui.Enabled -- the Lucky Wheel takeover owns that. Show and hide go
-- through Root.Visible.
--
-- REGISTERS. All mutable state is in `ui`, every page lives in its own
-- do-block, so the main chunk stays far below Luau's 200-local ceiling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local Skins = require(ReplicatedStorage:WaitForChild("ZyntraSkins"))
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))

local TAB_ORDER = {"Upgrades", "Shop", "Skins", "Donate", "Colors"}
local HEADER_PAGES = {"Records", "Settings"} -- pages without a dock tab
-- Shop, Upgrades and Skins have no hint (owner 2026-10-07): their footers stay empty.
local TAB_HINTS = {
	Donate = "Donations have no gameplay effect. Thank you.",
	Colors = "Colors save to your profile and show in every level.",
}
local RAIL = {"ZyntraShopButton", "ZyntraOpenButton", "ZyntraRewardsButton", "ZyntraWheelButton", "ZyntraMusicButton"}
local CLOSE_ACTION = "ZyntraShopL4Close"
local ARTBOARD = Vector2.new(1920, 1080)
local SKIN_WAIT = 10

local ui = {open = false, built = false, bindFailed = false, tab = "Shop",
	session = {}, counts = {}, contract = {}, controls = {}, tabs = {}, pages = {},
	headers = {}, allPages = {}, -- headers: RECORDS / SETTINGS buttons; allPages: every Page_* in the import
	handlers = {}, hooked = {}} -- handlers: strong keys (a weak Instance key can be collected while the Instance lives)
local pages = {}

-- The bridge exists from the first frame and says no until the modules load,
-- so the routing hook can never wait on this script.
do
	local old = playerScripts:FindFirstChild("ZyntraShopUIOpen")
	if old then old:Destroy() end
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ZyntraShopUIOpen"
	bridge.OnInvoke = function(tab, focus)
		-- "close" (2026-10-07): ZyntraStore's rail closes this window before it opens
		-- another rail window. Synchronous, so the flag is clear when Invoke returns.
		if tab == "close" then
			if ui.setOpen then ui.setOpen(false) end
			return false
		end
		if not ui.openShop then return false end
		local ok, used = pcall(ui.openShop, tab, focus)
		if ok then return used == true end
		warn("[ZyntraShopUI] L4 open failed: " .. tostring(used))
		ui.bindFailed = true
		if ui.setOpen then pcall(ui.setOpen, false) end
		return false
	end
	bridge.Parent = playerScripts
end

local folder = ReplicatedStorage:WaitForChild("ZyntraShopUI", 30)
local binderModule = folder and folder:WaitForChild("ShopBinder", 10)
local dataModule = folder and folder:WaitForChild("ShopData", 10)
if not (binderModule and dataModule) then
	warn("[ZyntraShopUI] ReplicatedStorage.ZyntraShopUI (ShopBinder, ShopData) is not installed: the shop cannot open")
	return
end
local Binder = require(binderModule)
local ShopData = require(dataModule)
local P = Binder.Palette
ShopData.start()

-- -- small shared helpers --------------------------------------------------

local function commas(n)
	local text = tostring(math.max(0, math.floor(tonumber(n) or 0)))
	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

local function robuxText(n) return "R$ " .. commas(n) end

-- An authored length in artboard px, whatever unit Framewisp used.
local function px(dim, axisLength) return dim.Scale * axisLength + dim.Offset end

local function setButton(control, text, style, enabled)
	control.Price.Text = text
	Binder.style(control, style)
	UIDevice.SetEnabled(control.Hit, enabled == true)
	if control.Glyph then control.Glyph.Visible = style == "token" and tonumber(text) ~= nil end
end

-- The Robux button ladder shared by Shop, Donate, colour locks and paid skins.
-- `owned` is ShopData.owns(): nil means the server has not read that pass yet.
local function robuxCaption(key, owned, prefix)
	if not ShopData.ready() then return "LOADING", "off", false end
	if owned then return "OWNED", "owned", false end
	if owned == nil then return "CHECKING", "off", false end
	if ShopData.pending(key) then return "WAITING", "off", false end
	local price = ShopData.price(key)
	local state = price and price.State or "off"
	if state == "soon" then return "COMING SOON", "off", false end
	if state == "pending" then return "CHECKING PRICE", "off", false end
	if state ~= "live" then return "UNAVAILABLE", "off", false end
	return (prefix or "") .. robuxText(price.Price), "robux", ShopData.promptOpen() == nil
end

-- The token ladder: the design greys a short button (NEED n MORE) and the
-- server still refuses on its own.
local function tokenCaption(pendingKey, cost)
	if not ShopData.ready() then return "LOADING", "off", false end
	if ShopData.pending(pendingKey) then return "SAVING...", "off", false end
	local short = cost - ShopData.tokens()
	if short > 0 then return ("NEED %d MORE"):format(short), "off", false end
	return tostring(cost), "token", true
end

-- Every press goes through here: Activated runs `fn` while the hit is Active,
-- and the Studio probe's press: runs the very same `fn`.
function ui.onPress(hit, fn)
	ui.handlers[hit] = fn
	hit.Activated:Connect(function()
		if hit.Active then fn() end
	end)
end

-- A switch knob's two stops, from the import: the authored knob sits at one
-- end of its track and the other end is its mirror (RECORDS 6 / 38 on a 72 px
-- track, SETTINGS 6 / 58 on 112). Returns the function that moves it.
function ui.knob(knob)
	local centre = knob.Position.X.Scale + (0.5 - knob.AnchorPoint.X) * knob.Size.X.Scale
	local off = math.min(centre, 1 - centre)
	knob.AnchorPoint = Vector2.new(0.5, knob.AnchorPoint.Y)
	return function(on)
		knob.Position = UDim2.new(on and 1 - off or off, 0, knob.Position.Y.Scale, knob.Position.Y.Offset)
	end
end

-- One registration per bound control: the probe's `cards` list, the regression
-- lane's attribute, the press visuals, and the one place a press is routed.
local function wire(control, page, key, action, fn)
	local id = ("%s|%s|%s"):format(page, key, action)
	table.insert(ui.contract, id)
	table.insert(ui.controls, {Key = id, Control = control})
	control.Hit:SetAttribute("ZyntraShopL4Card", id)
	ui.onPress(control.Hit, fn)
	Binder.press(control.Hit, control.Face, control.Shadow)
	-- The bundle hid the Skins and Donate lists (Framewisp's inactive tab panels).
	Binder.reveal(control.Face, ui.pages[page])
end

function ui.renderCounts()
	local tokens = ShopData.tokens()
	for _, label in ipairs(ui.counts) do label.Text = tokens and tostring(tokens) or "--" end
end

function ui.render()
	if not ui.built or ui.bindFailed then return end
	for name, page in pairs(pages) do
		if ui.pages[name] then page.render() end
	end
	ui.renderPending()
end

-- -- SHOP ------------------------------------------------------------------
do
	local HERO = "ExpeditionPack"
	local cards = {}
	local function iconFor(key)
		local entry = (Config.Passes or {})[key] or (Config.Products or {})[key]
			or (((Config.TokenEarner or {}).Passes) or {})[key] or (Config.Items or {})[key]
		local id = type(entry) == "table" and tonumber(entry.IconId) or nil
		return id and id > 0 and ("rbxassetid://" .. math.floor(id)) or nil
	end
	ui.iconFor = iconFor

	pages.Shop = {
		bind = function(page, need, needControl)
			for _, key in ipairs(ShopData.SHOP) do
				local where = "Page_Shop/Card_" .. key
				local card = need(page, "Card_" .. key, "Page_Shop")
				local buy = card and needControl(card, "Buy", where)
				if buy then
					local hook = Binder.text(Binder.find(card, "Hook"))
					cards[key] = {Card = card, Buy = buy, Hook = hook, HookText = hook and hook.Text,
						Badge = Binder.find(card, "OwnedBadge"),
						BadgeText = Binder.text(Binder.find(card, "BadgeText"))}
					local icon, slot = iconFor(key), Binder.find(card, "ProductIcon")
					if icon and slot then
						Binder.image(slot).Image = icon
					else -- the import's art is one placeholder for all six cards
						warn(("[ZyntraShopUI] L4 %s shows the import placeholder: %s"):format(key,
							slot and "no IconId in ZyntraConfig" or "no ProductIcon in the card"))
					end
					wire(buy, "Shop", key, "Buy", function() ShopData.purchase(key) end)
				end
			end
			local scroll = Binder.find(page, "Products")
			if scroll and scroll:IsA("GuiObject") and not scroll:IsA("ScrollingFrame") then
				-- Framewisp may flatten _scroll to a Frame: the shelf would clip the
				-- last cards out of reach. Re-home its children in a real one.
				local shelf = Instance.new("ScrollingFrame")
				for _, prop in ipairs({"Name", "Size", "Position", "AnchorPoint", "ZIndex", "LayoutOrder",
					"BackgroundColor3", "BackgroundTransparency"}) do shelf[prop] = scroll[prop] end
				shelf.BorderSizePixel = 0
				shelf.CanvasSize = UDim2.new()
				for _, child in ipairs(scroll:GetChildren()) do child.Parent = shelf end
				shelf.Parent = scroll.Parent
				scroll:Destroy()
				scroll = shelf
			end
			if scroll and scroll:IsA("ScrollingFrame") then
				-- Owner decision for L4: the shelf scrolls horizontally.
				scroll.ScrollingDirection = Enum.ScrollingDirection.X
				if scroll.CanvasSize.X.Scale == 0 and scroll.CanvasSize.X.Offset == 0 then
					scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
				end
				ui.products = scroll
			end
		end,
		render = function()
			local tier = ShopData.earnerTier()
			for key, entry in pairs(cards) do
				local owned = ShopData.owns(key)
				setButton(entry.Buy, robuxCaption(key, owned, key == HERO and "BUY \u{B7} " or ""))
				if entry.Badge then entry.Badge.Visible = owned == true end
				if entry.BadgeText then entry.BadgeText.Text = key == "TokenEarner2x" and "ACTIVE" or "OWNED" end
				if entry.Hook and key == "TokenEarner2x" then
					-- 3x and 5x owners keep their multiplier; the card says which.
					entry.Hook.Text = tier and tier >= 2 and ("TOKEN EARNER %dx ACTIVE"):format(tier) or entry.HookText
				end
			end
		end,
	}

	function ui.scrollToCard(key)
		local scroll, entry = ui.products, cards[key]
		if not scroll or not entry or not ui.open then return end
		local x = scroll.CanvasPosition.X + entry.Card.AbsolutePosition.X - scroll.AbsolutePosition.X
		TweenService:Create(scroll, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CanvasPosition = Vector2.new(math.max(0, x), scroll.CanvasPosition.Y)}):Play()
	end
end

-- -- UPGRADES --------------------------------------------------------------
do
	local stats, supplies, shield = {}, {}, nil
	local SUPPLY_WORD = {SpeedPotion = "STORED", RouteMarker = "MARKERS"}

	pages.Upgrades = {
		bind = function(page, need, needControl)
			for _, stat in ipairs({"Stamina", "Battery"}) do
				local card = need(page, "Upgrade_" .. stat, "Page_Upgrades")
				local buy = card and needControl(card, "Buy", "Page_Upgrades/Upgrade_" .. stat)
				if buy then
					stats[stat] = {Buy = buy, Percent = Binder.text(Binder.find(card, "Percent")),
						Level = Binder.text(Binder.find(card, "LevelReadout"))}
					wire(buy, "Upgrades", stat, "Buy", function() ShopData.purchase(stat) end)
				end
			end
			local card = need(page, "Card_EntityShield", "Page_Upgrades")
			local buy = card and needControl(card, "Buy", "Page_Upgrades/Card_EntityShield")
			if buy then
				shield = {Buy = buy, Stored = Binder.text(Binder.find(card, "StoredCount"))}
				wire(buy, "Upgrades", "EntityShield", "Buy", function() ShopData.purchase("EntityShield") end)
			end
			for key in pairs(SUPPLY_WORD) do
				local supply = need(page, "Card_" .. key, "Page_Upgrades")
				local supplyBuy = supply and needControl(supply, "Buy", "Page_Upgrades/Card_" .. key)
				if supplyBuy then
					supplies[key] = {Buy = supplyBuy, Stored = Binder.text(Binder.find(supply, "StoredCount"))}
					local icon, slot = ui.iconFor(key), Binder.find(supply, "ProductIcon")
					if icon and slot then Binder.image(slot).Image = icon end
					wire(supplyBuy, "Upgrades", key, "Buy", function() ShopData.purchase(key) end)
				end
			end
		end,
		render = function()
			local ready, profile = ShopData.ready(), ShopData.profile()
			for stat, entry in pairs(stats) do
				local level = ready and math.max(0, math.floor(tonumber(profile[stat .. "Level"]) or 0)) or 0
				if entry.Percent then
					entry.Percent.Text = ready
						and ("+%d%%"):format(math.floor((tonumber(profile[stat .. "Percent"]) or 0) + 0.5)) or "--"
				end
				if entry.Level then entry.Level.Text = ready and ("LEVEL %d"):format(level) or "LEVEL --" end
				setButton(entry.Buy, tokenCaption(stat, Config.UpgradeCost(level)))
			end
			if shield then
				local state = ShopData.protection()
				local cost = tonumber(Config.ProtectionItem and Config.ProtectionItem.TokenCost) or 5
				if shield.Stored then shield.Stored.Text = ("OWNED %d"):format(tonumber(state.Charges) or 0) end
				if not ready then
					setButton(shield.Buy, "LOADING", "off", false)
				elseif state.Pending then
					-- ProtectionClient owns the request; RETRY only once it allows one.
					setButton(shield.Buy, state.CanRetry and "RETRY REQUEST" or "CONFIRMING...", state.CanRetry and "token" or "off", state.CanRetry)
				elseif not state.Available then
					setButton(shield.Buy, "UNAVAILABLE", "off", false)
				else
					setButton(shield.Buy, tokenCaption("EntityShield", cost))
				end
			end
			for key, entry in pairs(supplies) do
				local count = ready and type(profile.Items) == "table" and tonumber(profile.Items[key]) or 0
				if entry.Stored then entry.Stored.Text = ("%d %s"):format(count, SUPPLY_WORD[key]) end
				setButton(entry.Buy, tokenCaption(key, tonumber((Config.Items[key] or {}).TokenCost) or 0))
			end
		end,
	}
end

-- -- SKINS -----------------------------------------------------------------
do
	local cards, preview = {}, {}
	local selected = nil

	local function caption(skinId)
		local state = ShopData.skinState(skinId)
		if not state then return "LOADING", "off", false, "" end
		local item, pendingKey = state.Item, "Skin:" .. skinId
		if state.Owned then
			-- A bought suit's pass flips before the profile grant lands, and the
			-- server only equips what the profile owns.
			if ShopData.pending(pendingKey) or not state.Equippable then return "SAVING...", "off", false, "OWNED" end
			if state.Equipped then return "EQUIPPED", "off", false, "OWNED" end
			return "EQUIP", "equip", true, "OWNED"
		end
		if item.Kind == "Tokens" then
			local cost, required = tonumber(item.TokenCost) or 0, tonumber(item.RequiredClears) or 0
			local meta = required > 0 and ("%d TOKENS \u{B7} %d/%d CLEARS"):format(cost, state.Clears, required)
				or ("%d TOKENS"):format(cost)
			if not ShopData.pending(pendingKey) and state.Clears < required then
				return ("%d/%d CLEARS"):format(state.Clears, required), "off", false, meta
			end
			local text, style, enabled = tokenCaption(pendingKey, cost)
			return text, style, enabled, meta
		end
		if item.Kind == "Robux" then
			local text, style, enabled = robuxCaption(skinId, ShopData.owns(skinId))
			return text, style, enabled, "PREMIUM SUIT"
		end
		return "UNAVAILABLE", "off", false, "DEVELOPER ONLY"
	end

	local function renderPreview()
		local skinId = selected
		if not skinId then
			local profile = ShopData.profile()
			local equipped = type(profile) == "table" and type(profile.Skins) == "table" and profile.Skins.Equipped
			skinId = cards[equipped] and equipped or Skins.DefaultId
		end
		local item, entry = Skins.ById[skinId], cards[skinId]
		if not item or not entry then return end
		if preview.Art then preview.Art.Image = "rbxassetid://" .. tostring(item.PreviewImageId) end
		if preview.Name then preview.Name.Text = string.upper(item.Name) end
		if preview.Status then
			local state = ShopData.skinState(skinId)
			-- The suit only renders in rounds (HazmatSkinVisuals), so say so.
			preview.Status.Text = state and state.Equipped and "EQUIPPED \u{B7} WORN IN YOUR NEXT RUN"
				or (entry.Meta and entry.Meta.Text or "")
		end
	end

	-- The developer suit has no card in the import, so a developer gets one,
	-- cloned from the last card into one more grid row. Skins.SyncDeveloper owns
	-- the grant and ZyntraMonetization refuses EquipSkin for it without
	-- DevAccess, so the card adds no power. Returns whether the card exists.
	local DEV_SUIT = "SignalArchitect"
	local function addDevCard(page, fromId)
		local source = Binder.find(page, "SkinCard_" .. fromId)
		if not source then return false end -- bind's need() reports it
		local cells = source.Parent
		local grid = cells:FindFirstChildOfClass("UIGridLayout")
		local scroll = source:FindFirstAncestorWhichIsA("ScrollingFrame")
		local size, pad = grid and grid.CellSize, grid and grid.CellPadding
		if not (scroll and size and size.X.Scale > 0 and size.Y.Scale > 0 and Binder.text(Binder.find(source, "Name"))) then
			warn("[ZyntraShopUI] L4 developer suit card skipped: Page_Skins/SkinCard_" .. fromId
				.. " is not a Name-labelled cell of a Scale grid in a ScrollingFrame")
			return false
		end
		local count = 0
		for _, child in ipairs(cells:GetChildren()) do
			if child:IsA("GuiObject") then count += 1 end
		end
		local columns = math.max(1, math.floor((1 + pad.X.Scale) / (size.X.Scale + pad.X.Scale) + 1e-6))
		local rows = math.ceil((count + 1) / columns)
		-- The cells are Scale of the canvas: a taller canvas shrinks them back to size.
		local grow = math.max(1, rows * size.Y.Scale + (rows - 1) * pad.Y.Scale)
		local canvas = scroll.CanvasSize
		scroll.CanvasSize = UDim2.new(canvas.X.Scale, canvas.X.Offset, canvas.Y.Scale * grow, canvas.Y.Offset)
		grid.CellSize = UDim2.fromScale(size.X.Scale, size.Y.Scale / grow)
		grid.CellPadding = UDim2.fromScale(pad.X.Scale, pad.Y.Scale / grow)
		-- Size is the grid's anyway; matching it keeps Binder.designSize true for the new text.
		for _, child in ipairs(cells:GetChildren()) do
			if child:IsA("GuiObject") then child.Size = grid.CellSize end
		end
		local card = source:Clone()
		card.Name = "SkinCard_" .. DEV_SUIT
		card.LayoutOrder = source.LayoutOrder + 1
		card.Size = grid.CellSize
		card.Parent = cells
		Binder.text(Binder.find(card, "Name")).Text = Skins.ById[DEV_SUIT].Name
		return true
	end

	pages.Skins = {
		bind = function(page, need, needControl)
			local ids = table.clone(ShopData.SKINS)
			if DevAccess.IsAllowed(player) and addDevCard(page, ids[#ids]) then table.insert(ids, DEV_SUIT) end
			for _, skinId in ipairs(ids) do
				local card = need(page, "SkinCard_" .. skinId, "Page_Skins")
				local buy = card and needControl(card, "Buy", "Page_Skins/SkinCard_" .. skinId)
				local item = Skins.ById[skinId]
				if buy and item then
					cards[skinId] = {Buy = buy, Meta = Binder.text(Binder.find(card, "Meta")),
						Badge = Binder.find(card, "EquippedBadge")}
					local art = Binder.find(card, "SkinArt")
					if art then Binder.image(art).Image = "rbxassetid://" .. tostring(item.PreviewImageId) end
					wire(buy, "Skins", skinId, "Buy", function()
						selected = skinId
						ShopData.purchase("Skin", skinId)
					end)
					-- The card itself selects; its hit sits UNDER Buy (ZIndex 0).
					Binder.button(card, "SelectHit", 0).Activated:Connect(function()
						selected = skinId
						renderPreview()
					end)
				end
			end
			local art = Binder.find(page, "PreviewArt")
			preview.Art = art and Binder.image(art)
			preview.Name = Binder.text(Binder.find(page, "PreviewName"))
			preview.Status = Binder.text(Binder.find(page, "PreviewStatus"))
		end,
		render = function()
			for skinId, entry in pairs(cards) do
				local text, style, enabled, meta = caption(skinId)
				setButton(entry.Buy, text, style, enabled)
				if entry.Meta then entry.Meta.Text = meta end
				if entry.Badge then
					local state = ShopData.skinState(skinId)
					entry.Badge.Visible = state ~= nil and state.Equipped
				end
			end
			renderPreview()
		end,
	}
end

-- -- DONATE ----------------------------------------------------------------
do
	local tiers, readout = {}, {}
	pages.Donate = {
		bind = function(page, need, needControl)
			for _, key in ipairs(ShopData.DONATE) do
				local card = need(page, "Donate_" .. key, "Page_Donate")
				local buy = card and needControl(card, "Buy", "Page_Donate/Donate_" .. key)
				if buy then
					tiers[key] = buy
					wire(buy, "Donate", key, "Buy", function() ShopData.purchase(key) end)
				end
			end
			readout.Total = Binder.text(Binder.find(page, "SupportTotal"))
			readout.Breakdown = Binder.text(Binder.find(page, "SupportBreakdown"))
			readout.Badge = Binder.find(page, "Support20K")
			-- "Purchases before 2 Sep 2026 are not recorded." is gone (owner 2026-10-07);
			-- Figma hides it too, so a later import does not bring it back.
			local note = Binder.find(page, "SupportNote")
			if note and note:IsA("GuiObject") then note.Visible = false end
		end,
		render = function()
			local profile = ShopData.ready() and ShopData.profile() or {}
			local total = tonumber(profile.RecordedSupportRobux) or tonumber(profile.DonationRobux) or 0
			if readout.Total then readout.Total.Text = ("RECORDED SUPPORT %s R$"):format(commas(total)) end
			if readout.Breakdown then
				readout.Breakdown.Text = ("Donations %s R$ \u{B7} Products %s R$ \u{B7} Passes %s R$"):format(
					commas(profile.DonationRobux), commas(profile.UtilityRobux), commas(profile.PassRobux))
			end
			-- Recognition only: the 20K pass is no longer sold, owners keep the badge.
			if readout.Badge then readout.Badge.Visible = ShopData.owns20K() == true end
			for key, buy in pairs(tiers) do setButton(buy, robuxCaption(key, false)) end
		end,
	}
end

-- -- COLORS ----------------------------------------------------------------
do
	local pickers = {}
	local drag = nil
	local SAT_MAX, VAL_MIN = 0.9, 0.35  -- the old terminal's clamps: H 0..1, S 0..0.9, V 0.35..1

	local function clampHSV(h, s, v)
		return math.clamp(h, 0, 1), math.clamp(s, 0, SAT_MAX), math.clamp(v, VAL_MIN, 1)
	end

	local function seed(entry)
		local profile = ShopData.profile()
		local color = type(profile) == "table" and profile[entry.Picker .. "Color"] or nil
		if typeof(color) ~= "Color3" then color = (Config.Colors or {})[entry.Picker .. "Default"] end
		if typeof(color) == "Color3" then entry.H, entry.S, entry.V = clampHSV(color:ToHSV()) end
	end

	-- Fraction 0..1 along each track.
	local function fraction(entry, channel)
		if channel == "H" then return entry.H end
		if channel == "S" then return entry.S / SAT_MAX end
		return (entry.V - VAL_MIN) / (1 - VAL_MIN)
	end

	local function paint(entry)
		local color = Color3.fromHSV(entry.H, entry.S, entry.V)
		if entry.Swatch then entry.Swatch.BackgroundColor3 = color end
		for channel, slider in pairs(entry.Sliders) do
			local f = fraction(entry, channel)
			local track, knob = slider.Track, slider.Knob
			local left = UDim.new(track.Position.X.Scale - track.AnchorPoint.X * track.Size.X.Scale,
				track.Position.X.Offset - track.AnchorPoint.X * track.Size.X.Offset)
			knob.Position = UDim2.new(left.Scale + f * track.Size.X.Scale, math.floor(left.Offset + f * track.Size.X.Offset),
				knob.Position.Y.Scale, knob.Position.Y.Offset)
			if slider.Value then
				slider.Value.Text = channel == "H" and ("%d\u{B0}"):format(math.floor(entry.H * 360 + 0.5))
					or ("%d%%"):format(math.floor((channel == "S" and entry.S or entry.V) * 100 + 0.5))
			end
			if slider.Gradient and channel ~= "H" then
				track.BackgroundColor3 = Color3.new(1, 1, 1) -- a UIGradient multiplies the fill
				slider.Gradient.Color = channel == "S"
					and ColorSequence.new(Color3.fromHSV(entry.H, 0, entry.V), Color3.fromHSV(entry.H, SAT_MAX, entry.V))
					or ColorSequence.new(Color3.fromHSV(entry.H, entry.S, VAL_MIN), Color3.fromHSV(entry.H, entry.S, 1))
			end
		end
	end

	function ui.stopDrag()
		if not drag then return end
		for _, connection in ipairs(drag.Connections) do connection:Disconnect() end
		drag = nil
	end

	local function dragTo(x)
		local track = drag.Slider.Track
		local f = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		local entry = drag.Entry
		if drag.Channel == "H" then entry.H = f
		elseif drag.Channel == "S" then entry.S = f * SAT_MAX
		else entry.V = VAL_MIN + f * (1 - VAL_MIN) end
		paint(entry)
	end

	local function beginDrag(entry, channel, input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
		if not ui.open or ShopData.owns(entry.Pass) ~= true then return end
		ui.stopDrag()
		drag = {Entry = entry, Channel = channel, Slider = entry.Sliders[channel], Input = input, Connections = {}}
		dragTo(input.Position.X)
		table.insert(drag.Connections, UserInputService.InputChanged:Connect(function(moved)
			if drag and (moved.UserInputType == Enum.UserInputType.MouseMovement or moved == drag.Input) then
				dragTo(moved.Position.X)
			end
		end))
		table.insert(drag.Connections, UserInputService.InputEnded:Connect(function(ended)
			if drag and (ended.UserInputType == Enum.UserInputType.MouseButton1 or ended == drag.Input) then
				ui.stopDrag()
			end
		end))
	end

	function ui.seedColors()
		for _, entry in pairs(pickers) do
			if not ShopData.pending("Color:" .. entry.Picker) then seed(entry); paint(entry) end
		end
	end

	pages.Colors = {
		bind = function(page, need, needControl)
			for picker, pass in pairs(ShopData.PICKERS) do
				local where = "Page_Colors/Picker_" .. picker
				local node = need(page, "Picker_" .. picker, "Page_Colors")
				if node then
					local entry = {Picker = picker, Pass = pass, H = 0, S = 0, V = 1, Sliders = {},
						Swatch = Binder.find(node, "Swatch"),
						Subtitle = Binder.text(Binder.find(node, "Subtitle")),
						Save = needControl(node, "Save", where, "SaveText"),
						Lock = need(node, "Lock", where)}
					entry.GetPass = entry.Lock and needControl(entry.Lock, "GetPass", where .. "/Lock")
					for _, channel in ipairs({"H", "S", "V"}) do
						local slider = need(node, "Slider_" .. channel, where)
						local track = slider and need(slider, "Track", where .. "/Slider_" .. channel)
						local knob = slider and need(slider, "Knob", where .. "/Slider_" .. channel)
						if track and knob then
							knob.AnchorPoint = Vector2.new(0.5, knob.AnchorPoint.Y)
							entry.Sliders[channel] = {Track = track, Knob = knob,
								Value = Binder.text(Binder.find(slider, "Value")),
								Gradient = track:FindFirstChildOfClass("UIGradient")}
							-- The whole slider row is the hit area (>= 122 artboard px tall).
							Binder.button(slider, "Hit").InputBegan:Connect(function(input)
								beginDrag(entry, channel, input)
							end)
						end
					end
					for _, preset in pairs(Binder.all(node, "Preset_")) do
						-- The bundle paints the swatch on a "Color" child; the button face is grey.
						local swatch = Binder.find(preset, "Color") or preset
						Binder.button(preset).Activated:Connect(function()
							if ShopData.owns(pass) ~= true then return end
							entry.H, entry.S, entry.V = clampHSV(swatch.BackgroundColor3:ToHSV())
							paint(entry)
						end)
					end
					if entry.Save then
						wire(entry.Save, "Colors", picker, "Save", function()
							ShopData.purchase("Color", {Picker = picker, Color = Color3.fromHSV(entry.H, entry.S, entry.V)})
						end)
					end
					if entry.GetPass then
						wire(entry.GetPass, "Colors", picker, "GetPass", function() ShopData.purchase(pass) end)
					end
					pickers[picker] = entry
				end
			end
		end,
		render = function()
			local ready = ShopData.ready()
			for picker, entry in pairs(pickers) do
				local owned = ShopData.owns(entry.Pass) == true
				if entry.Lock then
					-- An input shield over the picker while the pass is not owned.
					entry.Lock.Visible = ready and not owned
					entry.Lock.Active = entry.Lock.Visible
				end
				if entry.Subtitle then
					local item = ShopData.item(entry.Pass)
					entry.Subtitle.Text = ("%s \u{B7} %s"):format(string.upper(item and item.Name or entry.Pass),
						not ready and "--" or owned and "OWNED" or "REQUIRED")
				end
				if entry.GetPass then setButton(entry.GetPass, robuxCaption(entry.Pass, ShopData.owns(entry.Pass), "BUY \u{B7} ")) end
				if entry.Save then
					if not ready then
						setButton(entry.Save, "LOADING", "off", false)
					elseif ShopData.pending("Color:" .. picker) then
						setButton(entry.Save, "SAVING...", "off", false)
					else
						-- Under the lock it says why it is disabled (UIRegression reads the caption).
						setButton(entry.Save, owned and "SAVE COLOR" or "LOCKED", owned and "equip" or "off", owned)
					end
				end
				if not entry.Seeded and ready then
					entry.Seeded = true
					seed(entry)
				end
				paint(entry)
			end
		end,
	}
end

-- -- RECORDS ---------------------------------------------------------------
-- Read-only: personal bests and challenge flags from the public profile
-- (Records, Challenges), which ZyntraMonetization writes inside the transaction
-- that pays the clear; ZyntraChallenges.Rows is the server's own ledger shape,
-- and an older server (neither field) reads as "no record, nothing done". The
-- one control, SHOW ASSISTED, only picks which half is drawn: client-local, for
-- the session, kept across pushes, and it sends nothing.
do
	local Challenges = require(ReplicatedStorage:WaitForChild("ZyntraChallenges"))
	local settings = Config.Challenges
	local DASH = "\u{2014}"
	local intro, cards, showAssisted = {}, {}, false

	local function tokens(amount)
		local count = math.max(0, math.floor(tonumber(amount) or 0))
		return "+" .. count .. (count == 1 and " TOKEN" or " TOKENS")
	end

	-- A level in HiddenUntilPlayed (empty since Level 4 went public) shows its card
	-- once the profile has progress there: a clear, a record or a finished challenge.
	local function played(profile, row)
		local cleared = type(profile.LevelsCleared) == "table" and profile.LevelsCleared[tostring(row.Level)] == true
		return cleared or row.NoDeath or row.TimeGoalDone or next(row.Records) ~= nil
	end

	-- The reward is always shown; the chip says DONE (paid) or NOT YET.
	local function paintGoal(goal, name, done, reward)
		goal.Name.Text = name
		goal.Reward.Text = tokens(reward)
		goal.Reward.TextColor3 = done and P.Sage or P.IconTeal
		goal.State.BackgroundColor3 = done and P.RailTeal or P.TileHi
		goal.Label.Text = done and "DONE" or "NOT YET"
		goal.Label.TextColor3 = done and P.Tile or P.Sage
	end

	pages.Records = {
		bind = function(page, need, needText)
			local toggle = need(page, "ShowAssisted", "Page_Records")
			local track = toggle and need(toggle, "Track", "ShowAssisted")
			local knob = track and need(track, "Knob", "ShowAssisted/Track")
			intro = {Eyebrow = needText(page, "Eyebrow", "Page_Records"), Face = toggle, Track = track, Knob = knob,
				Slide = knob and ui.knob(knob), Ring = track and track:FindFirstChildOfClass("UIStroke"),
				Stroke = toggle and toggle:FindFirstChildOfClass("UIStroke")}
			intro.Width = intro.Stroke and intro.Stroke.Thickness
			-- Framewisp centres every hug text in its box, and this one is sized
			-- for ASSISTED RUNS: CLEAN RUNS sat 27 design px right of the title.
			-- Left keeps it flush with RECORDS (fitLine still widens it rightwards).
			if intro.Eyebrow then intro.Eyebrow.TextXAlignment = Enum.TextXAlignment.Left end
			if toggle then
				ui.onPress(Binder.button(toggle), function()
					if not ui.pages.Records then return end
					showAssisted = not showAssisted
					pages.Records.render()
				end)
			end
			local list = need(page, "RecordsList", "Page_Records")
			if list and list:IsA("ScrollingFrame") then list.ScrollingDirection = Enum.ScrollingDirection.Y end
			-- A card for a level the data does not have stays hidden.
			for suffix, card in pairs(Binder.all(page, "Record_Level")) do
				if not table.find(settings.Levels, tonumber(suffix)) then card.Visible = false end
			end
			for _, level in ipairs(settings.Levels) do
				local where = "Record_Level" .. level
				local card = need(page, where, "Page_Records")
				if card then
					local entry = {Card = card, Title = needText(card, "Title", where), Times = {}, Goals = {}}
					for _, mode in ipairs({"Solo", "Party"}) do
						entry.Times[string.lower(mode)] = {Time = needText(card, mode .. "Time", where),
							Badge = need(card, mode .. "Badge", where)}
					end
					for index, kind in ipairs({"NoDeath", "TimeGoal"}) do
						local at = where .. "/Challenge" .. index
						local chip = need(card, "Challenge" .. index, where)
						local state = chip and need(chip, "State", at)
						entry.Goals[kind] = {Chip = chip, Name = chip and needText(chip, "Name", at),
							Reward = chip and needText(chip, "Reward", at), State = state,
							Label = state and needText(state, "Label", at .. "/State")}
					end
					cards[level] = entry
				end
			end
		end,
		render = function()
			local profile = ShopData.profile()
			profile = type(profile) == "table" and profile or {}
			local on, view = showAssisted, showAssisted and "assisted" or "clean"
			intro.Eyebrow.Text = on and "ASSISTED RUNS" or "CLEAN RUNS"
			-- The dev menu's toggle (BINDINGS.md): the face, the track and the knob.
			intro.Face.BackgroundColor3 = on and P.OwnedFill or P.TileHi
			if intro.Stroke then
				intro.Stroke.Color = on and P.RailTeal or P.Line
				intro.Stroke.Thickness = on and intro.Width * 4 / 3 or intro.Width
			end
			intro.Track.BackgroundColor3 = on and P.RailTeal or P.Ink
			if intro.Ring then intro.Ring.Color, intro.Ring.Enabled = P.Sage, not on end
			intro.Knob.BackgroundColor3 = on and P.Ink or P.Sage
			intro.Slide(on)
			for _, row in ipairs(Challenges.Rows(profile.Records, profile.Challenges, settings)) do
				local entry = cards[row.Level]
				entry.Card.Visible = not table.find(settings.HiddenUntilPlayed or {}, row.Level) or played(profile, row)
				entry.Title.Text = "LEVEL " .. row.Level
				for mode, line in pairs(entry.Times) do
					local record = row.Records[mode .. ":" .. view]
					line.Time.Text = record and Challenges.FormatTime(record.Best) or DASH
					line.Time.TextColor3 = record and P.Cream or P.Sage
					line.Badge.Visible = record ~= nil and record.Equipped == true
				end
				paintGoal(entry.Goals.NoDeath, "NO DEATHS", row.NoDeath, settings.RewardTokens.NoDeath)
				local goal = entry.Goals.TimeGoal
				goal.Chip.Visible = row.TimeGoal ~= nil
				if row.TimeGoal then
					paintGoal(goal, "UNDER " .. Challenges.FormatTime(row.TimeGoal), row.TimeGoalDone,
						settings.RewardTokens.TimeGoal)
				end
			end
		end,
	}
end

-- -- SETTINGS --------------------------------------------------------------
-- One row per ZyntraConfig.AccessibilitySettings entry that is not Hidden
-- (DisableCaptions has none), found by its exact Key: Setting_<Key>. The whole
-- row is the toggle; ShopData sends it, holds it and reads it back from the
-- attribute the server publishes. Only State, Track and Knob carry the state.
do
	local rows = {}
	local SWITCH_OFF = Color3.fromRGB(48, 60, 64) -- #303C40, the OFF track (BINDINGS.md)
	pages.Settings = {
		bind = function(page, need, needText)
			for _, entry in ipairs(Config.AccessibilitySettings or {}) do
				if entry.Hidden ~= true then
					local key, where = entry.Key, "Setting_" .. entry.Key
					local row = need(page, where, "Page_Settings")
					local hit = row and need(row, "Toggle_" .. key, where)
					local track = row and need(row, "Track", where)
					local knob = track and need(track, "Knob", where .. "/Track")
					rows[key] = {Entry = entry, Hit = hit and Binder.button(hit), Track = track, Knob = knob,
						Slide = knob and ui.knob(knob), Title = row and needText(row, "Title", where),
						Desc = row and needText(row, "Desc", where), State = row and needText(row, "State", where)}
					if hit then ui.onPress(rows[key].Hit, function() ShopData.toggleSetting(key) end) end
				end
			end
		end,
		render = function()
			for key, row in pairs(rows) do
				local on = ShopData.setting(key)
				row.Title.Text, row.Desc.Text = row.Entry.Label, row.Entry.Description
				row.State.Text = on and "ON" or "OFF"
				row.State.TextColor3 = on and P.RailTeal or P.Sage
				row.Track.BackgroundColor3 = on and P.RailTeal or SWITCH_OFF
				row.Knob.BackgroundColor3 = on and P.Cream or P.Sage
				row.Slide(on)
				-- Lobby music stands down until the server has published it.
				UIDevice.SetEnabled(row.Hit, ShopData.settingReady(key))
			end
		end,
	}
end

-- -- status line, toast, "waiting for Roblox" ------------------------------
do
	local statusSerial, toastSerial, messageActive = 0, 0, false
	local TONE = {success = P.RailTeal, error = P.Coral, info = P.IconTeal}

	function ui.showHint()
		if ui.status and not messageActive then
			ui.status.Text = TAB_HINTS[ui.tab] or ""
			ui.status.TextColor3 = P.Sage
		end
	end

	function ui.showMessage(text, tone)
		if not ui.built or ui.bindFailed or type(text) ~= "string" or text == "" then return end
		statusSerial += 1
		local mine = statusSerial
		messageActive = true
		if ui.status then
			ui.status.Text = text
			ui.status.TextColor3 = tone == "error" and P.Coral or tone == "success" and P.RailTeal or P.Sage
		end
		task.delay(6, function()
			if statusSerial == mine then messageActive = false; ui.showHint() end
		end)
		if ui.toast and ui.open then
			toastSerial += 1
			local toastMine = toastSerial
			ui.toast.Visible = true
			if ui.toastText then ui.toastText.Text = text end
			if ui.toastAccent then ui.toastAccent.BackgroundColor3 = TONE[tone] or P.IconTeal end
			task.delay(tone == "error" and 3.5 or 2.4, function()
				if toastSerial == toastMine and ui.toast then ui.toast.Visible = false end
			end)
		end
	end

	function ui.hideToast()
		toastSerial += 1
		if ui.toast then ui.toast.Visible = false end
		if ui.pendingPanel then ui.pendingPanel.Visible = false end
	end

	function ui.renderPending()
		local panel = ui.pendingPanel
		if not panel then return end
		local key = ShopData.promptOpen()
		panel.Visible = ui.open and key ~= nil
		local item, price = key and ShopData.item(key), key and ShopData.price(key)
		if item and ui.pendingText then
			ui.pendingText.Text = ("%s \u{B7} %s. Confirm in the Roblox window."):format(
				item.Name, robuxText(price and price.Price or item.Price))
		end
	end
end

-- -- tabs, open, close -----------------------------------------------------

function ui.selectTab(name)
	if not ui.pages[name] then return end
	ui.tab = name
	-- Every Page_* of the import, known or not: only the chosen one shows.
	for _, page in pairs(ui.allPages) do page.Visible = page == ui.pages[name] end
	for tab, entry in pairs(ui.tabs) do
		local active = tab == name
		if entry.Bar then entry.Bar.Visible = active end
		entry.Node.BackgroundTransparency = active and 0 or 1
		if active then entry.Node.BackgroundColor3 = P.Tile end
		if entry.Stroke then entry.Stroke.Color = P.RailTeal; entry.Stroke.Enabled = active end
		if entry.Label then entry.Label.TextColor3 = active and P.Cream or P.Sage end
	end
	-- RECORDS / SETTINGS wear the dock tab's look while their page is up.
	for tab, entry in pairs(ui.headers) do
		local active = tab == name
		if entry.Bar then entry.Bar.Visible = active end
		entry.Node.BackgroundColor3 = active and P.Tile or entry.Fill
		entry.Node.BackgroundTransparency = active and 0 or entry.Alpha
		if entry.Stroke then
			entry.Stroke.Color = active and P.RailTeal or entry.Line
			entry.Stroke.Thickness = active and entry.Width * 4 / 3 or entry.Width
		end
	end
	ui.showHint()
	ui.render()
end

function ui.focus()
	if not ui.open or UIDevice.LastInput() ~= "Gamepad" or GuiService.MenuIsOpen then return end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(ui.root) then return end
	local tab = ui.tabs[ui.tab] or ui.headers[ui.tab] -- a header page has no dock tab
	if tab then GuiService.SelectedObject = tab.Hit end
end

function ui.setOpen(open)
	open = open == true
	if ui.open == open or not ui.root then return end
	ui.open = open
	ui.root.Visible = open
	player:SetAttribute("ZyntraStoreOpen", open or nil)
	-- Shared suppression: derive it from the whole modal set, as ZyntraStore does.
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	if open then
		ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
			if not ui.open or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
			if inputState == Enum.UserInputState.Begin then ui.setOpen(false) end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		table.insert(ui.session, UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.Escape then ui.setOpen(false) end
		end))
		table.insert(ui.session, UserInputService.LastInputTypeChanged:Connect(function()
			task.defer(ui.focus)
		end))
		ui.seedColors()
		ui.render()
		task.defer(ui.focus)
	else
		ContextActionService:UnbindAction(CLOSE_ACTION)
		for _, connection in ipairs(ui.session) do connection:Disconnect() end
		table.clear(ui.session)
		ui.stopDrag()
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(ui.root) then GuiService.SelectedObject = nil end
		ui.hideToast()
	end
	ui.refreshPill()
end

-- Fit the WINDOW (not the artboard) into ModalViewport: about 6% more scale
-- than fitting the whole 1920x1080 composition. On touch the window also takes
-- ModalViewport's 8 px above and below (the safe area's full height): a phone
-- landscape window is height-bound, and at 844x390 that lifts a 136 artboard px
-- tap target from 42.3 px (316 tall) to 44.4 px (332 tall). Pointer layouts are
-- unchanged.
-- PC (a pointer layout that is not a TV) shows the window at HALF that size,
-- centred (owner 2026-10-07: "Pc ui skal bare skaleres ned med 50%"), never
-- under PC_MIN_HEIGHT px tall so a small game window keeps readable text.
local PC_SCALE, PC_MIN_HEIGHT = 0.5, 400
function ui.fit()
	if not ui.holder then return end
	local layout = UIDevice.Layout()
	local area = layout.ModalViewport
	local left, top, width, height = area.Left, area.Top, area.Width, area.Height
	if layout.IsTouch then
		top, height = layout.Safe.Top, layout.Safe.Bottom - layout.Safe.Top
	elseif not GuiService:IsTenFootInterface() then
		-- The floor is on the WINDOW: in a viewport narrower than the window's aspect
		-- (5:4, 1024x768) the window is width-bound and shorter than the holder.
		local fitH = math.min(height, width * ui.design.Y / ui.design.X)
		local scale = math.min(1, math.max(PC_SCALE, PC_MIN_HEIGHT / math.max(1, fitH)))
		left, top = left + width * (1 - scale) / 2, top + height * (1 - scale) / 2
		width, height = width * scale, height * scale
	end
	-- The lobby rail stays up over this window (2026-10-07): start 8 px right of its
	-- edge. ZyntraStore publishes ZyntraRailRight in Layout() space; nil in a round.
	local railRight = player:GetAttribute("ZyntraRailRight")
	if type(railRight) == "number" and left < railRight + 8 then
		width, left = width - (railRight + 8 - left), railRight + 8
	end
	ui.holder.Position = UIDevice.LocalPosition(ui.gui, left, top)
	ui.holder.Size = UDim2.fromOffset(width, height)
end

-- DEV: a copy of SETTINGS one slot left of RECORDS, labelled DEV. The dev
-- menu never opens over a screen-owning modal, so this window closes first
-- (setOpen clears ZyntraStoreOpen synchronously). Its refusal is final.
function ui.addDevButton(window)
	local records, settings = Binder.find(window, "Records"), Binder.find(window, "Settings")
	if not (records and settings) then
		warn("[ZyntraShopUI] L4 DEV button skipped: ShopWindow Records or Settings is missing,"
			.. " so the dev menu has no lobby route on touch or gamepad")
		return
	end
	local dev = settings:Clone()
	dev.Name = "DevMenu"
	for _, child in ipairs(dev:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local x, step = records.Position.X, settings.Position.X.Scale - records.Position.X.Scale
	dev.Position = UDim2.new(x.Scale - step, x.Offset, records.Position.Y.Scale, records.Position.Y.Offset)
	local label = Instance.new("TextLabel")
	label.Name = "DevLabel"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.7, 0.42)
	label.ZIndex = dev.ZIndex
	label.Text = "DEV"
	label.TextScaled = true
	label.TextColor3 = P.Cream
	-- Scoped to Header: the RECORDS / SETTINGS pages hold Title nodes as well.
	local title = Binder.text(Binder.find(Binder.find(window, "Header") or window, "Title"))
	if title then label.FontFace = title.FontFace end
	label.Parent = dev
	dev.Parent = settings.Parent
	ui.onPress(Binder.button(dev), function()
		local bridge = playerScripts:FindFirstChild("ZyntraDevUIOpen")
		if bridge and bridge:IsA("BindableFunction") then
			ui.setOpen(false)
			pcall(bridge.Invoke, bridge, true)
		else
			warn("[ZyntraShopUI] DEV cannot open: PlayerScripts.ZyntraDevUIOpen (Zyntra Dev L4) is missing")
		end
	end)
end

-- RECORDS and SETTINGS: pages opened by their header buttons, not by a dock
-- tab. Not purchase-critical: a page the import lacks, or cannot bind, hides
-- its button, and every such loss is warned once. The active look is the dock
-- tab's (BINDINGS.md): TILE fill, the resting 3 px ring turned teal at 4 px, and
-- Tab_Shop's ActiveBar lent at 112 x 8 on the 144 button, 4 px off its bottom.
function ui.bindHeaderPages(window, foundPages)
	local header = Binder.find(window, "Header") or window
	local lostPages = {}
	for _, name in ipairs(HEADER_PAGES) do
		local node, button, lost = foundPages[name], Binder.find(header, name), {}
		local function need(scope, path, where)
			local found = scope and Binder.at(scope, path)
			if not found then table.insert(lost, (where and (where .. "/") or "") .. path) end
			return found
		end
		local function needText(scope, path, where)
			local text = Binder.text(scope and Binder.at(scope, path))
			if not text then table.insert(lost, (where and (where .. "/") or "") .. path) end
			return text
		end
		if node and button then pages[name].bind(node, need, needText) end
		if node and button and #lost == 0 then
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local entry = {Node = button, Hit = Binder.button(button), Stroke = stroke, Fill = button.BackgroundColor3,
				Alpha = button.BackgroundTransparency, Line = stroke and stroke.Color, Width = stroke and stroke.Thickness}
			local bar = ui.tabs.Shop and ui.tabs.Shop.Bar
			if bar then
				entry.Bar = bar:Clone()
				entry.Bar.AnchorPoint = Vector2.new(0.5, 0.5)
				entry.Bar.Size = UDim2.fromScale(112 / 144, 8 / 144)
				entry.Bar.Position = UDim2.fromScale(0.5, 136 / 144)
				entry.Bar.Visible = false
				entry.Bar.Parent = button
			end
			ui.pages[name], ui.headers[name] = node, entry
			ui.onPress(entry.Hit, function() ui.selectTab(name) end)
		else
			if button then button.Visible = false end
			table.insert(lostPages, not node and name or not button and (name .. " (no header button)")
				or ("%s (%s)"):format(name, table.concat(lost, ", ")))
		end
	end
	if #lostPages > 0 then
		warn("[ZyntraShopUI] L4 header pages missing, their buttons are hidden: " .. table.concat(lostPages, ", "))
	end
end

-- The token +, in the lobby pill and the window header alike: "a bit smaller"
-- (owner, 2026-10-07), then "still too big" (0.8 -> 0.6). The face and glyph
-- draw at this scale, right-aligned and centred; AddTokens keeps the imported
-- size and stays the tap target, so touch keeps its 44 px.
local PLUS_SCALE = 0.6
function ui.shrinkPlus(add, hit)
	local face = Instance.new("Frame")
	face.Name = "PlusFace"
	face.BackgroundColor3 = add.BackgroundColor3
	face.BorderSizePixel = 0
	face.AnchorPoint = Vector2.new(1, 0.5) -- UIScale shrinks toward this point
	face.Position = UDim2.fromScale(1, 0.5)
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = add.ZIndex
	local shrink = Instance.new("UIScale")
	shrink.Scale = PLUS_SCALE
	shrink.Parent = face
	for _, child in ipairs(add:GetChildren()) do
		if child ~= hit then child.Parent = face end
	end
	face.Parent = add
	add.BackgroundTransparency = 1
end

-- Clone, strip, fit and bind; once per session. Never yields. A missing
-- purchase-critical name fails the whole window for this player, warned by
-- path; nothing else opens in its place.
function ui.build()
	if ui.built then return not ui.bindFailed end
	ui.built = true
	local template = folder:FindFirstChild("ZyntraShop_L4")
	if not template then
		warn("[ZyntraShopUI] L4 missing: ReplicatedStorage.ZyntraShopUI.ZyntraShop_L4")
		ui.bindFailed = true
		return false
	end
	local clone = template:Clone()
	Binder.strip(clone)
	local art = clone:IsA("GuiObject") and clone or clone:FindFirstChildWhichIsA("GuiObject")
	local window = art and Binder.find(art, "ShopWindow")
	if not window then
		warn("[ZyntraShopUI] L4 missing: ZyntraShop_L4/ShopWindow")
		ui.bindFailed = true
		return false
	end

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = ui.gui
	ui.root = root

	-- The artboard stays full-screen and keeps only the scrim. Framewisp's
	-- "Fit & centre" constraint/scale on it would shrink the scrim, and the
	-- window is fitted on its own below (pixel units: L4PixelUnits + rescale).
	for _, child in ipairs(art:GetChildren()) do
		if child:IsA("UIAspectRatioConstraint") or child:IsA("UIScale") then child:Destroy() end
	end
	art.AnchorPoint = Vector2.new(0, 0)
	art.Position = UDim2.new()
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	-- Under WindowHolder (ZIndex 2), whatever ZIndex the import gave the frame:
	-- the 2026-10-07 bundle import carries 4, and an artboard above the holder
	-- puts its Active Dim over the window and swallows every click (v2770).
	art.ZIndex = 1
	art.Parent = root
	-- No backdrop behind the window (owner 2026-10-07: "The backdrops when you
	-- open up the different menus needs to be removed"), but Dim stays the
	-- Active input shield, so a tap past the window reaches nothing behind it.
	-- An import that lost the (now empty) Dim layer still gets one.
	local dim = Binder.find(art, "Dim")
	if not dim then
		dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.BorderSizePixel = 0
		dim.Parent = art
	end
	dim.AnchorPoint = Vector2.new(0, 0)
	dim.Position = UDim2.new()
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundTransparency = 1
	dim.Active = true

	-- ModalViewport holder > aspect-locked fit > shadow + window.
	local design = Binder.designSize(window) -- 1760x1016 artboard px in the L4 export
	ui.design = design -- ui.fit's aspect
	local authoredW, authoredH = design.X, design.Y
	local holder = Instance.new("Frame")
	holder.Name = "WindowHolder"
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2 -- above the artboard and its input-sinking Dim, never by tie order
	holder.Parent = root
	ui.holder = holder
	local fitFrame = Instance.new("Frame")
	fitFrame.Name = "WindowFit"
	fitFrame.BackgroundTransparency = 1
	fitFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	fitFrame.Position = UDim2.fromScale(0.5, 0.5)
	fitFrame.Size = UDim2.fromScale(1, 1)
	fitFrame.Parent = holder
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = authoredW / authoredH
	ratio.Parent = fitFrame
	local shadow = Binder.find(art, "WindowShadow")
	if shadow then
		local drop = (px(shadow.Position.Y, ARTBOARD.Y) - px(window.Position.Y, ARTBOARD.Y)) / authoredH
		shadow.AnchorPoint = Vector2.new(0, 0)
		shadow.Position = UDim2.fromScale(0, math.clamp(drop, 0, 0.05))
		shadow.Size = UDim2.fromScale(1, 1)
		shadow.ZIndex = 1
		shadow.Parent = fitFrame
	end
	window.AnchorPoint = Vector2.new(0, 0)
	window.Position = UDim2.new()
	window.Size = UDim2.fromScale(1, 1)
	window.ZIndex = 2
	window.Parent = fitFrame
	ui.fit()
	Binder.scaleText(window, design, art:GetAttribute("BB_TextFactor"))

	-- Bind. Every purchase-critical miss is collected, then reported at once.
	local missing = {}
	local function need(scope, path, where)
		local node = scope and Binder.at(scope, path)
		if not node then table.insert(missing, (where and (where .. "/") or "") .. path) end
		return node
	end
	local function needControl(scope, base, where, textBase)
		local control = scope and Binder.control(scope, base, textBase)
		if not control or not control.Price then
			table.insert(missing, ("%s/%s/%s"):format(where, base, textBase or "Price"))
			return nil
		end
		return control
	end

	local close = need(window, "Close", "ShopWindow")
	local count = Binder.text(need(window, "TokenCount", "ShopWindow"))
	if count then table.insert(ui.counts, count) end
	local foundPages, foundTabs = Binder.all(window, "Page_"), Binder.all(window, "Tab_")
	ui.allPages = foundPages
	local hiddenTabs = {}
	for _, name in ipairs(TAB_ORDER) do
		ui.pages[name] = foundPages[name] or (name == "Shop" and need(nil, "Page_Shop", "ShopWindow")) or nil
		if not ui.pages[name] and name ~= "Shop" then table.insert(hiddenTabs, name) end
		local tab = foundTabs[name] or need(nil, "Tab_" .. name, "ShopWindow/Categories")
		if tab then
			ui.tabs[name] = {Node = tab, Hit = Binder.button(tab), Bar = Binder.find(tab, "ActiveBar"),
				Label = Binder.text(Binder.find(tab, "Label")), Stroke = tab:FindFirstChildOfClass("UIStroke")}
			-- A page the import lacks: its tab is hidden, so nothing reaches it.
			if not ui.pages[name] then tab.Visible = false end
			ui.onPress(ui.tabs[name].Hit, function()
				if ui.pages[name] then ui.selectTab(name) end
			end)
		end
	end
	-- The export draws ActiveBar and the ring on the selected tab (Shop) only:
	-- lend them to the rest.
	local bar, ring = ui.tabs.Shop and ui.tabs.Shop.Bar, ui.tabs.Shop and ui.tabs.Shop.Stroke
	for _, entry in pairs(ui.tabs) do
		if not entry.Bar and bar then
			entry.Bar = bar:Clone()
			entry.Bar.Parent = entry.Node
		end
		if not entry.Stroke and ring then
			entry.Stroke = ring:Clone()
			entry.Stroke.Parent = entry.Node
		end
	end
	for _, name in ipairs(TAB_ORDER) do
		if ui.pages[name] then pages[name].bind(ui.pages[name], need, needControl) end
	end

	if #missing > 0 then
		for _, path in ipairs(missing) do warn("[ZyntraShopUI] L4 missing: " .. path) end
		ui.bindFailed = true
		root:Destroy()
		ui.root, ui.holder = nil, nil
		return false
	end

	-- Header: close, RECORDS / SETTINGS, and the token pill's +.
	local closeHit = Binder.button(close)
	ui.onPress(closeHit, function() ui.setOpen(false) end)
	Binder.press(closeHit, close, Binder.find(window, "CloseShadow"))
	if DevAccess.IsAllowed(player) then ui.addDevButton(window) end -- clones SETTINGS before its active look exists
	ui.bindHeaderPages(window, foundPages)
	local add = Binder.find(window, "AddTokens")
	if add then
		local hit = Binder.button(add)
		ui.shrinkPlus(add, hit)
		ui.onPress(hit, function()
			ui.selectTab("Shop")
			task.defer(ui.scrollToCard, "Tokens20")
		end)
	end
	ui.status = Binder.text(Binder.find(window, "Status"))
	-- The import's sample text never shows, whatever it says (it once read
	-- a line about live prices): only showHint and showMessage write it.
	if ui.status then ui.status.Text = "" end
	ui.toast = Binder.find(window, "Toast")
	ui.toastText = Binder.text(ui.toast and Binder.find(ui.toast, "ToastText"))
	ui.toastAccent = ui.toast and Binder.find(ui.toast, "ToastAccent")
	ui.pendingPanel = Binder.find(window, "Pending")
	local pendingText = ui.pendingPanel and Binder.find(ui.pendingPanel, "PendingText")
	ui.pendingText = Binder.text(pendingText)
	-- Both imports (2026-10-06, and the 2026-10-07 bundle) bake PendingText into
	-- an image of the design's sample line; it would name the wrong item, so
	-- only the title shows.
	if pendingText and not ui.pendingText and pendingText:IsA("GuiObject") then pendingText.Visible = false end
	if ui.toast then ui.toast.Visible = false end
	if ui.pendingPanel then ui.pendingPanel.Visible = false end
	-- Not purchase-critical, so the window still opens, but say once what the
	-- import lost: each of these silently removes a route or a message.
	local lost = {}
	for _, pair in ipairs({{"AddTokens", add}, {"PendingText", ui.pendingText},
		{"Status", ui.status}, {"Toast", ui.toastText}}) do
		if not pair[2] then table.insert(lost, pair[1]) end
	end
	if #lost > 0 then warn("[ZyntraShopUI] L4 optional nodes missing: " .. table.concat(lost, ", ")) end
	if #hiddenTabs > 0 then
		warn("[ZyntraShopUI] L4 pages missing, their tabs are hidden: " .. table.concat(hiddenTabs, ", "))
	end

	ShopData.fetchPrices()
	ui.renderCounts()
	return true
end

function ui.openShop(tab, focus)
	if type(tab) ~= "string" or not pages[tab] then return false end
	if player:GetAttribute("InRound") == true or player:GetAttribute("QueueModalOpen") == true then return false end
	-- Never over somebody else's modal; switching tabs in our own is fine.
	if not ui.open and UIDevice.ScreenOwningModalOpen() then return false end
	if not ui.build() or not ui.pages[tab] then return false end
	ui.selectTab(tab)
	ui.setOpen(true)
	if focus then task.defer(ui.scrollToCard, focus) end
	return true
end

-- -- the lobby token pill --------------------------------------------------
-- The top-right corner of the lobby (owner, 2026-10-07): the pill sits AT the
-- corner and "Friend Boost Client" hangs under it, reading this pill's own
-- rectangle (PlayerGui.ZyntraLobbyPillL4.TokenPill: Visible, AbsolutePosition,
-- AbsoluteSize). The pill never reads the chip, so the two cannot feed back.
-- Over a rail window (owner, 2026-10-08) the pill stays up at DisplayOrder 119.
-- Where its corner would sit on the window (touch, TV, or a PC narrower than
-- 1120 px) it docks at the right end of the topbar band and publishes
-- TokenPill.Docked, which Friend Boost follows.
do
	local PILL_HEIGHT = 52 -- AddTokens is 49 px at this height (ui.shrinkPlus draws its face)
	-- A 50% PC window ends at <= 3/4 of the safe width; at the 400 px floor it is 693 px
	-- wide (1760:1016) and ends at safe/2 + 347, plus up to 34 px of rail clamp, so the
	-- corner column (18 + 153 + 8 gap) clears it from 1120 px up. Narrower, it docks.
	local PC_DOCK_BELOW = 1120
	local pillGui, pill, aspect = nil, nil, 456 / 138
	local wasOver = false -- a window closing takes a pad's focus off the pill (owner, 2026-10-08)

	local function railRight()
		local store = playerGui:FindFirstChild("ZyntraStore")
		local right = 0
		for _, name in ipairs(RAIL) do
			local button = store and store:FindFirstChild(name)
			if button and button.Visible then
				right = math.max(right, button.AbsolutePosition.X + button.AbsoluteSize.X)
			end
		end
		return right
	end

	local function make()
		local template = folder:FindFirstChild("ZyntraShop_L4")
		local source = template and Binder.find(template, "TokenPill")
		if not source then return false end
		local design = Binder.designSize(source)
		aspect = design.X / design.Y
		pillGui = Instance.new("ScreenGui")
		pillGui.Name = "ZyntraLobbyPillL4"
		pillGui.DisplayOrder = 55
		pillGui.ResetOnSpawn = false
		pillGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the topbar band is inside it (UIRegression TopBound); LocalPosition keeps the resting spot
		pillGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pill = source:Clone()
		Binder.strip(pill)
		pill.Name = "TokenPill"
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Visible = false
		pill.Parent = pillGui
		pillGui.Parent = playerGui
		Binder.scaleText(pill, design, template:GetAttribute("BB_TextFactor"))
		local count = Binder.text(Binder.find(pill, "TokenCount"))
		if count then table.insert(ui.counts, count) end
		local add = Binder.find(pill, "AddTokens")
		if add then
			local hit = Binder.button(add)
			ui.shrinkPlus(add, hit)
			ui.onPress(hit, function()
				-- Over another rail window: ZyntraStore's own switch closes it first;
				-- openShop still refuses over anything left, so two never stack.
				-- A failed bind has already warned; the pill then stands down, and the
				-- other window is not closed for a shop that cannot open.
				if not ui.build() then ui.refreshPill() return end
				local switch = playerScripts:FindFirstChild("ZyntraRailSwitch")
				if switch and switch:IsA("BindableFunction") then pcall(switch.Invoke, switch, "ZyntraStoreOpen") end
				if not ui.openShop("Shop", "Tokens20") then ui.refreshPill() end
			end)
		end
		ui.renderCounts()
		return true
	end

	function ui.refreshPill()
		if not pill and not make() then return end
		-- Owner 2026-10-08: up over the rail's own windows too; a round, the queue
		-- host modal and re-entry still take it down.
		local visible = not ui.bindFailed and player:GetAttribute("InRound") ~= true
			and player:GetAttribute("QueueModalOpen") ~= true and player:GetAttribute("ZyntraReentryOpen") ~= true
		local over = UIDevice.ScreenOwningModalOpen() -- with the guards above: a rail window
		if wasOver and not over then
			local selected = GuiService.SelectedObject
			if selected and selected:IsDescendantOf(pillGui) then GuiService.SelectedObject = nil end
		end
		wasOver = over
		local docked = false
		if visible then
			local layout = UIDevice.Layout()
			local width = math.floor(PILL_HEIGHT * aspect)
			local right, top
			docked = over and (layout.IsTouch or GuiService:IsTenFootInterface()
				or layout.Safe.Right - layout.Safe.Left < PC_DOCK_BELOW)
			if docked then
				-- At rest the corner sits on the window's Close: the topbar band's right end.
				local band = layout.InsetAreas.TopbarSafeInsets
				right, top = band.Right - 8, band.Top + (band.Height - PILL_HEIGHT) / 2
				-- A legacy 36 px bar, or a band whose left end (the unibar) would reach
				-- Friend Boost's docked line (GAP 6 + LINE_WIDTH 104): hidden over the window.
				visible = band.Height >= PILL_HEIGHT + 4 and right - width - (6 + 104) >= band.Left
			else
				-- Only Right and Top: TopRightPanel's height is the room above the
				-- registered controls, and the Friend Boost chip is one of them.
				local panel = UIDevice.TopRightPanel(width, 1)
				right, top = panel.Right, panel.Top
			end
			pill.Size = UDim2.fromOffset(width, PILL_HEIGHT)
			pill.Position = UIDevice.LocalPosition(pillGui, right, top)
			-- On a narrow phone it would cross the rail: the window header has it anyway.
			visible = visible and right - width >= railRight() + 8
		end
		pill:SetAttribute("Docked", (visible and docked) or nil) -- Friend Boost follows it
		pill.Visible = visible
		pillGui.DisplayOrder = if visible and over then 119 else 55
	end
end

-- -- lobby skins: rail, wheel (runtime only; a rejoin removes them). Daily Rewards
-- is its own L4 window now ("Zyntra Daily L4", 2026-10-07): nothing to skin.
do
	local applied = false

	local function report(surface, missing)
		warn(("[ZyntraShopUI] %s skin skipped, missing: %s"):format(surface, table.concat(missing, ", ")))
	end

	-- Binder.scaleText honours the constraint (the imported labels are fixed size).
	local function floorText(label)
		if label and not label:FindFirstChildOfClass("UITextSizeConstraint") then
			local limit = Instance.new("UITextSizeConstraint")
			limit.MinTextSize = 11 -- UIRegression's text floor at the 52 px rail size
			limit.Parent = label
			-- The graft's first solve ran before this existed; the rail may never resize.
			label.TextSize = math.max(label.TextSize, limit.MinTextSize)
		end
	end

	-- The ZyntraStore rail keeps its names, layout ladder, dots and handlers;
	-- only its face changes. SectionButtonContent is hidden, never destroyed:
	-- ZyntraStore dot-indexes it.
	local function skinRail(template)
		local store = playerGui:WaitForChild("ZyntraStore", SKIN_WAIT)
		if not store then return report("rail", {"PlayerGui.ZyntraStore"}) end
		for _, name in ipairs(RAIL) do
			local live = store:FindFirstChild(name)
			if not live then
				report("rail", {name})
			else
				-- Labels in Roboto Condensed: Montserrat's UPGRADES / REWARDS do not fit
				-- the 52-64 px square at the 11 px floor and were cut to "UPGRA..."
				-- (owner, 2026-10-07). Set on this client's template copy, before the
				-- graft's first solve, so the fit measures the font it draws.
				local tplLabel = Binder.find(Binder.find(template, name), "Label")
				if tplLabel and tplLabel:IsA("TextLabel") then
					tplLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold)
				end
				local missing, grafts = Binder.skin(live, template, {
					-- Fills ZyntraStore's square button (see the one-tone note below).
					{graft = name, children = true, name = "Face", size = UDim2.fromScale(1, 1),
						pos = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), z = 4},
					{hide = {"SectionButtonContent"}},
					{set = "SquareSectionBorder", props = {Color = P.RailTeal}},
				})
				if #missing > 0 then
					report("rail " .. name, missing)
				else
					local graft = grafts.Face
					local face = Binder.find(graft, "Face")
					-- One tone (owner 2026-10-07: "den sorte/graa forskel"): the grey face
					-- covers the whole button, so ZyntraStore's black COLORS.bg (re-set on
					-- every refresh) never shows, and the label plate takes the face's
					-- colour; the black face edge and the drop shadows go.
					if face then
						face.AnchorPoint, face.Position, face.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
						local edge = face:FindFirstChildOfClass("UIStroke")
						if edge then edge.Enabled = false end
						local round, liveRound = face:FindFirstChildOfClass("UICorner"), live:FindFirstChildOfClass("UICorner")
						if round and liveRound then round.CornerRadius = liveRound.CornerRadius end
						local plate = Binder.find(graft, "Plate")
						if plate then plate.BackgroundColor3 = face.BackgroundColor3 end
						for _, shadow in ipairs({"FaceShadow", "PlateShadow"}) do
							local node = Binder.find(graft, shadow)
							if node then node.Visible = false end
						end
						Binder.press(live, face)
					end
					local label = Binder.text(Binder.find(graft, "Label"))
					floorText(label)
					local caption = Binder.find(live, "SectionCaption")
					if name == "ZyntraMusicButton" and label and caption then
						local function mirror() label.Text = string.upper(caption.Text) end
						caption:GetPropertyChangedSignal("Text"):Connect(mirror)
						mirror()
					end
				end
			end
		end
	end

	-- Lucky Wheel Client writes every property below exactly once, at build;
	-- applyLayout and paintHub only write Size, Position, Text, TextSize, Active.
	local function skinWheel(template)
		local gui = playerGui:WaitForChild("LuckyWheelGui", SKIN_WAIT)
		if not gui then return report("wheel", {"PlayerGui.LuckyWheelGui"}) end
		local map = {
			{from = "WheelDisc", to = "WheelDisc", props = {"Image"}},
			{set = "WheelPointer", props = {BackgroundTransparency = 1}},
			{hide = {"WheelPointer/UIStroke"}},
			{graft = "WheelPointer", into = "WheelHolder", pos = UDim2.fromScale(0.5, 0),
				size = UDim2.fromScale(104 / 760, 140 / 760), anchor = Vector2.new(0.5, 0.35), z = 4},
			{set = "HubButton", props = {BackgroundColor3 = P.RailTeal, TextColor3 = P.Ink}},
			{set = "HubButton/UIStroke", props = {Color = P.Ink}},
			-- Solid, like the shop's Close: legacy UIStyle.button left the face 8%
			-- see-through (the lobby showed through the coral) in a gold ring at
			-- 25%. AutoButtonColor, the legacy hover/press tint, is left alone;
			-- nothing in the client animates either transparency.
			{set = "CloseButton", props = {BackgroundColor3 = P.Coral, BackgroundTransparency = 0, TextColor3 = P.Cream}},
			{set = "CloseButton/UIStroke", props = {Color = P.CoralStroke, Transparency = 0}},
			{graft = "Odds", into = "WheelHolder", pos = UDim2.new(1, 24, 0.5, 0),
				size = UDim2.fromScale(0.62, 0.66), anchor = Vector2.new(0, 0.5), z = 6},
			{graft = "TitleBlock", into = "WheelShade", z = 6},
		}
		local hidden = {}
		for order = 1, 6 do
			table.insert(hidden, "FieldLabel" .. order) -- the pictograms are in the art
			table.insert(map, {set = "FieldOdds" .. order, props = {TextColor3 = P.Cream}})
		end
		table.insert(map, {hide = hidden})
		-- The current-row outline (see "the row under the pointer" below) goes into
		-- this client's template copy before the graft, so the graft's scaler sizes
		-- it from FigmaStrokeW with the panel, like every imported stroke.
		for _, row in pairs(Binder.all(template, "OddsRow_")) do
			if not row:FindFirstChild("CurrentStroke") then
				local stroke = Instance.new("UIStroke")
				stroke.Name, stroke.Color, stroke.Enabled = "CurrentStroke", P.RailTeal, false
				stroke:SetAttribute("FigmaStrokeW", 2)
				stroke.Parent = row
			end
		end
		local missing, grafts = Binder.skin(gui, template, map)
		if #missing > 0 then return report("wheel", missing) end

		-- WheelShade stays see-through (no backdrop: owner, Trello 25GLltY6 and
		-- 2026-10-07), so the grafted title reads over the lobby by an INK glyph
		-- outline, the way the legacy field labels do (Contextual, the default).
		for _, label in ipairs(grafts.TitleBlock:GetDescendants()) do
			if label:IsA("TextLabel") and not label:FindFirstChildOfClass("UIStroke") then
				local outline = Instance.new("UIStroke")
				outline.Color, outline.Thickness, outline.Transparency = P.Ink, 2, 0.2
				outline.Parent = label
			end
		end

		local holder, hub = Binder.find(gui, "WheelHolder"), Binder.find(gui, "HubButton")

		-- MOBILE_QA_20261008: the title keeps its designed corner only where that corner is free. On a phone the lobby
		-- rail stands in it (the L of LUCKY was under SHOP) and the disc reaches into it: the title starts right of
		-- the rail, and is not drawn where its lettering would then lie on the disc. Measured on the lettering, not on
		-- the block's box: the labels' text overflows their boxes.
		local titleBlock, titleAt, titleShift = grafts.TitleBlock, grafts.TitleBlock.Position, 0
		local function placeTitle()
			local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
			for _, label in ipairs(titleBlock:GetDescendants()) do
				if label:IsA("TextLabel") and label.Text ~= "" then
					local at, box, ink = label.AbsolutePosition, label.AbsoluteSize, label.TextBounds
					left, top = math.min(left, at.X), math.min(top, at.Y)
					right, bottom = math.max(right, at.X + math.max(box.X, ink.X)), math.max(bottom, at.Y + math.max(box.Y, ink.Y))
				end
			end
			if left == math.huge then return end
			-- where the lettering would be with no shift, then the shift the rail asks for
			left, right = left - titleShift, right - titleShift
			local railRight = player:GetAttribute("ZyntraRailRight")
			local shift = if type(railRight) == "number" then math.max(0, math.ceil(railRight + 12 - left)) else 0
			if shift ~= titleShift then
				titleShift = shift
				titleBlock.Position = titleAt + UDim2.fromOffset(shift, 0)
			end
			local centre = holder.AbsolutePosition + holder.AbsoluteSize / 2
			local near = Vector2.new(math.clamp(centre.X, left + shift, right + shift), math.clamp(centre.Y, top, bottom))
			titleBlock.Visible = (near - centre).Magnitude >= holder.AbsoluteSize.X / 2 + 6
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTitle)
		holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeTitle)
		titleBlock:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTitle)
		player:GetAttributeChangedSignal("ZyntraRailRight"):Connect(placeTitle)
		player:GetAttributeChangedSignal("LuckyWheelOpen"):Connect(function() task.defer(placeTitle) end)
		UIDevice.Changed:Connect(placeTitle)
		task.defer(placeTitle)
		local hubStroke = hub:FindFirstChildOfClass("UIStroke")
		local function strokeHub()
			if hubStroke then hubStroke.Thickness = math.max(2, math.floor(hub.AbsoluteSize.X * 6 / 208 + 0.5)) end
		end
		hub:GetPropertyChangedSignal("AbsoluteSize"):Connect(strokeHub)
		strokeHub()

		-- Odds come from the server weights, never from the design's copy.
		local wheel = (Config.DailyRewards or {}).Wheel or {}
		local total = 0
		for _, entry in ipairs(wheel) do total += math.max(0, tonumber(entry.Weight) or 0) end
		for _, entry in ipairs(wheel) do
			local row = Binder.find(grafts.Odds, "OddsRow_" .. tostring(entry.Key))
			local value = row and Binder.text(Binder.find(row, "OddsValue"))
			if value and total > 0 then
				value.Text = ("%d%%"):format(math.floor(math.max(0, tonumber(entry.Weight) or 0) / total * 100 + 0.5))
			end
		end
		-- The panel only where it fits beside the disc; otherwise the field odds stay.
		local function placeOdds()
			local fits = holder.AbsolutePosition.X + holder.AbsoluteSize.X * 1.62 + 24 <= UIDevice.Layout().Safe.Right
			grafts.Odds.Visible = fits
			for order = 1, 6 do
				local odds = Binder.find(gui, "FieldOdds" .. order)
				if odds then odds.Visible = not fits end
			end
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeOdds)
		holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeOdds)
		UIDevice.Changed:Connect(placeOdds)
		placeOdds()

		-- The row under the pointer lights up (owner 2026-10-07), live while the
		-- disc turns, held where it stops, right at rest on open. The fields are
		-- Lucky Wheel Client's: config order, equal, field n centred FIELD * (n - 1)
		-- clockwise from 12 o'clock, and the pointer reads (-Rotation) % 360. Skin5
		-- is its own field: its row says "SKIN OR 3 TOKENS", so a 3-token fallback
		-- still lights Skin5, never Token3. Purely visual; the disc is only read.
		local keys, rows = {}, {}
		for _, entry in ipairs(wheel) do
			if type(entry) == "table" then table.insert(keys, tostring(entry.Key or "")) end
		end
		for _, key in ipairs(keys) do
			local row = Binder.find(grafts.Odds, "OddsRow_" .. key)
			local label = row and Binder.text(Binder.find(row, "OddsLabel"))
			local value = row and Binder.text(Binder.find(row, "OddsValue"))
			if row and label and value then
				rows[key] = {Row = row, Stroke = row:FindFirstChild("CurrentStroke"), Label = label, Value = value,
					Fill = row.BackgroundColor3, FillAlpha = row.BackgroundTransparency,
					LabelColor = label.TextColor3, ValueColor = value.TextColor3}
			end
		end
		if #keys == 0 then return end
		local disc = Binder.find(gui, "WheelDisc")
		local lit, follow, queued = nil, nil, false
		local function light(key, on)
			local r = rows[key]
			if not r then return end
			r.Row.BackgroundColor3 = on and P.TileHi or r.Fill
			r.Row.BackgroundTransparency = on and 0 or r.FillAlpha
			if r.Stroke then r.Stroke.Enabled = on end
			r.Label.TextColor3 = on and P.Cream or r.LabelColor
			r.Value.TextColor3 = on and P.RailTeal or r.ValueColor
		end
		local function paint()
			local field = 360 / #keys
			local key = keys[math.floor(((-disc.Rotation) % 360 + field / 2) / field) % #keys + 1]
			if key == lit then return end
			if lit then light(lit, false) end
			lit = key
			light(key, true)
		end
		-- The disc's tween writes Rotation every frame. ReduceFlashing follows at
		-- 4 Hz instead of live: a change queues one paint 0.25 s later that reads
		-- the rotation THEN, so the row where the disc stops is always the last one.
		local function onRotation()
			if player:GetAttribute("ReduceFlashing") ~= true then return paint() end
			if queued then return end
			queued = true
			task.delay(0.25, function()
				queued = false
				if follow then paint() end
			end)
		end
		local function track()
			local open = player:GetAttribute("LuckyWheelOpen") == true
			if open and not follow then
				follow = disc:GetPropertyChangedSignal("Rotation"):Connect(onRotation)
				paint()
			elseif not open and follow then
				follow:Disconnect()
				follow = nil
			end
		end
		player:GetAttributeChangedSignal("LuckyWheelOpen"):Connect(track)
		track()
	end

	local function run(surface, fn, templateName)
		local template = folder:FindFirstChild(templateName)
		if not template then
			-- The surface still works in its unskinned face.
			return warn(("[ZyntraShopUI] %s skin skipped: ReplicatedStorage.ZyntraShopUI.%s is missing"):format(surface, templateName))
		end
		task.spawn(function()
			local ok, err = pcall(fn, template)
			if not ok then warn(("[ZyntraShopUI] %s skin failed: %s"):format(surface, tostring(err))) end
		end)
	end

	function ui.applyLobbySkins()
		if applied then return end
		applied = true
		run("rail", skinRail, "LobbyRail_L4")
		run("wheel", skinWheel, "LuckyWheel_L4")
	end
end

-- -- wiring ----------------------------------------------------------------

ui.gui = Instance.new("ScreenGui")
ui.gui.Name = "ZyntraShopL4"
-- One above ZyntraStore's resting 55. While a rail window is open the rail lifts
-- itself to 119 (2026-10-07), so it stays tappable over this window and its Dim.
ui.gui.DisplayOrder = 56
ui.gui.ResetOnSpawn = false
ui.gui.IgnoreGuiInset = false
ui.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ui.gui.Parent = playerGui

ShopData.Changed:Connect(function()
	ui.renderCounts()
	ui.render()
end)
ShopData.Message:Connect(ui.showMessage)

-- Another writer (UIRegression's scenario reset, a stale ZyntraStore build) may
-- clear it; while this window is up the flag is ours.
player:GetAttributeChangedSignal("ZyntraStoreOpen"):Connect(function()
	if ui.open and player:GetAttribute("ZyntraStoreOpen") ~= true then
		task.defer(function()
			if not ui.open then return end
			player:SetAttribute("ZyntraStoreOpen", true)
			-- The same write also released touch movement under this window.
			UIDevice.SuppressTouchMovement(true)
		end)
	end
end)

-- Close triggers: a round, a death, an escape, the queue modal.
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") == true then ui.setOpen(false) end
	ui.refreshPill()
end)
player:GetAttributeChangedSignal("Escaped"):Connect(function()
	if player:GetAttribute("Escaped") == true then ui.setOpen(false) end
end)
player:GetAttributeChangedSignal("QueueModalOpen"):Connect(function()
	if player:GetAttribute("QueueModalOpen") == true then ui.setOpen(false) end
	ui.refreshPill()
end)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") ~= true and player:GetAttribute("InRound") == true then
		ui.setOpen(false)
	end
end)
do
	local died = nil
	local function bindCharacter(character)
		if died then died:Disconnect(); died = nil end
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and player.Character == character then
				if died then died:Disconnect() end
				died = humanoid.Died:Connect(function() ui.setOpen(false) end)
			end
		end)
	end
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then bindCharacter(player.Character) end
end
UIDevice.OnScreenOwningModalChanged(ui.refreshPill)
UIDevice.Changed:Connect(function()
	ui.fit()
	ui.refreshPill()
end)
player:GetAttributeChangedSignal("ZyntraRailRight"):Connect(ui.fit)

-- Studio-only seam for UIRegression (the store-modal row and
-- BriefingExclusionMatrix) and the install QA probe (install/05_qa_probe_client.luau):
--   press:<card id | node path>  runs the press handler Activated would run
--   buy:<key>                    ShopData.purchase(key), the one dispatcher
--   hook / unhook / prompts      record Robux prompts instead of showing them
--   profile                      what ShopData knows: {Ready, Tokens, StaminaLevel, PromptOpen}
--   open[:<page>] / close / tab:<page>   the bridge, setOpen(false), selectTab (pages include Records, Settings)
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionZyntraShopL4Probe"
	probe.OnInvoke = function(action)
		action = tostring(action)
		if action:sub(1, 6) == "press:" then
			local target, hit = action:sub(7), nil
			for _, entry in ipairs(ui.controls) do
				if entry.Key == target then hit = entry.Control.Hit end
			end
			local node = not hit and ui.root and Binder.at(ui.root, target)
			if node then hit = node:IsA("GuiButton") and node or node:FindFirstChild("Hit") end
			local fn = hit and ui.handlers[hit]
			if not (fn and hit.Active) then return false end
			fn()
			return true
		elseif action:sub(1, 4) == "buy:" then
			return ShopData.purchase(action:sub(5))
		elseif action == "hook" then
			table.clear(ui.hooked)
			ShopData.promptHook = function(kind, id) table.insert(ui.hooked, kind .. ":" .. tostring(id)) end
			return true
		elseif action == "unhook" then
			ShopData.promptHook = nil
			return true
		elseif action == "prompts" then
			return table.concat(ui.hooked, ",")
		elseif action == "profile" then
			local profile = ShopData.profile()
			return {Ready = ShopData.ready(), Tokens = ShopData.tokens(),
				StaminaLevel = type(profile) == "table" and profile.StaminaLevel or nil, PromptOpen = ShopData.promptOpen()}
		elseif action == "open" or action:sub(1, 5) == "open:" then
			return ui.openShop(action:sub(6) ~= "" and action:sub(6) or "Shop")
		elseif action == "close" then
			ui.setOpen(false)
		elseif action:sub(1, 4) == "tab:" then
			ui.selectTab(action:sub(5))
			return ui.tab
		elseif action == "cards" then
			return table.concat(ui.contract, "\n")
		elseif action == "state" then
			local lines = {}
			for _, entry in ipairs(ui.controls) do
				table.insert(lines, entry.Key .. "|" .. tostring(entry.Control.Price.Text))
			end
			return table.concat(lines, "\n")
		end
		return ui.open
	end
	probe.Parent = ui.gui
end

ui.applyLobbySkins()
ui.refreshPill()
