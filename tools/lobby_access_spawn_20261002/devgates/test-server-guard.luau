-- Executes exact guard Source in a bounded engine mock; not a Studio gameplay claim.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local r = require("@lune/roblox")
local fixture = require("./mock-fixture")
local ROOT = "tools/lobby_access_spawn_20261002/devgates/"
local source = fs.readFile(ROOT .. "DevBayAccessGuard.ModuleScript.candidate.luau")
assert(pcall(luau.compile, source))
local cases = {}
local function test(name, run)
	local ok, problem = pcall(run)
	table.insert(cases, {name = name, passed = ok, error = if ok then nil else tostring(problem)})
	if not ok then warn(name .. ": " .. tostring(problem)) end
end
local function setup(userId, mode)
	local f = fixture(userId, mode)
	local rs = {Heartbeat = f.signal(), IsClient = function() return false end}
	function f.players:GetPlayers() return {f.player} end
	local module = luau.load(source, {environment = {
		game = {GetService = function(_, name)
			return ({Players = f.players, RunService = rs, ReplicatedStorage = {WaitForChild = function() return f.accessModule end}})[name]
		end}, workspace = f.world, typeof = f.envTypeof,
		require = function(instance) assert(instance == f.accessModule); return f.access end,
		CFrame = r.CFrame, Vector3 = r.Vector3,
	}})()
	local model = f.create("Model"); model.Name = "LobbyReimaginedPreview"
	model:SetAttribute("LobbyReimaginedOwned", true); model:SetAttribute("LobbyVisualRevision", 4); model:SetAttribute("Ready", true)
	local pads = f.create("Folder"); pads.Name = "PreviewQueuePads"; pads.Parent = model
	local signs = f.create("Folder"); signs.Name = "LevelGateSigns"; signs.Parent = model
	local gates, floors = {}, {}
	for _, level in ipairs({5, 6}) do
		local side = if level == 5 then -1 else 1
		local yaw = if level == 5 then math.pi / 2 else -math.pi / 2
		local gate = r.CFrame.new(220 + side * 28.6, 30.8, -680) * r.CFrame.Angles(0, yaw, 0)
		gates[level] = gate
		local header = f.create("Part"); header.Name = "LEVEL " .. level .. " Door Header"
		header.CFrame = gate * r.CFrame.new(0, 17.2, 1.42); header:SetAttribute("Level", level); header.Parent = signs
		local bay = f.create("Model"); bay.Name = "QueueBay_Level" .. level; bay:SetAttribute("CircularBayDiameter", 56); bay.Parent = pads
		local floor = f.create("Part"); floor.Name = "ChamberFloor"
		floor.Size = r.Vector3.new(.8, 57.3, 57.3); floor.Position = r.Vector3.new(220 + side * 63, 30.4, -680)
		floor.Anchored = true; floor.CanCollide = true; floor.Parent = bay; floors[level] = floor
	end
	model.Parent = f.world
	local character = f.create("Model"); character.Name = "Character"; character.Parent = f.world; f.player.Character = character
	local humanoid = f.create("Humanoid"); humanoid.Health = 100; humanoid.Parent = character
	local root = f.create("Part"); root.Name = "HumanoidRootPart"; root.Anchored = false; root.Parent = character
	root.CFrame = r.CFrame.new(220, 34, -680); root.Position = root.CFrame.Position; humanoid.RootPart = root
	local ejections = 0
	function character:GetPivot() return root.CFrame end
	function character:PivotTo(cf) ejections += 1; root.CFrame = cf; root.Position = cf.Position end
	local function place(position) root.CFrame = r.CFrame.new(position); root.Position = position end
	return {f = f, module = module, model = model, pads = pads, signs = signs, gates = gates, floors = floors,
		root = root, humanoid = humanoid, character = character, rs = rs, place = place, ejections = function() return ejections end}
end

