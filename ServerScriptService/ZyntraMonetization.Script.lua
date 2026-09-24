-- ZyntraMonetization
-- Server-owned persistence, pass grants, developer product receipts and upgrade actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")

local PlayerProtection = require(script.Parent:WaitForChild("PlayerProtection"))
-- Best-effort developer purchase alerts. Optional by construction: a missing or
-- broken module must never be able to affect a receipt, so the require is
-- non-blocking and pcall'd, and so is every call.
local PurchaseAlerts
do
	local alertModule = script.Parent:FindFirstChild("PurchaseAlerts")
	if alertModule then
		local ok, loaded = pcall(require, alertModule)
		PurchaseAlerts = ok and type(loaded) == "table" and loaded or nil
	end
end
-- ANALYTICS_20260921. Measurement only; ServerScriptService.ZyntraAnalytics
-- states the contract. No call below can yield, throw or touch a DataStore.
-- Optional by construction, like the alert module above: a place without the
-- module still loads, and the offline suites that run slices of this file in
-- isolation still run them. Every call site is guarded for that reason.
local Analytics
do
	local module = script.Parent:FindFirstChild("ZyntraAnalytics")
	if module then
		local ok, loaded = pcall(require, module)
		Analytics = ok and type(loaded) == "table" and loaded or nil
	end
end
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local store = DataStoreService:GetDataStore(Config.DataStoreName)
local supportStore = DataStoreService:GetOrderedDataStore(Config.SupportLeaderboardDataStoreName)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PERCENT_PER_LEVEL = math.floor(Config.TokenPercentPerLevel * 100 + 0.5)
local PCT = PERCENT_PER_LEVEL .. "%"

-- The accessibility switches, resolved once. The list is the whole contract:
-- every key here is persisted in profile.Settings, published as a player
-- attribute of the same name, carried in the public profile, and is the only
-- key SetAccessibility will accept.
local ACCESSIBILITY_SETTINGS = Config.AccessibilitySettings or {}
local ACCESSIBILITY_BY_KEY = {}
for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
	ACCESSIBILITY_BY_KEY[setting.Key] = setting
end

local SUPPORT_LEADERBOARD_SIZE = math.clamp(math.floor(tonumber(Config.SupportLeaderboardSize) or 10), 1, 25)
local supportFolder = ReplicatedStorage:FindFirstChild("ZyntraDonationLeaderboard")
if supportFolder and not supportFolder:IsA("Folder") then
	supportFolder:Destroy()
	supportFolder = nil
end
if not supportFolder then
	supportFolder = Instance.new("Folder")
	supportFolder.Name = "ZyntraDonationLeaderboard"
	supportFolder.Parent = ReplicatedStorage
end

local supportStatus = supportFolder:FindFirstChild("Status")
if supportStatus and not supportStatus:IsA("StringValue") then supportStatus:Destroy(); supportStatus = nil end
if not supportStatus then
	supportStatus = Instance.new("StringValue")
	supportStatus.Name = "Status"
	supportStatus.Parent = supportFolder
end
supportStatus.Value = "CONNECTING TO SUPPORT RANKINGS"

local supportRows = {}
for rank = 1, SUPPORT_LEADERBOARD_SIZE do
	local name = string.format("Row%02d", rank)
	local row = supportFolder:FindFirstChild(name)
	if row and not row:IsA("StringValue") then row:Destroy(); row = nil end
	if not row then
		row = Instance.new("StringValue")
		row.Name = name
		row.Parent = supportFolder
	end
	row.Value = rank == 1 and "NO SUPPORT RECORDED YET" or ""
	supportRows[rank] = row
end

local function ensureRemote(className, name)
	local existing = remotes:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	if existing then existing:Destroy() end
	local object = Instance.new(className)
	object.Name = name
	object.Parent = remotes
	return object
end

local getProfileRemote = ensureRemote("RemoteFunction", "ZyntraGetProfile")
local claimLobbyBriefingRemote = ensureRemote("RemoteFunction", "ZyntraClaimLobbyBriefing")
local actionRemote = ensureRemote("RemoteEvent", "ZyntraAction")
local profileChangedRemote = ensureRemote("RemoteEvent", "ZyntraProfileChanged")

local levelCompletedEvent = ServerStorage:FindFirstChild("ZyntraLevelCompleted")
if not levelCompletedEvent then
	levelCompletedEvent = Instance.new("BindableEvent")
	levelCompletedEvent.Name = "ZyntraLevelCompleted"
	levelCompletedEvent.Parent = ServerStorage
end

local sessions = {}
local protectionAttempts = {}
local protectionResponses = {}
local mutationLocks = {}
-- player -> { [action window key] = os.clock() of the last accepted call }.
local actionTimes = {}
local dispatchMuteQueues = {}
local briefingClaims = {}
local pendingDispatchSnapshots = {}
local dispatchSnapshotConnection
local profileLoads = setmetatable({}, { __mode = "k" })
local sessionFinalizers = setmetatable({}, { __mode = "k" })
local activeSessionFinalizers = 0
local serverClosing = false

local DISPATCH_SNAPSHOT_TOPIC = "ZyntraDispatchPreferenceV1"
-- A superseded server gets this long to atomically hand off its final accepted
-- mute target. Afterwards the current lease fences every older claim. This is
-- deliberately elapsed-time based on the current server: no cross-server wall
-- clock participates in preference ordering or decides which input wins.
-- BindToClose waits at most 25 seconds below. Five seconds of margin ensures a
-- legitimate shutdown handoff is never fenced while that finalizer may run.
local DISPATCH_HANDOFF_GRACE_SECONDS = 30
local DISPATCH_RECOVERY_RETRY_SECONDS = 30

local function colorData(color)
	return {
		R = math.floor(math.clamp(color.R, 0, 1) * 255 + 0.5),
		G = math.floor(math.clamp(color.G, 0, 1) * 255 + 0.5),
		B = math.floor(math.clamp(color.B, 0, 1) * 255 + 0.5),
	}
end

local function readColor(value, fallback)
	if type(value) ~= "table" then return fallback end
	return Color3.fromRGB(
		math.clamp(math.floor(tonumber(value.R) or fallback.R * 255), 0, 255),
		math.clamp(math.floor(tonumber(value.G) or fallback.G * 255), 0, 255),
		math.clamp(math.floor(tonumber(value.B) or fallback.B * 255), 0, 255)
	)
end

local MAX_SAFE_SUPPORT = 9007199254740991
local function isSafeSupportAmount(value)
	return type(value) == "number" and value == value and value >= 0
		and value <= MAX_SAFE_SUPPORT and value % 1 == 0
end

local function normalizedSupportAmount(value)
	local amount = tonumber(value)
	if not amount or amount ~= amount or amount < 0 or amount > MAX_SAFE_SUPPORT then return 0 end
	return math.floor(amount)
end

local function recordedSupportRobux(data)
	if not data then return 0 end
	return math.min(MAX_SAFE_SUPPORT,
		normalizedSupportAmount(data.DonationRobux) + normalizedSupportAmount(data.UtilityRobux)
			+ normalizedSupportAmount(data.PassRobux))
end

-- One bounded operation per inventory, separate from Roblox receipt history.
local function protectionState(data)
	local value = data and data.Protection
	if type(value) ~= "table" or not isSafeSupportAmount(value.Charges)
		or not isSafeSupportAmount(value.Revision) then return nil end
	local operation = value.LastOperation
	if operation ~= nil then
		if type(operation) ~= "table" or type(operation.SessionId) ~= "string"
			or #operation.SessionId == 0 or #operation.SessionId > 128
			or operation.Revision ~= value.Revision or operation.Revision < 1 then return nil end
		if operation.Kind == "Buy" then
			if operation.Status ~= "Bought" then return nil end
		elseif operation.Kind == "Use" then
			if operation.Status ~= "Reserved" and operation.Status ~= "Consumed"
				and operation.Status ~= "Refunded" then return nil end
		else
			return nil
		end
	elseif value.Revision ~= 0 then
		return nil
	end
	return value
end

local function protectionResult(value)
	local state = protectionState({Protection = value})
	local operation = state and state.LastOperation
	if not operation or operation.Status == "Reserved" then return nil end
	return {
		Action = operation.Kind == "Buy" and "BuyProtection" or "UseProtection",
		SessionNonce = operation.SessionId,
		Revision = operation.Revision - 1,
		Status = operation.Status,
	}
end

local function recoverProtectionReservation(data, ownerId)
	-- Called only in the existing atomic load/lease claim. An interrupted use
	-- never resumes gameplay. A still-Reserved operation gets one refund even
	-- if its old server applied an effect but lost the completion response.
	if data.Settings.MuteDispatchSessionId ~= ownerId then return false end
	local state = protectionState(data)
	local operation = state and state.LastOperation
	if not operation or operation.Status ~= "Reserved" or operation.SessionId == ownerId
		or state.Charges >= MAX_SAFE_SUPPORT then return false end
	state.Charges += 1
	operation.Status = "Refunded"
	return true
end

-- ---------------------------------------------------------------------------
-- Stored items, daily counters and the inert legacy field-note record
-- ---------------------------------------------------------------------------
-- The two stored consumables. One spelling serves as the profile field, the
-- Config.Items key, the BuyItem payload and the ZyntraInventory key; do not
-- introduce a second. EntityShield is deliberately NOT one of them: its charges
-- live in Protection.Charges and only applyReward may add one there.
local ITEM_KEYS = {"SpeedPotion", "RouteMarker"}
local ITEM_CONFIG = Config.Items or {}
local DAILY_REWARDS = Config.DailyRewards or {}
local DailyResearch = require(ReplicatedStorage:WaitForChild("ZyntraDailyResearch"))
local Skins = require(ReplicatedStorage:WaitForChild("ZyntraSkins"))
-- CHALLENGES_20260923 (Trello FnF49TWk): the pure record/challenge ledger.
local Challenges = require(ReplicatedStorage:WaitForChild("ZyntraChallenges"))
-- A consumable spent during a round makes that run assisted. Latched at the
-- moment of use: the round-end resets wipe the per-round attributes before the
-- completion event arrives. GameManager clears it when a round opens and reads
-- it for each escapee.
local function markRunAided(player)
	if player:GetAttribute("InRound") == true then player:SetAttribute("ZyntraRunAided", true) end
end

-- The clock every day comparison goes through, in one place so a test can pin
-- "today" and "now". Nothing else in this file reads the date.
local dailyClock = {
	day = function() return os.date("!%Y-%m-%d") end,
	now = os.time,
}
local function utcDay() return dailyClock.day() end
local function secondsToReset()
	local now = math.max(0, math.floor(tonumber(dailyClock.now()) or 0))
	return 86400 - now % 86400
end

-- A whole count a player can actually spend, or zero. Same rule the support
-- amounts use, so a hand-edited save cannot put a fraction, a NaN or a string
-- into an inventory.
local function wholeCount(value)
	return isSafeSupportAmount(value) and value or 0
end

-- Rebuilt from the KNOWN key set on every load, exactly like LevelsCleared and
-- AwardedBadges: a corrupt save can neither grow the inventory without bound nor
-- introduce an item this build has no way to spend.
local function normalizeItems(value)
	local saved = type(value) == "table" and value or {}
	local items = {}
	for _, key in ipairs(ITEM_KEYS) do items[key] = wholeCount(saved[key]) end
	return items
end

-- Today's counters. Day is the UTC day they belong to; when it no longer
-- matches, rollDaily below resets them inside whatever transaction reads them
-- next, so the roll can never be lost between a read and its write. WheelDay is
-- NOT part of that reset: it records the day of the last spin and is compared to
-- today directly. FlushId is the identity of the last playtime flush that landed
-- and is what makes a re-sent flush add nothing a second time.
local function normalizeDaily(value)
	local saved = type(value) == "table" and value or {}
	local function savedDay(field)
		local day = saved[field]
		return type(day) == "string" and #day == 10 and day or nil
	end
	local claimed = {}
	local savedClaimed = type(saved.Claimed) == "table" and saved.Claimed or {}
	for _, milestone in ipairs(DAILY_REWARDS.Milestones or {}) do
		local key = tostring(milestone.Minutes)
		if savedClaimed[key] == true then claimed[key] = true end
	end
	local wheelDay = savedDay("WheelDay")
	local wheelLast
	local savedLast = type(saved.WheelLast) == "table" and saved.WheelLast or nil
	if savedLast and type(savedLast.Key) == "string"
		and #savedLast.Key > 0 and #savedLast.Key <= 64 then
		local lastDay = savedLast.Day
		wheelLast = {
			Day = type(lastDay) == "string" and #lastDay == 10 and lastDay or wheelDay,
			Key = savedLast.Key,
			Serial = wholeCount(savedLast.Serial),
			-- WHEEL_COLLECT_20260922 (Trello 25GLltY6): a spin now records the
			-- prize and the CLAIM pays it. Only an explicit false is still owed;
			-- every result saved before this field existed was paid at spin time
			-- and must never be paid again.
			Claimed = savedLast.Claimed ~= false,
		}
		if savedLast.Key == "Skin5" then
			-- Only the two wheel-eligible suits can survive into a pending prize.
			-- A missing/invalid ID becomes the disclosed fallback instead of
			-- leaving an old save with an uncollectable prize forever.
			for _, skinId in ipairs(Skins.WheelEligible) do
				if savedLast.SkinId == skinId then wheelLast.SkinId = skinId; break end
			end
			if savedLast.FallbackTokens == 3 or not wheelLast.SkinId then
				wheelLast.FallbackTokens = 3
			end
		end
		-- TOKEN_EARNER_20260924: the tokens a claim actually paid, so the wheel's
		-- COLLECTED face names the multiplied amount. Absent on older records.
		local paidTokens = wholeCount(savedLast.PaidTokens)
		if paidTokens > 0 then wheelLast.PaidTokens = paidTokens end
	end
	local flushId = saved.FlushId
	return {
		-- Deliberately left nil when a save has none: "these counters belong to no
		-- day yet" is exactly right for a profile written before daily rewards
		-- existed, and the first daily transaction rolls it onto today. Reading the
		-- clock here instead would make normalization depend on it.
		Day = savedDay("Day"),
		Research = DailyResearch.Normalize(saved.Research),
		PlaytimeSeconds = wholeCount(saved.PlaytimeSeconds),
		Claimed = claimed,
		WheelDay = wheelDay,
		WheelLast = wheelLast,
		FlushId = type(flushId) == "string" and #flushId > 0 and #flushId <= 128 and flushId or nil,
	}
end

-- Discovered note ids, as string keys of a bounded length. Serial only grows, so
-- a UI can tell one discovery from the next without diffing the whole set.
local function normalizeFieldNotes(value)
	local saved = type(value) == "table" and value or {}
	local discovered = {}
	local savedDiscovered = type(saved.Discovered) == "table" and saved.Discovered or {}
	for key, flag in pairs(savedDiscovered) do
		if flag == true and type(key) == "string" and #key > 0 and #key <= 32 then
			discovered[key] = true
		end
	end
	return {Discovered = discovered, Serial = wholeCount(saved.Serial)}
end

-- Resets the counters that belong to a day that has already passed. Returns
-- whether it changed anything, because a caller that goes on to refuse must know
-- whether this transform has already touched the profile.
local function rollDaily(data, today)
	local daily = data.Daily
	if daily.Day == today then return false end
	daily.Day = today
	daily.PlaytimeSeconds = 0
	daily.Claimed = {}
	daily.Research = DailyResearch.Normalize(nil)
	return true
end

-- The one place a reward turns into profile state, shared by the playtime
-- milestones and the wheel so a prize cannot mean two different things in two
-- places. Returns a short human label, or nil when this build cannot pay the
-- reward -- a caller must read nil as "granted nothing" and refuse.
-- `tier` (TOKEN_EARNER_20260924) multiplies a Tokens reward only: callers pass
-- tokenEarner.tier(player), read once before their write.
local function applyReward(data, reward, tier)
	if type(reward) ~= "table" then return nil end
	local amount = wholeCount(reward.Amount)
	if amount < 1 then return nil end
	if reward.Kind == "Tokens" then
		amount *= (tier == 2 or tier == 3 or tier == 5) and tier or 1
		if not isSafeSupportAmount(data.Tokens)
			or amount > MAX_SAFE_SUPPORT - data.Tokens then return nil end
		data.Tokens += amount
		return amount .. (amount == 1 and " Research Token" or " Research Tokens")
	end
	if reward.Kind ~= "Item" then return nil end
	if reward.Key == "EntityShield" then
		-- A reward is not an inventory OPERATION. It adds a charge and leaves
		-- Revision and LastOperation exactly as they were, so a buy or use that is
		-- still in flight keeps its identity and cannot be resolved by this write.
		-- A Protection table that does not validate is left alone for repair
		-- rather than being replaced with invented charges.
		local state = protectionState(data)
		if not state or amount > MAX_SAFE_SUPPORT - state.Charges then return nil end
		state.Charges += amount
		return amount == 1 and "1 Entity Shield charge" or amount .. " Entity Shield charges"
	end
	local item = ITEM_CONFIG[reward.Key]
	local owned = item and data.Items[reward.Key]
	if not owned or amount > MAX_SAFE_SUPPORT - owned then return nil end
	data.Items[reward.Key] = owned + amount
	return amount .. " " .. item.Name .. (amount == 1 and "" or "s")
end

-- TOKEN_EARNER_20260924 (Trello EtdsUM4e). The tier is session state that
-- refreshPasses resolves from Roblox pass ownership. A caller reads it ONCE,
-- before its write, so every retry of that write pays the same; `bonus` tops up
-- tokens a transform has just EARNED. Balances, bought packs, refunds and grants
-- never pass through here.
local tokenEarner = {}
function tokenEarner.tier(player)
	local tier = player:GetAttribute("ZyntraTokenEarnerMultiplier")
	return (tier == 2 or tier == 3 or tier == 5) and tier or 1
end
function tokenEarner.bonus(data, earned, tier)
	local extra = math.max(0, math.floor(earned)) * (tier - 1)
	if extra < 1 or extra > MAX_SAFE_SUPPORT - data.Tokens then return 0 end
	data.Tokens += extra
	return extra
end

-- Live playtime accrual, per loaded player: where they were, when they last
-- moved, and the seconds earned since the last flush landed. Weak keys because
-- this is session state; finalizePlayerSession clears it explicitly as well.
local playtimeSessions = setmetatable({}, { __mode = "k" })
local playtimeSessionSequence = 0

-- FIELD_NOTES_REMOVED_20260922 (owner instruction). The Field Notes feature --
-- placed notes, the reading card, the NOTES tab, the discovery progress and the
-- FIELD ARCHIVIST title -- is gone. A profile's FieldNotes table is kept as
-- INERT legacy data by normalizeFieldNotes so an old save still loads exactly
-- as it was; nothing reads it, grants from it, or publishes a title off it.

-- The daily block as the client sees it. PlaytimeSeconds INCLUDES the seconds
-- this session has earned but not yet flushed, so the page never counts
-- backwards over a flush, and the counters are presented through the pending day
-- roll -- yesterday's playtime and claims are already spent, and publishing them
-- would show a claim button that the transform is guaranteed to refuse.
local function dailyPublic(data, player)
	local today = utcDay()
	local daily = data.Daily
	local sameDay = daily.Day == today
	local pending = playtimeSessions[player]
	local pendingSeconds = pending and pending.day == today and wholeCount(pending.unflushedSeconds) or 0
	-- mutate publishes before its caller returns. Once this flush is present in
	-- the saved profile, its seconds are no longer pending in that payload.
	if sameDay and pending and pending.activeFlushId == daily.FlushId then
		pendingSeconds = math.max(0, pendingSeconds - wholeCount(pending.activeFlushSeconds))
	end
	return {
		Day = today,
		Today = today,
		PlaytimeSeconds = (sameDay and daily.PlaytimeSeconds or 0)
			+ pendingSeconds,
		Claimed = sameDay and daily.Claimed or {},
		Research = DailyResearch.Public(daily.Research, sameDay),
		WheelDay = daily.WheelDay,
		WheelLast = daily.WheelLast,
		SecondsToReset = secondsToReset(),
		Accruing = pending ~= nil and pending.accruing == true,
	}
end

local function newProfile()
	return {
		Version = 4,
		Tokens = RunService:IsStudio() and Config.Studio.StartingTokens or 0,
		StaminaLevel = 0,
		BatteryLevel = 0,
		CompletedLevels = 0,
		-- FRIEND_BOOST_20260916. The part of a Friend Boost that has been earned
		-- but not yet paid, in TENTHS of a token (0..9). +10% of a 2-token clear
		-- is 0.2 of a token, so without this a one-friend boost would round to
		-- nothing every single time; with it, the fifth clear pays the whole token.
		FriendBoostTenths = 0,
		-- Which levels have been cleared at least once (string keys so the
		-- DataStore never turns this into a sparse array), and which badges have
		-- already been handed out. The badge set is what makes an award
		-- idempotent without asking Roblox on every clear.
		LevelsCleared = {},
		AwardedBadges = {},
		-- COMPLETION_SAVE_20260924: ids of the latest applied clears, oldest first.
		CompletionIds = {},
		-- CHALLENGES_20260923: personal records per level x solo/party x
		-- clean/assisted, and which one-time challenges are already paid.
		Records = {},
		Challenges = {NoDeath = {}, TimeGoal = {}},
		ReentryCredits = 0,
		Protection = {Charges = 0, Revision = 0},
		-- Stored consumables, today's daily counters and the note collection.
		-- Additive: every one of them normalizes from nil, so schema 4 saves
		-- written before they existed load without a version bump.
		Items = {SpeedPotion = 0, RouteMarker = 0},
		Skins = Skins.Normalize(nil),
		Daily = {PlaytimeSeconds = 0, Claimed = {}, Research = DailyResearch.Normalize(nil)},
		FieldNotes = {Discovered = {}, Serial = 0},
		DonationRobux = 0,
		UtilityRobux = 0,
		-- Game passes and private servers are bought on Roblox's own storefront
		-- and never reach ProcessReceipt, so this third stream has no live writer
		-- at all: only the historical sales import at the bottom of this script
		-- fills it.
		PassRobux = 0,
		Settings = {
			MuteDispatch = false,
			MuteDispatchInputEpoch = 0,
			MuteDispatchRevision = 0,
			MuteDispatchClosedEpoch = 0,
			MuteDispatchSessionEpoch = 0,
			MuteDispatchSessionId = nil,
			MuteDispatchSessionClaims = {},
			LobbyBriefingPlayed = false,
			-- REWARDS_INTRO_20260922 (Trello MsEn2mya): the one-time Rewards/Wheel
			-- note shown after the first real level completion.
			RewardsIntroSeen = false,
		},
		Colors = {
			Hazmat = colorData(Config.Colors.HazmatDefault),
			Glowstick = colorData(Config.Colors.GlowstickDefault),
		},
		Grants = {
			Supporter = false,
			AdvancedEquipment = false,
		},
		ReceiptIds = {},
	}
