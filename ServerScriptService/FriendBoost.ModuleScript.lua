-- FriendBoost  (FRIEND_BOOST_20260916, owner brief section 4)
--
-- WHAT "A FRIEND YOU INVITED AND PLAY WITH" MEANS HERE, AND WHY.
--
-- The owner asked for +10% completion tokens per unique Roblox friend the
-- player "invited and plays with", said to reuse the project's own invite or
-- party tracking if it has any, and ruled out inventing a referral system.
--
-- THIS PROJECT HAS NO INVITE TRACKING. Nothing records who sent a game invite:
-- SocialService:PromptGameInvite fires and forgets, Roblox reports no join
-- source into the round, and the queue stations track a party's MEMBERS, not
-- how any of them heard about it. So the criterion is the fallback the brief
-- itself names, stated exactly:
--
--   a friend counts when Player:IsFriendsWithAsync says so -- server-side, pcall'd
--   -- AND they were a participant of the SAME round on the SAME server.
--
-- Being friends and online elsewhere pays nothing. Being on this server but
-- not in the round pays nothing either: the roster GameManager hands us at
-- completion is that round's own participant list, never Players:GetPlayers().
--
-- ONLY DEFINITIVE ANSWERS ARE CACHED, the same rule and for the same reason as
-- GameManager's queue-station friend check: a throttled or failed friendship call
-- is indistinguishable here from "not a friend", and caching that would cost a
-- real friend their boost for the rest of the server's life. A failed lookup
-- counts 0 for that pass and is retried in the background even if nobody joins.
-- Roblox also caches definitive friendship answers; this does not promise an
-- immediate refresh when someone changes their friendship during this session.
--
-- NOTHING HERE READS THE CLIENT. The two published attributes exist for the
-- lobby chip to DRAW; the payout is counted from this cache, so a client that
-- rewrites them lies only to its own screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))

local PERCENT_PER_FRIEND = Config.FriendBoost.PercentPerFriend
local RETRY_SECONDS = 5

local FriendBoost = {}

-- ONE cache for the whole server, keyed by the UNORDERED pair, so A asking
-- about B and B asking about A are the same web call and the same answer.
local friendships = {}

local function pairKey(a, b)
	if a > b then a, b = b, a end
	return a .. ":" .. b
end

-- YIELDS. true/false for a definitive answer, nil when the call itself failed.
local function resolve(player, other)
	local key = pairKey(player.UserId, other.UserId)
	local known = friendships[key]
	if known ~= nil then return known end
	local ok, isFriend = pcall(function()
		return player:IsFriendsWithAsync(other.UserId)
	end)
	if not ok or type(isFriend) ~= "boolean" then return nil end
	friendships[key] = isFriend
	return friendships[key]
end

local pending = nil
local primeQueue = {}
local publishing = false
local retryScheduled = false
local started = false
local revision = 0
local republish

-- Resolve each pair once per worker pass, including failed pairs. A prime or a
-- join arriving while an API call yields shares this worker and its attempts.
local function warmPairs(roster, attempted)
	for i = 1, #roster do
		local player = roster[i]
		if player and player.Parent == Players then
			for j = i + 1, #roster do
				local other = roster[j]
				if other and other.Parent == Players and other.UserId ~= player.UserId then
					local key = pairKey(player.UserId, other.UserId)
					if friendships[key] == nil and not attempted[key] then
						attempted[key] = true
						resolve(player, other)
					end
				end
			end
		end
	end
end

local function hasUnresolved(roster)
	for i = 1, #roster do
		local player = roster[i]
		if player.Parent == Players then
			for j = i + 1, #roster do
				local other = roster[j]
				if other.Parent == Players and other.UserId ~= player.UserId
					and friendships[pairKey(player.UserId, other.UserId)] == nil then
					return true
				end
			end
		end
	end
	return false
end

-- No yields here: commit a complete count only after warming, and abandon a
-- snapshot superseded by a join/leave while its friendship calls were running.
local function publish(snapshot)
	if snapshot.Revision ~= revision then return false end
	local roster = snapshot.Roster
	for _, player in ipairs(roster) do
		local count = 0
		for _, other in ipairs(roster) do
			if other.Parent == Players and other.UserId ~= player.UserId
				and friendships[pairKey(player.UserId, other.UserId)] == true then count += 1 end
		end
		if player.Parent == Players then
			player:SetAttribute("FriendBoostFriends", count)
			player:SetAttribute("FriendBoostPercent", count * PERCENT_PER_FRIEND)
		end
	end
	return true
end

local function runWorker()
	if publishing then return end
	publishing = true
	task.spawn(function()
		local attempted = {}
		local lastPublished = nil
		while pending or #primeQueue > 0 do
			if #primeQueue > 0 then
				warmPairs(table.remove(primeQueue, 1), attempted)
			else
				local snapshot = pending
				pending = nil
				warmPairs(snapshot.Roster, attempted)
				if publish(snapshot) then lastPublished = snapshot.Roster end
			end
		end
		publishing = false
		-- One timer covers all unresolved pairs. It takes a fresh roster when it
		-- fires, so departed players are never retried from an old party snapshot.
		if lastPublished and hasUnresolved(lastPublished) and not retryScheduled then
			retryScheduled = true
			task.delay(RETRY_SECONDS, function()
				retryScheduled = false
				republish()
			end)
		end
	end)
end

-- The roster snapshot is taken SYNCHRONOUSLY here, because PlayerRemoving fires
-- while the leaver is still in Players:GetPlayers() and the pass that follows
-- must not count them. The slow half runs in one background loop: a join during
-- a running pass queues exactly one more pass rather than a second one per event.
republish = function(excluded)
	local roster = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= excluded then roster[#roster + 1] = player end
	end
	revision += 1
	pending = {Roster = roster, Revision = revision}
	runWorker()
end

function FriendBoost.Start()
	if started then return end
	started = true
	Players.PlayerAdded:Connect(function() republish() end)
	Players.PlayerRemoving:Connect(function(player) republish(player) end)
	republish()
end

-- Resolve every pair of a launching party up front, so CountRoundFriends -- which
-- runs inside GameManager's win loop and must not yield there -- has a warm
-- cache by the time the round ends.
function FriendBoost.PrimeRoster(roster)
	if type(roster) ~= "table" then return end
	-- GameManager mutates its own participants table when someone leaves mid-round.
	primeQueue[#primeQueue + 1] = table.clone(roster)
	-- Priming can recover a lookup that previously failed; refresh the lobby's
	-- display attributes from that same warmed cache rather than leaving 0%.
	republish()
end

-- THE PAYOUT COUNT. Reads the cache only: it never yields, never calls the web
-- and never sees anything the client said. An unresolved pair counts 0, which is
-- the safe direction -- a boost can be missed, never invented.
function FriendBoost.CountRoundFriends(player, roster)
	if not player or type(roster) ~= "table" then return 0 end
	local counted, count = {}, 0
	for _, other in ipairs(roster) do
		local userId = other and other.UserId
		-- By UserId, so the player cannot count themselves and one friend listed
		-- twice cannot count twice.
		if userId and userId ~= player.UserId and not counted[userId] then
			counted[userId] = true
			if friendships[pairKey(player.UserId, userId)] == true then count += 1 end
		end
	end
	return count
end

return FriendBoost