test("all three narrow preview developers remain inside both actual chamber volumes", function()
	for _, userId in ipairs({40920547, 9488575949, 11374988579}) do
		local s = setup(userId); s.module.Start(s.model)
		for _, level in ipairs({5, 6}) do
			s.place(s.floors[level].Position + r.Vector3.new(0, 3.6, 0)); s.rs.Heartbeat:Fire(.2)
			assert(s.ejections() == 0)
		end
		if userId == 11374988579 then assert(not s.f.access.IsAllowed(s.f.player)) end
	end
end)
test("regular player at either bay center is moved only to its own road-side gate", function()
	local s = setup(1); s.module.Start(s.model)
	for index, level in ipairs({5, 6}) do
		s.place(s.floors[level].Position + r.Vector3.new(0, 3.6, 0)); s.rs.Heartbeat:Fire(.2)
		local target = (s.gates[level] * r.CFrame.new(0, 3, 3.75)).Position
		assert(s.ejections() == index and (s.root.Position - target).Magnitude < 1e-4)
		assert(s.root.AssemblyLinearVelocity == r.Vector3.zero and s.root.AssemblyAngularVelocity == r.Vector3.zero)
	end
	assert(s.model:GetAttribute("DevBayDeniedEntryCount") == 2)
end)
test("both connector apertures reject before the circular chamber", function()
	local s = setup(1); s.module.Start(s.model)
	for index, level in ipairs({5, 6}) do
		s.place((s.gates[level] * r.CFrame.new(0, 3, -1)).Position); s.rs.Heartbeat:Fire(.2)
		assert(s.ejections() == index)
	end
end)
test("road, both sidewalks and door approaches remain untouched", function()
	local s = setup(1); s.module.Start(s.model)
	for _, position in ipairs({r.Vector3.new(220, 34, -680), r.Vector3.new(195, 34, -680), r.Vector3.new(245, 34, -680),
		(s.gates[5] * r.CFrame.new(0, 3, .5)).Position, (s.gates[6] * r.CFrame.new(0, 3, .5)).Position}) do
		s.place(position); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 0)
	end
end)
test("other level rows, old lobby and distant gameplay maps are untouched", function()
	local s = setup(1); s.module.Start(s.model)
	for _, position in ipairs({r.Vector3.new(157, 34, -760), r.Vector3.new(283, 34, -840),
		r.Vector3.new(0, 34, -680), r.Vector3.new(20000, 34, 90), r.Vector3.new(157, 34, -650)}) do
		s.place(position); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 0)
	end
end)
test("finite circular room and narrow doorway volumes do not extend to unrelated void", function()
	local s = setup(1); s.module.Start(s.model)
	for _, position in ipairs({r.Vector3.new(157, 60, -680), r.Vector3.new(157, 20, -680),
		(s.gates[5] * r.CFrame.new(13, 3, -1)).Position, (s.gates[6] * r.CFrame.new(13, 3, -1)).Position}) do
		s.place(position); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 0)
	end
end)
test("stale InRound and anchored-root flags never grant nondeveloper bay access", function()
	local s = setup(1); s.module.Start(s.model); s.f.player:SetAttribute("InRound", true); s.root.Anchored = true
	s.place(s.floors[5].Position + r.Vector3.new(0, 3.6, 0)); s.rs.Heartbeat:Fire(.2)
	assert(s.ejections() == 1 and s.root.Anchored == true and s.f.player:GetAttribute("InRound") == true)
end)
test("erroring preview predicate fails closed", function()
	local s = setup(9488575949, "error"); s.module.Start(s.model)
	s.place(s.floors[6].Position + r.Vector3.new(0, 3.6, 0)); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 1)
end)
test("changed display username never grants access", function()
	local s = setup(1); s.f.player.Name = "LaverSneglen"; s.module.Start(s.model)
	s.place(s.floors[5].Position + r.Vector3.new(0, 3.6, 0)); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 1)
end)
test("dead and detached characters are not repositioned", function()
	local s = setup(1); s.module.Start(s.model); s.place(s.floors[5].Position + r.Vector3.new(0, 3.6, 0))
	s.humanoid.Health = 0; s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 0)
	s.humanoid.Health = 100; s.character.Parent = nil; s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 0)
end)
test("seated user is unseated first so a chair weld is never teleported", function()
	local s = setup(1); s.module.Start(s.model); s.place(s.floors[6].Position + r.Vector3.new(0, 3.6, 0))
	s.humanoid.SeatPart = s.f.create("Seat"); s.humanoid.Sit = true; s.rs.Heartbeat:Fire(.2)
	assert(s.ejections() == 0 and s.humanoid.Sit == false)
	s.humanoid.SeatPart = nil; s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 1)
