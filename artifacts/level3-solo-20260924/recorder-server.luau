-- Server-side event recorder for a Level 3 QA round. Read-only: samples attributes, never writes game state.
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local old = SS:FindFirstChild("ClaudeL3Log")
if old then old:Destroy() end
local log = Instance.new("StringValue")
log.Name = "ClaudeL3Log"
log.Parent = SS
local stop = Instance.new("BoolValue")
stop.Name = "Stop"
stop.Parent = log

local t0 = workspace:GetServerTimeNow()
local lines = {}
local function push(s)
	lines[#lines + 1] = string.format("%7.1f %s", workspace:GetServerTimeNow() - t0, s)
	if #lines > 900 then table.remove(lines, 1) end
	log.Value = table.concat(lines, "\n")
end
push("recorder start t0=" .. string.format("%.2f", t0))

local WS_KEYS = { "SelectedLevel", "LoadStage", "WorldGenerated", "RoundActive", "RoundLoadingState",
	"Level3MallManagerHuntActive", "Level3BlackoutActive", "Level3ExitUnlocked", "Level3FinalHallChaseActive",
	"PostWinIntermissionActive", "EntityPaused" }
local ST_KEYS = { "Level3_Phase", "Level3_ResolvedSeed", "Level3_LayoutHash", "Level3_SeedPinned", "Level3_EntryRoomId",
	"Level3_CDCollectedProgress", "Level3_CDInsertedProgress", "Level3_CDCarriedCount", "Level3_CDDroppedCount",
	"Level3_CD1State", "Level3_CD2State", "Level3_CD3State", "Level3_CD4State", "Level3_CD5State",
	"Level3_CD1Room", "Level3_CD2Room", "Level3_CD3Room", "Level3_CD4Room", "Level3_CD5Room",
	"Level3_RoomSongPhase", "Level3_RoomSongCycle", "Level3_RoomSongStartServerTime", "Level3_MallManagerState",
	"Level3_MallManagerActive", "Level3_MallManagerTargetMode", "Level3_MallManagerTableCheckIndex",
	"Level3_MallManagerAttackSerial", "Level3_MallManagerFinaleSpawn", "Level3_HiddenPlayers", "Level3_ExitUnlocked",
	"Level3_FinalHallCrossedCount", "Level3_FinalHallChaseTriggered", "Level3_FinalHallChaseActive" }
local P_KEYS = { "InRound", "Escaped", "Level3_HeldCDCount", "Level3_Room", "Level3_Hiding", "Level3_HideTableIndex",
	"BeingChased", "ZyntraStaminaMultiplier", "Level2_ExitTransition", "PartyDown" }

local last = {}
local function snap(prefix, inst, keys)
	for _, k in ipairs(keys) do
		local v = inst:GetAttribute(k)
		local id = prefix .. k
		if typeof(v) == "number" and k:find("ServerTime") then v = string.format("%.2f", v) end
		local s = tostring(v)
		if last[id] ~= s then
			last[id] = s
			push(id .. "=" .. s)
		end
	end
end

local minDist, lastHp = math.huge, nil
task.spawn(function()
	while not stop.Value do
		local state = RS:FindFirstChild("Level 3 State")
		snap("ws.", workspace, WS_KEYS)
		if state then snap("st.", state, ST_KEYS) end
		for _, p in ipairs(Players:GetPlayers()) do
			snap("p." .. p.Name .. ".", p, P_KEYS)
			local ch = p.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local hp = hum and math.floor(hum.Health + 0.5) or -1
			if hp ~= lastHp then lastHp = hp; push("p." .. p.Name .. ".Health=" .. hp) end
			-- Manager proximity while it exists
			local world = workspace:FindFirstChild("Level 3 Generated World")
			local rt = world and world:FindFirstChild("Mall Manager Runtime")
			local mgr = rt and rt:FindFirstChild("Mall Manager")
			local mroot = mgr and mgr:FindFirstChild("HumanoidRootPart")
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if mroot and root then
				local d = (mroot.Position - root.Position).Magnitude
				if d < minDist then minDist = d end
				local b = math.floor(d / 10) * 10
				if last.mgrBucket ~= b then last.mgrBucket = b; push(string.format("mgr.dist~%d (min %.1f) mgrSpeed=%s", b, minDist, tostring(state and state:GetAttribute("Level3_MallManagerSpeed")))) end
			elseif last.mgrBucket ~= "none" then
				last.mgrBucket = "none"; push("mgr.absent (min so far " .. string.format("%.1f", minDist) .. ")")
			end
			local st = p:GetAttribute("Stamina")
			if typeof(st) == "number" then
				local b = math.floor(st * 10)
				if last.stam ~= b then last.stam = b; push("p.Stamina~" .. (b / 10)) end
			end
		end
		task.wait(0.2)
	end
	push("recorder stop")
end)
return "recorder running"