end

local function normalizeProfile(data)
	local existingProfile = type(data) == "table"
	if not existingProfile then data = newProfile() end
	data.Version = 4
	-- Additive inventory: preserve malformed saved state for repair instead of
	-- inventing charges or discarding an unresolved reservation.
	if data.Protection == nil then data.Protection = {Charges = 0, Revision = 0} end
	data.Tokens = math.max(0, math.floor(tonumber(data.Tokens) or 0))
	data.StaminaLevel = math.max(0, math.floor(tonumber(data.StaminaLevel) or 0))
	data.BatteryLevel = math.max(0, math.floor(tonumber(data.BatteryLevel) or 0))
	data.CompletedLevels = math.max(0, math.floor(tonumber(data.CompletedLevels) or 0))
	-- FRIEND_BOOST_20260916. The unpaid fraction of a Friend Boost, in tenths of
	-- a token. Range-tested rather than clamped: a NaN and a hand-edited 999 both
	-- fail the test and reset to 0, where math.clamp would have propagated the NaN
	-- straight into the token balance.
	local friendBoostTenths = math.floor(tonumber(data.FriendBoostTenths) or 0)
	data.FriendBoostTenths = (friendBoostTenths >= 0 and friendBoostTenths <= 9)
		and friendBoostTenths or 0
	-- Both sets are rebuilt from a KNOWN key set, so a corrupt or hand-edited
	-- save can neither grow the profile without bound nor claim a badge that
	-- this build does not know about. Numeric level keys from an older write are
	-- accepted once and re-saved as strings.
	local levelsCleared = {}
	local savedLevels = type(data.LevelsCleared) == "table" and data.LevelsCleared or {}
	for level = 1, 3 do
		local levelKey = tostring(level)
		if savedLevels[levelKey] == true or savedLevels[level] == true then
			levelsCleared[levelKey] = true
		end
	end
	data.LevelsCleared = levelsCleared
	local awardedBadges = {}
	local savedBadges = type(data.AwardedBadges) == "table" and data.AwardedBadges or {}
	for badgeKey in pairs(Config.Badges or {}) do
		if savedBadges[badgeKey] == true then awardedBadges[badgeKey] = true end
	end
	data.AwardedBadges = awardedBadges
	-- COMPLETION_SAVE_20260924. Only an in-flight retry of a clear ever looks an
	-- id up, and those end with this server's session, so the newest 20 are
	-- plenty; unlike ReceiptIds nothing outside this server can replay one.
	local completionIds = {}
	for _, id in ipairs(type(data.CompletionIds) == "table" and data.CompletionIds or {}) do
		if type(id) == "string" and #id > 0 and #id <= 96 then table.insert(completionIds, id) end
	end
	while #completionIds > 20 do table.remove(completionIds, 1) end
	data.CompletionIds = completionIds
	data.Records = Challenges.NormalizeRecords(data.Records, Config.Challenges)
	data.Challenges = Challenges.NormalizeDone(data.Challenges, Config.Challenges)
	data.ReentryCredits = math.max(0, math.floor(tonumber(data.ReentryCredits) or 0))
	data.Items = normalizeItems(data.Items)
	data.Skins = Skins.Normalize(data.Skins)
	data.Daily = normalizeDaily(data.Daily)
	data.FieldNotes = normalizeFieldNotes(data.FieldNotes)
	-- Keep the two recorded streams separate. Retired SupportRobux and old
	-- utility ReceiptIds are not evidence of an additional, uncounted payment.
	data.DonationRobux = normalizedSupportAmount(data.DonationRobux)
	data.UtilityRobux = normalizedSupportAmount(data.UtilityRobux)
	data.PassRobux = normalizedSupportAmount(data.PassRobux)
	-- Historical sales import bookkeeping: which export sources this profile has
	-- seen, and which individual rows of them have been applied. Permanent for
	-- the same reason ReceiptIds is -- dropping a row marker would let a re-run
	-- of the same export pay a game pass into the total a second time. Both are
	-- rebuilt from validated string keys so a hand-edited save cannot inject one.
	local salesImport = type(data.SalesImport) == "table" and data.SalesImport or {}
	local importSources, importRows = {}, {}
	for key, value in pairs(type(salesImport.Sources) == "table" and salesImport.Sources or {}) do
		if value == true and type(key) == "string" and #key > 0 and #key <= 64 then
			importSources[key] = true
		end
	end
	for key, value in pairs(type(salesImport.Rows) == "table" and salesImport.Rows or {}) do
		if value == true and type(key) == "string" and #key > 0 and #key <= 64 then
			importRows[key] = true
		end
	end
	data.SalesImport = { Sources = importSources, Rows = importRows }
	data.Settings = type(data.Settings) == "table" and data.Settings or {}
	data.Settings.MuteDispatch = data.Settings.MuteDispatch == true
	data.Settings.MuteDispatchInputEpoch = math.max(0,
		math.floor(tonumber(data.Settings.MuteDispatchInputEpoch) or 0))
	data.Settings.MuteDispatchRevision = math.max(0,
		math.floor(tonumber(data.Settings.MuteDispatchRevision) or 0))
	data.Settings.MuteDispatchClosedEpoch = math.max(0,
		math.floor(tonumber(data.Settings.MuteDispatchClosedEpoch) or 0))
	data.Settings.MuteDispatchSessionEpoch = math.max(
		data.Settings.MuteDispatchInputEpoch,
		math.floor(tonumber(data.Settings.MuteDispatchSessionEpoch) or 0)
	)
	local dispatchSessionId = data.Settings.MuteDispatchSessionId
	data.Settings.MuteDispatchSessionId = type(dispatchSessionId) == "string"
		and #dispatchSessionId > 0 and #dispatchSessionId <= 128 and dispatchSessionId or nil
	local rawSessionClaims = type(data.Settings.MuteDispatchSessionClaims) == "table"
		and data.Settings.MuteDispatchSessionClaims or {}
	local sessionClaims = {}
	local seenSessionClaims = {}
	local firstClaimIndex = math.max(1, #rawSessionClaims - 15)
	for index = firstClaimIndex, #rawSessionClaims do
		local record = rawSessionClaims[index]
		local id = type(record) == "table" and record.Id or nil
		local epoch = type(record) == "table" and math.max(0,
			math.floor(tonumber(record.Epoch) or 0)) or 0
		local previousId = type(record) == "table" and record.PreviousId or nil
		previousId = type(previousId) == "string" and #previousId > 0
			and #previousId <= 128 and previousId or nil
		local previousEpoch = type(record) == "table" and math.max(0,
			math.floor(tonumber(record.PreviousEpoch) or 0)) or 0
		if type(id) == "string" and #id > 0 and #id <= 128
			and epoch > 0 and not seenSessionClaims[id] then
			seenSessionClaims[id] = true
			local closed = record.Closed == true
				and epoch <= data.Settings.MuteDispatchClosedEpoch
			sessionClaims[#sessionClaims + 1] = {
				Id = id,
				Epoch = epoch,
				PreviousId = previousId,
				PreviousEpoch = previousEpoch,
				Departed = record.Departed == true or closed,
				Closed = closed,
				Recovered = closed and record.Recovered == true,
			}
		end
	end
	data.Settings.MuteDispatchSessionClaims = sessionClaims
	data.Settings.MuteDispatchSessionEpoch = math.max(
		data.Settings.MuteDispatchSessionEpoch,
		data.Settings.MuteDispatchClosedEpoch
	)
	if data.Settings.LobbyBriefingPlayed == nil then
		-- Anyone with legacy saved data has already logged in before this lifetime
		-- welcome existed; do not replay it once merely because schema v4 deployed.
		data.Settings.LobbyBriefingPlayed = existingProfile
	else
		data.Settings.LobbyBriefingPlayed = data.Settings.LobbyBriefingPlayed == true
	end
	local claimId = data.Settings.LobbyBriefingClaimId
	data.Settings.LobbyBriefingClaimId = data.Settings.LobbyBriefingPlayed == true
		and type(claimId) == "string" and #claimId <= 128 and claimId or nil
	data.Settings.RewardsIntroSeen = data.Settings.RewardsIntroSeen == true
	-- Accessibility switches are a fixed, config-driven key set: a hand-edited
	-- save can neither add keys nor push a non-boolean into a player attribute,
	-- and an untouched switch lands on its documented default.
	for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
		local value = data.Settings[setting.Key]
		if type(value) ~= "boolean" then value = setting.Default == true end
		data.Settings[setting.Key] = value
	end
	data.Colors = type(data.Colors) == "table" and data.Colors or {}
	data.Colors.Hazmat = colorData(readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault))
	data.Colors.Glowstick = colorData(readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault))
	data.Grants = type(data.Grants) == "table" and data.Grants or {}
	data.Grants.Supporter = data.Grants.Supporter == true
	data.Grants.AdvancedEquipment = data.Grants.AdvancedEquipment == true
	-- Receipt acknowledgement must be permanent. Roblox can retry any unresolved
	-- PurchaseId long after the original purchase; pruning old IDs would allow a
	-- delayed retry to grant the product and donation total a second time.
	-- Keep the established array representation so older live servers remain
	-- compatible during a rolling deploy. Clean malformed/duplicate entries, but
	-- never truncate a valid acknowledged PurchaseId.
	-- Deployment note: restart all servers when this migration first goes live;
	-- builds older than this one still contain the retired 500-receipt cap.
	local receiptIds = {}
	local seenReceiptIds = {}
	if type(data.ReceiptIds) == "table" then
		for key, value in pairs(data.ReceiptIds) do
			local receiptId = type(key) == "number" and value
				or (value == true and key or nil)
			if type(receiptId) == "string" and #receiptId > 0
				and #receiptId <= 128 and not seenReceiptIds[receiptId] then
				seenReceiptIds[receiptId] = true
				table.insert(receiptIds, receiptId)
			end
		end
	end
	data.ReceiptIds = receiptIds
	return data
end

local function isDispatchPredecessorClosed(settings, predecessorEpoch)
	predecessorEpoch = math.max(0, math.floor(tonumber(predecessorEpoch) or 0))
	return math.max(0, math.floor(tonumber(settings.MuteDispatchClosedEpoch) or 0))
		>= predecessorEpoch
end

local function advanceDispatchClosedEpoch(settings)
	local closedEpoch = math.max(0,
		math.floor(tonumber(settings.MuteDispatchClosedEpoch) or 0))
	local advanced = true
	while advanced do
		advanced = false
		for _, record in ipairs(settings.MuteDispatchSessionClaims) do
			local previousEpoch = math.max(0,
				math.floor(tonumber(record.PreviousEpoch) or 0))
			if record.Departed == true and record.Closed ~= true
				and previousEpoch <= closedEpoch then
				record.Closed = true
				closedEpoch = math.max(closedEpoch,
					math.floor(tonumber(record.Epoch) or 0))
				advanced = true
			end
		end
	end
	settings.MuteDispatchClosedEpoch = closedEpoch
	return closedEpoch
end

local function dispatchClaimCanFinalize(settings, sessionId, sessionEpoch)
	for _, record in ipairs(settings.MuteDispatchSessionClaims) do
		if record.Id == sessionId and record.Epoch == sessionEpoch then
			-- Recovery is a permanent fence. A callback that began before the
			-- fence will be re-run by UpdateAsync against this closed record and
			-- may no longer publish its older, previously unknown target.
			return record.Closed ~= true and record.Recovered ~= true
		end
	end
	-- A claim pruned from the bounded history is necessarily older than every
	-- retained lease. Refusing its late target is safer than resurrecting it.
	return false
end

-- Reads one accessibility switch off a profile without assuming it has been
-- normalized yet, so the default is applied in exactly one place.
local function accessibilityValue(data, setting)
	local value = data and data.Settings and data.Settings[setting.Key]
	if type(value) ~= "boolean" then value = setting.Default == true end
	return value
end

-- The switch a player just flipped lives here until its coalesced write lands.
-- Declared this early because EVERY mutation has to consult it: mutate() and
-- mutateIdempotent() replace session.data wholesale with the store's copy, and
-- that copy does not carry the pending toggle -- so an unrelated write (a mute
-- toggle, a level-completion token grant, or the switch's own in-flight write
-- after a second flip) republished the OLD value into the attribute the
-- gameplay readers consume, turning the shake back on for up to a write floor.
local accessibilityQueues = setmetatable({}, { __mode = "k" })

-- Re-assert the pending targets over a profile that was just read back, so the
-- attributes published from it match what the player last asked for. Targets
-- stay in the queue for the session, so once a write has landed this is a no-op.
local function reassertPendingAccessibility(player, data)
	local queue = accessibilityQueues[player]
	if not queue or not data or not data.Settings then return end
	for settingKey, settingValue in pairs(queue.desired) do
		data.Settings[settingKey] = settingValue
	end
end

-- `player` is optional and carries only SESSION facts the saved profile cannot
-- know: the playtime seconds that have not been flushed yet, whether they are
-- accruing right now, and the speed boost that is running. Called without one
-- (a profile that is not a live session) those simply read as "none".
local function advancedStaminaBonus(player)
	return player and player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
		and Config.Passes.AdvancedEquipment.StaminaBonus or 0
end

local function publicProfile(data, player)
	if not data then return nil end
	local result = {
		Tokens = data.Tokens,
		Items = data.Items,
		Skins = Skins.Public(data.Skins),
		Daily = dailyPublic(data, player),
		SpeedBoostUntil = player and player:GetAttribute("ZyntraSpeedBoostUntil") or 0,
		StaminaLevel = data.StaminaLevel,
		BatteryLevel = data.BatteryLevel,
		StaminaPercent = data.StaminaLevel * PERCENT_PER_LEVEL + advancedStaminaBonus(player) * 100,
		BatteryPercent = data.BatteryLevel * PERCENT_PER_LEVEL,
		CompletedLevels = data.CompletedLevels,
		-- The unpaid tenth-of-a-token remainder, carried so the client can see it
		-- exists. It is NOT a balance and no UI spends it.
		FriendBoostTenths = data.FriendBoostTenths,
		-- Carried so campaign progress is observable from a client without
		-- reading the DataStore; nothing in the UI consumes it yet.
		LevelsCleared = data.LevelsCleared,
		-- Read by the terminal's RECORDS page (CHALLENGES_20260923).
		Records = data.Records,
		Challenges = data.Challenges,
		ReentryCredits = data.ReentryCredits,
		ProtectionCharges = protectionState(data) and data.Protection.Charges or 0,
		ProtectionRevision = protectionState(data) and data.Protection.Revision or 0,
		ProtectionLastResult = protectionResult(data.Protection),
		DonationRobux = data.DonationRobux,
		UtilityRobux = data.UtilityRobux,
		PassRobux = data.PassRobux,
		RecordedSupportRobux = recordedSupportRobux(data),
		MuteDispatch = data.Settings.MuteDispatch,
		LobbyBriefingPlayed = data.Settings.LobbyBriefingPlayed,
		RewardsIntroSeen = data.Settings.RewardsIntroSeen,
		HazmatColor = readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault),
		GlowstickColor = readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault),
		OwnsSupporter = false,
		OwnsAdvancedEquipment = false,
		OwnsCosmeticEquipment = false,
		OwnsEntityDetector = false,
	}
	for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
		result[setting.Key] = accessibilityValue(data, setting)
	end
	return result
end

local tagCharacters = {}

local function clearPlayerTags(character)
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	for _, child in ipairs(head:GetChildren()) do
		if child.Name == "ZyntraSupporterTag" or child.Name == "ZyntraDeveloperTag"
			or child.Name == "ZyntraTitleTag" then
			child:Destroy()
		end
	end
end

local function createPlayerTag(head, name, text, row)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Size = UDim2.fromOffset(180, 28)
	billboard.StudsOffset = Vector3.new(0, 2.7, 0)
	-- Size-relative screen spacing keeps two fixed-pixel tags apart even at
	-- their maximum viewing distance. The existing Supporter anchor stays put.
	billboard.SizeOffset = Vector2.new(0, row * 1.1)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 65
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = Color3.fromRGB(90, 235, 215)
	label.TextStrokeColor3 = Color3.fromRGB(5, 12, 14)
	label.TextStrokeTransparency = 0.25
	label.TextScaled = true
	label.Parent = billboard
end

local function refreshPlayerTags(player, character)
	-- Deferred pass refreshes and old CharacterAdded work must not decorate a
	-- retired character, including after its replacement acquires a late Head.
	if player.Parent ~= Players or not character or player.Character ~= character
		or tagCharacters[player] ~= character then return end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	clearPlayerTags(character)
	-- Both tags are lobby badges. Developer identity never grants paid benefits.
	if player:GetAttribute("InRound") == true then return end
	local supporter = player:GetAttribute("ZyntraOwnsSupporter") == true
	local row = 0
	if supporter then
		createPlayerTag(head, "ZyntraSupporterTag", "ZYNTRA SUPPORTER", row)
		row += 1
	end
	if DevAccess.IsAllowed(player) then
		createPlayerTag(head, "ZyntraDeveloperTag", "Developer", row)
		row += 1
	end
end

local function applyHazmatColor(player)
	local character = player.Character
	if not character or player:GetAttribute("InRound") ~= true then return end
	local ownsAdvanced = player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
	if not ownsAdvanced then return end
	local color = player:GetAttribute("ZyntraHazmatColor") or Config.Colors.HazmatDefault
	for _, object in ipairs(character:GetChildren()) do
		if object:IsA("MeshPart") then
			local surface = object:FindFirstChildOfClass("SurfaceAppearance")
			if surface then
				surface.Color = color
			end
		end
	end
end

local function applyAttributes(player, data)
	local step = Config.TokenPercentPerLevel
	-- Raw profile numbers (tokens, levels, credits) travel only in the
	-- ZyntraProfileChanged/ZyntraGetProfile payloads; gameplay consumes the two
	-- derived multipliers plus the cosmetic colors below.
	player:SetAttribute("ZyntraStaminaMultiplier", 1 + data.StaminaLevel * step + advancedStaminaBonus(player))
	player:SetAttribute("ZyntraBatteryMultiplier", 1 + data.BatteryLevel * step)
	player:SetAttribute("ZyntraHazmatColor", readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault))
	-- Cosmetic selection replicates to other players. The visual applicator is
	-- installed only after the imported skinned model passes avatar/animation QA.
	player:SetAttribute("ZyntraSkinId", data.Skins.Equipped)
	player:SetAttribute("ZyntraGlowstickColor", readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault))
	player:SetAttribute("ZyntraMuteDispatch", data.Settings.MuteDispatch)
	player:SetAttribute("ZyntraLobbyBriefingPlayed", data.Settings.LobbyBriefingPlayed)
	player:SetAttribute("ZyntraDonationRobux", data.DonationRobux)
	player:SetAttribute("ZyntraUtilityRobux", data.UtilityRobux)
	player:SetAttribute("ZyntraPassRobux", data.PassRobux)
	player:SetAttribute("ZyntraRecordedSupportRobux", recordedSupportRobux(data))
	-- Stored consumables are attributes because the HUD reads them every frame it
	-- draws a slot; the profile packet carries the same numbers for the terminal.
	player:SetAttribute("ZyntraSpeedPotions", data.Items.SpeedPotion)
	player:SetAttribute("ZyntraRouteMarkers", data.Items.RouteMarker)
	-- Accessibility switches are published under their own bare names because
	-- that is what the client readers already ask for (ReduceCameraShake,
	-- ReduceFlashing, CaptionsEnabled, DisableCaptions) -- do not prefix them.
	for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
		player:SetAttribute(setting.Key, accessibilityValue(data, setting))
	end
	if player:GetAttribute("InRound") == true and player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true then
		player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
	end
	task.defer(applyHazmatColor, player)
end

local function enrichedPublicProfile(player)
	local session = sessions[player]
	local result = session and publicProfile(session.data, player) or nil
	if result then
		result.ProtectionSessionNonce = session.dispatchSessionId
		result.ProtectionAvailable = not RunService:IsStudio() and session.persistent == true
			and not session.closing and not serverClosing and session.dispatchLeaseActive == true
			and protectionState(session.data) ~= nil
			and session.data.Protection.Revision < MAX_SAFE_SUPPORT
		local attempt = protectionAttempts[player]
		local operation = protectionState(session.data) and session.data.Protection.LastOperation
		if operation and operation.Status == "Reserved" and not attempt then
			result.ProtectionAvailable = false
		end
		result.ProtectionPending = attempt and table.clone(attempt.Command) or nil
		result.ProtectionLastResponse = protectionResponses[player]
		result.OwnsSupporter = player:GetAttribute("ZyntraOwnsSupporter") == true
		result.OwnsAdvancedEquipment = player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
		result.OwnsCosmeticEquipment = player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true
		result.OwnsEntityDetector = player:GetAttribute("ZyntraOwnsEntityDetector") == true
	end
	return result
end

local function pushProfile(player, message, tone)
	if not player.Parent then return end
	profileChangedRemote:FireClient(player, enrichedPublicProfile(player), message, tone or "info")
end

local function dispatchSnapshotFromData(userId, data)
	data = normalizeProfile(data)
	return {
		UserId = math.floor(tonumber(userId) or 0),
		SessionId = data.Settings.MuteDispatchSessionId,
		SessionEpoch = data.Settings.MuteDispatchSessionEpoch,
		Muted = data.Settings.MuteDispatch == true,
		InputEpoch = data.Settings.MuteDispatchInputEpoch,
		Revision = data.Settings.MuteDispatchRevision,
		ClosedEpoch = data.Settings.MuteDispatchClosedEpoch,
	}
end

local function validDispatchSnapshot(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.Muted) ~= "boolean" then return nil end
	local userId = math.floor(tonumber(snapshot.UserId) or 0)
	local sessionId = snapshot.SessionId
	local sessionEpoch = math.max(0, math.floor(tonumber(snapshot.SessionEpoch) or 0))
	local inputEpoch = math.max(0, math.floor(tonumber(snapshot.InputEpoch) or 0))
	local revision = math.max(0, math.floor(tonumber(snapshot.Revision) or 0))
	local closedEpoch = math.max(0, math.floor(tonumber(snapshot.ClosedEpoch) or 0))
	if userId <= 0 or sessionEpoch <= 0
		or type(sessionId) ~= "string" or #sessionId == 0 or #sessionId > 128 then return nil end
	return {
		UserId = userId,
		SessionId = sessionId,
		SessionEpoch = sessionEpoch,
		Muted = snapshot.Muted,
		InputEpoch = inputEpoch,
		Revision = revision,
		ClosedEpoch = closedEpoch,
	}
end

local function dispatchVersionIsNewer(leftEpoch, leftRevision, rightEpoch, rightRevision)
	return leftEpoch > rightEpoch or (leftEpoch == rightEpoch and leftRevision > rightRevision)
end

