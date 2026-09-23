-- ZyntraAnalytics
-- Measurement only. Nothing in this module is allowed to change what the game
-- does: every public entry point is a pcall boundary, nothing in it yields, and
-- it neither reads nor writes a DataStore.
--
-- Roblox's AnalyticsService is the entire backend -- funnels and custom events
-- land on the Creator Dashboard and nothing is stored here. Checked against the
-- docs on 2026-09-21, and every one of these facts shapes the code below:
--
--   LogOnboardingFunnelStepEvent(player, step, stepName, customFields)
--   LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields)
--   LogCustomEvent(player, eventName, value, customFields)
--   customFields is keyed by Enum.AnalyticsCustomFieldKeys.CustomField01..03 --
--     THREE slots, no more, so every event below spends them deliberately.
--   Events are accepted from the SERVER of a PUBLISHED place only. Studio and
--     clients are refused outright, which is why the Studio path records instead.
--   A funnel step logged out of order marks every EARLIER step complete, and
--     only the FIRST instance of a step is counted.
--   Only the 10 most recent funnelSessionId values per user per funnel are kept.
--   At most 100 unique custom event names per experience.
--
-- The rate limit is the one number Roblox does not publish (the engine only
-- ever says "You have sent too many events"), so RATE_LIMIT below is ours.
--
-- docs/ANALYTICS_SCHEMA_2026-09-21.md is the schema, the call-site table and
-- the read-out plan. Change one and change the other.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))

local Analytics = {}
local impl = {}

-- ponytail: one sliding window for the whole server, not per player. Roblox
-- does not publish its own AnalyticsService ceiling, so this is a self-imposed
-- one chosen well under anything six players in a round can produce (a full
-- round is roughly 40 events). Per-player buckets only if one player is ever
-- shown to starve the rest.
local RATE_LIMIT = 120
local RATE_WINDOW = 60
local RING_LIMIT = 24
-- LastDeathCause is owned by another script. A field we do not control is the
-- one way cardinality can escape, so a server admits at most this many distinct
-- causes and calls everything after that "other".
local CAUSE_LIMIT = 12

local RETRY_FUNNEL = "ZQRetry"
local ONBOARDING_STEPS = {
	"Joined", "ProfileLoaded", "RoundLoaded", "RoundStarted", "FirstObjective", "FirstEscape",
}

-- Every string this module may ever put in a custom field. A value that is not
-- in here reads "other", which is what keeps cardinality bounded no matter what
-- a caller passes -- including a client-supplied product key.
local ALLOWED = {
	L0 = true, L1 = true, L2 = true, L3 = true,
	new = true, returning = true, unknown = true, continued = true,
	none = true, round = true, objective = true,
	lt60s = true, ["1to3m"] = true, ["3to10m"] = true, ["10m+"] = true,
	escaped = true, died = true, left = true, disconnected = true,
	afterdeath = true, afterclear = true,
	card = true, demo = true,
	Utility = true, Donation = true, Pass = true,
	SpeedPotion = true, RouteMarker = true, EntityShield = true,
	Reentry = true, DetectorScan = true,
	PC = true, Phone = true, Tablet = true, Console = true, Unknown = true,
}
-- The shop's product keys are the catalogue's own keys, so the client can name
-- a product without being trusted to name anything else.
local PRODUCTS = {}
for _, catalog in ipairs({Config.Passes, Config.Products, Config.Donations, Config.Items}) do
	for key in pairs(catalog or {}) do
		PRODUCTS[key] = true
		ALLOWED[key] = true
	end
end

-- Injected by _configure so the offline suite can drive a fake service.
local Service, Keys, now, PLACE_ID, JOB_ID, RESERVED, live
local sessions, window, ring, causes
local logged, dropped, failed, faults, causeCount
local debugFolder

