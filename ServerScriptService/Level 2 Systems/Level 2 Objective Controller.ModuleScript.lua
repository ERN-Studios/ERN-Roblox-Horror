local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObjectiveController = {}
local activeSession

local function disconnectAll(session)
	for _, connection in ipairs(session.Connections or {}) do
		connection:Disconnect()
	end
	session.Connections = {}
end

local function fireSound(cue, player)
	local event = ReplicatedStorage:FindFirstChild("Level 2 Sound Event")
	if not event then return end
	if player then event:FireClient(player, cue) else event:FireAllClients(cue) end
end

local function fireStatus(title, subtitle, instruction)
	local event = ReplicatedStorage:FindFirstChild("Level2AlertEvent")
	if not event then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") then
			event:FireClient(player, title, subtitle, instruction)
		end
	end
end

local function validPlayer(player, session)
	return activeSession == session
		and workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and session.Manifest.World.Parent ~= nil
		and session.Manifest.World:GetAttribute("Level2_Generation") == session.Generation
end

local function unlockExit(session)
	if session.ExitOpen then return end
	session.ExitOpen = true
	workspace:SetAttribute("Level2ExitPowered", true)
	workspace:SetAttribute("ValveColorWashUntil", 0)
	workspace:SetAttribute("ValveBlackoutActive", false)
	local state = ReplicatedStorage:FindFirstChild("Level 2 State")
	if state then
		state:SetAttribute("Level2_Phase", "EXIT_OPEN")
		state:SetAttribute("Level2_LightingMode", "EXIT_OPEN")
	end
	local exit = session.Manifest.Exit
	exit.Gate.CanCollide = false
	exit.Gate.Transparency = .74
	exit.Gate.Color = Color3.fromRGB(180, 218, 196)
	exit.GateLight.Color = Color3.fromRGB(194, 224, 205)
	exit.GateLight.Material = Enum.Material.Neon
	fireSound("Level 2 Exit Unlock")
	fireStatus("PRESSURE STABILIZED", "EXIT TUBE UNSEALED", "FOLLOW THE STEADY GREEN LIGHT")
end

function ObjectiveController.Start(manifest, generation)
	ObjectiveController.Stop()
	local session = {
		Manifest = manifest,
		Generation = generation,
		Connections = {},
		Activated = {},
		ActivatedCount = 0,
		ExitOpen = false,
	}
	activeSession = session
	workspace:SetAttribute("Level2Valves", 0)
	workspace:SetAttribute("Level2ValveGoal", #manifest.Valves)
	workspace:SetAttribute("Level2ExitPowered", false)

	for _, valve in ipairs(manifest.Valves) do
		local connection = valve.Prompt.Triggered:Connect(function(player)
			if not validPlayer(player, session) or session.Activated[valve.Index] then return end
			session.Activated[valve.Index] = true
			session.ActivatedCount += 1
			valve.Prompt.Enabled = false
			valve.Model:SetAttribute("Level2_ValveActivated", true)
			valve.Wheel.Material = Enum.Material.Neon
			valve.Wheel.Color = Color3.fromRGB(190, 220, 202)
			workspace:SetAttribute("Level2Valves", session.ActivatedCount)
			local state = ReplicatedStorage:FindFirstChild("Level 2 State")
			if state then state:SetAttribute("Level2_ValveProgress", session.ActivatedCount) end
			fireSound("Level 2 Valve Turn", player)
			fireStatus(
				string.format("PRESSURE VALVE %d OPEN", valve.Index),
				string.format("%d / %d", session.ActivatedCount, #manifest.Valves),
				session.ActivatedCount == #manifest.Valves and "EXIT PRESSURE RELEASED" or "FIND THE REMAINING VALVES"
			)
			if session.ActivatedCount >= #manifest.Valves then unlockExit(session) end
		end)
		table.insert(session.Connections, connection)
	end

	local escapeConnection = manifest.Exit.Trigger.Touched:Connect(function(hit)
		if activeSession ~= session or not session.ExitOpen then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or not validPlayer(player, session) then return end
		player:SetAttribute("Escaped", true)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = manifest.Exit.SafeSpawn.CFrame * CFrame.new(0, 3, 0)
		end
		fireSound("Level 2 Slide Rush", player)
	end)
	table.insert(session.Connections, escapeConnection)
	return session
end

function ObjectiveController.Stop()
	if not activeSession then return end
	disconnectAll(activeSession)
	activeSession = nil
end

return ObjectiveController
