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
--   a friend counts when Player:IsFriendsWith says so -- server-side, pcall'd
--   -- AND they were a participant of the SAME round on the SAME server.
--
-- Being friends and online elsewhere pays nothing. Being on this server but
-- not in the round pays nothing either: the roster GameManager hands us at
-- completion is that round's own participant list, never Players:GetPlayers().
--
-- ONLY DEFINITIVE ANSWERS ARE CACHED, the same rule and for the same reason as
-- GameManager's queue-station friend check: a throttled or failed IsFriendsWith
-- is indistinguishable here from "not a friend", and caching that would cost a
-- real friend their boost for the rest of the server's life. A failed lookup
-- counts 0 for that pass and is retried on the next one.
--
-- NOTHING HERE READS THE CLIENT. The two published attributes exist for the
-- lobby chip to DRAW; the payout is counted from this cache, so a client that
-- rewrites them lies only to its own screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))

local PERCENT_PER_FRIEND = Config.FriendBoost.PercentPerFriend

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
		return player:IsFriendsWith(other.UserId)
	end)
	if not ok then return nil end
	friendships[key] = isFriend == true
	return friendships[key]
end

local function publish(roster)
	for _, player in ipairs(roster) do
		local count = 0
		for _, other in ipairs(roster) do
			if other ~= player and resolve(player, other) == true then count += 1 end
		end
		-- The roster was snapshotted before the first yield, so someone in it may
		-- have left while the web calls ran. Skip them rather than write to them.
		if player.Parent == Players then
			player:SetAttribute("FriendBoostFriends", count)
			player:SetAttribute("FriendBoostPercent", count * PERCENT_PER_FRIEND)
		end
	end
end

local pending = nil
local publishing = false

-- The roster snapshot is taken SYNCHRONOUSLY here, because PlayerRemoving fires
-- while the leaver is still in Players:GetPlayers() and the pass that follows
-- must not count them. The slow half runs in one background loop: a join during
-- a running pass queues exactly one more pass rather than a second one per event.
local function republish(excluded)
	local roster = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= excluded then roster[#roster + 1] = player end
	end
	pending = roster
	if publishing then return end
	publishing = true
	task.spawn(function()
		while pending do
			local snapshot = pending
			pending = nil
			publish(snapshot)
		end
		publishing = false
	end)
end

function FriendBoost.Start()
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
	local party = table.clone(roster)
	task.spawn(function()
		for i = 1, #party do
			for j = i + 1, #party do
				resolve(party[i], party[j])
			end
		end
	end)
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