local function applyDispatchSnapshot(snapshot)
	snapshot = validDispatchSnapshot(snapshot)
	if not snapshot then return false end
	local player = Players:GetPlayerByUserId(snapshot.UserId)
	if not player then return false end
	local session = sessions[player]
	if not session then
		local pending = pendingDispatchSnapshots[snapshot.UserId]
		if not pending or snapshot.SessionEpoch > pending.SessionEpoch then
			pendingDispatchSnapshots[snapshot.UserId] = snapshot
		elseif snapshot.SessionEpoch == pending.SessionEpoch then
			if dispatchVersionIsNewer(snapshot.InputEpoch, snapshot.Revision,
				pending.InputEpoch, pending.Revision) then
				pendingDispatchSnapshots[snapshot.UserId] = snapshot
			elseif snapshot.ClosedEpoch > (pending.ClosedEpoch or 0) then
				pending.ClosedEpoch = snapshot.ClosedEpoch
			end
		end
		return false
	end

	-- Serialize local snapshot application with every profile mutation. A
	-- DataStore mutation that started before this message must apply its older
	-- response first; the authoritative handoff snapshot then wins locally.
	while mutationLocks[player] do task.wait() end
	mutationLocks[player] = true
	session = sessions[player]
	if not session or session.closing then
		mutationLocks[player] = nil
		return false
	end
	if session.dispatchSessionId ~= snapshot.SessionId
		or session.dispatchSessionEpoch ~= snapshot.SessionEpoch then
		local newerSession = snapshot.SessionEpoch > (session.dispatchSessionEpoch or 0)
		if newerSession then
			session.dispatchLeaseActive = false
		end
		mutationLocks[player] = nil
		if newerSession then player:SetAttribute("ZyntraDispatchPreferenceLoaded", false) end
		return false
	end

	local changed = false
	if snapshot.ClosedEpoch > (session.dispatchClosedEpoch or 0) then
		session.dispatchClosedEpoch = snapshot.ClosedEpoch
		session.dispatchPredecessorClosed = snapshot.ClosedEpoch
			>= (session.dispatchPredecessorEpoch or 0)
		session.data.Settings.MuteDispatchClosedEpoch = snapshot.ClosedEpoch
		changed = true
	end
	local current = session.data.Settings
	local currentEpoch = math.max(0, math.floor(tonumber(current.MuteDispatchInputEpoch) or 0))
	local currentRevision = math.max(0, math.floor(tonumber(current.MuteDispatchRevision) or 0))
	if dispatchVersionIsNewer(snapshot.InputEpoch, snapshot.Revision,
		currentEpoch, currentRevision) then
		current.MuteDispatch = snapshot.Muted
		current.MuteDispatchInputEpoch = snapshot.InputEpoch
		current.MuteDispatchRevision = snapshot.Revision
		changed = true
	end
	local preferenceReady = session.persistent and session.dispatchLeaseActive
		and session.dispatchPredecessorClosed
	mutationLocks[player] = nil
	-- Publish the authoritative value before opening the readiness barrier. Client
	-- listeners must never observe Loaded=true with the predecessor's stale mute.
	if changed then
		applyAttributes(player, session.data)
		pushProfile(player)
	end
	if preferenceReady then player:SetAttribute("ZyntraDispatchPreferenceLoaded", true) end
	return true
end

local function publishDispatchSnapshot(userId, data)
	if RunService:IsStudio() then return true end
	local snapshot = dispatchSnapshotFromData(userId, data)
	local ok, err = pcall(MessagingService.PublishAsync,
		MessagingService, DISPATCH_SNAPSHOT_TOPIC, snapshot)
	if not ok then warn("[Zyntra] Dispatch snapshot publish failed for", userId, err) end
	return ok
end

if not RunService:IsStudio() then
	task.spawn(function()
		local ok, result = pcall(MessagingService.SubscribeAsync,
			MessagingService, DISPATCH_SNAPSHOT_TOPIC, function(message)
				task.defer(applyDispatchSnapshot, message.Data)
			end)
		if not ok then
			warn("[Zyntra] Dispatch snapshot subscription failed:", result)
		else
			dispatchSnapshotConnection = result
		end
	end)
end

local function acquireMutation(player)
	while mutationLocks[player] do task.wait() end
	mutationLocks[player] = true
end

local function releaseMutation(player)
	mutationLocks[player] = nil
end

local function mutate(player, transform)
	local session = sessions[player]
	if not session or session.closing then return false, "Profile is not loaded" end
	acquireMutation(player)
	session = sessions[player]
	if not session or session.closing then
		releaseMutation(player)
		return false, "Profile is not loaded"
	end

	local changed = false
	local message
	local tone
	local resultData
	local success = true

	if RunService:IsStudio() then
		local current = normalizeProfile(session.data)
		changed, message, tone = transform(current)
		resultData = current
	else
		if not session.persistent then
			releaseMutation(player)
			return false, "DataStore is unavailable; try again shortly"
		end
		-- A transform that returns false REFUSED the action: no token to spend, a
		-- colour that is already saved, a receipt already granted. Returning nil
		-- from the callback CANCELS the update, so a refusal costs a read instead
		-- of a write -- the old code committed one either way, which is what let a
		-- player with zero tokens spend the server's DataStore budget by clicking.
		-- The profile the callback read is still adopted below, so the session copy
		-- ends as fresh as a committed write would have left it. This is only safe
		-- while no transform on this path mutates `current` and then returns false;
		-- keep it that way.
		local observed
		local cancelled = false
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. player.UserId, function(current)
				current = normalizeProfile(current)
				changed, message, tone = transform(current)
				observed = current
				cancelled = changed ~= true
				if cancelled then return nil end
				return current
			end)
		end)
		success = ok
		if ok then
			resultData = cancelled and observed or normalizeProfile(result)
		else
			message = tostring(result)
		end
	end

	if success and resultData then
		session.data = resultData
		reassertPendingAccessibility(player, resultData)
		if session.dispatchSessionId
			and resultData.Settings.MuteDispatchSessionId ~= session.dispatchSessionId then
			session.dispatchLeaseActive = false
		end
		applyAttributes(player, resultData)
	end
	releaseMutation(player)
	if success then
		pushProfile(player, message, tone)
		return changed == true, message
	end
	warn("[Zyntra] Profile mutation failed for", player.Name, message)
	pushProfile(player, "Could not save that change. Please try again.", "error")
	return false, message
end

-- Developer token gifts use the same serialized profile write as purchases.
-- RemoteFunction supplies the caller; the UI only chooses a recipient and amount.
do
	local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
	local grantRemote = ensureRemote("RemoteFunction", "ZyntraGrantTokens")
	local MAX_GRANT = 10000
	local COOLDOWN = 3
	local grantStates = setmetatable({}, { __mode = "k" })
	local function result(success, message)
		return { Success = success, Message = message }
	end

	grantRemote.OnServerInvoke = function(issuer, targetUserId, amount)
		if not DevAccess.IsAllowed(issuer) or issuer.Parent ~= Players then
			return result(false, "Developer access is required.")
		end
		if serverClosing then return result(false, "Server is closing. No tokens were given.") end
		local state = grantStates[issuer]
		if state and (state.busy or os.clock() - state.finishedAt < COOLDOWN) then
			return result(false, "Please wait for the previous gift and 3 seconds before giving again.")
		end
		if type(targetUserId) ~= "number" or targetUserId ~= targetUserId
			or targetUserId < 1 or targetUserId > 9007199254740991 or targetUserId % 1 ~= 0 then
			return result(false, "Choose a player in this server.")
		end
		if type(amount) ~= "number" or amount ~= amount or amount < 1
			or amount > MAX_GRANT or amount % 1 ~= 0 then
			return result(false, "Enter a whole number from 1 to 10,000.")
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target.Parent ~= Players then
			return result(false, "That player has left this server. Choose another player.")
		end
		local session = sessions[target]
		if not session or session.closing then
			return result(false, "That player's profile is still loading or closing. Try again shortly.")
		end
		if not RunService:IsStudio() and not session.persistent then
			return result(false, "That player's saved data is unavailable. No tokens were given.")
		end
		state = { busy = true, finishedAt = 0 }
		grantStates[issuer] = state
		local changed, reason = mutate(target, function(data)
			-- Recheck after waiting for another profile mutation to finish.
			if serverClosing or issuer.Parent ~= Players or target.Parent ~= Players then
				return false, "Gift cancelled because a player or server is leaving.", "error"
			end
			if data.Tokens ~= data.Tokens or data.Tokens + amount > 9007199254740991 then
				return false, "That player's token balance is too large for this gift.", "error"
			end
			data.Tokens += amount
			return true, "+" .. amount .. " free Zyntra Research Tokens from a developer.", "success"
		end)
		state.busy = false
		state.finishedAt = os.clock()
		if changed then
			local message = "Gave " .. amount .. " Research Tokens to @" .. target.Name .. "."
			if RunService:IsStudio() then message ..= " Studio test only; not saved." end
			print(string.format("[Zyntra] Token gift: issuer=%d target=%d amount=%d studio=%s",
				issuer.UserId, target.UserId, amount, tostring(RunService:IsStudio())))
			return result(true, message)
		else
			-- A failed UpdateAsync response may follow a committed write. Never
			-- automatically replay a currency delta or promise it was not saved.
			warn("[Zyntra] Token gift unconfirmed:", issuer.UserId, target.UserId, reason)
			return result(false, "Gift was not confirmed. Have the recipient rejoin and check their balance before repeating.")
		end
	end
end

local supportNameCache = {}
local supportRefreshRunning = false
local pendingSupportSync = {}
local supportSyncWorkers = {}

local function supportPlayerName(userId)
	local cached = supportNameCache[userId]
	if cached then return cached end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		cached = online.Name
		supportNameCache[userId] = cached
		return cached
	end
	local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and type(result) == "string" and #result > 0 then
		supportNameCache[userId] = result
		return result
	end
	-- Keep the temporary fallback out of the cache so the next board refresh can
	-- recover automatically after a throttled or transient name-service failure.
	return "USER " .. tostring(userId)
end

-- The same row, split into its three columns. The board aligns rank, name and
-- amount in separate columns and cannot do that by parsing the sentence back
-- apart; an empty row clears all three. The string above is unchanged, so any
-- reader that still wants one line keeps working.
-- The guard is for the offline harnesses in tools/tests, which run this function
-- against plain-table rows rather than real StringValues.
local function publishRowColumns(row, rank, name, robux)
	if typeof(row) ~= "Instance" then return end
	row:SetAttribute("Rank", rank)
	row:SetAttribute("Name", name)
	row:SetAttribute("Robux", robux)
end

local function publishSupportRows(entries)
	for rank = 1, SUPPORT_LEADERBOARD_SIZE do
		local entry = entries[rank]
		if entry then
			local name = string.upper(supportPlayerName(entry.UserId))
			supportRows[rank].Value = string.format("%02d   %s   •   %d R$", rank, name, entry.Value)
			publishRowColumns(supportRows[rank], rank, name, entry.Value)
		else
			supportRows[rank].Value = rank == 1 and "NO SUPPORT RECORDED YET" or ""
			publishRowColumns(supportRows[rank], nil, nil, nil)
		end
	end
	-- The existing cache preserves absent donors; the audited import also adds
	-- historical products, passes and private-server purchases exactly once.
	supportStatus.Value = "RECORDED ROBUX: PRODUCTS, PASSES & DONATIONS"
end

