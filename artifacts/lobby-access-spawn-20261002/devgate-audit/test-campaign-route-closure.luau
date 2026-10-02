-- Source-derived offline policy check; no Studio mutation or gameplay claim.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local ROOT = "artifacts/lobby-access-spawn-20261002/devgate-audit/"
local gm = fs.readFile(ROOT .. "GameManager.post-install.server.luau")
local routingSource = fs.readFile(ROOT .. "RoundCompletionRouting.post-install.server.luau")
local accessSource = fs.readFile(ROOT .. "ReplicatedStorage__DevAccess.post-install.server.luau")
local function subject(uid)
	return {UserId = uid, _instance = true, IsA = function(_, class) return class == "Player" end}
end
local envTypeof = function(value)
	return if type(value) == "table" and value._instance == true then "Instance" else typeof(value)
end
local routing = luau.load(routingSource)()
local access = luau.load(accessSource, {environment = {typeof = envTypeof}})()
local body = assert(gm:match("local LEVEL4_PUBLIC = false(.-)%-%- Always%-on server authority"))
local policySource = "local LEVEL4_PUBLIC = false" .. body
	.. "\nreturn {canAccessLevel=canAccessLevel, devCeiling=devCeiling}\n"
local policy = luau.load(policySource, {environment = {Routing = routing, DevAccess = access, typeof = envTypeof}})()
local cases = {}
local function test(name, run)
	local ok, error = pcall(run)
	table.insert(cases, {name = name, passed = ok, error = if ok then nil else tostring(error)})
end
test("fresh unchanged Routing limits are public3 developer4 and campaign ends at3", function()
	assert(routing.MaxLevel == 3 and routing.DevMaxLevel == 4)
	assert(routing.NextLevel(1) == 2 and routing.NextLevel(2) == 3 and routing.NextLevel(3) == nil)
	for _, level in ipairs({4, 5, 6}) do assert(routing.NextLevel(level) == nil) end
	assert(routing.ClampLevelTo(5, 6) == 4 and routing.ClampLevelTo(6, 6) == 4)
end)
for _, row in ipairs({
	{name = "ordinary", group = {subject(1)}, ceiling = 3},
	{name = "Zen narrow preview only", group = {subject(11374988579)}, ceiling = 3},
	{name = "shared developer", group = {subject(9488575949)}, ceiling = 4},
	{name = "both shared developers", group = {subject(9488575949), subject(40920547)}, ceiling = 4},
	{name = "mixed ordinary/developer cohort", group = {subject(9488575949), subject(1)}, ceiling = 3},
	{name = "empty cohort", group = {}, ceiling = 3},
}) do
	test("exact GameManager campaign policy: " .. row.name, function()
		assert(policy.devCeiling(row.group) == row.ceiling)
		for level = 1, 6 do assert(policy.canAccessLevel(level, row.group) == (level <= row.ceiling)) end
		assert(not policy.canAccessLevel("5", row.group) and not policy.canAccessLevel("6", row.group))
		assert(not policy.canAccessLevel(5.1, row.group) and not policy.canAccessLevel(0 / 0, row.group)
			and not policy.canAccessLevel(math.huge, row.group))
	end)
end
test("fresh DevAccess still grants Zen preview only, never general DEV commands", function()
	assert(access.IsLevel6PreviewAllowed(subject(11374988579)) and not access.IsAllowed(subject(11374988579)))
	assert(not access.IsAllowed(subject(1)) and not access.IsLevel6PreviewAllowed(subject(1)))
end)
test("hypothetical nonrevision nonpreview Level5/6 station still fails actual playerInsideZone", function()
	local functionBody = assert(gm:match("(local function playerInsideZone%(player, station, includeBusy%).-)%s*local function rawQueuedPlayers"))
	local inside = luau.load(functionBody .. "\nreturn playerInsideZone\n", {environment = {
		DevAccess = access, Routing = routing, canAccessLevel = policy.canAccessLevel,
		revisedQueueBridge = function() error("Campaign-only policy must reject before bridge or character work") end,
	}})()
	for _, level in ipairs({5, 6}) do
		assert(inside(subject(1), {level = level, revisionOwned = false, previewQueue = false}) == false)
		assert(inside(subject(9488575949), {level = level, revisionOwned = false, previewQueue = false}) == false)
	end
end)
test("actual revised Level5/6 metadata is fixed by untouched trusted server Bridge.Build", function()
	local bridge = fs.readFile(ROOT .. "ServerScriptService__LobbyReimaginedPreview__QueueBridge.post-install.server.luau")
	assert(bridge:find("revisionOwned = true, lobbyOwner = model, renderOwner = owner, previewOnly = level > 3, previewQueue = level > 3", 1, true))
	local native = serde.decode("json", fs.readFile(ROOT .. "post-install-server-auth.json"))
	local found, count = {}, 0
	for _, zone in ipairs(native.actualQueueZones) do
		if zone.level >= 5 then
			count += 1; found[zone.id] = true
			assert(zone.id >= 117 and zone.id <= 124)
			assert(zone.level == math.floor((zone.id - 101) / 4) + 1)
			assert(zone.display == (zone.id - 101) % 4 + 1)
		end
	end
	assert(count == 8)
	for id = 117, 124 do assert(found[id]) end
end)
local passed = true
for _, case in ipairs(cases) do passed = passed and case.passed end
local receipt = {scope = "Independent fresh PlayServer Source inspection and offline exact campaign-policy execution; not actual ordinary-player admission, private GameManager table inspection or multiplayer proof.",
	passed = passed, testCount = #cases, cases = cases,
	gameManagerSHA256 = serde.hash("sha256", gm), gameManagerBytes = #gm,
	routingSHA256 = serde.hash("sha256", routingSource), routingBytes = #routingSource,
	accessSHA256 = serde.hash("sha256", accessSource), extractedCampaignPolicySHA256 = serde.hash("sha256", policySource)}
fs.writeFile(ROOT .. "campaign-route-closure-test-receipt.json", serde.encode("json", receipt, true) .. "\n")
print(serde.encode("json", receipt, true)); assert(passed)
