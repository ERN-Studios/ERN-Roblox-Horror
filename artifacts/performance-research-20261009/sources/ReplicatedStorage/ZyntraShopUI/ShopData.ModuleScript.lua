-- ShopData (ReplicatedStorage.ZyntraShopUI.ShopData)
--
-- Everything the L4 shop window KNOWS, and the one place it ACTS
-- (L4-ROBLOX-PLAN.md section 2.3). One instance per client: the LocalScripts
-- "Zyntra Shop L4" and "Zyntra Daily L4" share it (ShopData.start() is idempotent).
--
-- TRUST. This module never decides ownership, a price or a grant. It reads:
--   * the public profile (ZyntraGetProfile once, then every ZyntraProfileChanged);
--   * the server-written ZyntraOwns* attributes (a pass flips there first);
--   * MarketplaceService live prices, with earner and skin passes VERIFIED on
--     sale (IsForSale, TargetId, a positive whole price) before they are offered;
--   * ProtectionClient's own state for the Entity Shield.
-- It sends only what already exists: ZyntraAction actions, ProtectionClient
-- requests and the two Marketplace prompts. ZyntraMonetization is untouched.
--
-- THE GATE. Until ZyntraProfileLoaded is true AND a profile has arrived,
-- ready() is false and purchase() returns without calling anything.
--
-- PENDING. Every request owns a pending entry with a serial and a timeout, so a
-- silent server drop (the 1 s per-action window, or no session yet) can never
-- leave a button stuck, and a late timer never clears a newer request. A press
-- inside the server's per-action window is held until it has passed instead of
-- being sent to be dropped, and a timeout says so instead of reverting silently.
--
-- UNKNOWN IS NOT "NOT OWNED". ZyntraProfileLoaded flips BEFORE refreshPasses
-- has read a single pass, so every ZyntraOwns<Pass> attribute is nil for a few
-- seconds after the gate opens. A pass whose attribute is still nil reads
-- CHECKING and is never prompted; the Token Earner waits for the server's
-- ZyntraTokenEarnerMultiplier (published only once every earner read answered),
-- because Roblox WILL sell 2x to a 3x/5x owner -- it is a different pass.
--
-- RE-CHECKED 2026-10-05 against the Studio ZyntraMonetization (209,509 B, the
-- repo copy byte for byte): the ZyntraAction names and payloads used below;
-- WRITE_ACTION_WINDOW = 1 keyed per action, per BuyItem Key and per skin id;
-- ZyntraProfileChanged:FireClient(player, profile, message, tone); EquipSkin
-- requiring PROFILE ownership (Skins.IsOwned), not the pass attribute;
-- refreshPasses setting every ZyntraOwns<Pass> after ZyntraProfileLoaded;
-- ZyntraTokenEarnerMultiplier written only when every earner read answered.
-- Re-check these whenever ZyntraMonetization changes again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local Skins = require(ReplicatedStorage:WaitForChild("ZyntraSkins"))
local ProtectionClient = require(ReplicatedStorage:WaitForChild("ProtectionClient"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("ZyntraAction")
local getProfile = remotes:WaitForChild("ZyntraGetProfile")
local profileChanged = remotes:WaitForChild("ZyntraProfileChanged")

local ACTION_TIMEOUT = 6    -- silent drops: the 1 s per-action window, or no session yet
local PROMPT_TIMEOUT = 30   -- a Roblox prompt that never reports Finished
local RECEIPT_TIMEOUT = 15  -- bought, but no push / no ownership flip yet
local PROFILE_RETRY = 10    -- ZyntraGetProfile can answer nil after its own 10 s wait
local WRITE_WINDOW = 1.1    -- ZyntraMonetization WRITE_ACTION_WINDOW (1 s per action key) + margin

local ShopData = {
	ACTION_TIMEOUT = ACTION_TIMEOUT,
	PROMPT_TIMEOUT = PROMPT_TIMEOUT,
	RECEIPT_TIMEOUT = RECEIPT_TIMEOUT,
	PROFILE_RETRY = PROFILE_RETRY,
	-- What L4 sells, in card order (OWNER-DECISIONS.md). Everything else in the
	-- catalogue is "not sold in this layout": Tokens4, EmergencyReentry,
	-- CosmeticEquipment (sold in COLORS only), TokenEarner3x/5x and upgrades,
	-- DonationField/Command/5000 and Donation20K.
	SHOP = {"ExpeditionPack", "Supporter", "AdvancedEquipment", "EntityDetector", "TokenEarner2x", "Tokens20"},
	DONATE = {"DonationSignal", "DonationSupply", "DonationResearch", "DonationDirector", "Donation10000"},
	SKINS = {"BaselineYellow", "PoolService", "SuburbSurvey", "BlacksiteDirector", "StaticWraith", "FalseSun"},
	PICKERS = {Hazmat = "AdvancedEquipment", Glowstick = "CosmeticEquipment"},
}

local changed = Instance.new("BindableEvent")
local message = Instance.new("BindableEvent")
ShopData.Changed = changed.Event   -- profile, price, pending, ownership or shield change
ShopData.Message = message.Event   -- (text, tone): every push message plus client toasts

local profile = nil
local prices = {}     -- key -> {State = "pending" | "live" | "off" | "soon", Price = n}
local pending = {}    -- key -> {Kind = "action" | "prompt" | "receipt", Serial = n}
local promptOpen = nil
local serial = 0
local pushes = 0 -- every ZyntraProfileChanged; ShopData.refresh drops a re-read older than one
local started, pricesFetched, requesting = false, false, false

local function fire() changed:Fire() end
function ShopData.notify(text, tone) message:Fire(text, tone) end

-- -- the Robux catalogue L4 can prompt, read from Config at runtime --------
-- Built defensively: a key the pulled Config no longer has simply never
-- appears, and its card renders UNAVAILABLE rather than erroring.
local robux = {}
local function addRobux(key, entry, isPass, verified, price)
	if type(entry) ~= "table" then return end
	robux[key] = {
		Key = key,
		Id = math.floor(tonumber(entry.Id or entry.PassId) or 0),
		Pass = isPass,
		Verified = verified,
		Name = tostring(entry.Name or key),
		Price = math.floor(tonumber(price or entry.Price) or 0),
	}
end
for _, key in ipairs({"Supporter", "AdvancedEquipment", "EntityDetector", "CosmeticEquipment"}) do
	addRobux(key, (Config.Passes or {})[key], true, false)
end
for _, key in ipairs({"ExpeditionPack", "Tokens20"}) do
	addRobux(key, (Config.Products or {})[key], false, false)
end
for _, key in ipairs(ShopData.DONATE) do
	local entry = (Config.Donations or {})[key]
	addRobux(key, entry, type(entry) == "table" and entry.Kind == "GamePass", false)
end
-- Only the 2x pass, never an upgrade offer (owner decision; risk 9: the same
-- script that renders this price is the one that prompts it).
addRobux("TokenEarner2x", ((Config.TokenEarner or {}).Passes or {}).TokenEarner2x, true, true)
for _, skinId in ipairs({"StaticWraith", "FalseSun"}) do
	local item = Skins.Get(skinId)
	if item and item.Kind == "Robux" then addRobux(skinId, item, true, true, item.RobuxPrice) end
end
for key, item in pairs(robux) do
	prices[key] = item.Id <= 0 and {State = "soon"}
		or item.Verified and {State = "pending"}
		or {State = "live", Price = item.Price}
end

function ShopData.item(key) return robux[key] end
function ShopData.price(key) return prices[key] end
function ShopData.pending(key) local entry = pending[key]; return entry and entry.Kind or nil end
function ShopData.promptOpen() return promptOpen end
function ShopData.protection() return ProtectionClient.GetState() end

-- -- reads ------------------------------------------------------------------

function ShopData.ready()
	return profile ~= nil and player:GetAttribute("ZyntraProfileLoaded") == true
end

function ShopData.profile() return profile end

function ShopData.tokens()
	if not ShopData.ready() then return nil end
	local tokens = tonumber(profile.Tokens)
	return tokens and math.max(0, math.floor(tokens)) or 0
end

local function attr(key) return player:GetAttribute("ZyntraOwns" .. key) == true end
local function unread(key) return player:GetAttribute("ZyntraOwns" .. key) == nil end

-- 1, 2, 3 or 5; nil while unknown. The server's published multiplier is the
-- answer; an owned earner attribute can only ever raise it (a purchase latches
-- the attribute first), so a 3x or 5x owner keeps reading 3x / 5x although only
-- 2x is sold.
function ShopData.earnerTier()
	if not ShopData.ready() then return nil end
	local published = tonumber(player:GetAttribute("ZyntraTokenEarnerMultiplier"))
	local earner, derived = Config.TokenEarner, nil
	if type(earner) == "table" and type(earner.Tier) == "function" then
		local owns = {}
		for key in pairs(earner.Passes or {}) do owns[key] = attr(key) end
		derived = earner.Tier(owns)
	end
	if not published then return derived and derived >= 2 and derived or nil end
	return math.max(published, derived or 1)
end

-- nil before ready (unknown is not "not owned"). Owned counts a Robux suit's
-- pass attribute; Equippable is what the server's EquipSkin accepts: the
-- PROFILE's ownership (the grant lands a moment after the attribute).
function ShopData.skinState(skinId)
	local item = Skins.Get(skinId)
	if not item or not ShopData.ready() then return nil end
	local state = type(profile.Skins) == "table" and profile.Skins or {}
	local owned = type(state.Owned) == "table" and state.Owned or {}
	local equippable = skinId == Skins.DefaultId or owned[skinId] == true
	local isOwned = equippable or (item.Kind == "Robux" and attr(skinId))
	return {
		Item = item,
		Owned = isOwned,
		Equippable = equippable,
		Equipped = equippable and (state.Equipped or Skins.DefaultId) == skinId,
		Clears = math.max(0, math.floor(tonumber(profile.CompletedLevels) or 0)),
	}
end

-- true / false, or nil while unknown: before ready, and for a pass the server
-- has not read yet.
function ShopData.owns(key)
	if not ShopData.ready() then return nil end
	if key == "TokenEarner2x" then
		local tier = ShopData.earnerTier()
		return tier and tier >= 2
	end
	local item = robux[key]
	if Skins.Get(key) then
		local state = ShopData.skinState(key)
		if not state.Owned and item and item.Pass and unread(key) then return nil end
		return state.Owned
	end
	if profile["Owns" .. key] == true or attr(key) then return true end
	if item and item.Pass and unread(key) then return nil end
	return false
end

function ShopData.owns20K() return ShopData.ready() and attr("Donation20K") end

-- -- live prices: once per session, on first open --------------------------

local function verifiedPrice(info, id)
	if type(info) ~= "table" or info.IsForSale ~= true or info.TargetId ~= id then return nil end
	local price = info.PriceInRobux
	if type(price) ~= "number" or price ~= price or price <= 0
		or price == math.huge or price % 1 ~= 0 then return nil end
	return price
end

function ShopData.fetchPrices()
	if pricesFetched then return end
	pricesFetched = true
	for key, item in pairs(robux) do
		if item.Id > 0 then
			task.spawn(function()
				local infoType = item.Pass and Enum.InfoType.GamePass or Enum.InfoType.Product
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, item.Id, infoType)
				if item.Verified then
					local price = ok and verifiedPrice(info, item.Id) or nil
					prices[key] = price and {State = "live", Price = price} or {State = "off"}
				else
					local live = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
					if live and live >= 0 and live == live then
						prices[key] = {State = "live", Price = math.floor(live)}
					end
				end
				fire()
			end)
		end
	end
end

-- -- pending entries -------------------------------------------------------

local function finish(key)
	pending[key] = nil
	if promptOpen == key then promptOpen = nil end
end

local function begin(key, kind, timeout, onTimeout)
	serial += 1
	local entry = {Kind = kind, Serial = serial}
	pending[key] = entry
	task.delay(timeout, function()
		local current = pending[key]
		if not current or current.Serial ~= entry.Serial then return end
		finish(key)
		if onTimeout then onTimeout() end
		fire()
	end)
	fire()
	return entry
end

local lastSent = {} -- "<action>|<pending key>" -> os.clock() of the last FireServer

local function noAnswer() ShopData.notify("No answer from the server yet. Check your balance before trying again.", "info") end

local function sendAction(key, action, payload, onTimeout)
	local entry = begin(key, "action", ACTION_TIMEOUT, onTimeout or noAnswer)
	local windowKey = action .. "|" .. key
	local function send()
		lastSent[windowKey] = os.clock()
		if not pcall(actionRemote.FireServer, actionRemote, action, payload) then
			if pending[key] == entry then finish(key) end
			fire()
		end
	end
	-- A second press right after a fast push would land inside the server's
	-- per-action window and be dropped without a word: hold it until it opens.
	local wait = (lastSent[windowKey] or -math.huge) + WRITE_WINDOW - os.clock()
	if wait > 0 then task.delay(wait, send) else send() end
	return true
end

local promptFinished -- defined below; the QA seam in prompt() needs it

-- Studio QA seam: the L4 probe (RunService:IsStudio() only) can set this to a
-- function(kind, id). prompt() then records the call instead of showing a
-- Roblox purchase prompt, and finishes it as a cancel at once.
ShopData.promptHook = nil

local function prompt(key, item)
	promptOpen = key
	begin(key, "prompt", PROMPT_TIMEOUT)
	local hook = ShopData.promptHook
	if hook then
		hook(item.Pass and "GamePass" or "Product", item.Id)
		task.defer(promptFinished, item.Pass, item.Id, false)
		return true
	end
	local ok, err = pcall(function()
		if item.Pass then
			MarketplaceService:PromptGamePassPurchase(player, item.Id)
		else
			MarketplaceService:PromptProductPurchase(player, item.Id)
		end
	end)
	if not ok then
		warn("[ZyntraShopUI] prompt failed for " .. key .. ": " .. tostring(err))
		finish(key)
		fire()
	end
	return ok
end

local function processing() ShopData.notify("Processing, it will arrive shortly.", "info") end

function promptFinished(isPass, id, purchased)
	for key, entry in pairs(pending) do
		local item = robux[key]
		if entry.Kind == "prompt" and item and item.Pass == isPass and item.Id == id then
			finish(key)
			if purchased then
				-- A product grants in ProcessReceipt and pushes; a pass flips its
				-- ZyntraOwns attribute. Either clears this; silence becomes a toast.
				-- A cancel is not an error: nothing is said.
				if isPass and ShopData.owns(key) then
					ShopData.notify(item.Name .. " is yours.", "success")
				else
					begin(key, "receipt", RECEIPT_TIMEOUT, processing)
				end
			end
			fire()
			return
		end
	end
end

local function ownershipChanged(key)
	local entry = pending[key]
	if entry and entry.Kind == "receipt" and ShopData.owns(key) then
		finish(key)
		ShopData.notify(robux[key].Name .. " is yours.", "success")
	end
	fire()
end

-- -- the ONE dispatcher ----------------------------------------------------
-- Every L4 button calls this and nothing else prompts or fires. Returns true
-- only when a request actually left the client.
function ShopData.purchase(key, arg)
	if not ShopData.ready() or type(key) ~= "string" then return false end
	local tokens = ShopData.tokens()

	if key == "Skin" then
		local state = ShopData.skinState(arg)
		if not state then return false end
		if state.Item.Kind == "Robux" and not state.Owned then return ShopData.purchase(arg) end
		local pendingKey = "Skin:" .. arg
		if pending[pendingKey] then return false end
		if state.Owned then
			-- The server drops EquipSkin silently unless the PROFILE owns the suit.
			if state.Equipped or not state.Equippable then return false end
			return sendAction(pendingKey, "EquipSkin", arg)
		end
		local item = state.Item
		if item.Kind ~= "Tokens" or state.Clears < (item.RequiredClears or 0)
			or tokens < (tonumber(item.TokenCost) or 0) then return false end
		return sendAction(pendingKey, "BuySkin", arg)
	end

	local item = robux[key]
	if item then
		if promptOpen or pending[key] or item.Id <= 0 then return false end
		-- Owned OR not read yet: never prompt a pass on a guess.
		if item.Pass and ShopData.owns(key) ~= false then return false end
		if item.Verified and prices[key].State ~= "live" then return false end
		return prompt(key, item)
	end

	if key == "Stamina" or key == "Battery" then
		if pending[key] or tokens < Config.UpgradeCost(profile[key .. "Level"]) then return false end
		return sendAction(key, "Upgrade" .. key)
	end

	local supply = type(Config.Items) == "table" and Config.Items[key] or nil
	if supply then
		if pending[key] or tokens < (tonumber(supply.TokenCost) or 0) then return false end
		return sendAction(key, "BuyItem", {Key = key})
	end

	if key == "EntityShield" then
		local state = ProtectionClient.GetState()
		if state.Pending then
			if not state.CanRetry then return false end
			ProtectionClient.Retry()
			return true
		end
		if not state.Available then return false end
		return ProtectionClient.Request("BuyProtection") == true
	end

	if key == "Color" and type(arg) == "table" then
		local pass = ShopData.PICKERS[arg.Picker]
		local pendingKey = "Color:" .. tostring(arg.Picker)
		if not pass or typeof(arg.Color) ~= "Color3" or pending[pendingKey]
			or not ShopData.owns(pass) then return false end
		return sendAction(pendingKey, "Set" .. arg.Picker .. "Color", arg.Color)
	end

	return false
end

-- -- daily rewards (Zyntra Daily L4) ----------------------------------------

-- A forced re-read: the daily window on open, at the UTC reset, and after a claim
-- nobody answered. An answer that left before a newer push is dropped.
function ShopData.refresh()
	if requesting then return end
	requesting = true
	local seen = pushes
	task.spawn(function()
		local ok, data = pcall(getProfile.InvokeServer, getProfile)
		requesting = false
		if ok and type(data) == "table" and seen == pushes then
			profile = data
			fire()
		end
	end)
end

-- A playtime milestone, through the legacy remote and payload. The window offers
-- CLAIM only when the profile says the milestone is reached and unclaimed; the
-- server re-checks it and answers with a push, which ends the pending entry
-- ("Daily:<minutes>"). Silence is a re-read, never a local grant.
function ShopData.claim(minutes)
	local key = "Daily:" .. tostring(minutes)
	if not ShopData.ready() or type(minutes) ~= "number" or pending[key] then return false end
	return sendAction(key, "ClaimPlaytimeReward", {Minutes = minutes}, function()
		ShopData.notify("No answer yet. Try again.", "error")
		ShopData.refresh()
	end)
end

-- -- settings (the SETTINGS page) ------------------------------------------
-- The retired terminal's contract, unchanged: SetAccessibility {Key, Enabled}
-- for a ZyntraConfig.AccessibilitySettings key, drawn at once and confirmed by
-- the player attribute the server publishes (a push does not end it, so this is
-- not sendAction); silently put back after 12 s if the attribute never agrees.
-- One fix: a press inside the server's 1 s per-key window is held until the
-- window has passed, and a newer press replaces a held one. The terminal sent
-- it to be dropped, so a quick ON-OFF showed the dropped OFF for 12 s.
local SETTING_REVERT = 12
local switches = {} -- key -> {Default, Pending = bool?, Serial, Sent = os.clock()}
for _, entry in ipairs(Config.AccessibilitySettings or {}) do
	if type(entry) == "table" and type(entry.Key) == "string" and entry.Hidden ~= true then
		switches[entry.Key] = {Default = entry.Default == true, Serial = 0}
	end
end

-- The value drawn: the press in flight, else the attribute, else the config
-- default (nil is not "off": captions and lobby music default ON). nil for a key
-- that is not a visible setting.
function ShopData.setting(key)
	local switch = switches[key]
	if not switch then return nil end
	if switch.Pending ~= nil then return switch.Pending end
	local value = player:GetAttribute(key)
	if value == nil then return switch.Default end
	return value == true
end

-- LobbyMusicEnabled stands down until the server has published it: the music
-- client plays only on true, so a default is no answer for it.
function ShopData.settingReady(key)
	return switches[key] ~= nil and (key ~= "LobbyMusicEnabled" or type(player:GetAttribute(key)) == "boolean")
end

function ShopData.toggleSetting(key)
	local switch = switches[key]
	if not ShopData.settingReady(key) then return false end
	local wanted = not ShopData.setting(key)
	switch.Pending = wanted
	switch.Serial += 1
	local mine = switch.Serial
	local function send()
		if switch.Serial ~= mine then return end -- a newer press took its place
		switch.Sent = os.clock()
		pcall(actionRemote.FireServer, actionRemote, "SetAccessibility", {Key = key, Enabled = wanted})
	end
	local wait = (switch.Sent or -math.huge) + WRITE_WINDOW - os.clock()
	if wait > 0 then task.delay(wait, send) else send() end
	task.delay(SETTING_REVERT, function()
		if switch.Serial == mine and switch.Pending ~= nil then
			switch.Pending = nil
			fire()
		end
	end)
	fire()
	return true
end

-- -- start -----------------------------------------------------------------

local function requestProfile(retries)
	if requesting or profile then return end
	requesting = true
	task.spawn(function()
		local ok, data = pcall(getProfile.InvokeServer, getProfile)
		requesting = false
		if profile then return end -- a push won the race; never overwrite it
		if ok and type(data) == "table" then
			profile = data
			fire()
		elseif (retries or 0) > 0 then
			task.delay(PROFILE_RETRY, function() requestProfile(retries - 1) end)
		end
	end)
end

function ShopData.start()
	if started then return end
	started = true
	profileChanged.OnClientEvent:Connect(function(data, text, tone)
		if type(data) == "table" then profile = data end
		pushes += 1
		-- The next push ends every token request and every product receipt; a
		-- pass receipt waits for its ownership attribute instead.
		for key, entry in pairs(pending) do
			if entry.Kind == "action" or (entry.Kind == "receipt" and not robux[key].Pass) then
				pending[key] = nil
			end
		end
		if type(text) == "string" and text ~= "" then ShopData.notify(text, tone) end
		fire()
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, id, purchased)
		if who == player then promptFinished(true, id, purchased == true) end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id, purchased)
		if userId == player.UserId then promptFinished(false, id, purchased == true) end
	end)
	local watched = {Donation20K = true}
	for key, item in pairs(robux) do if item.Pass then watched[key] = true end end
	for key in pairs(((Config.TokenEarner or {}).Passes) or {}) do watched[key] = true end
	for key in pairs(watched) do
		player:GetAttributeChangedSignal("ZyntraOwns" .. key):Connect(function() ownershipChanged(key) end)
	end
	player:GetAttributeChangedSignal("ZyntraTokenEarnerMultiplier"):Connect(function()
		if robux.TokenEarner2x then ownershipChanged("TokenEarner2x") else fire() end
	end)
	player:GetAttributeChangedSignal("ZyntraProfileLoaded"):Connect(function()
		if player:GetAttribute("ZyntraProfileLoaded") == true and not profile then requestProfile(0) end
		fire()
	end)
	ProtectionClient.Changed:Connect(fire)
	for key, switch in pairs(switches) do
		player:GetAttributeChangedSignal(key):Connect(function()
			if switch.Pending == nil or player:GetAttribute(key) == switch.Pending then switch.Pending = nil end
			fire()
		end)
	end
	requestProfile(1)
end

return ShopData