local function studioSupportEntries()
	local entries = {}
	for player, session in pairs(sessions) do
		local value = recordedSupportRobux(session.data)
		if player.Parent and value > 0 then
			entries[#entries + 1] = { UserId = player.UserId, Value = value }
		end
	end
	table.sort(entries, function(a, b)
		if a.Value == b.Value then return a.UserId < b.UserId end
		return a.Value > b.Value
	end)
	return entries
end

local function refreshSupportLeaderboard()
	if supportRefreshRunning then return end
	supportRefreshRunning = true
	local entries = {}
	local success = true
	local failure
	if RunService:IsStudio() then
		entries = studioSupportEntries()
	else
		local ok, result = pcall(function()
			return supportStore:GetSortedAsync(false, SUPPORT_LEADERBOARD_SIZE):GetCurrentPage()
		end)
		if ok then
			for _, record in ipairs(result) do
				local userId = tonumber(tostring(record.key):match("^u_(%d+)$"))
				local value = normalizedSupportAmount(record.value)
				if userId and value > 0 then
					entries[#entries + 1] = { UserId = userId, Value = value }
				end
			end
		else
			success = false
			failure = result
		end
	end
	if success then
		publishSupportRows(entries)
	else
		warn("[Zyntra] Support leaderboard refresh failed:", failure)
		supportStatus.Value = "SUPPORT RANKINGS TEMPORARILY UNAVAILABLE"
	end
	supportRefreshRunning = false
end

local function syncSupportTotal(userId, total)
	total = normalizedSupportAmount(total)
	if RunService:IsStudio() or total <= 0 then return true end
	local ok, err = pcall(function()
		supportStore:UpdateAsync("u_" .. tostring(userId), function(current)
			return math.max(normalizedSupportAmount(current), total)
		end)
	end)
	if not ok then warn("[Zyntra] Support leaderboard sync failed for", userId, err) end
	return ok
end

-- Outer retries are safe for target states or durable operation identities checked
-- before its delta (the protection item below). Unkeyed currency/reward deltas
-- stay on mutate(): an errored response may already have committed.
local IDEMPOTENT_RETRY_DELAYS = {0, 0.35, 0.80}
local function mutateIdempotent(player, transform, suppressPush)
	local session = sessions[player]
	if not session or session.closing then return false, false, "Profile is not loaded" end
	acquireMutation(player)
	session = sessions[player]
	if not session or session.closing then
		releaseMutation(player)
		return false, false, "Profile is not loaded"
	end

	local success = false
	local changed = false
	local message
	local tone
	local resultData
	if RunService:IsStudio() then
		local current = normalizeProfile(session.data)
		changed, message, tone = transform(current)
		resultData = current
		success = true
	elseif session.persistent then
		for _, delaySeconds in ipairs(IDEMPOTENT_RETRY_DELAYS) do
			if delaySeconds > 0 then task.wait(delaySeconds) end
			-- The FIRST attempt runs even for a player already unparented: the
			-- leave-time finalizer writes through here (accessibility, pending
			-- clears) while the session is still open. Only retries stop.
			if (delaySeconds > 0 and not player.Parent) or sessions[player] ~= session then break end
			local attemptChanged = false
			local attemptMessage
			local attemptTone
			local observed
			local cancelled = false
			local ok, result = pcall(function()
				return store:UpdateAsync("u_" .. player.UserId, function(current)
					current = normalizeProfile(current)
					attemptChanged, attemptMessage, attemptTone = transform(current)
					observed = current
					-- Same no-op rule as mutate(): a target-state transform that
					-- reports no change (already claimed, already awarded, a newer
					-- session owns the value) cancels its update instead of
					-- committing a write that changes nothing.
					cancelled = attemptChanged ~= true
					if cancelled then return nil end
					return current
				end)
			end)
			if ok then
				success = true
				changed = attemptChanged == true
				message = attemptMessage
				tone = attemptTone
				resultData = cancelled and observed or normalizeProfile(result)
				break
			end
			message = tostring(result)
		end
	else
		message = "DataStore is unavailable; try again shortly"
	end

	if success and resultData and sessions[player] == session then
		session.data = resultData
		reassertPendingAccessibility(player, resultData)
		if session.dispatchSessionId
			and resultData.Settings.MuteDispatchSessionId ~= session.dispatchSessionId then
			session.dispatchLeaseActive = false
		end
		applyAttributes(player, resultData)
	end
	releaseMutation(player)
	if success then
		if not suppressPush then pushProfile(player, message, tone) end
		return true, changed, message
	end
	warn("[Zyntra] Idempotent profile mutation failed for", player.Name, message)
	if not suppressPush then
		pushProfile(player, "Could not save that change. Please try again.", "error")
	end
	return false, false, message
end

local function sameProtectionCommand(left, right)
	return left and right and left.Action == right.Action
		and left.SessionNonce == right.SessionNonce and left.Revision == right.Revision
		and left.RequestNonce == right.RequestNonce
end

local function protectionOperationMatches(operation, command)
	return operation and operation.SessionId == command.SessionNonce
		and operation.Revision == command.Revision + 1
		and operation.Kind == (command.Action == "BuyProtection" and "Buy" or "Use")
end

local function protectionResponse(player, command, status, reason)
	local response = table.clone(command)
	response.Status = status
	response.Reason = reason
	protectionResponses[player] = response
	local refusals = {
		NeedFiveTokens = "You need 5 Research Tokens.",
		NoCharges = "Buy an Entity Shield charge in Upgrades first.",
		AlreadyActive = "Entity Shield is already active.",
		RetryLater = "Please wait a moment and try again.",
		AnotherActionPending = "Finish your pending Entity Shield action first.",
		StaleRevision = "Your inventory changed. Please try again.",
	}
	local messages = {
		Bought = "Entity Shield purchased: one charge.",
		Consumed = "Entity Shield charge used.",
		Refunded = "Entity Shield could not start. Your charge was returned.",
		Pending = "Confirming your Entity Shield action. Retry the same request.",
		Rejected = refusals[reason] or "Entity Shield is unavailable right now. No charge was used.",
	}
	pushProfile(player, messages[status], status == "Rejected" and "error" or "info")
end

local function protectionOwnsLease(player, session, data)
	return player.Parent == Players and sessions[player] == session and not session.closing
		and not serverClosing and session.persistent == true and session.dispatchLeaseActive == true
		and data.Settings.MuteDispatchSessionId == session.dispatchSessionId
		and data.Settings.MuteDispatchSessionEpoch == session.dispatchSessionEpoch
end

local function handleProtectionAction(player, action, payload)
	-- A malformed command cannot be correlated and never reaches persistence.
	if type(payload) ~= "table" or type(payload.SessionNonce) ~= "string"
		or #payload.SessionNonce == 0 or #payload.SessionNonce > 128
		or not isSafeSupportAmount(payload.Revision) or payload.Revision >= MAX_SAFE_SUPPORT then return end
	if payload.RequestNonce ~= nil and (type(payload.RequestNonce) ~= "string"
		or #payload.RequestNonce == 0 or #payload.RequestNonce > 64) then return end
	-- RequestNonce correlates UI intentions after a definitive refusal. It is
	-- deliberately absent from the durable operation ID and cannot bypass dedupe.
	local command = {
		Action = action, SessionNonce = payload.SessionNonce, Revision = payload.Revision,
		RequestNonce = payload.RequestNonce,
	}
	local session = sessions[player]
	local attempt = protectionAttempts[player]
	if attempt and not sameProtectionCommand(attempt.Command, command) then
		protectionResponse(player, command, "Rejected", "AnotherActionPending")
		return
	end
	if attempt and attempt.Running then
		protectionResponse(player, command, "Pending", "Processing")
		return
	end
	if not session or RunService:IsStudio() or not protectionOwnsLease(player, session, session.data)
		or command.SessionNonce ~= session.dispatchSessionId then
		protectionResponse(player, command, attempt and "Pending" or "Rejected", "ProfileUnavailable")
		return
	end
	local state = protectionState(session.data)
	if not state then
		protectionResponse(player, command, attempt and "Pending" or "Rejected", "InventoryUnavailable")
		return
	end
	local operation = state.LastOperation
	if protectionOperationMatches(operation, command) and operation.Status ~= "Reserved" then
		protectionAttempts[player] = nil
		protectionResponse(player, command, operation.Status)
		return
	end
	local times = actionTimes[player] or {}
	actionTimes[player] = times
	if os.clock() - (times.ProtectionItem or -math.huge) < 1 then
		protectionResponse(player, command, attempt and "Pending" or "Rejected", "RetryLater")
		return
	end
	times.ProtectionItem = os.clock()
	if not attempt then
		local reason
		if command.Revision ~= state.Revision then reason = "StaleRevision"
		elseif operation and operation.Status == "Reserved" then reason = "AnotherActionPending"
		elseif action == "BuyProtection" then
			if not isSafeSupportAmount(session.data.Tokens) or state.Charges >= MAX_SAFE_SUPPORT then
				reason = "InventoryUnavailable"
			elseif session.data.Tokens < Config.ProtectionItem.TokenCost then reason = "NeedFiveTokens" end
		elseif state.Charges < 1 then reason = "NoCharges" end
		local context
		if not reason and action == "UseProtection" then
			-- Capture once BEFORE any wait/lock/UpdateAsync. Retry never renews it.
			context, reason = PlayerProtection.GetContext(player)
		end
		if reason then
			protectionResponse(player, command, "Rejected", reason)
			return
		end
		attempt = {Command = command, Session = session, Context = context}
		protectionAttempts[player] = attempt
	end
	attempt.Running = true
	protectionResponse(player, command, "Pending", "Processing")
	local outcome
	local definiteRejection = false
	local success = mutateIdempotent(player, function(data)
		-- Roblox can discard a callback result and retry on a newer profile.
		outcome = nil
		definiteRejection = false
		local current = protectionState(data)
		if not current then outcome = "InventoryUnavailable"; return false end
		local last = current.LastOperation
		if protectionOperationMatches(last, command) then
			outcome = last.Status
			return false
		end
		-- A successful read at the original revision proves this operation has
		-- not committed, even if an earlier response was lost. A newer revision
		-- with an overwritten operation cannot establish that fact.
		definiteRejection = current.Revision == command.Revision
		if not protectionOwnsLease(player, attempt.Session, data) then outcome = "ProfileUnavailable"; return false end
		if current.Revision ~= command.Revision then outcome = "StaleRevision"; return false end
		if last and last.Status == "Reserved" then outcome = "AnotherActionPending"; return false end
		if action == "BuyProtection" then
			if not isSafeSupportAmount(data.Tokens) or current.Charges >= MAX_SAFE_SUPPORT then
				outcome = "InventoryUnavailable"; return false
			end
			if data.Tokens < Config.ProtectionItem.TokenCost then outcome = "NeedFiveTokens"; return false end
		else
			if current.Charges < 1 then outcome = "NoCharges"; return false end
		end
		definiteRejection = false
		-- Validate everything before changing balance, inventory or operation ID.
		if action == "BuyProtection" then
			data.Tokens -= Config.ProtectionItem.TokenCost
			current.Charges += 1
			outcome = "Bought"
		else
			current.Charges -= 1
			outcome = "Reserved"
		end
		current.Revision += 1
		current.LastOperation = {
			SessionId = command.SessionNonce, Revision = current.Revision,
			Kind = action == "BuyProtection" and "Buy" or "Use", Status = outcome,
		}
		return true
	end, true)
	if success and outcome == "Reserved" then
		if attempt.Applied == nil then
			-- The service call does not yield: its private epoch/character check and
			-- deadline commit happen together, after the durable reservation.
			attempt.Applied = protectionOwnsLease(player, attempt.Session, attempt.Session.data)
				and PlayerProtection.Activate(player, attempt.Context) == true
			-- AUDIT_FIX_20260924: the run is aided the moment the shield is live, not
			-- after the finalize write -- which can fail, or land after the round read
			-- ZyntraRunAided and filed a shielded escape as a clean record.
			if attempt.Applied then markRunAided(player) end
		end
		local wanted = attempt.Applied and "Consumed" or "Refunded"
		success = mutateIdempotent(player, function(data)
			outcome = nil
			definiteRejection = false
			local current = protectionState(data)
			local last = current and current.LastOperation
			if not protectionOperationMatches(last, command) then return false end
			outcome = last.Status
			if last.Status ~= "Reserved" then return false end
			if not protectionOwnsLease(player, attempt.Session, data) then return false end
			if wanted == "Refunded" then
				if current.Charges >= MAX_SAFE_SUPPORT then return false end
				current.Charges += 1
			end
			last.Status = wanted
			outcome = wanted
			return true
		end, true)
	end
	attempt.Running = false
	-- PlayerRemoving may complete while persistence yields. It owns cleanup;
	-- do not resurrect a response/attempt for a departed or replacement session.
	if sessions[player] ~= attempt.Session or protectionAttempts[player] ~= attempt then return end
	if success and (outcome == "Bought" or outcome == "Consumed" or outcome == "Refunded") then
		protectionAttempts[player] = nil
		if outcome == "Consumed" and Analytics then Analytics.ItemUse(player, "EntityShield") end
		protectionResponse(player, command, outcome)
	elseif success and outcome and definiteRejection then
		protectionAttempts[player] = nil
		protectionResponse(player, command, "Rejected", outcome)
	else
		-- No blind refund or fresh activation after an unknown completion. A retry
		-- retains Context and Applied and resolves precisely this operation.
		protectionResponse(player, command, "Pending", "SaveUnconfirmed")
	end
end

local function recoverStaleDispatchPredecessor(player, expectedSession)
	if RunService:IsStudio() or not expectedSession or not expectedSession.persistent then
		return false
	end
	local predecessorEpoch = math.max(0,
		math.floor(tonumber(expectedSession.dispatchPredecessorEpoch) or 0))
	if predecessorEpoch <= 0 then return true end

	local ownsLease = false
	local recovered = false
	local success = mutateIdempotent(player, function(data)
		ownsLease = data.Settings.MuteDispatchSessionId == expectedSession.dispatchSessionId
			and data.Settings.MuteDispatchSessionEpoch == expectedSession.dispatchSessionEpoch
		recovered = false
		if not ownsLease then
			return false
		end
		local closedEpoch = math.max(0,
			math.floor(tonumber(data.Settings.MuteDispatchClosedEpoch) or 0))
		if closedEpoch >= predecessorEpoch then
			recovered = true
			return false
		end

		-- The currently active lease has granted its entire predecessor chain a
		-- bounded handoff window. Atomically fencing every older epoch is safe now:
		-- normal mute writes require the active SessionId, and a late final callback
		-- must observe Closed/Recovered in this same UpdateAsync before writing.
		for _, record in ipairs(data.Settings.MuteDispatchSessionClaims) do
			if math.floor(tonumber(record.Epoch) or 0) <= predecessorEpoch then
				record.Departed = true
				record.Closed = true
				record.Recovered = true
			end
		end
		-- History is intentionally bounded. The watermark also fences an older
		-- record that was already pruned, without needing to reconstruct it.
		data.Settings.MuteDispatchClosedEpoch = math.max(closedEpoch, predecessorEpoch)
		advanceDispatchClosedEpoch(data.Settings)
		recovered = true
		return true
	end, true)

	local session = sessions[player]
	if not success or session ~= expectedSession then return false end
	if not ownsLease then
		session.dispatchLeaseActive = false
		player:SetAttribute("ZyntraDispatchPreferenceLoaded", false)
		return false
	end
	local closedEpoch = math.max(0,
		math.floor(tonumber(session.data.Settings.MuteDispatchClosedEpoch) or 0))
	if recovered and closedEpoch >= predecessorEpoch then
		session.dispatchClosedEpoch = closedEpoch
		session.dispatchPredecessorClosed = true
		player:SetAttribute("ZyntraDispatchPreferenceLoaded", true)
		task.spawn(publishDispatchSnapshot, player.UserId, session.data)
		return true
	end
	return false
end

local function closeAbandonedDispatchLoad(userId, sessionId)
	if RunService:IsStudio() or type(sessionId) ~= "string" or #sessionId == 0 then
		return true
	end
	local lastError
	for _, delaySeconds in ipairs(IDEMPOTENT_RETRY_DELAYS) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		local foundClaim = false
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. tostring(userId), function(current)
				-- If the load never committed, do not create a profile merely to record
				-- its cancellation.
				if type(current) ~= "table" then return nil end
				current = normalizeProfile(current)
				foundClaim = false
				for _, record in ipairs(current.Settings.MuteDispatchSessionClaims) do
					if record.Id == sessionId then
						record.Departed = true
						foundClaim = true
						break
					end
				end
				if foundClaim then advanceDispatchClosedEpoch(current.Settings) end
				return current
			end)
		end)
		if ok then
			if foundClaim and type(result) == "table" then
				publishDispatchSnapshot(userId, normalizeProfile(result))
			end
			return true
		end
		lastError = result
	end
	warn("[Zyntra] Abandoned profile-load claim close failed for user", userId, lastError)
	return false
end

claimLobbyBriefingRemote.OnServerInvoke = function(player)
	local session = sessions[player]
	if not session or session.closing then return false end

	-- Keep one token for this player's entire server session. If UpdateAsync or
	-- the RemoteFunction response is lost, every later non-overlapping invocation
	-- with this same server-owned token receives the same true result. A different
	-- server/session token still cannot claim an already-played briefing.
	local claim = briefingClaims[player]
	if not claim then
		if session.data.Settings.LobbyBriefingPlayed == true then return false end
		claim = {
			id = game.JobId .. ":" .. tostring(player.UserId) .. ":" .. HttpService:GenerateGUID(false),
			running = false,
		}
		briefingClaims[player] = claim
	end

	-- Do not queue arbitrary InvokeServer callers behind an outage. The one
	-- active invocation already owns this stable token and its bounded retries;
	-- a later, non-overlapping client retry can reuse the token if it fails.
	if claim.running then return false end

	session = sessions[player]
	if not session or session.closing then return false end
	if session.data.Settings.LobbyBriefingPlayed == true then
		return session.data.Settings.LobbyBriefingClaimId == claim.id
	end

	claim.running = true
	local didClaim = false
	local success = mutateIdempotent(player, function(data)
		didClaim = false
		if data.Settings.LobbyBriefingPlayed == true then
			didClaim = data.Settings.LobbyBriefingClaimId == claim.id
			return false
		end
		didClaim = true
		data.Settings.LobbyBriefingPlayed = true
		data.Settings.LobbyBriefingClaimId = claim.id
		return true
	end)
	claim.running = false
	return success == true and didClaim == true
end

local queueSupportTotalSync
queueSupportTotalSync = function(userId, total)
	userId = math.floor(tonumber(userId) or 0)
	total = normalizedSupportAmount(total)
	if userId <= 0 or total <= 0 then return end
	pendingSupportSync[userId] = math.max(pendingSupportSync[userId] or 0, total)
	if supportSyncWorkers[userId] then return end

	supportSyncWorkers[userId] = true
	task.spawn(function()
		local lastAttempted = 0
		for _, delaySeconds in ipairs({0, 1, 3, 8, 20}) do
			if delaySeconds > 0 then task.wait(delaySeconds) end
			local target = pendingSupportSync[userId]
			if not target then break end
			lastAttempted = target
			if syncSupportTotal(userId, target) then
				-- A newer receipt may have raised the requested total while UpdateAsync
				-- yielded. Clear only the exact-or-older target we actually synced.
				if (pendingSupportSync[userId] or 0) <= target then
					pendingSupportSync[userId] = nil
				end
				refreshSupportLeaderboard()
				break
			end
		end

		supportSyncWorkers[userId] = nil
		local newest = pendingSupportSync[userId]
		if newest and newest > lastAttempted then
			task.defer(queueSupportTotalSync, userId, newest)
		end
	end)
end

task.spawn(function()
	task.wait(1)
	refreshSupportLeaderboard()
	while true do
		task.wait(math.max(30, tonumber(Config.SupportLeaderboardRefreshSeconds) or 90))
		-- Failed derived-cache writes stay dirty after their bounded immediate
		-- retries. Re-arm one worker per donor before each scheduled board read.
		for userId, total in pairs(pendingSupportSync) do
			queueSupportTotalSync(userId, total)
		end
		refreshSupportLeaderboard()
	end
end)

local function loadProfile(player, loadState)
	if not loadState or loadState.cancelled or not player.Parent then return end
	player:SetAttribute("ZyntraProfileLoaded", false)
	player:SetAttribute("ZyntraDispatchPreferenceLoaded", false)
	local data
	local persistent = not RunService:IsStudio()
	-- "First login" for the first-entry guide. Only the UpdateAsync callback below
	-- can tell: it is the one place that sees the record before it is written back.
	-- A load that never commits leaves this false -- the next SUCCESSFUL load is
	-- then the first one -- so a lost save can never burn a player's first login.
	local firstLogin = false
	local dispatchSessionId = game.JobId .. ":" .. tostring(player.UserId) .. ":"
		.. HttpService:GenerateGUID(false)
	loadState.dispatchSessionId = dispatchSessionId
	local claimedSessionEpoch
	local predecessorSessionId
	local predecessorSessionEpoch = 0
	if RunService:IsStudio() then
		data = newProfile()
		data.Settings.MuteDispatchSessionEpoch = 1
		data.Settings.MuteDispatchSessionId = dispatchSessionId
		data.Settings.MuteDispatchSessionClaims = {{
			Id = dispatchSessionId,
			Epoch = 1,
			PreviousEpoch = 0,
			Closed = false,
		}}
		claimedSessionEpoch = 1
		-- No DataStore in Studio, so there is no record to have existed. Set
		-- workspace.DevSimulateFirstLogin in Edit before Play to preview the guide.
		firstLogin = workspace:GetAttribute("DevSimulateFirstLogin") == true
	else
		local lastError
		local recordExisted = false
		for attempt = 1, 3 do
			if loadState.cancelled then break end
			-- Loading atomically claims this player's dispatch-setting lease and a
			-- monotonically increasing session epoch. A newer GUID stops the old
			-- live queue; the epoch still lets PlayerRemoving hand off its last
			-- accepted input only when the newer session has not recorded one.
			loadState.claimAttempted = true
			local ok, result = pcall(function()
				return store:UpdateAsync("u_" .. player.UserId, function(current)
					-- Read before normalizeProfile invents an empty profile out of nil.
					-- Rewritten on every run on purpose: Roblox re-runs this callback on a
					-- conflict, and only the LAST run's view is the one that commits.
					recordExisted = type(current) == "table"
					current = normalizeProfile(current)
					-- PlayerRemoving/BindToClose can cancel while UpdateAsync is waiting.
					-- Roblox may re-run this callback after a competing server claims the
					-- profile; the in-callback fence prevents that retry from stealing the
					-- newer lease with this now-abandoned GUID.
					if loadState.cancelled then
						claimedSessionEpoch = nil
						return current
					end
					claimedSessionEpoch = nil
					for _, record in ipairs(current.Settings.MuteDispatchSessionClaims) do
						if record.Id == dispatchSessionId then
							claimedSessionEpoch = record.Epoch
							predecessorSessionId = record.PreviousId
							predecessorSessionEpoch = record.PreviousEpoch
							break
						end
					end
					if not claimedSessionEpoch then
						predecessorSessionId = current.Settings.MuteDispatchSessionId
						predecessorSessionEpoch = current.Settings.MuteDispatchSessionEpoch
						current.Settings.MuteDispatchSessionEpoch = math.max(
							current.Settings.MuteDispatchSessionEpoch,
							current.Settings.MuteDispatchInputEpoch
						) + 1
						current.Settings.MuteDispatchSessionId = dispatchSessionId
						claimedSessionEpoch = current.Settings.MuteDispatchSessionEpoch
						table.insert(current.Settings.MuteDispatchSessionClaims, {
							Id = dispatchSessionId,
							Epoch = claimedSessionEpoch,
							PreviousId = predecessorSessionId,
							PreviousEpoch = predecessorSessionEpoch,
							Departed = false,
							Closed = false,
						})
						while #current.Settings.MuteDispatchSessionClaims > 16 do
							table.remove(current.Settings.MuteDispatchSessionClaims, 1)
						end
					end
					recoverProtectionReservation(current, dispatchSessionId)
					return current
				end)
			end)
			if ok then
				data = result
				lastError = nil
				-- The callback's return value is what commits, so the record exists from
				-- here on: this join was the first one exactly when it did not before.
				firstLogin = not recordExisted
				break
			end
			lastError = result
			if loadState.cancelled then break end
			task.wait(attempt)
		end
		if lastError then
			warn("[Zyntra] Could not load and claim profile for", player.Name, lastError)
			data = newProfile()
			data.Settings.MuteDispatchSessionEpoch = 1
			data.Settings.MuteDispatchSessionId = dispatchSessionId
			data.Settings.MuteDispatchSessionClaims = {{
				Id = dispatchSessionId,
				Epoch = 1,
				PreviousEpoch = 0,
				Closed = false,
			}}
			claimedSessionEpoch = 1
			persistent = false
		end
	end
	if loadState.cancelled or not player.Parent then return end
	local normalized = normalizeProfile(data)
	if not claimedSessionEpoch then
		for _, record in ipairs(normalized.Settings.MuteDispatchSessionClaims) do
			if record.Id == dispatchSessionId then
				claimedSessionEpoch = record.Epoch
				predecessorSessionId = record.PreviousId
				predecessorSessionEpoch = record.PreviousEpoch
				break
			end
		end
	end
	claimedSessionEpoch = math.max(0, math.floor(tonumber(claimedSessionEpoch) or 0))
	sessions[player] = {
		data = normalized,
		persistent = persistent,
		firstLogin = firstLogin,
		dispatchSessionId = dispatchSessionId,
		dispatchSessionEpoch = claimedSessionEpoch,
		dispatchLeaseActive = normalized.Settings.MuteDispatchSessionId == dispatchSessionId
			and normalized.Settings.MuteDispatchSessionEpoch == claimedSessionEpoch,
		dispatchPredecessorId = predecessorSessionId,
		dispatchPredecessorEpoch = predecessorSessionEpoch,
		dispatchClosedEpoch = normalized.Settings.MuteDispatchClosedEpoch,
		dispatchPredecessorClosed = isDispatchPredecessorClosed(
			normalized.Settings, predecessorSessionEpoch),
	}
	applyAttributes(player, sessions[player].data)
	-- Strictly before ZyntraProfileLoaded: the first-entry guide latches on that
	-- flag and reads this one in the same tick, once, and never again.
	player:SetAttribute("ZyntraFirstLogin", firstLogin)
	player:SetAttribute("ZyntraProfileLoaded", true)
	if Analytics then Analytics.ProfileLoaded(player, firstLogin) end
	local pendingSnapshot = pendingDispatchSnapshots[player.UserId]
	if pendingSnapshot then
		pendingDispatchSnapshots[player.UserId] = nil
		applyDispatchSnapshot(pendingSnapshot)
	end
	local loadedSession = sessions[player]
	-- A live session becomes audible only after its predecessor atomically closes
	-- (last input + Closed marker). Failure remains quiet instead of temporarily
	-- unmuting a returning player with an incomplete handoff.
	player:SetAttribute("ZyntraDispatchPreferenceLoaded", RunService:IsStudio()
		or (persistent and loadedSession.dispatchLeaseActive
			and loadedSession.dispatchPredecessorClosed))
	pushProfile(player)
	if persistent and sessions[player].dispatchLeaseActive
		and not sessions[player].dispatchPredecessorClosed then
		-- MessagingService provides the immediate handoff. This delayed read is a
		-- fallback for a publish/subscription outage or the tiny window between the
		-- lease claim and this local session being installed.
		task.spawn(function()
			local startedAt = os.clock()
			local delays = {1, 2, 4, 8}
			for _, delaySeconds in ipairs(delays) do
				task.wait(delaySeconds)
				local session = sessions[player]
				if not player.Parent or not session or session.closing
					or session.dispatchLeaseActive == false
					or session.dispatchPredecessorClosed then return end
				if os.clock() - startedAt >= DISPATCH_HANDOFF_GRACE_SECONDS then return end
				local ok, latest = pcall(store.GetAsync, store, "u_" .. player.UserId)
				if ok and type(latest) == "table" then
					latest = normalizeProfile(latest)
					if latest.Settings.MuteDispatchSessionId ~= session.dispatchSessionId then
						session.dispatchLeaseActive = false
						player:SetAttribute("ZyntraDispatchPreferenceLoaded", false)
						return
					end
					applyDispatchSnapshot(dispatchSnapshotFromData(player.UserId, latest))
				end
			end
		end)
		-- This timer is independent from the best-effort GetAsync reads above, so a
		-- slow read cannot extend the predecessor's write window. At the deadline,
		-- only the still-active lease may atomically fence it. DataStore outages retry
		-- slowly; successful recovery or a newer lease terminates this task.
		task.spawn(function()
			task.wait(DISPATCH_HANDOFF_GRACE_SECONDS)
			while true do
				local session = sessions[player]
				if not player.Parent or not session or session.closing
					or session.dispatchLeaseActive == false
					or session.dispatchPredecessorClosed then return end
				if recoverStaleDispatchPredecessor(player, session) then return end
				session = sessions[player]
				if not player.Parent or not session or session.closing
					or session.dispatchLeaseActive == false
					or session.dispatchPredecessorClosed then return end
				task.wait(DISPATCH_RECOVERY_RETRY_SECONDS)
			end
		end)
	end
	queueSupportTotalSync(player.UserId, recordedSupportRobux(sessions[player] and sessions[player].data))
end

-- A throw and a "no" used to collapse into the same false, and that false
-- latched for the whole session: one MarketplaceService blip at join cost a
-- paying Supporter their tag, their pickers and their grant until they rejoined.
-- Retry the throw a few times, and answer nil -- NOT false -- when Roblox never
-- answered at all, so a caller can tell "does not own" from "do not know".
local PASS_RETRY_DELAYS = {0, 1, 3}
local function ownsPass(player, pass)
	if RunService:IsStudio() and Config.Studio.GrantAllPasses then return true end
	if not pass or tonumber(pass.Id) == nil or pass.Id <= 0 then return false end
	local lastError
	for _, delaySeconds in ipairs(PASS_RETRY_DELAYS) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		if not player.Parent then return nil end
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
		if ok then return result == true end
		lastError = result
	end
	warn("[Zyntra] Pass ownership check failed:", pass.Name, lastError)
	return nil
end

-- A finished purchase is the strongest answer this server will ever get.
-- UserOwnsGamePassAsync caches per server and commonly still reads false for a
-- while after PromptGamePassPurchaseFinished, so the purchase is latched here
-- and wins over every later ownership read for the rest of the session; no
-- retry loop can beat that cache.
local passPurchases = setmetatable({}, { __mode = "k" })
-- Set when a read failed outright, so a bounded background re-check can pick the
-- pass up later instead of leaving the player locked out until they rejoin.
local passReadFailed = setmetatable({}, { __mode = "k" })
-- How many of those re-checks a player has already been given. The cap is what
-- stops a MarketplaceService outage becoming a permanent poll.
local passRechecks = setmetatable({}, { __mode = "k" })
local PASS_RECHECK_DELAY = 20
local PASS_RECHECK_LIMIT = 3

local function passOwnership(player, key, pass)
	-- Owner-authorized permanent in-experience entitlement. Does not grant other passes.
	if key == "AdvancedEquipment" and player.UserId == 9488575949 then return true end -- LaverSneglen
	local purchases = passPurchases[player]
	if purchases and purchases[key] then return true end
	local answer = ownsPass(player, pass)
	if answer == nil then
		passReadFailed[player] = true
		-- Unknown: keep whatever this session already published rather than
		-- downgrading an owner to false.
		return player:GetAttribute("ZyntraOwns" .. key) == true
	end
	return answer
end

local function refreshPasses(player)
	if not sessions[player] then return end
	-- FEEDBACK_GIFT_20260914 (card 71). One persistent thank-you grant for the
	-- player who gave feedback on Discord: the Advanced Equipment package's two
	-- capacity upgrades plus ten Research Tokens. Official username lookup
	-- 2026-09-14: Kecoalmutt / AdminNBCRxAria, UserId 10152463945. The grant
	-- key is separate from Grants.AdvancedEquipment so a later real purchase of
	-- that pass still awards its own benefits; ReceiptIds and pass ownership
	-- are untouched. mutate is serialized and the marker makes it idempotent,
	-- so a failed DataStore write simply retries on the next profile load or
	-- pass recheck. normalizeProfile keeps unknown Grants keys, which is what
	-- makes the marker survive every later load.
	if player.UserId == 10152463945 then
		mutate(player, function(data)
			if data.Grants.FeedbackThanks20260914 == true then return false end
			data.Grants.FeedbackThanks20260914 = true
			data.StaminaLevel += 1
			data.BatteryLevel += 1
			data.Tokens += 10
			return true, "Thanks for your feedback: +" .. PCT .. " stamina, +" .. PCT .. " battery and 10 Research Tokens", "success"
		end)
	end
	passReadFailed[player] = nil
	local supporter = passOwnership(player, "Supporter", Config.Passes.Supporter)
	local advanced = passOwnership(player, "AdvancedEquipment", Config.Passes.AdvancedEquipment)
	local cosmetic = passOwnership(player, "CosmeticEquipment", Config.Passes.CosmeticEquipment)
	player:SetAttribute("ZyntraOwnsSupporter", supporter)
	player:SetAttribute("ZyntraOwnsAdvancedEquipment", advanced)
	player:SetAttribute("ZyntraOwnsCosmeticEquipment", cosmetic)
	player:SetAttribute("ZyntraOwnsEntityDetector", passOwnership(player,"EntityDetector",Config.Passes.EntityDetector))
	for key, pass in pairs(Config.Donations or {}) do
		if pass.Kind == "GamePass" then
			player:SetAttribute("ZyntraOwns" .. key, passOwnership(player, key, pass))
		end
	end
	-- Permanent premium skins are Game Passes, not repeatable Developer
	-- Products. An unconfigured ID cannot grant even in Studio's all-pass mode.
	for _, skinId in ipairs(Skins.Order) do
		local skin = Skins.ById[skinId]
		if skin.Kind == "Robux" and skin.PassId > 0 then
			local pass = {Id = skin.PassId, Name = skin.Name}
			local owns = passOwnership(player, skinId, pass)
			player:SetAttribute("ZyntraOwns" .. skinId, owns)
			local session = sessions[player]
			if owns and session and not Skins.IsOwned(session.data.Skins, skinId) then
				local changed = mutate(player, function(data)
					if not Skins.Grant(data.Skins, skinId) then return false end
					return true, skin.Name .. " hazmat skin unlocked.", "success"
				end)
				if not changed and sessions[player]
					and not Skins.IsOwned(sessions[player].data.Skins, skinId) then
					passReadFailed[player] = true
				end
			end
		end
	end

	-- TOKEN_EARNER_20260924: six passes, one tier. Each ownership is published
	-- like any other pass; earning code reads only the resolved tier.
	local earnerOwns = {}
	for key, pass in pairs(Config.TokenEarner.Passes) do
		earnerOwns[key] = passOwnership(player, key, pass)
		player:SetAttribute("ZyntraOwns" .. key, earnerOwns[key])
	end
	player:SetAttribute("ZyntraTokenEarnerMultiplier", Config.TokenEarner.Tier(earnerOwns))

	if supporter then
		mutate(player, function(data)
			if data.Grants.Supporter then return false end
			data.Grants.Supporter = true
			data.Tokens += Config.Passes.Supporter.TokenGrant
			return true, "+" .. Config.Passes.Supporter.TokenGrant .. " Zyntra Research Tokens", "success"
		end)
	end
	if advanced then
		mutate(player, function(data)
			if data.Grants.AdvancedEquipment then return false end
			data.Grants.AdvancedEquipment = true
			data.StaminaLevel += 1
			data.BatteryLevel += 1
			-- Names what the pass is (focus beam, +50% base stamina, colours) and
			-- then the one-time bonus this branch actually grants; the grant and
			-- its once-only flag above are unchanged.
			return true, "Advanced Equipment unlocked: focused torch, +50% base stamina and hazmat colors. One-time bonus: +"
				.. PCT .. " stamina and +" .. PCT .. " battery.", "success"
		end)
	end
	if cosmetic and player:GetAttribute("InRound") == true then
		player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
	end
	if player.Character then
		task.defer(refreshPlayerTags, player, player.Character)
		task.defer(applyHazmatColor, player)
	end
	-- A read that never answered leaves a paying player without their pass, and
	-- nothing else re-asks. It cannot be left to "the next action that needs the
	-- pass" either: the store locks its colour picker on this very attribute and
	-- returns before firing the remote, so the one action that would trigger a
	-- re-check is exactly the one the client refuses to send -- and the Supporter
	-- pass has no such action at all. Re-ask in the background, a few times, then
	-- stop. A successful pass clears passReadFailed above and schedules no more.
	local rechecks = passRechecks[player] or 0
	if passReadFailed[player] and rechecks < PASS_RECHECK_LIMIT then
		passRechecks[player] = rechecks + 1
		task.delay(PASS_RECHECK_DELAY, function()
			if sessions[player] and passReadFailed[player] then refreshPasses(player) end
		end)
	end
	-- Existing owners may have already received their one-time grant, so refresh
	-- derived capacity even when mutate made no profile change. Never award levels twice.
	if not sessions[player] then return end
	applyAttributes(player, sessions[player].data)
	pushProfile(player)
end

local function setupPlayer(player)
	if serverClosing or profileLoads[player] or sessions[player] then return end
	local loadState = {
		cancelled = false,
		done = false,
		success = false,
		claimAttempted = false,
		dispatchSessionId = nil,
	}
	profileLoads[player] = loadState
	task.spawn(function()
		local ok, result = pcall(loadProfile, player, loadState)
		loadState.success = ok
		loadState.error = ok and nil or result
		loadState.done = true
		if not ok then
			warn("[Zyntra] Profile-load task failed for user", player.UserId, result)
		end
		if ok and not loadState.cancelled and sessions[player] then refreshPasses(player) end
	end)
	local headAddedConnection
	local function releaseCharacter()
		if headAddedConnection then headAddedConnection:Disconnect(); headAddedConnection = nil end
		local character = tagCharacters[player]
		-- CharacterRemoving may precede the Player.Character property update.
		-- Invalidate every queued Head/pass refresh before clearing its badges.
		tagCharacters[player] = nil
		if character then clearPlayerTags(character) end
	end
	local function characterReady(character)
		if player.Parent ~= Players or player.Character ~= character then return end
		releaseCharacter()
		tagCharacters[player] = character
		local function refreshCharacter()
			if player.Parent ~= Players or player.Character ~= character
				or tagCharacters[player] ~= character then return end
			refreshPlayerTags(player, character)
			applyHazmatColor(player)
		end
		-- No timeout: custom avatars may receive Head after profile loading or
		-- well after CharacterAdded. Disconnect when this character is retired.
		headAddedConnection = character.ChildAdded:Connect(function(child)
			if child.Name == "Head" and child:IsA("BasePart") then task.defer(refreshCharacter) end
		end)
		task.defer(refreshCharacter)
	end
	player.CharacterAdded:Connect(characterReady)
	player.CharacterRemoving:Connect(function(character)
		if tagCharacters[player] == character then releaseCharacter() end
	end)
	player.AncestryChanged:Connect(function()
		if player.Parent ~= Players then releaseCharacter() end
	end)
	if player.Character then characterReady(player.Character) end
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player.Character then task.defer(refreshPlayerTags, player, player.Character) end
		if player:GetAttribute("InRound") == true then
			if player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true then
				player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
			end
			task.defer(applyHazmatColor, player)
		end
	end)