end)
test("at most one sweep occurs per .2 seconds and no long-frame catch-up loop runs", function()
	local s = setup(1); s.module.Start(s.model); s.place(s.floors[5].Position + r.Vector3.new(0, 3.6, 0))
	s.rs.Heartbeat:Fire(.1); assert(s.ejections() == 0); s.rs.Heartbeat:Fire(.1); assert(s.ejections() == 1)
	s.place(s.floors[5].Position + r.Vector3.new(0, 3.6, 0)); s.rs.Heartbeat:Fire(5); assert(s.ejections() == 2)
	s.place(s.floors[5].Position + r.Vector3.new(0, 3.6, 0)); s.rs.Heartbeat:Fire(.1); assert(s.ejections() == 2)
end)
test("ready pause and reserved round server guard prevent unrelated routing work", function()
	local s = setup(1); s.module.Start(s.model); s.place(s.floors[5].Position + r.Vector3.new(0, 3.6, 0))
	s.model:SetAttribute("Ready", false); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 0)
	s.model:SetAttribute("Ready", true); s.f.world:SetAttribute("ReservedRoundServer", true); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 0)
	s.f.world:SetAttribute("ReservedRoundServer", false); s.rs.Heartbeat:Fire(.2); assert(s.ejections() == 1)
end)
test("repeated Start adds no connections and model removal releases every guard connection", function()
	local s = setup(1); local before = s.f.stats.connections; local state = s.module.Start(s.model)
	assert(s.f.stats.connections == before + 3 and s.module.Start(s.model) == state)
	s.model.Parent = nil; assert(state.stopped and #state.connections == 0 and s.f.stats.connections == before)
	s.model.Parent = s.f.world; local replacement = s.module.Start(s.model); assert(replacement ~= state and not replacement.stopped)
	s.model:Destroy(); assert(replacement.stopped and s.f.stats.connections == before)
end)
test("foreign, unready or wrong-revision model cannot register the guard", function()
	for _, change in ipairs({function(m) m:SetAttribute("LobbyReimaginedOwned", false) end,
		function(m) m:SetAttribute("Ready", false) end, function(m) m:SetAttribute("LobbyVisualRevision", 3) end,
		function(m) m.Name = "ServerLobby" end}) do
		local s = setup(1); change(s.model); assert(not pcall(s.module.Start, s.model))
	end
end)
test("missing, nonphysical or wrongly marked bay geometry fails before guard registration", function()
	for _, change in ipairs({function(s) s.floors[5].Parent = nil end,
		function(s) s.floors[6].CanCollide = false end,
		function(s) s.signs["LEVEL 5 Door Header"]:SetAttribute("Level", 6) end}) do
		local s = setup(1); change(s); local before = s.f.stats.connections
		assert(not pcall(s.module.Start, s.model) and s.f.stats.connections == before)
	end
end)
test("Level5 candidate changes only its two narrow authorization predicates", function()
	local baseline = fs.readFile("artifacts/lobby-access-spawn-20261002/devgate-audit/ServerScriptService__Level5PreviewAccess.live.luau")
	local candidate = fs.readFile(ROOT .. "Level5PreviewAccess.Script.candidate.luau")
	local expected, count = baseline:gsub("DevAccess%.IsAllowed%(player%)", "DevAccess.IsLevel6PreviewAllowed(player)")
	assert(count == 2 and candidate == expected and pcall(luau.compile, candidate))
end)

local passed = true
for _, case in ipairs(cases) do passed = passed and case.passed end
local receipt = {scope = "Offline exact-source compile, mock server bay guard policy/geometry/lifetime and exact Level5 predicate diff. Does not prove actual Studio gameplay or multiplayer.",
	passed = passed, testCount = #cases, cases = cases, candidateBytes = #source, candidateSHA256 = serde.hash("sha256", source)}
fs.writeFile(ROOT .. "server-test-receipt.json", serde.encode("json", receipt, true) .. "\n")
print(serde.encode("json", receipt, true)); assert(passed)