local function remember(record)
	ring[#ring + 1] = record
	if #ring > RING_LIMIT then table.remove(ring, 1) end
	if not debugFolder then return end
	debugFolder:SetAttribute("Logged", logged)
	debugFolder:SetAttribute("Dropped", dropped)
	debugFolder:SetAttribute("Failed", failed)
	debugFolder:SetAttribute("Faults", faults)
	debugFolder:SetAttribute("Last", record)
	debugFolder:SetAttribute("Recent", table.concat(ring, "\n"))
end

local function allow()
	local at = now()
	while window[1] and at - window[1] >= RATE_WINDOW do table.remove(window, 1) end
	if #window >= RATE_LIMIT then
		dropped += 1
		if debugFolder then debugFolder:SetAttribute("Dropped", dropped) end
		return false
	end
	window[#window + 1] = at
	return true
end

-- THE one place anything leaves this module. The record is kept either way, so
-- a Studio probe sees exactly what a published server would have sent.
local function send(record, method, ...)
	if not allow() then return end
	logged += 1
	remember(record)
	if not live then return end
	-- The Log* calls are fire-and-forget and do not yield, but a throw out of
	-- one must never reach a round, a receipt or a DataStore transform.
	if not pcall(Service[method], Service, ...) then failed += 1 end
end

local function value(raw)
	if raw == nil then return "none" end
	return (ALLOWED[raw] or causes[raw]) and raw or "other"
end

local function fields(a, b, c)
	return {[Keys[1]] = value(a), [Keys[2]] = value(b), [Keys[3]] = value(c)}
end

local function levelTag(level)
	local n = math.floor(tonumber(level) or 0)
	return (n >= 1 and n <= 4) and ("L" .. n) or "L0"
end

local function cause(raw)
	if type(raw) ~= "string" then return "unknown" end
	local trimmed = string.lower(string.sub(raw, 1, 24))
	if not string.match(trimmed, "^[a-z0-9_]+$") then return "other" end
	if causes[trimmed] then return trimmed end
	if causeCount >= CAUSE_LIMIT then return "other" end
	causeCount += 1
	causes[trimmed] = true
	return trimmed
end

-- Nothing server-side publishes a device class today, so this reads "Unknown"
-- everywhere and Roblox's own OS breakdown is the interim segmentation. The
-- day a client publishes ZyntraDeviceClass this starts answering, and a client
-- that lies can only pick another name from the fixed enum.
local DEVICE = {PC = true, Phone = true, Tablet = true, Console = true}
local function platform(player)
	local claimed = player:GetAttribute("ZyntraDeviceClass")
	return DEVICE[claimed] and claimed or "Unknown"
end

-- A round runs on a RESERVED server of this same place, so one play session is
-- several server joins: lobby -> reserved round -> lobby. GetJoinData is
-- server-trusted and SourcePlaceId is this place for every one of our own
-- teleports (the station launch packet out, ReturnToLobby home), so an arrival
-- from ourselves is the SAME session continuing, never a fresh join.
local function arrival(player)
	if RESERVED then return true end
	local ok, joinData = pcall(player.GetJoinData, player)
	return ok and type(joinData) == "table" and joinData.SourcePlaceId == PLACE_ID
end

local function session(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return nil
	end
	local state = sessions[player]
	if not state then
		state = {
			StartedAt = now(), Continued = arrival(player), Origin = "unknown",
			Reached = "none", Step = 0, Deaths = 0, Loops = 0, Rounds = 0,
			RoundAt = nil, LobbyAt = nil, Level = 0,
		}
		sessions[player] = state
	end
	return state
end

-- The onboarding funnel is Roblox's own once-per-user funnel: it takes the
-- FIRST instance of each step for that user's lifetime, which is exactly the
-- semantics we want and the reason this needs no DataStore field of its own.
-- All we owe it is never going backwards, which the per-server furthest-step
-- latch below guarantees. A forward JUMP is left alone on purpose: a reserved
-- round server never saw steps 1-2, the player did them, and Roblox completing
-- them from step 3 is the correct answer.
local function onboard(state, player, step, level)
	if step <= state.Step then return end
	state.Step = step
	local name = ONBOARDING_STEPS[step]
	send(string.format("onboard %d %s %s user=%d", step, name, levelTag(level), player.UserId),
		"LogOnboardingFunnelStepEvent", player, step, name,
		fields(levelTag(level), state.Origin, platform(player)))
end

local function custom(player, state, name, amount, a, b, c)
	send(string.format("%s %s %s|%s|%s user=%d", name, tostring(amount),
		tostring(value(a)), tostring(value(b)), tostring(value(c)), player.UserId),
		"LogCustomEvent", player, name, amount, fields(a, b, c))
end

-- A player's round has ended and they are back where another one can be
-- started. Only a server that can also observe the NEXT launch may open this,
-- or every reserved round server would log a funnel session nobody can ever
-- finish and the dashboard would read 100% drop-off.
local function openRetryLoop(state, player)
	if RESERVED then return end
	-- ONBOARD_ORDER_20260922: idempotent. A second Join for the same player
	-- (GameManager re-running its arrival hook) must not open a second funnel
	-- session while the first is still waiting for a launch.
	if state.LobbyAt and (state.RoundAt == nil or state.RoundAt < state.LobbyAt) then return end
	state.Loops += 1
	state.LobbyAt = now()
	send(string.format("retry 1 BackInLobby user=%d", player.UserId),
		"LogFunnelStepEvent", player, RETRY_FUNNEL,
		string.format("%s:%d:%d", JOB_ID, player.UserId, state.Loops),
		1, "BackInLobby", fields("L0", state.Origin, platform(player)))
end

-- A player arriving in the lobby, whether that is a first join or the walk back
-- from a finished round. Only the walk back opens the retry funnel.
function impl.Join(player)
	local state = session(player)
	if not state then return end
	onboard(state, player, 1, 0)
	if state.Continued then openRetryLoop(state, player) end
end

function impl.ProfileLoaded(player, isNew)
	local state = session(player)
	if not state then return end
	state.Origin = isNew == true and "new" or (isNew == false and "returning" or "unknown")
	if debugFolder then debugFolder:SetAttribute("Mode", live and "live" or "studio") end
	-- ONBOARD_ORDER_20260922: the funnel contract is 1 Joined, then 2
	-- ProfileLoaded, in that order. Whether GameManager's arrival hook or the
	-- DataStore answers first is a race (in Studio the profile wins), so step 1
	-- is logged here if it has not been yet; the later Join then finds its step
	-- taken and only does its own work (the retry loop).
	onboard(state, player, 1, 0)
	onboard(state, player, 2, 0)
end

-- The client's entryready, AFTER the loading runtime accepted it. Never on the
-- client's word alone -- the accept is the authoritative event.
function impl.Ready(player, level)
	local state = session(player)
	if not state then return end
	onboard(state, player, 3, level)
end

function impl.RoundStart(player, level)
	local state = session(player)
	if not state then return end
	state.RoundAt = now()
	state.Level = level
	state.Rounds += 1
	state.Reached = state.Reached == "objective" and "objective" or "round"
	onboard(state, player, 4, level)
	custom(player, state, "zq_round_start", 1, levelTag(level), state.Origin, platform(player))
end

-- One server-validated objective mutation, attributed to the ACTOR only. Every
-- later one is silent: this measures whether a player ever got that far.
function impl.Objective(player, level)
	local state = session(player)
	if not state then return end
	state.Reached = "objective"
	if state.Step >= 5 then return end
	onboard(state, player, 5, level)
	custom(player, state, "zq_objective_first",
		math.max(0, now() - (state.RoundAt or now())),
		levelTag(level), state.Origin, platform(player))
end

-- A death is its own branch, never a step of the linear funnel: it can happen
-- before any objective, and a clear can happen without any death.
-- `causeKey` is what GameManager just took from DeathAdvice; Take CONSUMES the
-- player attribute, so reading it here afterwards would always say unknown.
function impl.Death(player, level, causeKey)
	local state = session(player)
	if not state then return end
	state.Deaths += 1
	if state.Deaths > 1 then return end
	custom(player, state, "zq_first_death",
		math.max(0, now() - (state.RoundAt or now())),
		levelTag(level), cause(causeKey or player:GetAttribute("LastDeathCause")), state.Origin)
end

-- escaped / died / left / disconnected, once per player per round. A nil
-- outcome reads the authoritative Escaped attribute rather than guessing.
function impl.Outcome(player, level, outcome)
	local state = session(player)
	if not state or not state.RoundAt then return end
	local elapsed = math.max(0, now() - state.RoundAt)
	state.RoundAt = nil
	if outcome == nil then
		outcome = player:GetAttribute("Escaped") == true and "escaped" or "died"
	end
	custom(player, state, "zq_round_outcome", elapsed, levelTag(level), outcome, state.Origin)
	if outcome == "escaped" then onboard(state, player, 6, level) end
	-- Studio and the local-lobby fallback run the round on this same server, so
	-- this is where the retry loop opens there. A published round is on a
	-- reserved server and openRetryLoop stands down; its lobby opens it instead.
	openRetryLoop(state, player)
end

-- A station launch that Roblox accepted: this party has started another ROUND,
-- which is what separates a retry from an Emergency Re-entry inside a round
-- (re-entry never reaches RoundStart, so it can never look like an attempt).
-- Step 2 only fires for a player who came back from a round in the first place.
--
-- Whether that round ended in a death is only knowable when the SAME server ran
-- it, which is Studio and the local-lobby fallback; a published round runs on a
-- reserved server, so state.Rounds is 0 here and the field reads "unknown".
function impl.Launch(player, level)
	local state = session(player)
	if not state then return end
	state.Reached = state.Reached == "objective" and "objective" or "round"
	if not state.LobbyAt then return end
	local waited = math.max(0, now() - state.LobbyAt)
	state.LobbyAt = nil
	local after = "unknown"
	if state.Deaths > 0 then
		after = "afterdeath"
	elseif state.Rounds > 0 then
		after = "afterclear"
	end
	send(string.format("retry 2 StartedAgain %s user=%d", after, player.UserId),
		"LogFunnelStepEvent", player, RETRY_FUNNEL,
		string.format("%s:%d:%d", JOB_ID, player.UserId, state.Loops),
		2, "StartedAgain", fields(levelTag(level), after, platform(player)))
	custom(player, state, "zq_round_relaunch", waited, levelTag(level), after, state.Origin)
end

local function bucket(seconds)
	if seconds < 60 then return "lt60s" end
	if seconds < 180 then return "1to3m" end
	if seconds < 600 then return "3to10m" end
	return "10m+"
end

-- The session exit. A player who disconnects mid-round settles that round here
-- first, because no other hook will ever run for them again.
function impl.Leave(player)
	local state = sessions[player]
	if not state then return end
	sessions[player] = nil
	if state.RoundAt and player:GetAttribute("InRound") == true then
		local elapsed = math.max(0, now() - state.RoundAt)
		state.RoundAt = nil
		custom(player, state, "zq_round_outcome", elapsed,
			levelTag(state.Level), "disconnected", state.Origin)
	end
	local seconds = math.max(0, now() - state.StartedAt)
	custom(player, state, "zq_session_end", seconds, bucket(seconds), state.Reached,
		state.Continued and "continued" or state.Origin)
end

-- The client opened a product card, or started a free demo. This is the only
-- thing in here a client reports, it grants nothing, and an unknown key is
-- dropped rather than logged as "other" -- a made-up key is not a measurement.
function impl.ShopView(player, key, isDemo)
	local state = session(player)
	if not state or not PRODUCTS[key] then return end
	custom(player, state, "zq_shop_view", 1, key, isDemo == true and "demo" or "card", state.Origin)
end

-- Only ever after the authoritative grant is committed: a first-time receipt or
-- a first verified game-pass grant. Never when a prompt opens.
function impl.Purchase(player, key, kind, robux)
	local state = session(player)
	if not state then return end
	custom(player, state, "zq_shop_purchase", math.max(0, math.floor(tonumber(robux) or 0)),
		key, kind, state.Origin)
end

function impl.ItemUse(player, item, level)
	local state = session(player)
	if not state then return end
	custom(player, state, "zq_item_use", 1, item, levelTag(level or state.Level), state.Origin)
end

function impl.Snapshot()
	return {
		Mode = live and "live" or "studio",
		Logged = logged, Dropped = dropped, Failed = failed, Faults = faults,
		Recent = table.clone(ring),
	}
end

-- Test seam and state reset. Production calls this once, argument-less, below.
function Analytics._configure(deps)
	deps = deps or {}
	Service = deps.AnalyticsService or game:GetService("AnalyticsService")
	Keys = deps.Keys or {
		Enum.AnalyticsCustomFieldKeys.CustomField01,
		Enum.AnalyticsCustomFieldKeys.CustomField02,
		Enum.AnalyticsCustomFieldKeys.CustomField03,
	}
	now = deps.now or os.time
	PLACE_ID = deps.placeId or game.PlaceId
	JOB_ID = deps.jobId or game.JobId
	RESERVED = deps.reserved
	if RESERVED == nil then
		RESERVED = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	end
	-- Studio and an unpublished place both reject every event, so neither is
	-- asked. The ring is still filled, which is the only way to see this module
	-- working before a release exists to see it on the dashboard.
	if deps.live ~= nil then
		live = deps.live
	else
		live = not RunService:IsStudio() and PLACE_ID > 0
	end
	sessions = setmetatable({}, {__mode = "k"})
	window, ring, causes = {}, {}, {}
	logged, dropped, failed, faults, causeCount = 0, 0, 0, 0, 0
	debugFolder = deps.folder
	if debugFolder == nil and deps.folder ~= false then
		debugFolder = ServerStorage:FindFirstChild("ZyntraAnalyticsDebug")
		if not debugFolder then
			debugFolder = Instance.new("Folder")
			debugFolder.Name = "ZyntraAnalyticsDebug"
			debugFolder.Parent = ServerStorage
		end
	end
	if debugFolder then
		debugFolder:SetAttribute("Mode", live and "live" or "studio")
		debugFolder:SetAttribute("Logged", 0)
		debugFolder:SetAttribute("Dropped", 0)
		debugFolder:SetAttribute("Failed", 0)
		debugFolder:SetAttribute("Faults", 0)
		debugFolder:SetAttribute("Last", "")
		debugFolder:SetAttribute("Recent", "")
	end
end

-- Every public name is the pcall boundary. This module measures; a measurement
-- that throws must never reach the flow that reported it, and nothing below
-- yields, so no caller is ever held up either.
for name, body in pairs(impl) do
	Analytics[name] = function(...)
		local ok, result = pcall(body, ...)
		if ok then return result end
		faults += 1
		if debugFolder then debugFolder:SetAttribute("Faults", faults) end
		return nil
	end
end

Analytics._configure()

return Analytics