end

getProfileRemote.OnServerInvoke = function(player)
	local deadline = os.clock() + 10
	while not sessions[player] and os.clock() < deadline do task.wait(0.1) end
	return enrichedPublicProfile(player)
end

local function sameColorData(saved, wanted)
	return type(saved) == "table"
		and saved.R == wanted.R and saved.G == wanted.G and saved.B == wanted.B
end

local function validColor(value)
	if typeof(value) ~= "Color3" then return nil end
	local h, s, v = value:ToHSV()
	s = math.clamp(s, 0, 0.9)
	v = math.clamp(v, 0.35, 1)
	return Color3.fromHSV(h, s, v)
end

-- Back-to-back mute writes escalate toward Roblox's one-write-per-six-seconds
-- guidance for a single key. A client that alternates true/false is never a
-- duplicate, so without this floor every toggle it sends becomes a real
-- UpdateAsync on that player's profile key -- about 72 a minute, indefinitely,
-- out of a server budget of 60 + 10 per player. The first toggle after a quiet
-- spell still commits at the old responsive pace; only a stream of them slows
-- down, and the queue folds everything that arrives while it waits into the one
-- write that follows, so nothing is lost and the client stays optimistic.
local MUTE_WRITE_FLOORS = {0.75, 2, 6}
local MUTE_WRITE_STREAK_RESET_SECONDS = 30

local queueMuteDispatch
local function muteQueueActive(player, queue)
	return queue.closing ~= true
		and player.Parent ~= nil
		and sessions[player] ~= nil
		and sessions[player].closing ~= true
		and sessions[player].dispatchLeaseActive ~= false
		and dispatchMuteQueues[player] == queue
end

local function takeLatestMuteDesired(queue, desired, revision)
	if type(queue.desired) == "boolean" then
		desired = queue.desired
		revision = queue.desiredRevision
		queue.desired = nil
		queue.desiredRevision = nil
		queue.desiredIsReassert = nil
	end
	queue.processingDesired = desired
	queue.processingRevision = revision
	return desired, revision
end

local function runMuteDispatchQueue(player, queue)
	while muteQueueActive(player, queue) do
		local desired = queue.desired
		local revision = queue.desiredRevision
		queue.desired = nil
		queue.desiredRevision = nil
		if type(desired) ~= "boolean" or type(revision) ~= "number" then break end
		queue.processingDesired = desired
		queue.processingRevision = revision

		local idle = os.clock() - queue.lastAttemptFinishedAt
		if idle > MUTE_WRITE_STREAK_RESET_SECONDS then queue.writeStreak = 0 end
		local streak = math.floor(tonumber(queue.writeStreak) or 0)
		local remaining = MUTE_WRITE_FLOORS[math.clamp(streak + 1, 1, #MUTE_WRITE_FLOORS)] - idle
		if remaining > 0 then task.wait(remaining) end
		if not muteQueueActive(player, queue) then break end
		desired, revision = takeLatestMuteDesired(queue, desired, revision)

		-- A receipt/pass/profile mutation can own the shared lock for multiple
		-- seconds. Continue folding toggles into this one target while we wait,
		-- then call mutateIdempotent immediately after observing the lock free;
		-- acquireMutation has no yield on that path, so another writer cannot slip
		-- between this check and its acquisition.
		while mutationLocks[player] do
			task.wait()
			if not muteQueueActive(player, queue) then break end
			desired, revision = takeLatestMuteDesired(queue, desired, revision)
		end
		if not muteQueueActive(player, queue) then break end
		desired, revision = takeLatestMuteDesired(queue, desired, revision)

		local session = sessions[player]
		local current = session and session.data and session.data.Settings.MuteDispatch
		local dispatchSessionEpoch = session and session.dispatchSessionEpoch or 0
		local currentInputEpoch = session and session.data
			and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchInputEpoch) or 0)) or 0
		local currentRevision = session and session.data
			and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchRevision) or 0)) or 0
		if current == desired and currentInputEpoch == dispatchSessionEpoch
			and currentRevision >= revision and not queue.uncertain then
			-- A client may resend the same target every frame. Acknowledge an
			-- already-current target once, without spawning a worker or firing a
			-- profile packet for every duplicate RemoteEvent.
			if queue.lastAcknowledged ~= desired then
				pushProfile(player, desired and "Dispatch audio muted." or "Dispatch audio enabled.", "success")
				queue.lastAcknowledged = desired
			end
		else
			queue.inFlightDesired = desired
			queue.inFlightRevision = revision
			local targetApplied = false
			local dispatchSessionId = session and session.dispatchSessionId
			local success = mutateIdempotent(player, function(data)
				targetApplied = false
				if data.Settings.MuteDispatchSessionId ~= dispatchSessionId then
					return false, "Dispatch preference belongs to a newer session.", "info"
				end
				local storedInputEpoch = math.max(0,
					math.floor(tonumber(data.Settings.MuteDispatchInputEpoch) or 0))
				local storedRevision = math.max(0,
					math.floor(tonumber(data.Settings.MuteDispatchRevision) or 0))
				-- The atomically allocated session epoch is the cross-server causal
				-- order; revision is strictly increasing inside that epoch. Equality
				-- is this exact idempotent retry and must never overwrite an opposite.
				if storedInputEpoch > dispatchSessionEpoch
					or (storedInputEpoch == dispatchSessionEpoch and storedRevision >= revision) then
					targetApplied = data.Settings.MuteDispatch == desired
					return false,
						targetApplied and (desired and "Dispatch audio muted." or "Dispatch audio enabled.")
							or "Dispatch preference was updated in another server.",
						targetApplied and "success" or "info"
				end
				targetApplied = true
				local changed = data.Settings.MuteDispatch ~= desired
					or storedInputEpoch ~= dispatchSessionEpoch or storedRevision ~= revision
				data.Settings.MuteDispatch = desired
				data.Settings.MuteDispatchInputEpoch = dispatchSessionEpoch
				data.Settings.MuteDispatchRevision = revision
				return changed,
					desired and "Dispatch audio muted." or "Dispatch audio enabled.",
					"success"
			end)
			if success and session and session.data.Settings.MuteDispatchSessionId ~= dispatchSessionId then
				session.dispatchLeaseActive = false
			end
			queue.inFlightDesired = nil
			queue.inFlightRevision = nil
			-- Rate-limit from completion, not start. UpdateAsync plus its bounded
			-- retries may yield for seconds, and that time must not permit another
			-- write to begin immediately when it returns.
			queue.lastAttemptFinishedAt = os.clock()
			-- Only an attempt that actually opened a write counts toward the floor;
			-- an acknowledged duplicate above never reaches this branch.
			queue.writeStreak = math.min(streak + 1, #MUTE_WRITE_FLOORS)
			if success then
				queue.uncertain = false
				queue.lastAcknowledged = targetApplied and desired or nil
				if targetApplied and session and session.data then
					task.spawn(publishDispatchSnapshot, player.UserId, session.data)
				end
				if targetApplied and queue.desired == desired and queue.desiredIsReassert == true then
					-- Matching spam that arrived during this write is redundant once the
					-- target is confirmed. Preserve it only when this attempt lost to a
					-- newer external revision or remained ambiguous.
					queue.desired = nil
					queue.desiredRevision = nil
					queue.desiredIsReassert = nil
				end
			else
				-- A failed response does not prove UpdateAsync failed to commit. Until
				-- a later target-state write succeeds, never trust the local no-op
				-- shortcut: force the newest accepted target through DataStore.
				queue.uncertain = true
			end
		end
		queue.processingDesired = nil
		queue.processingRevision = nil
	end

	queue.processingDesired = nil
	queue.processingRevision = nil
	queue.inFlightDesired = nil
	queue.inFlightRevision = nil
	queue.running = false
end

queueMuteDispatch = function(player, desired)
	local queue = dispatchMuteQueues[player]
	if not queue then
		queue = {
			desired = nil,
			desiredRevision = nil,
			desiredIsReassert = nil,
			acceptedDesired = nil,
			acceptedRevision = 0,
			running = false,
			closing = false,
			uncertain = false,
			lastAttemptFinishedAt = -math.huge,
			writeStreak = 0,
			lastAcknowledged = nil,
			processingDesired = nil,
			processingRevision = nil,
			inFlightDesired = nil,
			inFlightRevision = nil,
		}
		dispatchMuteQueues[player] = queue
	end
	if queue.closing then return end

	local session = sessions[player]
	if not session or session.dispatchLeaseActive == false then return end
	local current = session and session.data and session.data.Settings.MuteDispatch
	local dispatchSessionEpoch = session and session.dispatchSessionEpoch or 0
	local duplicate = queue.acceptedDesired == desired
	local pendingSame = queue.desired == desired
	local processingSame = queue.processingDesired == desired or queue.inFlightDesired == desired
	if duplicate and not queue.running and not queue.uncertain and current == desired then
		return
	end
	local storedInputEpoch = session and session.data
		and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchInputEpoch) or 0)) or 0
	local storedRevision = storedInputEpoch == dispatchSessionEpoch and session and session.data
		and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchRevision) or 0)) or 0
	local revision = math.max(
		math.floor(tonumber(queue.acceptedRevision) or 0) + 1,
		storedRevision + 1
	)
	local isReassert = false
	if duplicate then
		if pendingSame then
			isReassert = queue.desiredIsReassert == true
		elseif processingSame then
			isReassert = true
		end
	end
	queue.acceptedDesired = desired
	queue.acceptedRevision = revision
	queue.lastAcknowledged = nil
	queue.desired = desired
	queue.desiredRevision = revision
	queue.desiredIsReassert = isReassert
	if queue.running then return end
	queue.running = true
	task.spawn(runMuteDispatchQueue, player, queue)
end

local function persistDispatchTargetOnLeave(player, session, queue)
	local desired = queue and queue.acceptedDesired
	local revision = queue and queue.acceptedRevision
	local dispatchSessionEpoch = session and session.dispatchSessionEpoch
	local dispatchSessionId = session and session.dispatchSessionId
	if type(dispatchSessionEpoch) ~= "number"
		or type(dispatchSessionId) ~= "string" or not session then return true end
	local hasAcceptedTarget = type(desired) == "boolean" and type(revision) == "number"

	local function closeClaim(settings)
		local found = false
		for _, record in ipairs(settings.MuteDispatchSessionClaims) do
			if record.Id == dispatchSessionId and record.Epoch == dispatchSessionEpoch then
				record.Departed = true
				found = true
				break
			end
		end
		if not found then
			local alreadyFenced = math.max(0,
				math.floor(tonumber(settings.MuteDispatchClosedEpoch) or 0)) >= dispatchSessionEpoch
			table.insert(settings.MuteDispatchSessionClaims, {
				Id = dispatchSessionId,
				Epoch = dispatchSessionEpoch,
				PreviousId = session.dispatchPredecessorId,
				PreviousEpoch = session.dispatchPredecessorEpoch or 0,
				Departed = true,
				Closed = alreadyFenced,
				Recovered = alreadyFenced,
			})
		end
		while #settings.MuteDispatchSessionClaims > 16 do
			table.remove(settings.MuteDispatchSessionClaims, 1)
		end

		-- Close only a causally contiguous departed chain. If B departs while A
		-- is still saving, B remains pending; A's later final transaction advances
		-- the watermark through both A and B in this same atomic UpdateAsync.
		advanceDispatchClosedEpoch(settings)
	end

	if RunService:IsStudio() then
		local current = normalizeProfile(session.data)
		if hasAcceptedTarget and dispatchClaimCanFinalize(current.Settings,
			dispatchSessionId, dispatchSessionEpoch) then
			local storedInputEpoch = math.max(0,
				math.floor(tonumber(current.Settings.MuteDispatchInputEpoch) or 0))
			local storedRevision = math.max(0,
				math.floor(tonumber(current.Settings.MuteDispatchRevision) or 0))
			if storedInputEpoch < dispatchSessionEpoch
				or (storedInputEpoch == dispatchSessionEpoch and storedRevision < revision) then
				current.Settings.MuteDispatch = desired
				current.Settings.MuteDispatchInputEpoch = dispatchSessionEpoch
				current.Settings.MuteDispatchRevision = revision
			end
		end
		closeClaim(current.Settings)
		session.data = current
		return true
	end
	if not session.persistent then return false end

	local userId = player.UserId
	local lastError
	for _, delaySeconds in ipairs(IDEMPOTENT_RETRY_DELAYS) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. tostring(userId), function(current)
				current = normalizeProfile(current)
				if hasAcceptedTarget and dispatchClaimCanFinalize(current.Settings,
					dispatchSessionId, dispatchSessionEpoch) then
					local storedInputEpoch = math.max(0,
						math.floor(tonumber(current.Settings.MuteDispatchInputEpoch) or 0))
					local storedRevision = math.max(0,
						math.floor(tonumber(current.Settings.MuteDispatchRevision) or 0))
					if storedInputEpoch < dispatchSessionEpoch
						or (storedInputEpoch == dispatchSessionEpoch and storedRevision < revision) then
						current.Settings.MuteDispatch = desired
						current.Settings.MuteDispatchInputEpoch = dispatchSessionEpoch
						current.Settings.MuteDispatchRevision = revision
					end
				end
				closeClaim(current.Settings)
				return current
			end)
		end)
		if ok then
			publishDispatchSnapshot(userId, normalizeProfile(result))
			return true
		end
		lastError = result
	end
	warn("[Zyntra] Final dispatch preference save failed for user", userId, lastError)
	return false
end

-- ---------------------------------------------------------------------------
-- Emergency Re-entry: reserve the credit, THEN ask for the respawn
-- ---------------------------------------------------------------------------
-- The old order invoked the respawn first and spent the credit afterwards, so a
-- DataStore write that failed behind an accepted respawn left the player holding
-- both. Reserving first inverts the failure: the worst case is now a credit
-- spent on a respawn that was refused, and that case refunds itself.
--
-- The refund is keyed on a per-attempt token and is only ever paid against the
-- attempt that is still current, so a superseded attempt, a repeated call, or a
-- player whose session ended mid-flow (the token dies with the session) can
-- never be credited twice for one reservation.
local reentryAttempts = {}

-- The exact conditions the store's re-entry button uses to show itself, read
-- server-side: in a live round, dead, and the round's one re-entry unspent.
local function reentryEligible(player)
	if not player.Parent then return false end
	if player:GetAttribute("InRound") ~= true then return false end
	if workspace:GetAttribute("RoundActive") ~= true then return false end
	if player:GetAttribute("ZyntraReentryUsed") == true then return false end
	-- GameManager's OnInvoke also refuses an escapee, so this has to as well:
	-- these conditions gate the AUTO-use after a purchase, and every condition
	-- missing here is a credit spent on a respawn that is then refused.
	if player:GetAttribute("Escaped") == true then return false end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid == nil or humanoid.Health <= 0
end

local function useReentry(player)
	local session = sessions[player]
	if not session then return false end
	-- One attempt at a time. Without this, a second click during the yielding
	-- respawn would reserve a second credit that the first attempt's refund
	-- would then decline to pay back.
	if reentryAttempts[player] then return false end
	if session.data.ReentryCredits < 1 then
		pushProfile(player, "You do not have an Emergency Re-entry credit.", "error")
		return false
	end
	local reentry = ServerStorage:FindFirstChild("ZyntraReentry")
	if not reentry or not reentry:IsA("BindableFunction") then
		pushProfile(player, "Re-entry is not available right now.", "error")
		return false
	end

	local token = {}
	reentryAttempts[player] = token
	local reserved = mutate(player, function(data)
		if data.ReentryCredits < 1 then
			return false, "You do not have an Emergency Re-entry credit.", "error"
		end
		data.ReentryCredits -= 1
		-- Deliberately no message: the credit is only RESERVED here. Announcing
		-- success now is how a player would read "activated" one frame before
		-- being told the respawn was refused. The push still carries the new
		-- credit count, so the store button updates either way.
		return true
	end)
	if not reserved then
		-- Nothing was spent, so there is nothing to give back.
		if reentryAttempts[player] == token then reentryAttempts[player] = nil end
		return false
	end

	local ok, accepted = pcall(reentry.Invoke, reentry, player)
	if reentryAttempts[player] ~= token then return ok and accepted == true end
	reentryAttempts[player] = nil
	if ok and accepted == true then
		markRunAided(player)
		if Analytics then Analytics.ItemUse(player, "Reentry") end
		pushProfile(player, "Emergency Re-entry activated.", "success")
		return true
	end

	-- The refund is a delta, so it cannot go through mutateIdempotent: replaying
	-- a `+= 1` whose write in fact committed would hand out a credit nobody paid
	-- for. It gets a small bounded retry instead, because one transient
	-- DataStore error must not turn "respawn refused" into "paid credit
	-- destroyed" -- and if all three attempts fail, the warn is the only trace
	-- left, so it names the userId to make the credit reconcilable by hand.
	local function refund(data)
		data.ReentryCredits += 1
		return true, "Re-entry is only available after death during an active round.", "error"
	end
	for attempt = 1, 3 do
		if mutate(player, refund) then return false end
		if not player.Parent or sessions[player] ~= session then break end
		if attempt < 3 then task.wait(0.35) end
	end
	warn("[Zyntra] Re-entry refund FAILED; owes 1 ReentryCredit to userId", player.UserId)
	return false
end

