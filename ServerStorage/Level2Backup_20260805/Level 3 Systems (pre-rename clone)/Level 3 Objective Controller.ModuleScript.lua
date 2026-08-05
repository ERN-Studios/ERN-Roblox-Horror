-- Level 3 Objective Controller
--
-- Level 3's own objective, not Level 2's:
--   1. Three PUMP STATIONS are scattered through the complex and can all be
--      reached freely from the arrival.
--   2. Starting a pump DRAINS the flooded corridor next to it — the water is
--      actually removed from the terrain, so the space physically changes and
--      a new route opens up.
--   3. With all three pumps running, the PRESSURE DOORS into the Grand Slide
--      Hall unseal.
--   4. The exit is at the TOP of that hall: climb the spiral stair to the deck
--      and ride the exit flume out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = workspace.Terrain

local ObjectiveController = {}
local activeSession

local RUNNING_COLOR = Color3.fromRGB(150, 232, 176)
local OPEN_COLOR = Color3.fromRGB(180, 218, 196)

local function state()
	return ReplicatedStorage:FindFirstChild("Level 3 State")
end

local function disconnectAll(session)
	for _, connection in ipairs(session.Connections or {}) do
		connection:Disconnect()
	end
	session.Connections = {}
end

local function fireStatus(title, subtitle, instruction)
	local event = ReplicatedStorage:FindFirstChild("Level3AlertEvent")
		or ReplicatedStorage:FindFirstChild("Level2AlertEvent")
	if not event then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") then
			event:FireClient(player, title, subtitle, instruction)
		end
	end
end

-- Level 2 never fires this, so its players only see the result at round end.
-- Level 3 fires it so an escape reads immediately for everyone.
local function fireEscape(player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local status = remotes and remotes:FindFirstChild("RoundStatus")
	if status then
		status:FireAllClients("escape", player.Name)
	end
end

local function validPlayer(player, session)
	return activeSession == session
		and workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and session.Manifest.World.Parent ~= nil
		and session.Manifest.World:GetAttribute("Level3_Generation") == session.Generation
end

local function drain(record)
	if not record or not record.Water or record.Drained then return end
	record.Drained = true
	Terrain:FillBlock(record.Water.CFrame, record.Water.Size, Enum.Material.Air)
end

local function openPressureDoors(session)
	if session.DoorsOpen then return end
	session.DoorsOpen = true
	workspace:SetAttribute("Level3ExitPowered", true)

	local level3State = state()
	if level3State then
		level3State:SetAttribute("Level3_Phase", "EXIT_OPEN")
		level3State:SetAttribute("Level3_LightingMode", "EXIT_OPEN")
	end

	for _, record in ipairs(session.Manifest.PressureDoors) do
		if record.Door and record.Door.Parent then
			record.Door.CanCollide = false
			record.Door.Transparency = .72
			record.Door.Color = OPEN_COLOR
			record.Door.Material = Enum.Material.Neon
		end
		-- The grand hall's approaches drain as the doors release.
		drain(record)
	end

	local exit = session.Manifest.Exit
	if exit and exit.Mouth then
		exit.Mouth.Color = OPEN_COLOR
		exit.Mouth.Transparency = .35
	end

	fireStatus(
		"PRESSURE EQUALIZED",
		"GRAND HALL UNSEALED",
		"CLIMB TO THE TOP DECK AND TAKE THE FLUME OUT"
	)
end

function ObjectiveController.Start(manifest, generation)
	ObjectiveController.Stop()
	local session = {
		Manifest = manifest,
		Generation = generation,
		Connections = {},
		Started = {},
		StartedCount = 0,
		DoorsOpen = false,
	}
	activeSession = session

	local goal = #manifest.Pumps
	workspace:SetAttribute("Level3Pumps", 0)
	workspace:SetAttribute("Level3PumpGoal", goal)
	workspace:SetAttribute("Level3ExitPowered", false)

	for _, pump in ipairs(manifest.Pumps) do
		local connection = pump.Prompt.Triggered:Connect(function(player)
			if not validPlayer(player, session) or session.Started[pump.Index] then return end
			session.Started[pump.Index] = true
			session.StartedCount += 1

			pump.Prompt.Enabled = false
			pump.Lamp.Color = RUNNING_COLOR
			pump.Lever.Color = RUNNING_COLOR
			pump.Lever.CFrame = pump.Lever.CFrame * CFrame.Angles(math.rad(76), 0, 0)
			pump.Model:SetAttribute("Level3_PumpRunning", true)

			workspace:SetAttribute("Level3Pumps", session.StartedCount)
			local level3State = state()
			if level3State then
				level3State:SetAttribute("Level3_PumpProgress", session.StartedCount)
			end

			-- The visible payoff: this pump's corridor empties out.
			local drained = manifest.Drains and manifest.Drains[pump.Index]
			drain(drained)

			fireStatus(
				string.format("PUMP %d ONLINE", pump.Index),
				string.format("%d / %d", session.StartedCount, goal),
				session.StartedCount == goal
					and "PRESSURE DOORS RELEASING"
					or (drained and "A FLOODED SECTION HAS DRAINED" or "FIND THE REMAINING PUMPS")
			)

			if session.StartedCount >= goal then
				openPressureDoors(session)
			end
		end)
		table.insert(session.Connections, connection)
	end

	local escapeConnection = manifest.Exit.Trigger.Touched:Connect(function(hit)
		if activeSession ~= session or not session.DoorsOpen then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or not validPlayer(player, session) then return end
		player:SetAttribute("Escaped", true)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = manifest.Exit.SafeSpawn.CFrame * CFrame.new(0, 3, 0)
		end
		fireEscape(player)
	end)
	table.insert(session.Connections, escapeConnection)

	-- Build() runs before anyone has InRound, so an immediate intro would reach
	-- no one. Fire it once the round actually starts (or shortly after, if the
	-- round was already live when this session started).
	local function fireIntro()
		if activeSession ~= session then return end
		fireStatus(
			"SUNKEN LEISURE COMPLEX",
			string.format("%d PUMP STATIONS OFFLINE", goal),
			"START EVERY PUMP TO DRAIN THE COMPLEX"
		)
	end
	if workspace:GetAttribute("RoundActive") == true then
		task.delay(2, fireIntro)
	else
		local introConnection
		introConnection = workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
			if workspace:GetAttribute("RoundActive") ~= true then return end
			introConnection:Disconnect()
			task.delay(4, fireIntro)
		end)
		table.insert(session.Connections, introConnection)
	end
	return session
end

function ObjectiveController.Stop()
	if not activeSession then return end
	disconnectAll(activeSession)
	activeSession = nil
end

return ObjectiveController
