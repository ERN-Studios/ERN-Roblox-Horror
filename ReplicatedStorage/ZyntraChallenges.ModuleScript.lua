-- Pure challenge and personal-record ledger (CHALLENGES_20260923, Trello FnF49TWk).
-- Shared by ZyntraMonetization, which applies a finished run inside the same
-- profile transaction that pays the level clear, and by the terminal's RECORDS
-- page, which only reads. No services, no requires: the settings table is
-- ZyntraConfig.Challenges, passed in, so the offline tests run the real module.
--
-- A run is what GameManager measured for ONE escapee:
--   {Seconds, Deaths, Revived, Aided, Equipped, Solo, DevTouched}
-- Clean    = no Emergency Re-entry and no consumable aid in the run.
-- Records are kept per level x solo/party x clean/assisted, so a time is only
-- ever compared with times set under the same conditions. Equipped marks a
-- record set with a paid permanent upgrade. Both challenges need a clean run,
-- because an Entity Shield or a revive is exactly what "no deaths" measures.
local Challenges = {}

Challenges.Modes = {"solo", "party"}
Challenges.Conditions = {"clean", "assisted"}
Challenges.Kinds = {"NoDeath", "TimeGoal"}
Challenges.MaxSeconds = 86400
local MAX_TOKENS = 9007199254740991

function Challenges.Key(level, mode, condition)
	return tostring(level) .. ":" .. mode .. ":" .. condition
end

local function tenths(seconds)
	return math.floor(seconds * 10 + 0.5) / 10
end

local function validSeconds(value)
	local seconds = tonumber(value)
	return seconds ~= nil and seconds == seconds and seconds > 0 and seconds < Challenges.MaxSeconds
		and seconds or nil
end

-- Rebuilt from the KNOWN key set only, like LevelsCleared: a hand-edited or
-- corrupt save can neither grow the profile nor carry an impossible time.
function Challenges.NormalizeRecords(value, settings)
	local result = {}
	if type(value) ~= "table" then return result end
	for _, level in ipairs(settings.Levels) do
		for _, mode in ipairs(Challenges.Modes) do
			for _, condition in ipairs(Challenges.Conditions) do
				local key = Challenges.Key(level, mode, condition)
				local saved = value[key]
				local best = type(saved) == "table" and validSeconds(saved.Best)
				if best then
					result[key] = {
						Best = tenths(best),
						Equipped = saved.Equipped == true,
						At = math.max(0, math.floor(tonumber(saved.At) or 0)),
					}
				end
			end
		end
	end
	return result
end

function Challenges.NormalizeDone(value, settings)
	local result = {}
	for _, kind in ipairs(Challenges.Kinds) do
		local saved = type(value) == "table" and type(value[kind]) == "table" and value[kind] or {}
		local done = {}
		for _, level in ipairs(settings.Levels) do
			local levelKey = tostring(level)
			if saved[levelKey] == true then done[levelKey] = true end
		end
		result[kind] = done
	end
	return result
end

function Challenges.FormatTime(seconds)
	local whole = math.floor((tonumber(seconds) or 0) + 0.5)
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

local function pay(data, amount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if type(data.Tokens) ~= "number" or data.Tokens ~= data.Tokens or data.Tokens < 0
		or data.Tokens > MAX_TOKENS - amount then
		return 0
	end
	data.Tokens += amount
	return amount
end

-- Applies one finished run to a normalized profile (data.Records,
-- data.Challenges, data.Tokens) and returns the player-facing messages.
-- Called inside the profile transform, so a challenge flag and its reward are
-- written together or not at all, and a second clear finds the flag set.
function Challenges.Apply(data, level, run, settings, now)
	local messages = {}
	local levelKey = tostring(level)
	if not table.find(settings.Levels, tonumber(level)) then return messages end
	if type(run) ~= "table" or run.DevTouched == true then return messages end
	local seconds = validSeconds(run.Seconds)
	if not seconds then return messages end
	seconds = tenths(seconds)
	local clean = run.Revived ~= true and run.Aided ~= true
	local mode = run.Solo == true and "solo" or "party"
	local key = Challenges.Key(levelKey, mode, clean and "clean" or "assisted")
	local previous = data.Records[key]
	if not previous or seconds < previous.Best then
		data.Records[key] = {Best = seconds, Equipped = run.Equipped == true, At = math.floor(tonumber(now) or 0)}
		table.insert(messages, ("New %s record, Level %s: %s%s."):format(
			mode, levelKey, Challenges.FormatTime(seconds), clean and "" or " (assisted)"))
	end
	if not clean then return messages end
	local deaths = math.floor(tonumber(run.Deaths) or 0)
	if deaths == 0 and not data.Challenges.NoDeath[levelKey] then
		data.Challenges.NoDeath[levelKey] = true
		local paid = pay(data, settings.RewardTokens.NoDeath)
		table.insert(messages, ("Challenge complete: Level %s without a death. +%d tokens."):format(levelKey, paid))
	end
	local goal = tonumber(settings.TimeGoalSeconds[levelKey])
	if goal and seconds <= goal and not data.Challenges.TimeGoal[levelKey] then
		data.Challenges.TimeGoal[levelKey] = true
		local paid = pay(data, settings.RewardTokens.TimeGoal)
		table.insert(messages, ("Challenge complete: Level %s under %s. +%d tokens."):format(
			levelKey, Challenges.FormatTime(goal), paid))
	end
	return messages
end

-- One row per level for the RECORDS page, read from a public profile.
function Challenges.Rows(records, done, settings)
	local rows = {}
	records = type(records) == "table" and records or {}
	done = type(done) == "table" and done or {}
	for _, level in ipairs(settings.Levels) do
		local levelKey = tostring(level)
		local row = {
			Level = level,
			TimeGoal = tonumber(settings.TimeGoalSeconds[levelKey]),
			NoDeath = type(done.NoDeath) == "table" and done.NoDeath[levelKey] == true,
			TimeGoalDone = type(done.TimeGoal) == "table" and done.TimeGoal[levelKey] == true,
			Records = {},
		}
		for _, mode in ipairs(Challenges.Modes) do
			for _, condition in ipairs(Challenges.Conditions) do
				row.Records[mode .. ":" .. condition] = records[Challenges.Key(levelKey, mode, condition)]
			end
		end
		table.insert(rows, row)
	end
	return rows
end

return table.freeze(Challenges)