-- One Roblox badge, decided from OUR record first. UserHasBadgeAsync is asked
-- only when we have no record of the award, which keeps an account that earned
-- the badge before this shipped from being re-awarded (and re-notified) on every
-- later clear. Everything yields inside task.spawn and every Roblox call is
-- wrapped, so a throttled or failing badge service can neither block nor fail
-- the profile write that reported the clear.
local function awardBadge(player, badgeKey)
	local badgeId = math.floor(tonumber(Config.Badges and Config.Badges[badgeKey]) or 0)
	if badgeId <= 0 then return end
	local session = sessions[player]
	if not session or session.data.AwardedBadges[badgeKey] == true then return end
	task.spawn(function()
		local asked, owns = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badgeId)
		if not (asked and owns == true) then
			-- BOTH returns matter. pcall's second value is AwardBadge's own
			-- boolean, and AwardBadge RETURNS false rather than throwing for the
			-- ordinary refusals: badge disabled, badge not owned by this place,
			-- award throttled, player gone. Reading only pcall's ok would record
			-- an award that never happened -- and that record is checked first on
			-- every later clear, so the badge would never be retried again.
			local ok, awarded = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
			if not ok or awarded ~= true then
				warn("[Zyntra] AwardBadge failed for", player.Name, badgeKey, awarded)
				return
			end
		end
		-- Recording the award is a target state, not a delta, so a retried write
		-- cannot hand anything out twice: the idempotent path is the right one.
		mutateIdempotent(player, function(data)
			if data.AwardedBadges[badgeKey] == true then return false end
			data.AwardedBadges[badgeKey] = true
			return true
		end, true)
	end)
end

-- Accessibility switches persist like the dispatch mute and for the same
-- reason: they are target state, not deltas, and a client can flip one as fast
-- as it likes. The attribute and the session copy move immediately (the client
-- stays optimistic), while ONE deferred write commits whatever the newest
-- target is -- so forty flips cost one write, not forty. The first change after
-- a quiet spell writes at once; only a follow-up inside the floor waits. A
-- player who quits inside the floor is covered by the flush in
-- finalizePlayerSessionBody, which commits the same targets before the session
-- closes -- without it the second change of a session was simply lost.
local ACCESSIBILITY_WRITE_FLOOR = 6

-- Target state, not a delta: writing the same value twice is a no-op, so this
-- transform reports "no change" and mutateIdempotent cancels the update.
-- The caller hands over the LIVE queue, so snapshot it first (that copy cannot
-- yield): the write below can, and a switch flipped while it does must not be
-- added to a table this is still iterating.
local function writeAccessibilityTargets(player, desired)
	local targets = {}
	for settingKey, settingValue in pairs(desired) do
		targets[settingKey] = settingValue
	end
	return mutateIdempotent(player, function(data)
		local changed = false
		for settingKey, settingValue in pairs(targets) do
			if data.Settings[settingKey] ~= settingValue then
				data.Settings[settingKey] = settingValue
				changed = true
			end
		end
		return changed
	end, true)
end

local function queueAccessibilityWrite(player, key, value)
	local queue = accessibilityQueues[player]
	if not queue then
		queue = { running = false, dirty = false, desired = {}, lastWriteAt = -math.huge }
		accessibilityQueues[player] = queue
	end
	-- The target is remembered HERE and not read back out of session.data later:
	-- any unrelated profile write landing in between replaces session.data with
	-- the store's copy, which does not have this toggle in it yet. Keeping every
	-- key toggled this session also means the next write re-asserts them all, so
	-- a value that was overwritten that way heals itself.
	queue.desired[key] = value
	queue.dirty = true
	if queue.running then return end
	queue.running = true
	task.spawn(function()
		while queue.dirty do
			local remaining = ACCESSIBILITY_WRITE_FLOOR - (os.clock() - queue.lastWriteAt)
			if remaining > 0 then task.wait(remaining) end
			local session = sessions[player]
			if not session or session.closing or not player.Parent
				or accessibilityQueues[player] ~= queue then break end
			-- Snapshot AFTER the wait (writeAccessibilityTargets takes it): every
			-- toggle that arrived while we waited is already in queue.desired, so
			-- they all commit in this one write.
			queue.dirty = false
			writeAccessibilityTargets(player, queue.desired)
			-- Rate-limit from completion, as the dispatch queue does.
			queue.lastWriteAt = os.clock()
		end
		queue.running = false
	end)
end

-- ---------------------------------------------------------------------------
-- Daily rewards, stored items and the inventory service
-- ---------------------------------------------------------------------------
local DAILY_AFK_GRACE = math.max(1, tonumber(DAILY_REWARDS.AfkGraceSeconds) or 90)
local DAILY_ACTIVITY_STUDS = math.max(0, tonumber(DAILY_REWARDS.ActivityMinimumStuds) or 1)
local DAILY_FLUSH_INTERVAL = math.max(5, tonumber(DAILY_REWARDS.FlushIntervalSeconds) or 60)

local function playtimeState(player)
	local state = playtimeSessions[player]
	local today = utcDay()
	if state then
		if state.day ~= today then
			state.day = today
			state.unflushedSeconds = 0
			state.activeFlushId, state.activeFlushSeconds = nil, nil
		end
		return state
	end
	playtimeSessionSequence += 1
	state = {
		day = today,
		sessionSequence = playtimeSessionSequence,
		lastPosition = nil,
		lastMovedAt = 0,
		lastFlushAt = 0,
		unflushedSeconds = 0,
		flushCount = 0,
		-- nil, not false: the first tick then always differs and publishes, so a
		-- player who never earns a second still has the attribute to read.
		accruing = nil,
	}
	playtimeSessions[player] = state
	return state
end

-- The identity of ONE flush. It changes only when the seconds it covers are
-- known to be in the profile, so every retry of the same flush carries the same
-- id -- which is how a write that committed and lost its response is recognised
-- instead of being added a second time.
local function flushIdFor(player, state)
	return string.format("%s:%d:%d:%d", tostring(game.JobId), player.UserId, state.sessionSequence, state.flushCount)
end

-- One transaction for everything that touches today's counters. It rolls the
-- day, folds in the seconds this session has earned since its last flush, and
-- then runs the caller's own change -- so a claim at exactly five minutes can
-- never lose the seconds that took it there.
--
-- `body(data, today)` returns the same triple a mutate transform does and must
-- only mutate `data` when it accepts. Returns the BODY's answer, which is not
-- mutate's: a write that carried nothing but banked playtime is a successful
-- write and still a refused action.
local function dailyMutate(player, body)
	local state = playtimeState(player)
	local delta, flushId, deltaDay
	local accepted, banked, proven = false, false, false
	local committed, message = mutate(player, function(data)
		-- Snapshot only after mutate owns the existing profile lock. Retain that
		-- snapshot across UpdateAsync retries, including a lost-response retry.
		if delta == nil then
			state = playtimeState(player)
			delta = state.activeFlushId and state.activeFlushSeconds or wholeCount(state.unflushedSeconds)
			flushId = state.activeFlushId or flushIdFor(player, state)
			deltaDay = state.day
			state.activeFlushId, state.activeFlushSeconds = flushId, delta
		end
		accepted, banked, proven = false, false, false
		local today = utcDay()
		local rolled = rollDaily(data, today)
		local already = deltaDay == today and delta > 0 and data.Daily.FlushId == flushId
		local adding = deltaDay == today and delta > 0 and not already
			and delta <= MAX_SAFE_SUPPORT - data.Daily.PlaytimeSeconds
		if adding then
			data.Daily.PlaytimeSeconds += delta
			data.Daily.FlushId = flushId
		end
		local granted, bodyMessage, tone = body(data, today)
		accepted = granted == true
		proven = already
		banked = already or adding
		-- A refusal costs a read and not a write -- unless this transform has
		-- already changed the profile, because cancelling then would adopt a copy
		-- the store never received. A day roll and banked playtime are both real
		-- changes and worth the write on their own.
		if not accepted and not rolled and not adding then
			return false, bodyMessage, tone
		end
		return true, bodyMessage, tone
	end)
	-- `committed` is mutate's "the transform reported a change", and the transform
	-- above reports one whenever it added seconds, so it doubles as proof the
	-- write landed. `proven` covers the other direction: the profile already held
	-- this exact flush, which only a previous commit can explain.
	if delta ~= nil and state.day == deltaDay and ((committed and banked) or proven) then
		-- Subtract, never zero: seconds that arrived while the write yielded belong
		-- to the next flush.
		state.unflushedSeconds = math.max(0, wholeCount(state.unflushedSeconds) - delta)
		state.flushCount += 1
		if state.activeFlushId == flushId then
			state.activeFlushId, state.activeFlushSeconds = nil, nil
		end
	elseif delta == 0 and state.activeFlushId == flushId then
		state.activeFlushId, state.activeFlushSeconds = nil, nil
	end
	return committed and accepted, message
end

-- Only validated server gameplay emits this event; clients cannot submit progress.
local researchProgress = ServerStorage:FindFirstChild("ZyntraResearchProgress")
if not researchProgress then
 researchProgress = Instance.new("BindableEvent")
 researchProgress.Name="ZyntraResearchProgress"
 researchProgress.Parent=ServerStorage
end
researchProgress.Event:Connect(function(player, key)
 if typeof(player)~="Instance" or not player:IsA("Player") or player.Parent~=Players
  or (key~="Fuse" and key~="Lever") or not sessions[player] then return end
 local earnedDay=utcDay()
 local earnerTier=tokenEarner.tier(player)
 for attempt=1,3 do
  if utcDay()~=earnedDay or player.Parent~=Players then return end
  local session=sessions[player]
  if not session or session.closing then return end
  if session.data.Daily.Day==earnedDay and session.data.Daily.Research[key] then return end
  local done=dailyMutate(player,function(data,today)
   if today~=earnedDay then return false end
   local changed,amount=DailyResearch.Complete(data,key)
   if changed then amount+=tokenEarner.bonus(data,amount,earnerTier) end
   return changed, changed and ("Daily research complete: +"..amount.." Research Token"..(amount==1 and "" or "s")) or nil,"success"
  end)
  if done then return end
  task.wait(attempt)
 end
end)

local function flushPlaytime(player)
	local state = playtimeSessions[player]
	if not state or wholeCount(state.unflushedSeconds) <= 0 then return false end
	dailyMutate(player, function() return false end)
	return true
end

-- Does this second count? Every condition is the contract's. The lobby is out
-- because InRound is false there; a round that is loading, over or in its
-- Level 2 exit transition is out by the workspace flags.
--
-- SPECTATING COUNTS (owner, 2026-09-17). A participant of an active round who
-- has no living humanoid -- dead, escaped and waiting, or between bodies -- is
-- watching that round, and that time is play time. There is nothing for them
-- to move, so the AFK gate below cannot apply to them; the round's own end is
-- what bounds it (the flags above go false the moment it ends).
local function playtimeCounts(player, state, now)
	if player:GetAttribute("InRound") ~= true then return false end
	if workspace:GetAttribute("RoundActive") ~= true then return false end
	if workspace:GetAttribute("RoundLoadingState") ~= "ready" then return false end
	if player:GetAttribute("Level2_ExitTransition") == true then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if player:GetAttribute("Escaped") == true or not humanoid or not root or humanoid.Health <= 0 then
		return true
	end
	local position = root.Position
	local last = state.lastPosition
	if not last or (position - last).Magnitude >= DAILY_ACTIVITY_STUDS then
		state.lastPosition = position
		state.lastMovedAt = now
	end
	-- Hiding under a table is the one legitimate way to be perfectly still, and
	-- it is exactly when a player most needs the time to count.
	if player:GetAttribute("Level3_Hiding") == true then return true end
	return now - state.lastMovedAt <= DAILY_AFK_GRACE
end

task.spawn(function()
	while true do
		task.wait(1)
		local now = workspace:GetServerTimeNow()
		for player, session in pairs(sessions) do
			if player.Parent and not session.closing then
				local state = playtimeState(player)
				local counting = playtimeCounts(player, state, now)
				-- Only ever add. A second that was earned stays earned: nothing in
				-- this file subtracts from PlaytimeSeconds except the day roll.
				if counting then state.unflushedSeconds += 1 end
				if state.accruing ~= counting then
					state.accruing = counting
					player:SetAttribute("ZyntraDailyAccruing", counting)
				end
				if counting and state.unflushedSeconds > 0
					and now - state.lastFlushAt >= DAILY_FLUSH_INTERVAL then
					state.lastFlushAt = now
					task.spawn(flushPlaytime, player)
				end
			end
		end
	end
end)

-- The speed potion's one-per-round rule needs a round identity, and the same
-- pair of attribute changes PlayerProtection already treats as a round boundary
-- is the right one: RoundActive flips between consecutive rounds even when the
-- level does not, and a direct level change is its own boundary.
local roundEpoch = 0
local potionRoundUsed = setmetatable({}, { __mode = "k" })
local speedBoostTokens = setmetatable({}, { __mode = "k" })

-- The client owns movement speed; this only publishes how much and until when.
-- Nothing here writes Humanoid.WalkSpeed -- a server that did would fight the
-- sprint, crouch and stun controllers and would restore a stale value on death.
local function clearSpeedBoost(player)
	speedBoostTokens[player] = nil
	player:SetAttribute("ZyntraSpeedBoostUntil", 0)
	player:SetAttribute("ZyntraSpeedBoostMultiplier", 1)
end

local function roundChanged()
	roundEpoch += 1
	table.clear(potionRoundUsed)
	local ended = workspace:GetAttribute("RoundActive") ~= true
	for player in pairs(sessions) do
		player:SetAttribute("ZyntraSpeedPotionUsedThisRound", false)
		clearSpeedBoost(player)
		-- Bank the round's playtime at the boundary rather than waiting out the
		-- flush interval; a player who leaves straight from the results screen
		-- would otherwise lose up to a minute of what they just played.
		if ended then task.spawn(flushPlaytime, player) end
	end
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(roundChanged)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(roundChanged)

local function watchSpeedBoost(player)
	local function characterBoost(character)
		clearSpeedBoost(player)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function() clearSpeedBoost(player) end)
		end
	end
	player.CharacterAdded:Connect(characterBoost)
	player.CharacterRemoving:Connect(function() clearSpeedBoost(player) end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") ~= true then clearSpeedBoost(player) end
	end)
	clearSpeedBoost(player)
	player:SetAttribute("ZyntraSpeedPotionUsedThisRound", false)
	if player.Character then task.spawn(characterBoost, player.Character) end
end
Players.PlayerAdded:Connect(watchSpeedBoost)
for _, player in ipairs(Players:GetPlayers()) do watchSpeedBoost(player) end

-- Exactly PlayerProtection's eligibility, plus the two the contract adds: the
-- loading cover must be gone, and a player folded under a table cannot drink.
local function speedPotionRefusal(player)
	if workspace:GetAttribute("RoundActive") ~= true
		or player:GetAttribute("InRound") ~= true
		or workspace:GetAttribute("RoundLoadingState") ~= "ready"
		or player:GetAttribute("Escaped") == true
		or player:GetAttribute("Level2_ExitTransition") == true then return "Not in a round" end
	if player:GetAttribute("Level3_Hiding") == true then return "Not while hiding" end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not character:IsDescendantOf(workspace)
		or not humanoid or humanoid.Health <= 0 then return "Not in a round" end
	if potionRoundUsed[player] == roundEpoch then return "Already used this round" end
	return nil
end

local function useSpeedPotion(player)
	local item = ITEM_CONFIG.SpeedPotion
	local session = sessions[player]
	if not item or not session or session.closing then return end
	-- Refuse in memory FIRST, like the upgrade path: a player with no potion or
	-- no round must not be able to spend a DataStore write per press.
	local refusal = speedPotionRefusal(player)
	if not refusal and session.data.Items.SpeedPotion < 1 then refusal = "No Speed Potion stored" end
	if refusal then
		pushProfile(player, refusal .. ".", "error")
		return
	end

	local epoch = roundEpoch
	local duration = math.max(0, tonumber(item.DurationSeconds) or 0)
	local multiplier = math.max(1, tonumber(item.SpeedMultiplier) or 1)
	local consumed = dailyMutate(player, function(data)
		-- Rechecked after waiting for the mutation lock and the store.
		if data.Items.SpeedPotion < 1 then return false, "No Speed Potion stored.", "error" end
		if epoch ~= roundEpoch or potionRoundUsed[player] == epoch then
			return false, "Already used this round.", "error"
		end
		local late = speedPotionRefusal(player)
		if late then return false, late .. ".", "error" end
		data.Items.SpeedPotion -= 1
		return true, string.format("Speed Potion: +%d%% speed for %d seconds.",
			math.floor((multiplier - 1) * 100 + 0.5), duration), "success"
	end)
	if not consumed then return end
	-- The potion is spent. If the round ended while the write yielded, the boost
	-- is simply not applied: roundChanged has already cleared the attributes and
	-- resurrecting them here would hand a lobby player a speed boost.
	if epoch ~= roundEpoch then return end
	potionRoundUsed[player] = epoch
	markRunAided(player)
	if Analytics then Analytics.ItemUse(player, "SpeedPotion") end
	local token = {}
	speedBoostTokens[player] = token
	player:SetAttribute("ZyntraSpeedBoostUntil", workspace:GetServerTimeNow() + duration)
	player:SetAttribute("ZyntraSpeedBoostMultiplier", multiplier)
	player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	task.delay(duration, function()
		if speedBoostTokens[player] == token then clearSpeedBoost(player) end
	end)
end

local function milestoneFor(minutes)
	for _, milestone in ipairs(DAILY_REWARDS.Milestones or {}) do
		if milestone.Minutes == minutes then return milestone end
	end
	return nil
end

-- The playtime this player can claim against right now: what is saved for today
-- plus what this session has earned since the last flush landed.
local function claimablePlaytime(player, data)
	local state = playtimeSessions[player]
	local daily = data.Daily
	return (daily.Day == utcDay() and daily.PlaytimeSeconds or 0)
		+ (state and state.day == utcDay() and wholeCount(state.unflushedSeconds) or 0)
end

local function claimPlaytimeReward(player, payload)
	local minutes = type(payload) == "table" and payload.Minutes or nil
	local milestone = type(minutes) == "number" and milestoneFor(minutes) or nil
	local session = sessions[player]
	if not milestone or not session or session.closing then return end
	local key = tostring(milestone.Minutes)
	local required = milestone.Minutes * 60
	local claimedMessage = string.format("You already claimed the %d minute reward today.", milestone.Minutes)
	if session.data.Daily.Day == utcDay() and session.data.Daily.Claimed[key] == true then
		pushProfile(player, claimedMessage, "error")
		return
	end
	local have = claimablePlaytime(player, session.data)
	if have < required then
		pushProfile(player, string.format(
			"Play %d minutes of a round today to claim this. You are at %d minutes.",
			milestone.Minutes, math.floor(have / 60)), "error")
		return
	end
	local earnerTier = tokenEarner.tier(player)
	dailyMutate(player, function(data)
		if data.Daily.Claimed[key] == true then return false, claimedMessage, "error" end
		if data.Daily.PlaytimeSeconds < required then
			return false, string.format(
				"Play %d minutes of a round today to claim this.", milestone.Minutes), "error"
		end
		local label = applyReward(data, milestone.Reward, earnerTier)
		if not label then return false, "That reward is unavailable right now.", "error" end
		data.Daily.Claimed[key] = true
		return true, string.format("%s collected -- %d minutes of play today.", label, milestone.Minutes), "success"
	end)
end

-- The wheel's own generator, so a test can pin the sequence without touching
-- anything else that needs randomness.
local wheelRandom = Random.new()

local function wheelPrizeByKey(key)
	for _, prize in ipairs(DAILY_REWARDS.Wheel or {}) do
		if prize.Key == key then return prize end
	end
	return nil
end

