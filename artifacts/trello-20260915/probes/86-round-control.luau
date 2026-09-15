--!strict
-- Card #86 probe (c) + (d): drive a Level 2 round for the recorder.
--
-- Set ACTION and run. Every action returns well inside the 18 s execute_luau
-- budget; anything long-running is a task.spawn that reports through Probe86.
-- Nothing here edits a script or a configuration module.
--
-- ACTIONS
--   "pinSeed"    pin Level2Seed before the world is built (see PINS below)
--   "pumps"      start the spawn pump pair; the slide appears ~0.5 s after pump 2
--   "invincible" survive the 100-damage attack so a round lasts long enough to
--                measure. Restored by "restore".
--   "still"      invincible + anchor the root: the STILL mode, which is what
--                reproduces the clearance-latch stall (a player who stands
--                still never moves the goal, so nothing releases the wait)
--   "chase"      invincible + release the anchor: the CHASE mode, long routes
--   "quietFoam"  hide the Pool Foam from the measurement without touching its
--                configuration: it keeps running, its models are parented to a
--                holding folder so they cannot reach or kill the tester.
--                "restore" puts them back.
--   "restore"    undo invincible / still / quietFoam
--   "status"     one line of the current state
--
-- SEED PLAN (probe c). Run each as its own round, recorder installed first:
--   1. unpinned      -- whatever the generator gives; the owner's actual case
--   2. 101           -- the seed every stall in the module comments was measured
--                       on (tiled column + lounger pocket, 38 anchors, 12 of
--                       them unoccupiable)
--   3. 303           -- the seed that pushed a valid route past eight seconds of
--                       detour search before the binary heap landed
--   4. 651224003     -- pool-slide-acceptance generation2
--   5. 341095071     -- pool-slide-acceptance generation3
-- Seeds 2-5 come from this project's own recorded measurements, so a stall on
-- them is comparable with what is already written down.

local ACTION = "status"
local PIN = 0 -- used by "pinSeed"; >= 1 pins, 0/absent means random

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local HOLD_NAME = "Probe86FoamHold"

local function tester()
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return player, humanoid, root and root:IsA("BasePart") and root or nil
end

if ACTION == "pinSeed" then
	if PIN >= 1 then workspace:SetAttribute("Level2Seed", PIN)
	else workspace:SetAttribute("Level2Seed", nil) end
	return ("Level2Seed = %s (pin before the launch pad; Level2_SeedPinned reads back)")
		:format(tostring(workspace:GetAttribute("Level2Seed")))

elseif ACTION == "pumps" then
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes", true)
	local dev = remotes and remotes:FindFirstChild("DevControl")
	if not dev then return "Remotes.DevControl not found; fire level2PumpPair from the client" end
	return "fire Remotes.DevControl:FireServer(\"level2PumpPair\", true) from the CLIENT;"
		.. " the server cannot fire its own RemoteEvent. Pumps now: "
		.. tostring(workspace:GetAttribute("Level2Pumps"))

elseif ACTION == "invincible" or ACTION == "still" or ACTION == "chase" then
	local player, humanoid, root = tester()
	if not (player and humanoid and root) then return "no living tester character" end
	-- The slide deals 100 to a 100-max humanoid. Raising the ceiling keeps the
	-- round alive without protecting the player (PlayerProtection would make
	-- livingRecord return nil and stop the chase, which is the thing we measure).
	if humanoid:GetAttribute("Probe86Health") == nil then
		humanoid:SetAttribute("Probe86Health", humanoid.MaxHealth)
	end
	humanoid.MaxHealth = 1e9
	humanoid.Health = 1e9
	if ACTION == "still" then
		root.Anchored = true
	elseif ACTION == "chase" then
		root.Anchored = false
	end
	return ("%s: %s, anchored=%s, at %.0f,%.0f,%.0f")
		:format(ACTION, player.Name, tostring(root.Anchored),
			root.Position.X, root.Position.Y, root.Position.Z)

elseif ACTION == "quietFoam" then
	local hold = ServerStorage:FindFirstChild(HOLD_NAME)
	if not hold then
		hold = Instance.new("Folder")
		hold.Name = HOLD_NAME
		hold.Parent = ServerStorage
	end
	local moved = 0
	local runtime = workspace:FindFirstChild("Level 2 Pool Foam Runtime", true)
	if runtime then
		for _, child in ipairs(runtime:GetChildren()) do
			child:SetAttribute("Probe86Origin", runtime:GetFullName())
			child.Parent = hold
			moved += 1
		end
	end
	return ("parked %d Pool Foam instances in ServerStorage.%s (its controller keeps"
		.. " running; restore before ending the session)"):format(moved, HOLD_NAME)

elseif ACTION == "restore" then
	local notes = {}
	local player, humanoid, root = tester()
	if humanoid and humanoid:GetAttribute("Probe86Health") then
		humanoid.MaxHealth = humanoid:GetAttribute("Probe86Health")
		humanoid.Health = math.min(humanoid.Health, humanoid.MaxHealth)
		humanoid:SetAttribute("Probe86Health", nil)
		table.insert(notes, "health restored")
	end
	if root and root.Anchored then root.Anchored = false; table.insert(notes, "unanchored") end
	local hold = ServerStorage:FindFirstChild(HOLD_NAME)
	if hold then
		local runtime = workspace:FindFirstChild("Level 2 Pool Foam Runtime", true)
		for _, child in ipairs(hold:GetChildren()) do
			if runtime then child.Parent = runtime else child:Destroy() end
		end
		hold:Destroy()
		table.insert(notes, "foam returned")
	end
	workspace:SetAttribute("Level2Seed", nil)
	table.insert(notes, "seed unpinned")
	return #notes > 0 and table.concat(notes, "; ") or "nothing to restore"
end

local folder = workspace:FindFirstChild("Probe86")
return ("level=%s round=%s world=%s seed=%s pinned=%s pumps=%s paused=%s slide=%s"
	.. " recorder=%s samples=%s stalls=%s")
	:format(tostring(workspace:GetAttribute("SelectedLevel")),
		tostring(workspace:GetAttribute("RoundActive")),
		tostring(workspace:GetAttribute("WorldGenerated")),
		tostring(workspace:GetAttribute("Level2Seed")),
		tostring(workspace:GetAttribute("Level2_SeedPinned")),
		tostring(workspace:GetAttribute("Level2Pumps")),
		tostring(workspace:GetAttribute("EntityPaused")),
		tostring(workspace:GetAttribute("Level2_PoolSlideActive")),
		folder and tostring(folder:GetAttribute("Running")) or "absent",
		folder and tostring(folder:GetAttribute("Samples")) or "-",
		folder and tostring(folder:GetAttribute("Stalls")) or "-")
