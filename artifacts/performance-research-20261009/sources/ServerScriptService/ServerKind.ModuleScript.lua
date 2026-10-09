-- SERVER_KIND_20261008. What kind of server this is, decided once and asked by everything that needs to know.
--
--   public lobby       PrivateServerId == ""                    the game's front door
--   round server       a reserved server                        one party's Level 1-4 round (GameManager)
--   live-level lobby   a reserved server REGISTERED here first  one party's own lobby, started so that Level 5 or
--                                                               6 runs for that party alone; a lobby in every
--                                                               other respect
--
-- Owner, 2026-10-08: Levels 5 and 6 are to get a server per party, "whatever is the case for Levels 1, 2 and 3".
-- Those two levels run on a lobby server (one map, one game per server), so a party gets a lobby server of its
-- own: the lobby it left reserves a server, registers that server's PrivateServerId in MemoryStore (Register) and
-- teleports the party there with what level they asked for. The new server reads its own id here before anything
-- else decides what it is. The module body yields for that one read, on reserved servers only, so every requirer
-- gets the settled answer; a public server never touches MemoryStore. A read that fails three times leaves the
-- server a round server, which is what every reserved server was before this module existed.
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local MAP_NAME = "LiveLevelServersV1"
local KEEP_SECONDS = 900           -- a registration outlives the teleport it was made for by a wide margin

local ServerKind = {}

-- Who gets a server per party for Levels 5 and 6.
--   "developers"  only a party whose every member passes DevAccess.IsLevel6PreviewAllowed (the owner's accounts
--                 and the developers), so the path can be proved on the live game before the public is on it.
--                 Every other party keeps the one-party-at-a-time lock on the lobby server (PARTY_LOCK_20261008).
--   "everyone"    every party.
--   "off"         nobody: both levels run on the lobby server for all, as before 2026-10-08.
-- It cannot be tested in Studio (no reserved servers, no teleports), which is why it started on "developers".
-- "everyone" since 2026-10-08, on the owner's word ("own servers from now on ... same setup as the other levels"):
-- it went public without a live run by a developer party first. Where Roblox refuses the reservation the party
-- still enters on the lobby server behind the one-party lock, as before; "off" is the way back.
ServerKind.OwnServers = "everyone"

local reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local live = nil                   -- {Level = 5 | 6, Session = string} on a live-level lobby

local function map()
	return MemoryStoreService:GetHashMap(MAP_NAME)
end

if reserved then
	local answered = false
	for attempt = 1, 3 do
		local ok, value = pcall(function() return map():GetAsync(game.PrivateServerId) end)
		if ok then
			answered = true
			if type(value) == "table" and (value.Level == 5 or value.Level == 6) then live = value end
			break
		end
		warn("[ServerKind] could not read this server's registration (try " .. attempt .. "): " .. tostring(value))
		task.wait(0.35 * attempt)
	end
	if not answered then
		-- MemoryStore did not answer at all. A reserved server only starts because somebody is on the way to it,
		-- and what they were sent for is in their teleport data, which only a server of this game can have written.
		local deadline = os.clock() + 20
		while #Players:GetPlayers() == 0 and os.clock() < deadline do task.wait(0.1) end
		local first = Players:GetPlayers()[1]
		local ok, data = pcall(function() return first and first:GetJoinData() end)
		local packet = ok and type(data) == "table" and data.TeleportData
		if type(packet) == "table" and (packet.LiveLevel == 5 or packet.LiveLevel == 6) then
			live = {Level = packet.LiveLevel, Session = tostring(packet.LiveSession or "none"), FromPacket = true}
		end
		warn("[ServerKind] decided from the first arrival's teleport data: " .. (live and ("Level " .. live.Level) or "a round server"))
	end
elseif RunService:IsStudio() then
	-- Studio is never a reserved server. A workspace attribute stands one in for a play test.
	local simulated = workspace:GetAttribute("DevLiveLevelServer")
	if simulated == 5 or simulated == 6 then live = {Level = simulated, Session = "studio", Simulated = true} end
end

function ServerKind.IsReserved(): boolean
	return reserved
end

-- True on a server that exists for one GameManager round. This is the question every old
-- `PrivateServerId ~= "" and PrivateServerOwnerId == 0` test was really asking.
function ServerKind.IsRoundServer(): boolean
	return reserved and live == nil
end

function ServerKind.LiveLevel(): number?
	return live and live.Level or nil
end

function ServerKind.Info()
	return live
end

-- Called by the lobby that reserved the server, BEFORE it teleports anybody there. Yields.
function ServerKind.Register(privateServerId: string, level: number, session: string): (boolean, any)
	if type(privateServerId) ~= "string" or privateServerId == "" or (level ~= 5 and level ~= 6) then
		return false, "BAD_REGISTRATION"
	end
	return pcall(function()
		map():SetAsync(privateServerId, {Level = level, Session = tostring(session)}, KEEP_SECONDS)
	end)
end

-- May these players have a server of their own for a live level? Never from Studio, and never from a server
-- that already IS a party's own: there the level is entered on the spot.
function ServerKind.OwnServerFor(players): boolean
	if RunService:IsStudio() or live ~= nil or ServerKind.OwnServers == "off" then return false end
	if type(players) ~= "table" or #players == 0 then return false end
	if ServerKind.OwnServers == "everyone" then return true end
	local found, DevAccess = pcall(function() return require(ReplicatedStorage:WaitForChild("DevAccess", 5)) end)
	if not found or type(DevAccess) ~= "table" or type(DevAccess.IsLevel6PreviewAllowed) ~= "function" then return false end
	for _, player in ipairs(players) do
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not DevAccess.IsLevel6PreviewAllowed(player) then
			return false
		end
	end
	return true
end

-- Reserve a server for `players` and register it as their own lobby for `level`. Returns the access code to
-- teleport them with, or nil when they are to go in on this server instead (not allowed one, Roblox or
-- MemoryStore refused, or it took longer than `patience` seconds). Yields.
function ServerKind.Reserve(level: number, players, session: string, patience: number?): string?
	if (level ~= 5 and level ~= 6) or not ServerKind.OwnServerFor(players) then return nil end
	local done, code = false, nil
	task.spawn(function()
		local ok, access, privateId = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
		if ok and type(access) == "string" and access ~= "" and type(privateId) == "string" and privateId ~= "" then
			local registered, problem = ServerKind.Register(privateId, level, session)
			if registered then
				code = access
			else
				warn("[ServerKind] could not register a Level " .. level .. " server: " .. tostring(problem))
			end
		else
			warn("[ServerKind] could not reserve a Level " .. level .. " server: " .. tostring(access))
		end
		done = true
	end)
	local deadline = os.clock() + (patience or 6)
	while not done and os.clock() < deadline do task.wait(0.05) end
	if not done then warn("[ServerKind] reserving a Level " .. level .. " server took too long; entering on this server") end
	return if done then code else nil
end

-- Replicated, so a client can tell this lobby is only a way into a level.
workspace:SetAttribute("LiveLevelServer", ServerKind.LiveLevel())

return ServerKind
