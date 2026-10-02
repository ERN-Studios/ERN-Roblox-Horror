-- Offline execution of exact fresh captured policy helpers; not a Play test.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local ROOT = "artifacts/lobby-end-blockades-20261002/concurrent-access-review/"
local AFTER = "/private/tmp/lobby-endfix-after-20261002/scripts.json"
local BEFORE = "/private/tmp/lobby-endfix-before-20261002/scripts.json"
local rows, before = {}, {}
for _, row in ipairs(serde.decode("json", fs.readFile(AFTER))) do rows[row.path]=row end
for _, row in ipairs(serde.decode("json", fs.readFile(BEFORE))) do before[row.path]=row end
local cases, compilations = {}, {}
local function test(name, run)
	local ok, err = pcall(run)
	table.insert(cases, {name=name, passed=ok, error=if ok then nil else tostring(err)})
end
for path, row in pairs(rows) do
	assert(serde.hash("sha256", row.source) == row.sourceSha256, path)
	assert(row.editorMatch == true and row.editorSourceSha256 == row.sourceSha256, path)
	if not before[path] or before[path].sourceSha256 ~= row.sourceSha256 then
		local ok, err = pcall(luau.compile, row.source)
		table.insert(compilations, {path=path, sha256=row.sourceSha256, passed=ok, error=if ok then nil else tostring(err)})
	end
end
table.sort(compilations, function(a,b) return a.path < b.path end)
local function source(path) return assert(rows[path], path).source end
local function between(s, start, finish)
	local a = assert(string.find(s,start,1,true), start)
	local b = assert(string.find(s,finish,a+1,true), finish)
	return string.sub(s,a,b-1)
end
local function fakePlayer(userId)
	local p = {_player=true, UserId=userId, attributes={}}
	function p:IsA(class) return class=="Player" end
	function p:GetAttribute(name) return self.attributes[name] end
	return p
end
local function fakeTypeof(value)
	return if type(value)=="table" and value._player then "Instance" else typeof(value)
end
local access = luau.load(source("ReplicatedStorage.DevAccess"), {environment={typeof=fakeTypeof}})()
local routing = luau.load(source("ServerScriptService.Round Completion Routing"))()
local gmSource = source("ServerScriptService.GameManager")
local gmPolicy = between(gmSource, "local LEVEL4_PUBLIC = false", "-- Always-on server authority")
	.. "\nreturn {groupIsDevelopers=groupIsDevelopers, devCeiling=devCeiling, canAccessLevel=canAccessLevel}\n"
local gm = luau.load(gmPolicy, {environment={typeof=fakeTypeof, DevAccess=access, Routing=routing}})()
local ordinary, mikkel, laver, zen = fakePlayer(101), fakePlayer(40920547), fakePlayer(9488575949), fakePlayer(11374988579)
test("public campaign ceiling and next-level flow remain 1-3", function()
	assert(routing.MaxLevel==3 and routing.DevMaxLevel==4)
	assert(routing.NextLevel(1)==2 and routing.NextLevel(2)==3)
	assert(routing.NextLevel(3)==nil and routing.NextLevel(4)==nil)
	assert(not routing.OffersContinue(3) and not routing.OffersContinue(4))
end)
test("ordinary users retain campaign levels1-3 and cannot enter levels4-6", function()
	for level=1,3 do assert(gm.canAccessLevel(level,{ordinary})) end
	for level=4,6 do assert(not gm.canAccessLevel(level,{ordinary})) end
end)
test("general developer Level4 ceiling requires every actual party participant", function()
	assert(gm.devCeiling({mikkel,laver})==4 and gm.canAccessLevel(4,{mikkel,laver}))
	assert(gm.devCeiling({mikkel,ordinary})==3 and not gm.canAccessLevel(4,{mikkel,ordinary}))
	assert(gm.devCeiling({})==3 and not gm.canAccessLevel(4,{}))
end)
test("Zen keeps only the previously authorized Level6 preview expansion", function()
	assert(not access.IsAllowed(zen) and access.IsLevel6PreviewAllowed(zen))
	assert(gm.devCeiling({zen})==3 and not gm.canAccessLevel(4,{zen}))
end)
test("campaign admission cannot use developer ceiling to enter Level5 or Level6", function()
	for _, roster in ipairs({{ordinary},{zen},{mikkel},{mikkel,laver}}) do
		for level=5,6 do assert(not gm.canAccessLevel(level,roster)) end
	end
end)
test("bad destination requests cannot gain access", function()
	for _, value in ipairs({0,-1,3.5,0/0,math.huge,-math.huge,"bad"}) do
		assert(not gm.canAccessLevel(value,{mikkel}))
	end
	assert(not gm.canAccessLevel(nil,{mikkel}))
end)
test("transport clamp retains Level4 only with explicit server developer ceiling", function()
	assert(routing.ClampLevel(4)==3)
	assert(routing.ClampLevelTo(4,gm.devCeiling({ordinary}))==3)
	assert(routing.ClampLevelTo(4,gm.devCeiling({mikkel}))==4)
	assert(routing.ClampLevelTo(6,math.huge)==4)
end)
test("exact shared predicates reject spoofed identity data", function()
	for _, bad in ipairs({true,false,"40920547","11374988579",{UserId=40920547},0,-1,0/0,math.huge,101}) do
		assert(not access.IsAllowed(bad) and not access.IsLevel6PreviewAllowed(bad))
	end
	assert(not access.IsAllowed(nil) and not access.IsLevel6PreviewAllowed(nil))
end)
local players, world = {}, {attributes={}}
function world:GetAttribute(name) return self.attributes[name] end
local enum = {HumanoidStateType={Dead="Dead"}}
local function attachHealthy(p)
	p.Parent=players; p.attributes={}
	local root = {Anchored=false}
	local humanoid = {Health=100, RootPart=root, SeatPart=nil}
	function humanoid:GetState() return "Running" end
	local character = {}
	function character:FindFirstChildOfClass(class) return if class=="Humanoid" then humanoid else nil end
	function character:IsDescendantOf(parent) return parent==world end
	p.Character=character
	return humanoid,root