local function pickWheelPrize()
	local wheel = DAILY_REWARDS.Wheel or {}
	local total = 0
	for _, prize in ipairs(wheel) do total += math.max(0, tonumber(prize.Weight) or 0) end
	if total <= 0 then return nil end
	local roll = wheelRandom:NextNumber() * total
	local seen = 0
	for _, prize in ipairs(wheel) do
		seen += math.max(0, tonumber(prize.Weight) or 0)
		if roll < seen then return prize end
	end
	return wheel[#wheel]
end

local function wheelResultLabel(last, prize)
	if prize and prize.Key == "Skin5" then
		if last and last.FallbackTokens == 3 then
			return "3 Research Tokens (skin fallback)"
		end
		local skin = last and Skins.Get(last.SkinId)
		return skin and (skin.Name .. " hazmat skin") or "a hazmat skin"
	end
	return prize and prize.Label or "the last spin"
end

local function spentSpinMessage(daily)
	local last = daily.WheelLast
	local prize = last and wheelPrizeByKey(last.Key)
	return string.format("Today's spin is done: %s. Next spin at 00:00 UTC.",
		prize and wheelResultLabel(last, prize) or "already claimed")
end

-- WHEEL_COLLECT_20260922 (Trello 25GLltY6). A spin RECORDS the prize
-- (WheelLast.Claimed = false) and the claim PAYS it, so the player sees what
-- they won, presses COLLECT PRIZE, and the confirmation is the server's word.
-- Exactly one payout: applyReward and Claimed = true sit in the same UpdateAsync
-- transform, a second claim finds Claimed == true and writes nothing, and a
-- spin is refused while a prize is still owed -- so a day change cannot
-- overwrite an uncollected prize with a new result (the free spin waits).
local function pendingWheelPrize(daily)
	local last = daily.WheelLast
	return last and last.Claimed == false and last or nil
end

local function collectFirstMessage(daily)
	local last = pendingWheelPrize(daily)
	local prize = last and wheelPrizeByKey(last.Key)
	return string.format("Collect your prize first: %s.", wheelResultLabel(last, prize))
end

local function spinDailyWheel(player)
	local session = sessions[player]
	if not session or session.closing then return end
	local today = utcDay()
	if pendingWheelPrize(session.data.Daily) then
		pushProfile(player, collectFirstMessage(session.data.Daily), "info")
		return
	end
	-- Already spun: re-report the RECORDED prize and write nothing. That one rule
	-- is what makes a lost reply, a rejoin, a retry and a double click all safe --
	-- the outcome the UI animates to is durable before any of them can happen.
	if session.data.Daily.WheelDay == today then
		pushProfile(player, spentSpinMessage(session.data.Daily), "info")
		return
	end
	dailyMutate(player, function(data)
		if pendingWheelPrize(data.Daily) then return false, collectFirstMessage(data.Daily), "info" end
		if data.Daily.WheelDay == today then
			return false, spentSpinMessage(data.Daily), "info"
		end
		local prize = pickWheelPrize()
		if not prize or type(prize.Reward) ~= "table" then
			return false, "The supply wheel is offline right now.", "error"
		end
		local skinId, fallbackTokens
		if prize.Key == "Skin5" then
			local eligible = {}
			for _, candidate in ipairs(Skins.WheelEligible) do
				if not Skins.IsOwned(data.Skins, candidate) then
					eligible[#eligible + 1] = candidate
				end
			end
			if #eligible == 0 then
				fallbackTokens = 3
			else
				skinId = eligible[math.floor(wheelRandom:NextNumber() * #eligible) + 1]
			end
		end
		data.Daily.WheelDay = today
		data.Daily.WheelLast = {
			Day = today,
			Key = prize.Key,
			SkinId = skinId,
			FallbackTokens = fallbackTokens,
			Serial = wholeCount(data.Daily.WheelLast and data.Daily.WheelLast.Serial) + 1,
			Claimed = false,
		}
		return true, "Supply Wheel: " .. wheelResultLabel(data.Daily.WheelLast, prize)
			.. " -- collect your prize.", "success"
	end)
end

-- REWARDS_INTRO_20260922. Target-state write: "seen" is true afterwards no
-- matter how many times the client says so, and a lost reply costs nothing.
local function markRewardsIntroSeen(player)
	local session = sessions[player]
	if not session or session.closing then return end
	if session.data.Settings.RewardsIntroSeen == true then return end
	mutateIdempotent(player, function(data)
		if data.Settings.RewardsIntroSeen == true then return false end
		data.Settings.RewardsIntroSeen = true
		return true
	end)
end

local function claimWheelPrize(player)
	local session = sessions[player]
	if not session or session.closing then return end
	if not pendingWheelPrize(session.data.Daily) then
		pushProfile(player, "Nothing to collect.", "info")
		return
	end
	local earnerTier = tokenEarner.tier(player)
	dailyMutate(player, function(data)
		local last = pendingWheelPrize(data.Daily)
		if not last then return false, "Nothing to collect.", "info" end
		local prize = wheelPrizeByKey(last.Key)
		local label
		local tokensBefore = data.Tokens
		if prize and prize.Key == "Skin5" then
			if last.FallbackTokens == 3 or Skins.IsOwned(data.Skins, last.SkinId) then
				-- A player can buy the selected suit after spinning but before
				-- collecting. Keep the exact SkinId receipt and pay the same fallback.
				label = applyReward(data, {Kind = "Tokens", Amount = 3}, earnerTier)
				if label then last.FallbackTokens = 3 end
			else
				local skin = Skins.Get(last.SkinId)
				if skin and Skins.Grant(data.Skins, last.SkinId) then
					label = skin.Name .. " hazmat skin"
				end
			end
		else
			label = prize and applyReward(data, prize.Reward, earnerTier)
		end
		if not label then return false, "That prize is unavailable right now.", "error" end
		if data.Tokens > tokensBefore then last.PaidTokens = data.Tokens - tokensBefore end
		last.Claimed = true
		return true, label .. " collected.", "success"
	end)
end

local function buyItem(player, payload)
	local key = type(payload) == "table" and payload.Key or nil
	local item = type(key) == "string" and ITEM_CONFIG[key] or nil
	local session = sessions[player]
	if not item or not session or session.closing or session.data.Items[key] == nil then return end
	local cost = math.max(0, math.floor(tonumber(item.TokenCost) or 0))
	local amount = math.max(1, math.floor(tonumber(item.PackSize) or 1))
	local needMessage = string.format("You need %d Research Tokens.", cost)
	if session.data.Tokens < cost then
		pushProfile(player, needMessage, "error")
		return
	end
	dailyMutate(player, function(data)
		if data.Tokens < cost then return false, needMessage, "error" end
		local label = applyReward(data, {Kind = "Item", Key = key, Amount = amount})
		if not label then return false, "That item is unavailable right now.", "error" end
		data.Tokens -= cost
		return true, string.format("%s stored (%d owned).", item.Name, data.Items[key]), "success"
	end)
end

-- ServerStorage.ZyntraInventory: the only way another server script may read or
-- spend a stored item, or hand out a field note. Every op validates its caller;
-- Consume is a durable transaction and a caller must not apply its effect when
-- it answers false.
local inventoryFunction = ServerStorage:FindFirstChild("ZyntraInventory")
if inventoryFunction and not inventoryFunction:IsA("BindableFunction") then
	inventoryFunction:Destroy()
	inventoryFunction = nil
end
if not inventoryFunction then
	inventoryFunction = Instance.new("BindableFunction")
	inventoryFunction.Name = "ZyntraInventory"
	inventoryFunction.Parent = ServerStorage
end

local function inventorySession(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player")
		or player.Parent ~= Players then return nil end
	local session = sessions[player]
	if not session or session.closing then return nil end
	return session
end

local function inventoryItemKey(session, key)
	if type(key) ~= "string" or session.data.Items[key] == nil then return nil end
	return key
end

inventoryFunction.OnInvoke = function(operation, player, key, amount)
	if operation == "Count" then
		local session = inventorySession(player)
		local itemKey = session and inventoryItemKey(session, key)
		return itemKey and session.data.Items[itemKey] or 0
	end

	if operation == "Consume" then
		local session = inventorySession(player)
		if not session then return false, "Your profile is not loaded" end
		local itemKey = inventoryItemKey(session, key)
		if not itemKey then return false, "Unknown item" end
		if not isSafeSupportAmount(amount) or amount < 1 then return false, "Invalid amount" end
		if session.data.Items[itemKey] < amount then return false, "You do not have that item" end
		local spent = dailyMutate(player, function(data)
			if data.Items[itemKey] < amount then return false, nil, nil end
			data.Items[itemKey] -= amount
			return true
		end)
		if not spent then return false, "That could not be saved. Try again." end
		markRunAided(player)
		if Analytics then Analytics.ItemUse(player, itemKey) end
		return true, ""
	end

	return false, "Unknown inventory operation"
end

-- Actions that open a DataStore write get a window a human click fits in;
-- everything else keeps the responsive one. UseReentry is deliberately NOT in
-- here: it is a single press inside the fifteen-second wipe window, it refuses
-- itself in memory when there is no credit, and reentryAttempts already allows
-- only one at a time.
-- SetAccessibility belongs here even though its DataStore write is coalesced
-- behind a six-second floor: every accepted call still republishes sixteen
-- attributes and a whole profile packet, and a client alternating true/false is
-- never a duplicate. One human click per switch per second is plenty.
local WRITE_BEARING_ACTIONS = {
	UpgradeStamina = true,
	UpgradeBattery = true,
	SetHazmatColor = true,
	SetGlowstickColor = true,
	SetAccessibility = true,
	-- All four open a profile transaction. UseSpeedPotion is one press inside a
	-- round, but that press spends a stored consumable, so it belongs here.
	ClaimPlaytimeReward = true,
	SpinDailyWheel = true,
	ClaimWheelPrize = true,
	MarkRewardsIntroSeen = true,
	BuyItem = true,
	BuySkin = true,
	EquipSkin = true,
	UseSpeedPotion = true,
}
local ACTION_WINDOW = 0.12
local WRITE_ACTION_WINDOW = 1

actionRemote.OnServerEvent:Connect(function(player, action, payload)
	if type(action) ~= "string" or not sessions[player] then return end
	-- Dispatch preference is an idempotent target state with its own coalescing
	-- queue. It must never be silently dropped because the player clicked any
	-- unrelated store action during the shared 120 ms action window.
	if action == "BuyProtection" or action == "UseProtection" then
		handleProtectionAction(player, action, payload)
		return
	end
	if action == "SetMuteDispatch" then
		if type(payload) == "boolean" then queueMuteDispatch(player, payload) end
		return
	end
	local now = os.clock()
	-- The window is PER ACTION, not per player. One shared timestamp turned two
	-- legitimate consecutive clicks on different controls -- UPGRADE STAMINA then
	-- UPGRADE BATTERY, HAZMAT SAVE then GLOWSTICK SAVE -- into one click plus a
	-- dead button, which at a one-second window is a human interval. Accessibility
	-- switches key on the switch as well, because the settings page is a column of
	-- them; an unknown key falls into the shared bucket so a spammer cannot grow
	-- this table.
	local windowKey = action
	if action == "SetAccessibility" and type(payload) == "table"
		and ACCESSIBILITY_BY_KEY[payload.Key] then
		windowKey = "SetAccessibility:" .. payload.Key
	elseif action == "ClaimPlaytimeReward" and type(payload) == "table"
		and milestoneFor(payload.Minutes) then
		-- The rewards page is a column of claim buttons, like the settings page is
		-- a column of switches: two legitimate consecutive clicks on DIFFERENT
		-- milestones must not collapse into one. Both key sets are fixed by config,
		-- so a spammer cannot grow this table.
		windowKey = "ClaimPlaytimeReward:" .. tostring(payload.Minutes)
	elseif action == "BuyItem" and type(payload) == "table" and ITEM_CONFIG[payload.Key] then
		windowKey = "BuyItem:" .. payload.Key
	elseif (action == "BuySkin" or action == "EquipSkin")
		and type(payload) == "string" and Skins.Get(payload) then
		windowKey = action .. ":" .. payload
	end
	local times = actionTimes[player]
	if not times then
		times = {}
		actionTimes[player] = times
	end
	local window = WRITE_BEARING_ACTIONS[action] and WRITE_ACTION_WINDOW or ACTION_WINDOW
	if now - (times[windowKey] or 0) < window then return end
	times[windowKey] = now

	if action == "ShopView" then
		-- ANALYTICS_20260921, measurement only. A card opening and a demo starting
		-- are the only two shop facts the server cannot observe for itself. This
		-- branch grants nothing, answers nothing and prompts nothing; the module
		-- drops any key that is not in the catalogue. Lobby only, like the shop,
		-- and already behind the shared per-action window above.
		if Analytics and type(payload) == "table" and player:GetAttribute("InRound") ~= true then
			Analytics.ShopView(player, payload.Key, payload.Demo == true)
		end
	elseif action == "DeviceClass" then
		-- ANALYTICS_20260921, segmentation only: first answer per session wins,
		-- from a fixed enum, and nothing in gameplay or the store reads it.
		local class = type(payload) == "table" and payload.Class
		if player:GetAttribute("ZyntraDeviceClass") == nil
			and (class == "PC" or class == "Phone" or class == "Tablet") then
			player:SetAttribute("ZyntraDeviceClass", class)
		end
	elseif action == "UpgradeStamina" or action == "UpgradeBattery" then
		-- Refuse in memory FIRST. The in-transform check below stays as the
		-- cross-server race guard, but reaching it costs a DataStore write, and a
		-- player with zero tokens could once drive one of those per click.
		-- UPGRADE_COST_20260924: the price rises with the level held, and is
		-- recomputed inside the transform from the profile it actually writes.
		local field = action == "UpgradeStamina" and "StaminaLevel" or "BatteryLevel"
		local function shortOf(data)
			local price = Config.UpgradeCost(data[field])
			if data.Tokens >= price then return nil end
			return ("You need %d Zyntra Research Token%s."):format(price, price == 1 and "" or "s")
		end
		local refusal = shortOf(sessions[player].data)
		if refusal then
			pushProfile(player, refusal, "error")
			return
		end
		mutate(player, function(data)
			refusal = shortOf(data)
			if refusal then return false, refusal, "error" end
			data.Tokens -= Config.UpgradeCost(data[field])
			data[field] += 1
			if action == "UpgradeStamina" then
				return true, "Stamina increased by " .. PCT .. ".", "success"
			end
			return true, "Battery increased by " .. PCT .. ".", "success"
		end)
	elseif action == "SetHazmatColor" then
		if player:GetAttribute("ZyntraOwnsAdvancedEquipment") ~= true then
			pushProfile(player, "Advanced Equipment is required.", "error")
			return
		end
		local color = validColor(payload)
		if not color then return end
		local wanted = colorData(color)
		local session = sessions[player]
		if not session then return end
		-- A colour that is already saved is acknowledged, not written. The same
		-- check inside the transform stays as the cross-server race guard.
		if sameColorData(session.data.Colors.Hazmat, wanted) then
			pushProfile(player, "Hazmat color saved.", "success")
			return
		end
		mutate(player, function(data)
			if sameColorData(data.Colors.Hazmat, wanted) then
				return false, "Hazmat color saved.", "success"
			end
			data.Colors.Hazmat = wanted
			return true, "Hazmat color saved.", "success"
		end)
	elseif action == "SetGlowstickColor" then
		if player:GetAttribute("ZyntraOwnsCosmeticEquipment") ~= true then
			pushProfile(player, "Glowstick Customizer is required.", "error")
			return
		end
		local color = validColor(payload)
		if not color then return end
		local wanted = colorData(color)
		local session = sessions[player]
		if not session then return end
		if sameColorData(session.data.Colors.Glowstick, wanted) then
			pushProfile(player, "Glowstick color saved.", "success")
			return
		end
		mutate(player, function(data)
			if sameColorData(data.Colors.Glowstick, wanted) then
				return false, "Glowstick color saved.", "success"
			end
			data.Colors.Glowstick = wanted
			return true, "Glowstick color saved.", "success"
		end)
	elseif action == "SetAccessibility" then
		if type(payload) ~= "table" or type(payload.Enabled) ~= "boolean"
			or type(payload.Key) ~= "string" then return end
		local setting = ACCESSIBILITY_BY_KEY[payload.Key]
		if not setting then return end
		local session = sessions[player]
		if not session or session.closing then return end
		-- Idempotent: an unchanged switch is not a write and not a packet.
		if accessibilityValue(session.data, setting) == payload.Enabled then return end
		session.data.Settings[setting.Key] = payload.Enabled
		-- Record the target BEFORE anything publishes it: from here on, a mutation
		-- finishing on another thread re-asserts it instead of overwriting it with
		-- the store's older copy (reassertPendingAccessibility).
		queueAccessibilityWrite(player, setting.Key, payload.Enabled)
		applyAttributes(player, session.data)
		pushProfile(player, setting.Label .. (payload.Enabled and ": on" or ": off"), "success")
	elseif action == "UseReentry" then
		useReentry(player)
	elseif action == "ClaimPlaytimeReward" then
		claimPlaytimeReward(player, payload)
	elseif action == "SpinDailyWheel" then
		spinDailyWheel(player)
	elseif action == "ClaimWheelPrize" then
		claimWheelPrize(player)
	elseif action == "MarkRewardsIntroSeen" then
		markRewardsIntroSeen(player)
	elseif action == "BuyItem" then
		buyItem(player, payload)
	elseif action == "BuySkin" then
		local skin = Skins.Get(payload)
		if not skin or skin.Kind ~= "Tokens" then return end
		local current = sessions[player].data
		if Skins.IsOwned(current.Skins, payload) then
			pushProfile(player, "Already owned.", "info")
			return
		end
		if current.CompletedLevels < (skin.RequiredClears or 0) then
			pushProfile(player, ("Requires %d lifetime clears."):format(skin.RequiredClears), "error")
			return
		end
		if current.Tokens < skin.TokenCost then
			pushProfile(player, ("Requires %d Research Tokens."):format(skin.TokenCost), "error")
			return
		end
		mutate(player, function(data)
			local changed, message = Skins.BuyToken(data, payload)
			return changed, message, changed and "success" or "error"
		end)
	elseif action == "EquipSkin" then
		if not Skins.Get(payload) then return end
		local current = sessions[player].data.Skins
		if not Skins.IsOwned(current, payload) then return end
		if current.Equipped == payload then return end
		mutate(player, function(data)
			local changed, message = Skins.Equip(data.Skins, payload)
			return changed, message, changed and "success" or "error"
		end)
	elseif action == "UseSpeedPotion" then
		useSpeedPotion(player)
	end
end)

-- COMPLETION_SAVE_20260924 (Trello EYpXKa9S). A clear is ONE keyed write: its
-- id (GameManager's round id + level) lands in the same UpdateAsync as the
-- tokens, clear count, daily Clear, level flag and records, and a transform that
-- finds the id already there changes nothing. So a failed write is retried with
-- backoff instead of dropped, and a retry after a lost response (committed, reply
-- lost) cannot pay twice. Whatever is still unsaved when the player leaves rides
-- the finalizer's last write. Limit: the retry state lives in this server only,
-- so a clear that never lands before the session ends (a DataStore outage that
-- outlasts it, a server crash) is lost and logged, never paid later.
local completionSaves = {pending = {}, delays = {0, 2, 5, 10, 20, 40}}

-- True once the profile holds this clear. Only the caller that retires the
-- pending entry announces it, so a retry racing the leave-time flush cannot
-- report or award twice.
function completionSaves.save(player, id)
	local queue = completionSaves.pending[player]
	local entry = queue and queue[id]
	if not entry then return true end
	local ok, _, message = mutateIdempotent(player, entry.Apply, true)
	if not ok then return false end
	if queue[id] ~= entry then return true end
	queue[id] = nil
	pushProfile(player, message, "success")
	entry.OnSaved()
	return true
end

function completionSaves.settle(player, id, apply, onSaved)
	local queue = completionSaves.pending[player] or {}
	completionSaves.pending[player] = queue
	if queue[id] then return end -- the same clear is already being saved
	queue[id] = {Apply = apply, OnSaved = onSaved}
	for attempt, delaySeconds in ipairs(completionSaves.delays) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		local session = sessions[player]
		-- A closing session belongs to the finalizer, which flushes this queue.
		if not session or session.closing or not player.Parent then return end
		if completionSaves.save(player, id) then return end
		if attempt == 1 then
			pushProfile(player, "Your level clear is not saved yet. Retrying automatically.", "error")
		end
	end
	warn("[Zyntra] Completion save still pending after retries; left for the leave-time save:",
		player.UserId, id)
end

function completionSaves.flush(player)
	local queue = completionSaves.pending[player]
	if not queue then return end
	for id in pairs(table.clone(queue)) do
		local saved = false
		for attempt = 1, 3 do
			saved = completionSaves.save(player, id)
			if saved then break end
			if attempt < 3 then task.wait(attempt * 0.5) end
		end
		if not saved then
			warn("[Zyntra] Completion save FAILED at leave; clear not saved for userId", player.UserId, id)
		end
	end
end

levelCompletedEvent.Event:Connect(function(player, level, friendCount, run, roundId)
	if not player or not player:IsA("Player") or not sessions[player] then return end
	-- GameManager fires this once per escapee with the level they just cleared and
	-- how many of that round's OTHER participants are verified friends of theirs
	-- (ServerScriptService.FriendBoost counts them; it is never a client's claim).
	local cleared = math.floor(tonumber(level) or 0)
	local tracked = cleared >= 1 and cleared <= 3
	local base = Config.LevelCompletionTokens
	-- The count is a bounded loop result from FriendBoost, so anything outside a
	-- sane range -- NaN, infinity, a negative -- is a caller bug, and it pays no
	-- boost rather than poisoning a token balance with a non-finite number. The
	-- range test is a sanity bound, NOT a cap on the bonus: the owner asked for
	-- none, and a real party cannot approach it.
	local counted = math.floor(tonumber(friendCount) or 0)
	local friends = (counted >= 0 and counted < 1e6) and counted or 0
	local boostPercent = friends * Config.FriendBoost.PercentPerFriend
	-- One id per escapee per round and level. A caller without a round id still
	-- gets a stable id for its own retries.
	local completionId = (type(roundId) == "string" and #roundId > 0 and #roundId <= 80)
		and roundId .. ":" .. cleared or HttpService:GenerateGUID(false)
	local earnerTier = tokenEarner.tier(player)
	completionSaves.settle(player, completionId, function(data)
		if table.find(data.CompletionIds, completionId) then
			return false, "Level clear saved.", "success"
		end
		local tokensBefore = data.Tokens
		-- FRIEND_BOOST_20260916. The boost is counted in TENTHS of a token and the
		-- remainder rides on the profile, so +10% of a 2-token clear (0.2) builds
		-- up instead of rounding away: one friend pays a whole extra token on the
		-- fifth clear, five friends pay one every clear. This is the ONLY
		-- multiplier on completion tokens -- nothing else touches them.
		local tenths = data.FriendBoostTenths + base * boostPercent / 10
		local bonus = math.floor(tenths / 10)
		data.FriendBoostTenths = tenths % 10
		data.Tokens += base + bonus
		data.CompletedLevels += 1
		rollDaily(data, utcDay())
		if tracked then DailyResearch.Complete(data, "Clear") end
		if tracked then data.LevelsCleared[tostring(cleared)] = true end
		local message = ("+%d Zyntra Research Tokens for completing the level."):format(base + bonus)
		if friends > 0 then
			message = ("+%d Zyntra Research Tokens for completing the level (Friend Boost +%d%%).")
				:format(base + bonus, boostPercent)
		end
		-- CHALLENGES_20260923. The run GameManager measured for THIS escapee, in
		-- this same write: a record, a challenge flag and its tokens land
		-- together or not at all, and a second clear finds the flag already set.
		if tracked then
			for _, note in ipairs(Challenges.Apply(data, cleared, run, Config.Challenges, os.time())) do
				message ..= " " .. note
			end
		end
		-- TOKEN_EARNER_20260924: everything this clear paid -- tokens, daily Clear,
		-- challenges -- is earned, and is multiplied once, here.
		local extra = tokenEarner.bonus(data, data.Tokens - tokensBefore, earnerTier)
		if extra > 0 then
			message ..= (" Token Earner %dx: +%d more."):format(earnerTier, extra)
		end
		table.insert(data.CompletionIds, completionId)
		while #data.CompletionIds > 20 do table.remove(data.CompletionIds, 1) end
		return true, message, "success"
	end, function()
		if not tracked then return end
		-- Badges follow the CONFIRMED write, never precede it: a First Clear badge
		-- on a profile that has no saved clear is exactly the bug this replaced.
		-- awardBadge is non-blocking and contains its own failures.
		awardBadge(player, "FirstClearLevel" .. cleared)
		local session = sessions[player]
		local levelsCleared = session and session.data.LevelsCleared
		if levelsCleared and levelsCleared["1"] and levelsCleared["2"] and levelsCleared["3"] then
			awardBadge(player, "CampaignComplete")
		end
	end)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	-- Donation passes share the ownership latch, but grant no gameplay benefits.
	local passes = table.clone(Config.Passes)
	for key, pass in pairs(Config.Donations or {}) do
		if pass.Kind == "GamePass" then passes[key] = pass end
	end
	for _, skinId in ipairs(Skins.Order) do
		local skin = Skins.ById[skinId]
		if skin.Kind == "Robux" and skin.PassId > 0 then
			passes[skinId] = {Id = skin.PassId, Name = skin.Name, Price = skin.RobuxPrice}
		end
	end
	for key, pass in pairs(Config.TokenEarner.Passes) do passes[key] = pass end
	for key, pass in pairs(passes) do
		if pass.Id > 0 and pass.Id == passId then
			-- Latch the purchase BEFORE refreshing: Roblox has just told us this
			-- player paid, and its own ownership cache may still say otherwise for
			-- seconds. Without the latch a 99 R$ purchase can grant nothing until
			-- the player rejoins.
			local purchases = passPurchases[player]
			if not purchases then
				purchases = {}
				passPurchases[player] = purchases
			end
			purchases[key] = true
			-- Roblox has confirmed this player paid; a pass cannot be bought twice.
			if Analytics then Analytics.Purchase(player, key, "Pass", pass.Price) end
			task.spawn(refreshPasses, player)
			break
		end
	end
end)

local productById = {}
local function registerProductCatalog(catalog, kind)
	for key, product in pairs(catalog or {}) do
		local productId = math.floor(tonumber(product.Id) or 0)
		if productId > 0 and product.Kind ~= "GamePass" then
			assert(not productById[productId],
				string.format("Duplicate Zyntra Developer Product ID %d (%s)", productId, key))
			productById[productId] = { Key = key, Kind = kind, Product = product }
		end
	end
end
registerProductCatalog(Config.Products, "Utility")
registerProductCatalog(Config.Donations, "Donation")

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local entry = productById[receiptInfo.ProductId]
	if not player or not entry or not sessions[player] or not sessions[player].persistent and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = receiptInfo.PurchaseId
	if type(purchaseId) ~= "string" or #purchaseId == 0 or #purchaseId > 128 then
		warn("[Zyntra] Receipt has no valid PurchaseId:", purchaseId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Studio purchases are free test grants, never evidence of paid support.
	-- A live receipt's paid amount is authoritative; catalog prices are not.
	local spent = RunService:IsStudio() and 0 or receiptInfo.CurrencySpent

	local alreadyGranted = false
	local changed = mutate(player, function(data)
		alreadyGranted = false
		for _, id in ipairs(data.ReceiptIds) do
			if id == purchaseId then
				alreadyGranted = true
				return false
			end
		end
		-- Validate before changing any field: a rejected transform adopts its
		-- observed profile locally even though UpdateAsync cancels the write.
		if not isSafeSupportAmount(spent) then
			return false, "Receipt has no valid paid amount.", "error"
		end
		if data.PassRobux > MAX_SAFE_SUPPORT - data.UtilityRobux
			or data.DonationRobux > MAX_SAFE_SUPPORT - data.UtilityRobux - data.PassRobux
			or spent > MAX_SAFE_SUPPORT - recordedSupportRobux(data) then
			return false, "Recorded support total exceeds the safe limit.", "error"
		end
		local grant = entry.Product.TokenGrant or entry.Product.ReentryGrant
		local balance = entry.Product.TokenGrant and data.Tokens or data.ReentryCredits
		if grant and (not isSafeSupportAmount(grant) or not isSafeSupportAmount(balance)
			or grant > MAX_SAFE_SUPPORT - balance) then
			return false, "Purchase balance exceeds the safe limit.", "error"
		end
		-- Validate EVERY bundle balance before touching any profile field. The
		-- reward and receipt marker commit in the same UpdateAsync transaction.
		local bundle = entry.Product.BundleGrant
		local shield
		if bundle then
			shield = protectionState(data)
			local markers = data.Items and data.Items.RouteMarker
			if type(bundle) ~= "table" or not shield
				or not isSafeSupportAmount(bundle.Reentry) or bundle.Reentry < 1
				or not isSafeSupportAmount(bundle.Shield) or bundle.Shield < 1
				or not isSafeSupportAmount(bundle.RouteMarkers) or bundle.RouteMarkers < 1
				or not isSafeSupportAmount(data.ReentryCredits)
				or not isSafeSupportAmount(markers)
				or bundle.Reentry > MAX_SAFE_SUPPORT - data.ReentryCredits
				or bundle.Shield > MAX_SAFE_SUPPORT - shield.Charges
				or bundle.RouteMarkers > MAX_SAFE_SUPPORT - markers then
				return false, "Expedition Pack inventory cannot be updated yet.", "error"
			end
		end
		table.insert(data.ReceiptIds, purchaseId)
		if entry.Kind == "Donation" then
			data.DonationRobux += spent
			return true, string.format("Thank you — %d R$ added to your donation total.", spent), "success"
		end
		data.UtilityRobux += spent
		if bundle then
			data.ReentryCredits += bundle.Reentry
			shield.Charges += bundle.Shield
			data.Items.RouteMarker += bundle.RouteMarkers
			return true, "Expedition Pack stored: 1 re-entry, 1 shield, 3 markers.", "success"
		end
		if entry.Product.TokenGrant then
			data.Tokens += entry.Product.TokenGrant
			return true, "+" .. entry.Product.TokenGrant .. " Zyntra Research Tokens", "success"
		elseif entry.Product.ReentryGrant then
			data.ReentryCredits += entry.Product.ReentryGrant
			return true, "+1 Emergency Re-entry credit", "success"
		end
		return true, "Purchase recorded.", "success"
	end)
	if changed or alreadyGranted then
		if changed and entry.Product.ReentryGrant then
			-- The wipe window is fifteen seconds long. A player who buys a credit
			-- inside it has no time to find the button a second time, so a FRESH
			-- grant spends itself the moment it lands if the buyer is still dead in
			-- a live round. Spawned: the receipt is already committed above and must
			-- be acknowledged now, not after a respawn has finished yielding.
			task.spawn(function()
				if reentryEligible(player) then useReentry(player) end
			end)
		end
		-- The grant is committed and this is its FIRST time: the only moment a
		-- purchase is real. Never when the prompt opens.
		if changed and Analytics then Analytics.Purchase(player, entry.Key, entry.Kind, spent) end
		-- First-time grant only: a Roblox retry of an already-granted PurchaseId
		-- must not alert twice. Notify never yields and never throws; the pcall
		-- is the belt to that braces.
		if changed and PurchaseAlerts then
			pcall(PurchaseAlerts.Notify, {
				PurchaseId = purchaseId,
				ProductId = receiptInfo.ProductId,
				ProductKey = entry.Key,
				ProductName = entry.Product.Name,
				Kind = entry.Kind,
				RobuxSpent = spent,
				PlayerName = player.Name,
				UserId = player.UserId,
				IsStudio = RunService:IsStudio(),
			})
		end
		local session = sessions[player]
		-- The profile mutation is authoritative. Ranking failure must not delay
		-- acknowledgement, and replay also repairs a missing derived-cache write.
		queueSupportTotalSync(player.UserId, recordedSupportRobux(session and session.data))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
local function finalizePlayerSessionBody(player)
	local loadState = profileLoads[player]
	if loadState then
		-- Cancellation is visible before we wait: a not-yet-started load performs no
		-- claim, while an in-flight UpdateAsync finishes before this finalizer closes
		-- any stable claim it may have committed.
		loadState.cancelled = true
		while not loadState.done do task.wait() end
	end
	local session = sessions[player]
	local muteQueue = dispatchMuteQueues[player]
	-- Accessibility switches wait up to ACCESSIBILITY_WRITE_FLOOR for their
	-- coalesced write, and nothing else on this path writes session.data -- the
	-- final save below carries only the dispatch preference. So commit the pending
	-- targets HERE, while the session is still open (mutateIdempotent refuses a
	-- closing one). Without it a player who flipped a second switch and quit
	-- inside the floor lost that change for good.
	local accessibility = accessibilityQueues[player]
	if session and not session.closing and accessibility and accessibility.dirty then
		accessibility.dirty = false
		writeAccessibilityTargets(player, accessibility.desired)
	end
	-- Playtime accrues in memory between flushes, for the same reason and with the
	-- same consequence: bank it HERE, while the session is still open, or the last
	-- minute of every round is lost to whoever leaves from the results screen.
	-- BindToClose reaches this through finalizePlayerSession as well.
	if session and not session.closing then flushPlaytime(player) end
	-- COMPLETION_SAVE_20260924: a clear still retrying gets its last attempts
	-- here, keyed, while the session can still write.
	if session and not session.closing then completionSaves.flush(player) end
	local dispatchPersisted = true
	if muteQueue then
		-- Stop a sleeping worker before it can begin an obsolete write. The last
		-- value accepted from the client remains in acceptedDesired for the final
		-- userId-keyed save below.
		muteQueue.closing = true
		muteQueue.desired = nil
		muteQueue.desiredRevision = nil
		muteQueue.desiredIsReassert = nil
	end
	if session then session.closing = true end

	-- Any mutation that acquired the lock before PlayerRemoving is older than
	-- acceptedDesired and must finish first. New mutations reject closing
	-- sessions, so once this drains the direct setter is the final eligible
	-- writer (a higher input epoch still wins inside UpdateAsync).
	while mutationLocks[player] do task.wait() end
	if session then
		-- Deliberately the BASE floor and not the escalated one: this is the
		-- session's single final write, and BindToClose has 25 seconds to fit
		-- every departing player into.
		local remaining = muteQueue
			and MUTE_WRITE_FLOORS[1] - (os.clock() - muteQueue.lastAttemptFinishedAt) or 0
		if remaining > 0 then task.wait(remaining) end
		dispatchPersisted = persistDispatchTargetOnLeave(player, session, muteQueue)
	end
	if loadState and loadState.claimAttempted and loadState.dispatchSessionId
		and (not session or not session.persistent) then
		-- A load can commit its lease and still lose every response. In that case it
		-- intentionally installed no persistent session, so close the stable claim
		-- by identity after all claim attempts have returned.
		dispatchPersisted = closeAbandonedDispatchLoad(
			player.UserId, loadState.dispatchSessionId) and dispatchPersisted
	end
	if session and session.data then
		queueSupportTotalSync(player.UserId, recordedSupportRobux(session.data))
	end
	return dispatchPersisted
end

local function finalizePlayerSession(player)
	local existing = sessionFinalizers[player]
	if existing then
		while not existing.done do task.wait() end
		return existing.success
	end

	local state = { done = false, success = false }
	sessionFinalizers[player] = state
	activeSessionFinalizers += 1
	local ok, result = pcall(finalizePlayerSessionBody, player)
	state.success = ok and result == true
	state.done = true
	activeSessionFinalizers = math.max(0, activeSessionFinalizers - 1)
	if not ok then
		warn("[Zyntra] Player finalization failed for user", player.UserId, result)
	end

	-- Cleanup is unconditional: a failed callback must not leave a local queue or
	-- mutation lock able to write after this finalizer has declared completion.
	sessions[player] = nil
	mutationLocks[player] = nil
	actionTimes[player] = nil
	protectionAttempts[player] = nil
	protectionResponses[player] = nil
	-- Dropping the token is what stops a refund landing for a reservation whose
	-- player is gone: no session, no second credit.
	reentryAttempts[player] = nil
	playtimeSessions[player] = nil
	potionRoundUsed[player] = nil
	completionSaves.pending[player] = nil
	speedBoostTokens[player] = nil
	dispatchMuteQueues[player] = nil
	briefingClaims[player] = nil
	pendingDispatchSnapshots[player.UserId] = nil
	profileLoads[player] = nil
	return state.success
end

Players.PlayerRemoving:Connect(finalizePlayerSession)

game:BindToClose(function()
	serverClosing = true
	-- PlayerRemoving normally begins these writes first. Explicitly joining every
	-- remaining player here also covers shutdown order differences, and the active
	-- counter keeps BindToClose waiting for handlers whose Player already vanished.
	local players = {}
	local seenPlayers = {}
	for player in pairs(sessions) do
		seenPlayers[player] = true
		players[#players + 1] = player
	end
	for player in pairs(profileLoads) do
		if not seenPlayers[player] then
			seenPlayers[player] = true
			players[#players + 1] = player
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if not seenPlayers[player] then
			seenPlayers[player] = true
			players[#players + 1] = player
		end
	end
	local pendingStarts = #players
	for _, player in ipairs(players) do
		task.spawn(function()
			finalizePlayerSession(player)
			pendingStarts -= 1
		end)
	end
	local deadline = os.clock() + 25
	while (pendingStarts > 0 or activeSessionFinalizers > 0) and os.clock() < deadline do
		task.wait(0.05)
	end
end)

-- SALES_IMPORT_20260915
-- Historical sales import (Trello #36). Roblox's sales export is the only record
-- of what players spent before this build began recording paid amounts, and the
-- only record at all of game pass and private server purchases, which never
-- reach ProcessReceipt. The lead places the generated rows in Studio as
-- ServerStorage.ZyntraSalesBackfill; with that module absent this whole block is
-- a silent no-op, which is the normal state before it is placed and after it is
-- taken away again.
--
-- Each export includes a separately audited per-buyer snapshot. The complete
-- pre-cutoff receipt sets were checked in Creator Dashboard; CSV ids are NOT
-- PurchaseIds. Add (CSV total - audited recorded total) once. Later receipts
-- remain on top, unlike max(current, CSV), which loses old missing purchases
-- whenever newer purchases overlap. Refuse drift below the baseline or missing
-- audited receipts. Pass/private-server rows have their own permanent markers.
local SALES_IMPORT_STREAM_FIELDS = {donation = "DonationRobux", utility = "UtilityRobux", pass = "PassRobux"}
-- How long one server's claim on the import blocks the others. A crash mid-run
-- leaves the claim behind; after this it expires and the next server redoes the
-- whole thing, which is safe because every per-user write is idempotent.
local SALES_IMPORT_CLAIM_SECONDS = 3600
local SALES_IMPORT_BOOT_DELAY = 20
local SALES_IMPORT_USER_DELAY = 0.2

local function salesImportReadback(key, value)
	ServerStorage:SetAttribute("ZyntraSalesImport" .. key, value)
end

local function runSalesImport()
	-- Studio never writes live player data, and a Studio session must not be able
	-- to claim the import away from the servers that can.
	if RunService:IsStudio() then return salesImportReadback("Status", "skipped-studio") end
	local module = ServerStorage:FindFirstChild("ZyntraSalesBackfill")
	if not module or not module:IsA("ModuleScript") then
		return salesImportReadback("Status", "no-module")
	end
	local ok, source = pcall(require, module)
	if not ok or type(source) ~= "table" or type(source.Rows) ~= "table"
		or type(source.Baselines) ~= "table"
		or type(source.SourceKey) ~= "string" or #source.SourceKey == 0
		or #source.SourceKey > 64 then
		warn("[Zyntra] ZyntraSalesBackfill is unusable; no sales import ran:", ok and "bad shape" or source)
		return salesImportReadback("Status", "bad-module")
	end
	local sourceKey = source.SourceKey
	salesImportReadback("Source", sourceKey)
	salesImportReadback("Sha256", tostring(source.Sha256))

	-- Group by buyer first: one atomic write per profile, never one per row.
	local byUser, invalidRows, userCount = {}, 0, 0
	for _, row in ipairs(source.Rows) do
		local userId = type(row) == "table" and math.floor(tonumber(row.UserId) or 0) or 0
		local price = type(row) == "table" and math.floor(tonumber(row.Price) or -1) or -1
		local field = type(row) == "table" and SALES_IMPORT_STREAM_FIELDS[row.Stream] or nil
		local marker = type(row) == "table" and row.Marker or nil
		if userId > 0 and price >= 0 and price <= MAX_SAFE_SUPPORT and field
			and type(marker) == "string" and #marker > 0 and #marker <= 64 then
			local bucket = byUser[userId]
			if not bucket then
				bucket = {}
				byUser[userId] = bucket
				userCount += 1
			end
			bucket[#bucket + 1] = {
				Field = field,
				Price = price,
				Marker = marker,
				CsvId = type(row.CsvId) == "string" and row.CsvId or nil,
			}
		else
			invalidRows += 1
		end
	end
	salesImportReadback("RowsTotal", #source.Rows)
	salesImportReadback("RowsInvalid", invalidRows)
	if invalidRows > 0 or userCount == 0 then return salesImportReadback("Status", "invalid-rows") end

	-- One server does the work. The claim is only a budget guard: it is safe for
	-- two servers to run this concurrently, because every write below is either a
	-- guarded by a permanent source/row marker.
	local claimKey = "salesimport_" .. sourceKey
	local claimed = false
	local okClaim, claimErr = pcall(function()
		store:UpdateAsync(claimKey, function(current)
			claimed = false
			if type(current) == "table" and current.Done == true then return nil end
			local heldFor = math.huge
			if type(current) == "table" then heldFor = os.time() - (tonumber(current.At) or 0) end
			if type(current) == "table" and current.JobId ~= game.JobId
				and heldFor < SALES_IMPORT_CLAIM_SECONDS then return nil end
			claimed = true
			return { JobId = game.JobId, At = os.time(), Sha = source.Sha256, Done = false }
		end)
	end)
	if not okClaim then
		warn("[Zyntra] Sales import could not read its claim:", claimErr)
		return salesImportReadback("Status", "claim-failed")
	end
	if not claimed then return salesImportReadback("Status", "claim-held") end
	salesImportReadback("Status", "running")

	local applied, alreadyCounted, written, failed, idMatches, ambiguous = 0, 0, 0, 0, 0, 0

	-- Runs inside UpdateAsync, so it may be called more than once for one write:
	-- it only ever ASSIGNS into `outcome`, never accumulates, and the caller folds
	-- the outcome into the totals once, after the write has actually landed.
	local function applyRows(data, rows, outcome, userId)
		outcome.Pending, outcome.Applied, outcome.Skipped = false, 0, 0
		outcome.Recorded = recordedSupportRobux(data)
		outcome.Rejected, outcome.Ambiguous, outcome.IdMatches = false, false, 0
		if data.SalesImport.Sources[sourceKey] then
			outcome.Skipped = #rows
			return false
		end
		local baseline = source.Baselines[tostring(userId)]
		local totals, productRows, passAdd = {DonationRobux=0, UtilityRobux=0}, 0, 0
		local markers = data.SalesImport.Rows
		for _, row in ipairs(rows) do
			if row.Field == "PassRobux" then
				if not markers[row.Marker] then passAdd += row.Price end
			else
				productRows += 1
				totals[row.Field] += row.Price
				-- A different source already touched this product row. It needs a
				-- newly audited baseline, never an automatic second correction.
				if markers[row.Marker] then outcome.Rejected = true end
			end
		end
		if type(baseline) ~= "table" or type(baseline.ReceiptIds) ~= "table"
			or #baseline.ReceiptIds ~= productRows then outcome.Rejected = true end
		local receipts, audited = {}, {}
		for _, id in ipairs(data.ReceiptIds) do receipts[id] = true end
		if not outcome.Rejected then
			for _, id in ipairs(baseline.ReceiptIds) do
				if type(id) ~= "string" or audited[id] or not receipts[id] then outcome.Rejected = true end
				audited[id] = true
			end
		end
		local additions, totalAdd = {}, passAdd
		if not outcome.Rejected then
			for field, total in pairs(totals) do
				local before = baseline[field]
				if not isSafeSupportAmount(before) or before > total or data[field] < before then
					outcome.Rejected = true
				else
					additions[field] = total - before
					totalAdd += total - before
				end
			end
		end
		if outcome.Rejected or totalAdd > MAX_SAFE_SUPPORT - outcome.Recorded then
			outcome.Rejected = true
			return false
		end
		-- All validation precedes the first mutation. UpdateAsync retries get a
		-- fresh profile and either add this same delta or see the source marker.
		for field, add in pairs(additions) do data[field] += add end
		data.PassRobux += passAdd
		for _, row in ipairs(rows) do markers[row.Marker] = true end
		data.SalesImport.Sources[sourceKey] = true
		outcome.Applied = #rows
		outcome.Recorded = recordedSupportRobux(data)
		outcome.Pending = true
		return true
	end
	local processed = 0

	for userId, rows in pairs(byUser) do
		if serverClosing then break end
		local outcome = {}
		local player = Players:GetPlayerByUserId(userId)
		local session = player and sessions[player] or nil
		local okWrite
		if player and player.Parent == Players and session and session.persistent and not session.closing then
			-- Online buyer: go through the session's own retrying writer so the
			-- session copy and the published attributes adopt the imported totals
			-- rather than lagging behind the saved profile. Its own failure toast
			-- is suppressed; a silent refresh follows a successful write.
			okWrite = mutateIdempotent(player, function(data)
				return applyRows(data, rows, outcome, userId)
			end, true)
			if okWrite and player.Parent then pushProfile(player) end
		end
		if not okWrite then
			-- Offline, or a session that closed underneath the write above -- a
			-- buyer leaving mid-import must not be what leaves the whole source
			-- unfinished. Safe to follow a write that committed and lost its
			-- response: the markers it left cancel this one.
			okWrite = pcall(function()
				store:UpdateAsync("u_" .. tostring(userId), function(current)
					local data = normalizeProfile(current)
					if not applyRows(data, rows, outcome, userId) then return nil end
					return data
				end)
			end)
		end
		processed += 1
		if okWrite and not outcome.Rejected then
			-- Changed, not merely processed: a re-run reads every profile and
			-- commits none of them, and the readback should say so.
			if outcome.Pending then written += 1 end
			applied += outcome.Applied or 0
			alreadyCounted += outcome.Skipped or 0
			idMatches += outcome.IdMatches or 0
			if outcome.Ambiguous then ambiguous += 1 end
			-- The ordered store is a max, so this is how an OFFLINE buyer reaches
			-- the board without ever logging in -- and a replay repairs an entry
			-- that was lost even when the profile write itself was a no-op.
			local recorded = outcome.Recorded or 0
			if recorded > 0 and not syncSupportTotal(userId, recorded) then failed += 1 end
		else
			failed += 1
		end
		task.wait(SALES_IMPORT_USER_DELAY)
	end

	failed += userCount - processed -- shutdown cannot mark unvisited buyers done
	salesImportReadback("Buyers", userCount)
	salesImportReadback("RowsApplied", applied)
	salesImportReadback("RowsAlreadyCounted", alreadyCounted)
	salesImportReadback("ProfilesChanged", written)
	salesImportReadback("ProfilesFailed", failed)
	salesImportReadback("IdMatches", idMatches)
	salesImportReadback("Ambiguous", ambiguous)
	salesImportReadback("Status", failed == 0 and "done" or "incomplete")
	-- Done only when nothing failed. Otherwise the claim simply expires and the
	-- next server retries; the buyers that already landed cost one cancelled read.
	pcall(function()
		store:UpdateAsync(claimKey, function(current)
			local record = type(current) == "table" and current or {}
			record.Done = failed == 0
			record.At = os.time()
			record.Sha = source.Sha256
			record.Applied = applied
			record.Failed = failed
			return record
		end)
	end)
	print(string.format(
		"[Zyntra] Sales import %s: source %s, %d rows (%d invalid), %d buyers, %d applied, %d already counted, %d profiles changed, %d failed, %d export ids found in ReceiptIds, %d ambiguous profiles",
		failed == 0 and "complete" or "incomplete", sourceKey, #source.Rows, invalidRows,
		userCount, applied, alreadyCounted, written, failed, idMatches, ambiguous))
	refreshSupportLeaderboard()
end

-- SALES_IMPORT_BOOT
task.spawn(function()
	task.wait(SALES_IMPORT_BOOT_DELAY)
	local ok, err = pcall(runSalesImport)
	if not ok then
		warn("[Zyntra] Sales import failed:", err)
		salesImportReadback("Status", "failed")
	end
end)