end
local l5src=source("ServerScriptService.Level5PreviewAccess")
local l6src=source("ServerScriptService.Level6PreviewAccess")
local l5=luau.load(between(l5src,"local function readyPlayer(player)","local function upright").."\nreturn readyPlayer",{environment={Players=players,DevAccess=access,workspace=world,Enum=enum}})()
local l6=luau.load(between(l6src,"local function playerReady(player)","local function previewReady()").."\nreturn playerReady",{environment={Players=players,DevAccess=access,workspace=world,Enum=enum}})()
test("exact Level5 readiness helper denies ordinary and Zen, accepts general developers",function()
	for _,p in ipairs({ordinary,zen,mikkel,laver}) do attachHealthy(p) end
	assert(l5(ordinary)==nil and l5(zen)==nil)
	assert(l5(mikkel)==mikkel.Character and l5(laver)==laver.Character)
end)
test("exact Level6 readiness helper denies ordinary, preserves Zen/general developers",function()
	assert(l6(ordinary)==nil)
	for _,p in ipairs({zen,mikkel,laver}) do assert(l6(p)==p.Character) end
end)
test("exact preview readiness helpers reject round, reserved, dead and immobilized state",function()
	for _,helper in ipairs({l5,l6}) do
		local hum,root=attachHealthy(mikkel)
		mikkel.attributes.InRound=true; assert(helper(mikkel)==nil); mikkel.attributes.InRound=nil
		world.attributes.ReservedRoundServer=true; assert(helper(mikkel)==nil); world.attributes.ReservedRoundServer=nil
		hum.Health=0; assert(helper(mikkel)==nil); hum.Health=100
		root.Anchored=true; assert(helper(mikkel)==nil); root.Anchored=false
		hum.SeatPart={}; assert(helper(mikkel)==nil); hum.SeatPart=nil
		mikkel.Parent=nil; assert(helper(mikkel)==nil); mikkel.Parent=players
	end
end)
test("fresh GameManager revised zone and preview launch branches are byte-identical",function()
	local old=before["ServerScriptService.GameManager"].source
	assert(between(old,"local function playerInsideZone","local function rawQueuedPlayers")==between(gmSource,"local function playerInsideZone","local function rawQueuedPlayers"))
	local function launchBranch(s)
		local a=assert(string.find(s,"local function launchStation(station, participants)",1,true))
		local b=assert(string.find(s,"if not canAccessLevel(station.level or 1, participants)",a,true))
		return string.sub(s,a,b-1)
	end
	assert(launchBranch(old)==launchBranch(gmSource))
end)
test("all preexisting Level5/6 server preview authorities remain byte-identical",function()
	for _,path in ipairs({"ReplicatedStorage.DevAccess","ServerScriptService.Level5PreviewAccess","ServerScriptService.Level6PreviewAccess","ServerScriptService.LobbyReimaginedPreview.QueueBridge"}) do
		assert(before[path].source==rows[path].source,path)
	end
end)
local passed=true
for _,row in ipairs(cases) do if not row.passed then passed=false end end
for _,row in ipairs(compilations) do if not row.passed then passed=false end end
local receipt={passed=passed,cases=cases,compilations=compilations,kind="offline_exact_captured_policy_helpers_and_syntax",sourceCapture=AFTER,studioWrites=false,actualGameplayVerified=false,level4GameplayVerified=false,notes="Mock Player/character state. Fresh Source/editor hashes read separately in live Studio. These are not runtime queue or multiplayer tests."}
fs.writeFile(ROOT.."fresh-access-test-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",{passed=passed,cases=#cases,compiled=#compilations},true))
if not passed then error("one or more fresh access checks failed") end
