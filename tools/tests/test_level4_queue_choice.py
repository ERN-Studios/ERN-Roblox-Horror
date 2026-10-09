"""Level 4 bays are ordinary public pads (owner, 2026-10-05).

The TRIAL ROUND / MAP PREVIEW choice (LEVEL4_QUEUE_CHOICE_20261002) is retired:
QueueBridge marks only levels above 4 previewOnly, and the Level 4 map preview
and its controller Level4V4PreviewAccess are deleted. This proves, against the
REAL GameManager sections (Level 4 access, isLevel4Choice, level4ChoiceModes,
revisedQueueIdleSubtitle, playerInsideZone, resetStation, the new-host /
queuehost block and the ConfigureQueue handler), the REAL DevAccess, Round
Completion Routing and LobbyReimaginedPreview.QueueBridge (stations from
Bridge.Build over a fake lobby):
- the bridge refuses a Level 4 preview launcher; Level 4 bays 113-116 are built
  with previewOnly/previewQueue false and level4ChoiceModes is nil on every bay;
- any player (developer, Level 6 preview guest, guest) is admitted to a Level 4
  bay, the host's queuehost carries no launch modes, and ConfigureQueue yields a
  normal round (launchMode nil, previewQueue false, no TRIAL ROUND / MAP PREVIEW
  on the sign) for every requested mode, with queue sizes and privacy intact;
- Level 5 and Level 6 bays keep their preview launchers (registered through the
  real RegisterPreviewLauncher) and the admission GameManager decides for them.
Then RoundUI's real queue panel (submit block, submit-row layouts,
refreshQueuePanel, queuehost / lobbycountdown branches) under fake GUI objects
shows a Level 4 host CREATE PARTY and sends no mode. No Studio, no network.
Set LUAU_BIN.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER_PATH = ROOT / "ServerScriptService/GameManager.Script.lua"
CLIENT_PATH = ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"
BRIDGE_PATH = ROOT / "ServerScriptService/LobbyReimaginedPreview/QueueBridge.ModuleScript.lua"
SERVER = SERVER_PATH.read_text(encoding="utf-8")
CLIENT = CLIENT_PATH.read_text(encoding="utf-8")
BRIDGE = BRIDGE_PATH.read_text(encoding="utf-8")
ACCESS = (ROOT / "ReplicatedStorage/DevAccess.ModuleScript.lua").read_text(encoding="utf-8")
ROUTING = (ROOT / "ServerScriptService/Round Completion Routing.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    assert source.count(start) == 1, "marker drifted: " + start[:70]
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


SERVER_MOCK = r'''
local checks = 0
local function check(ok, why) checks += 1; assert(ok, why) end
local function typeof(v) return type(v) == "table" and rawget(v, "ClassName") and "Instance" or type(v) end
local Inst = {}
Inst.__index = Inst
local BASE = {Part = "BasePart", Script = "BaseScript"}
local function inst(class, name, parent)
    local o = setmetatable({ClassName = class, Name = name, attrs = {}, kids = {}}, Inst)
    if parent then o.Parent = parent; table.insert(parent.kids, o) end
    return o
end
function Inst:IsA(c) return c == self.ClassName or BASE[self.ClassName] == c end
function Inst:GetAttribute(k) return self.attrs[k] end
function Inst:SetAttribute(k, v) self.attrs[k] = v end
function Inst:FindFirstChild(n, deep)
    for _, k in ipairs(self.kids) do
        if k.Name == n then return k end
        if deep then local found = k:FindFirstChild(n, true); if found then return found end end
    end
    return nil
end
function Inst:FindFirstChildOfClass(c)
    for _, k in ipairs(self.kids) do if k.ClassName == c then return k end end
    return nil
end
function Inst:GetDescendants()
    local out = {}
    local function walk(o) for _, k in ipairs(o.kids) do table.insert(out, k); walk(k) end end
    walk(self)
    return out
end
function Inst:IsDescendantOf(a)
    local p = self.Parent
    while p do if p == a then return true end; p = p.Parent end
    return false
end
local workspace = inst("Workspace", "Workspace")
local Players = inst("Players", "Players")
local SSS = inst("ServerScriptService", "ServerScriptService")
local studio = false
local RunService = {IsStudio = function() return studio end, IsClient = function() return false end}
local game = {GetService = function(_, name)
    local service = ({Players = Players, RunService = RunService, ServerScriptService = SSS})[name]
    return assert(service, "unexpected service " .. tostring(name))
end}
local Enum = {HumanoidStateType = {Dead = "Dead"}}
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
local task = {spawn = function(fn, ...) fn(...) end, wait = function() end}
local warnings = {}
local function warn(...) table.insert(warnings, table.concat({...}, " ")) end
local DevAccess = (function()
'''

AFTER_ACCESS = r'''
end)()
-- Stale mirror: GameManager's playerInsideZone (mirrored from Studio in 9102e6e) calls DevAccess.IsLevel5Allowed /
-- IsLevel6Allowed ("Levels 5 and 6 are public"), which the repo's DevAccess does not define yet. Model them as
-- public; the real ones win as soon as they are mirrored.
DevAccess.IsLevel5Allowed = DevAccess.IsLevel5Allowed or function() return true end
DevAccess.IsLevel6Allowed = DevAccess.IsLevel6Allowed or function() return true end
local Routing = (function()
'''

AFTER_ROUTING = r'''
end)()
local Bridge = (function()
'''

AFTER_BRIDGE = r'''
end)()
-- GameManager's own placement: script.Parent is ServerScriptService, QueueBridge in its folder.
local script = inst("Script", "GameManager", SSS)
local bridgeModule = inst("ModuleScript", "QueueBridge", inst("Folder", "LobbyReimaginedPreview", SSS))
local function require(module) assert(module == bridgeModule, "only QueueBridge is required here"); return Bridge end
-- Test launchers registered through the real RegisterPreviewLauncher for the only controllers it still expects.
-- allowed() is shaped like Level5/Level6PreviewAccess's: IsLevel6PreviewAllowed-gated behind a readiness/cooldown
-- gate (previewOpen).
local previewOpen, previewAnyone, launchHook = true, false, nil
for level, name in pairs({[5] = "Level5PreviewAccess", [6] = "Level6PreviewAccess"}) do
    Bridge.RegisterPreviewLauncher(level, inst("Script", name, SSS), {
        allowed = function(player) return previewOpen and (previewAnyone or DevAccess.IsLevel6PreviewAllowed(player)) end,
        ready = function() return nil end,
        launch = function(context) if launchHook then return launchHook(context) end; return false, "TEST" end,
    })
end
-- A ready revised lobby with all 24 bays, built so the REAL Bridge.Build accepts it.
local lobby = inst("Model", "LobbyReimaginedPreview", workspace)
lobby.attrs = {LobbyReimaginedOwned = true, R3QueueRevision = 3, Ready = true}
for id = 101, 124 do
    local ordinal = id - 101
    local bay = inst("Model", "Bay" .. id, lobby)
    bay.attrs.CircularBayDiameter = 24
    inst("Part", "ChamberFloor", bay)
    local zone = inst("Part", "QueueZone", bay)
    zone.attrs = {R3QueueId = id, LevelNumber = math.floor(ordinal / 4) + 1, QueueDisplayIndex = ordinal % 4 + 1,
        QueueDetectorShape = "Circle", QueueRadius = 8}
    zone.Anchored, zone.CanCollide, zone.CanTouch, zone.CanQuery = true, false, false, false
    zone.Size, zone.Color = {X = 16, Y = 1, Z = 16}, "color" .. id
    zone.CFrame = {PointToObjectSpace = function(_, p) return p end}
    local owner = inst("Model", "Render" .. id, lobby)
    inst("ObjectValue", "QueueRenderOwner", zone).Value = owner
    local surface = inst("SurfaceGui", "Display", owner)
    inst("TextLabel", "QueueTitle", surface); inst("TextLabel", "QueueSubtitle", surface)
end
local inRound = {}
local MAX_PLAYERS_PER_STATION = 6
local IS_RESERVED_ROUND_SERVER = false
local lobbyStations = {}
for _, station in ipairs(Bridge.Build(lobby)) do lobbyStations[station.index] = station end
local fired = {}
local status = {FireClient = function(_, player, ...) table.insert(fired, table.pack(player, ...)) end}
local queueHandler
local queueConfig = {OnServerEvent = {Connect = function(_, fn) queueHandler = fn end}}
local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
'''

SERVER_CHECKS = r'''
local function makePlayer(userId, name)
    local player = inst("Player", name, Players); player.UserId = userId
    local character = inst("Model", name, workspace)
    local humanoid = inst("Humanoid", "Humanoid", character)
    local root = inst("Part", "HumanoidRootPart", character)
    humanoid.Health, humanoid.RootPart = 100, root
    humanoid.GetState = function() return "Running" end
    root.Position, root.Anchored = {X = 1, Y = 2, Z = 1}, false
    player.Character = character
    return player
end
local owner = makePlayer(40920547, "Owner")
local partner = makePlayer(9488575949, "Partner")
local zen = makePlayer(11374988579, "ZenMeister02") -- Level 6 preview guest, not a developer
local guest = makePlayer(222, "Guest")
local everyone = {owner, partner, zen, guest}
local function lastFired(player, event)
    for i = #fired, 1, -1 do
        local f = fired[i]
        if f[1] == player and f[2] == event then return f end
    end
    return nil
end
local bay, five, six, one = lobbyStations[113], lobbyStations[117], lobbyStations[121], lobbyStations[101]

-- the Level 4 map preview is gone: the real bridge refuses its launcher even with the controller present
local registered, problem = pcall(Bridge.RegisterPreviewLauncher, 4, inst("Script", "Level4V4PreviewAccess", SSS), {
    allowed = function() return true end, ready = function() return nil end, launch = function() return true end,
})
check(not registered and string.find(tostring(problem), "Wrong active preview controller", 1, true),
    "the real bridge refuses a Level 4 preview launcher")

-- the real Bridge.Build: Level 4 bays are ordinary pads, only bays above Level 4 are preview queues
check(bay.level == 4 and lobbyStations[116].level == 4 and five.level == 5 and six.level == 6
    and lobbyStations[112].level == 3, "real Bridge.Build maps 113-116 to Level 4")
for id = 101, 124 do
    local station = lobbyStations[id]
    check(station.previewOnly == (station.level > 4) and station.previewQueue == station.previewOnly,
        "only bays above Level 4 are preview queues, not " .. id)
    check(not isLevel4Choice(station), "no bay offers a Level 4 launch choice, not " .. id)
    for _, player in ipairs(everyone) do
        check(level4ChoiceModes(station, player) == nil, "level4ChoiceModes is nil on bay " .. id .. " for " .. player.Name)
    end
end
for _, old in ipairs({
    {index = 4, level = 4}, {index = 2, level = 5},
    {index = 4, level = 4, previewOnly = true, previewQueue = true},
    {index = 113, level = 4, revisionOwned = true, previewOnly = false},
}) do
    check(not isLevel4Choice(old), "tunnel-lobby and non-preview stations are never choice bays")
end
check(not Bridge.AllowsPreview(bay, owner), "the bridge offers no Level 4 preview")
bay.busy = true
local launched, why = Bridge.LaunchPreviewGroup(bay, {owner})
check(launched == false and why == "PREVIEW_LAUNCHER_UNAVAILABLE", "a Level 4 bay cannot launch a preview")
bay.busy = false

-- idle subtitles
check(revisedQueueIdleSubtitle(bay) == "ENTER TO HOST  •  CHOOSE 1-6 PLAYERS", "Level 4 bay idles like a campaign bay")
check(revisedQueueIdleSubtitle(one) == "ENTER TO HOST  •  CHOOSE 1-6 PLAYERS", "Level 1 bay subtitle unchanged")
check(revisedQueueIdleSubtitle(five) == "THE VOID ROOMS  •  1-6 PLAYERS", "Level 5 preview bay keeps its own subtitle")
check(revisedQueueIdleSubtitle(six) == "HIDE AND SEEK  •  1-6 PLAYERS", "Level 6 preview bay keeps its own subtitle")

-- Level 4 admission: everyone, in Studio or not, whatever the preview launchers say
for _, isStudio in ipairs({false, true}) do
    for _, open in ipairs({false, true}) do
        studio, previewOpen = isStudio, open
        for _, player in ipairs(everyone) do
            check(playerInsideZone(player, bay), "Level 4 bay admits " .. player.Name .. " (public round)")
        end
    end
end
studio, previewOpen = false, true
inRound[guest] = true
check(not playerInsideZone(guest, bay), "a player already in a round is refused")
inRound[guest] = nil

-- Level 5/6 admission stays GameManager's level gate plus the bridge's preview launcher
for _, station in ipairs({five, six}) do
    local name = "Level " .. station.level .. " bay"
    for _, isStudio in ipairs({false, true}) do
        studio = isStudio
        check(playerInsideZone(owner, station) and playerInsideZone(partner, station) and playerInsideZone(zen, station),
            name .. " admits the players its launcher admits")
        check(not playerInsideZone(guest, station), name .. " refuses a player its launcher refuses")
    end
    studio, previewAnyone = false, true
    check(playerInsideZone(guest, station), name .. " admits whoever its launcher admits")
    previewAnyone, previewOpen = false, false
    check(not playerInsideZone(owner, station), name .. " refuses everyone while its launcher is not ready")
    previewOpen = true
    owner:SetAttribute("Level6InRound", true)
    check(not playerInsideZone(owner, station), name .. ": real bridge refuses a player inside another preview")
    owner:SetAttribute("Level6InRound", nil)
end

-- resetStation
bay.launchMode, bay.previewQueue = "trial", true -- leftovers of an old choice session
resetStation(bay, false)
check(bay.launchMode == nil and bay.previewQueue == false and bay.host == nil and not bay.configured,
    "resetStation makes a Level 4 bay an ordinary pad again")
check(bay.title.Text == "STATION 1  •  0/6" and bay.sub.Text == "ENTER TO HOST  •  CHOOSE 1-6 PLAYERS",
    "reset display shows the ordinary idle subtitle")
five.launchMode, five.previewQueue = "trial", false
resetStation(five, false)
check(five.launchMode == nil and five.previewQueue == true and five.sub.Text == "THE VOID ROOMS  •  1-6 PLAYERS",
    "resetStation keeps a Level 5 bay a preview queue")
one.launchMode, one.previewQueue = "trial", true
resetStation(one, false)
check(one.launchMode == nil and one.previewQueue == false, "resetStation keeps a campaign bay a campaign bay")

-- queuehost from the real new-host block (seeded with a previous session's leftovers)
local function host(station, player)
    station.host, station.launchMode, station.previewQueue = nil, "trial", not station.previewOnly
    hostStep(station, {player})
    return lastFired(player, "queuehost")
end
for _, player in ipairs(everyone) do
    local q = host(bay, player)
    check(bay.host == player and bay.awaitingConfig and bay.launchMode == nil and bay.previewQueue == false,
        "new host block resets a Level 4 bay to an ordinary pad for " .. player.Name)
    check(q and q.n == 6 and q[3] == 113 and q[4] == 6 and q[5] == "public" and q[6] == nil,
        "queuehost to a Level 4 host carries no launch modes (" .. player.Name .. ")")
end
check(host(one, owner)[6] == nil and one.previewQueue == false, "Level 1 bay sends no mode list")
check(host(five, owner)[6] == nil and five.previewQueue == true, "Level 5 bay sends no mode list")
check(host(six, zen)[6] == nil and six.previewQueue == true, "Level 6 bay sends no mode list")

-- ConfigureQueue: whatever an old or forged client asks for, a Level 4 party is a normal round
local function fresh(station, player) table.clear(fired); resetStation(station, false); host(station, player) end
local function configure(station, player, mode, privacy, size)
    queueHandler(player, station.index, size or 4, privacy or "public", mode)
end
local MODES = {"trial", "preview", "TRIAL", "trial,preview", 42, false}
for _, player in ipairs(everyone) do
    for _, isStudio in ipairs({false, true}) do
        for i = 1, #MODES + 1 do
            studio = isStudio
            fresh(bay, player); configure(bay, player, MODES[i])
            local case = player.Name .. " / mode " .. tostring(MODES[i]) .. (isStudio and " / Studio" or "")
            check(bay.configured and not bay.awaitingConfig and bay.maxPlayers == 4 and bay.privacy == "public",
                "a Level 4 party configures: " .. case)
            check(bay.launchMode == nil and bay.previewQueue == false,
                "a Level 4 party is a normal round, never a preview or a labelled launch: " .. case)
            check(bay.sub.Text == "PUBLIC  •  COUNTDOWN STARTING", "the sign names no TRIAL ROUND / MAP PREVIEW: " .. case)
            local c = lastFired(player, "queueconfigured")
            check(c and c[3] == 4 and c[4] == "public" and c[5] == 113, "host is told the party is configured: " .. case)
        end
    end
end
studio = false
for _, player in ipairs(everyone) do
    check(playerInsideZone(player, bay), "the Level 4 countdown admits " .. player.Name)
end
resetStation(bay, true)
check(bay.launchMode == nil and bay.previewQueue == false and lastFired(guest, "queueconfigclosed"),
    "reset after a party keeps the ordinary pad and closes the host panel")

-- privacy and queue sizes
fresh(bay, guest); configure(bay, guest, nil, "friends")
check(bay.configured and bay.privacy == "friends" and bay.sub.Text == "FRIENDS ONLY  •  COUNTDOWN STARTING"
    and lastFired(guest, "queueconfigured")[4] == "friends", "a friends-only Level 4 party")
for _, size in ipairs({{0, 1}, {1, 1}, {3, 3}, {6, 6}, {99, 6}, {"x", 6}}) do
    fresh(bay, owner); configure(bay, owner, nil, nil, size[1])
    check(bay.maxPlayers == size[2] and bay.title.Text == "STATION 1  •  1/" .. size[2],
        "requested size " .. tostring(size[1]) .. " clamps to " .. size[2])
end
fresh(bay, owner); configure(bay, partner, nil)
check(not bay.configured and bay.awaitingConfig, "only the host configures")

-- Level 5/6 preview bays keep their preview path; a campaign bay stays a round
for _, station in ipairs({five, six}) do
    local name = "Level " .. station.level
    fresh(station, owner); configure(station, owner, "trial")
    check(station.configured and station.launchMode == nil and station.previewQueue == true
        and station.sub.Text == "PUBLIC  •  COUNTDOWN STARTING", "a requested trial cannot turn a " .. name .. " preview bay into a round")
    fresh(station, zen); configure(station, zen, nil, "friends")
    check(station.configured and station.previewQueue == true and station.privacy == "friends",
        "the Level 6 preview guest hosts a " .. name .. " preview")
    fresh(station, guest); configure(station, guest, nil)
    check(not station.configured, "a player the launcher refuses cannot configure a " .. name .. " preview")
end
fresh(one, owner); configure(one, owner, "preview")
check(one.configured and one.launchMode == nil and one.previewQueue == false, "a requested preview cannot turn a Level 1 bay into a preview")

-- the real preview launch path still runs on a Level 5 bay
fresh(five, owner); configure(five, owner, nil)
five.busy = true
local seen
launchHook = function() seen = revisedQueueIdleSubtitle(five); return true end
check(Bridge.LaunchPreviewGroup(five, {owner}) == true, "real bridge launches the configured Level 5 preview cohort")
check(seen == "PREPARING PREVIEW WORLD  •  PLEASE WAIT", "preparing subtitle while the Level 5 preview launches")
five.busy, launchHook = false, nil
check(#warnings == 0, "no warnings: " .. table.concat(warnings, " | "))
print("Level 4 ordinary bays (server): " .. checks .. " checks passed")
'''

CLIENT_MOCK = r'''
local checks = 0
local function check(ok, why) checks += 1; assert(ok, why) end
local function signal()
    local s = {fns = {}}
    function s:Connect(fn) table.insert(self.fns, fn); return {Disconnect = function() end} end
    function s:Fire(...) for _, fn in ipairs(self.fns) do fn(...) end end
    return s
end
local childrenOf = {}
local function gui(class, name, parent)
    local props = {ClassName = class, Name = name, Visible = true, Text = "", TextSize = 21, Active = true, Activated = signal()}
    local attrs, attrSignals, propSignals, methods = {}, {}, {}, {}
    local o = setmetatable({}, {
        __index = function(_, k) if methods[k] ~= nil then return methods[k] end; return props[k] end,
        __newindex = function(_, k, v)
            local old = props[k]; props[k] = v
            if old ~= v and propSignals[k] then propSignals[k]:Fire() end
        end,
    })
    function methods:FindFirstChild(n) for _, c in ipairs(childrenOf[self]) do if c.Name == n then return c end end; return nil end
    function methods:GetAttribute(k) return attrs[k] end
    function methods:SetAttribute(k, v)
        local old = attrs[k]; attrs[k] = v
        if old ~= v and attrSignals[k] then attrSignals[k]:Fire() end
    end
    function methods:GetAttributeChangedSignal(k) attrSignals[k] = attrSignals[k] or signal(); return attrSignals[k] end
    function methods:GetPropertyChangedSignal(k) propSignals[k] = propSignals[k] or signal(); return propSignals[k] end
    function methods:IsDescendantOf() return false end
    childrenOf[o] = {}
    if parent then o.Parent = parent; table.insert(childrenOf[parent], o) end
    return o
end
local UDim2 = {new = function(a, b, c, d) return {a, b, c, d} end, fromOffset = function(x, y) return {0, x, 0, y} end}
local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
local Enum = {ContextActionResult = {Pass = "Pass", Sink = "Sink"}, UserInputState = {Begin = "Begin"},
    ContextActionPriority = {High = {Value = 2000}}, KeyCode = {ButtonB = "ButtonB"}}
local delayed = {}
local task = {delay = function(_, fn) table.insert(delayed, fn) end}
local GuiService = {MenuIsOpen = false}
local game = {GetService = function(_, n) assert(n == "GuiService", n); return GuiService end}
local bound = {}
local ContextActionService = {BindActionAtPriority = function(_, name) bound[name] = true end,
    UnbindAction = function(_, name) bound[name] = nil end}
local UIDevice = {LastInput = function() return "MouseKeyboard" end}
local layoutCalls = 0
local function applyQueueDeviceLayout() layoutCalls += 1 end
local sent = {}
local queueRemote = {FireServer = function(_, ...) table.insert(sent, table.pack(...)) end}
local messages = {}
local function setMsg(text) table.insert(messages, text or "") end
local loadingFrame = gui("Frame", "Loading")
local label = gui("TextLabel", "Message")
local queueShade = gui("Frame", "QueueShade"); queueShade.Visible = false
local queuePanel = gui("Frame", "QueuePanel", queueShade)
local function queueButton(name, text, position, size)
    local button = gui("TextButton", name, queuePanel)
    button.Text, button.Position, button.Size = text, position, size
    return button, gui("UIStroke", "Stroke", button)
end
local queueSubmit, queueSubmitStroke = queueButton("CreateParty", "CREATE PARTY", UDim2.new(0.10, 0, 1, -78), UDim2.new(0.80, 0, 0, 50))
local queueClose = queueButton("CloseQueue", "X", UDim2.new(1, -46, 0, 10), UDim2.fromOffset(34, 34))
local queuePrivacyButton, queuePrivacyStroke = queueButton("PrivacyToggle", "PUBLIC", UDim2.new(0.1, 0, 0, 224), UDim2.new(0.8, 0, 0, 48))
local queueCount = gui("TextLabel", "PlayerCount", queuePanel)
local queueStationLabel = gui("TextLabel", "StationLabel", queuePanel)
'''

CLIENT_CHECKS = r'''
local preview = queuePanel:FindFirstChild("MapPreview")
check(preview and preview.Visible == false, "the MapPreview button stays hidden")
check(queueSubmit.Text == "CREATE PARTY", "no modes: the submit is CREATE PARTY")

-- what GameManager now sends a Level 4 host: queuehost with no launch modes
onStatus("queuehost", 113, 6, "public", nil)
check(queueShade.Visible and queueShade:GetAttribute("QueueLaunchModes") == nil, "a Level 4 queuehost publishes no launch modes")
check(queueSubmit.Text == "CREATE PARTY" and queueStationLabel.Text == "STATION 113  •  YOU ARE THE HOST",
    "the Level 4 host panel shows CREATE PARTY")
for i, apply in ipairs(submitRows) do
    preview.Visible = true
    apply(200, 48)
    check(not preview.Visible and queueSubmit.Size[1] > 0.5 and queueSubmit.Position[4] == 200,
        "layout " .. i .. " keeps one full-width CREATE PARTY")
end
queueSubmit.Activated:Fire()
local s = sent[1]
check(#sent == 1 and s.n == 4 and s[1] == 113 and s[2] == 6 and s[3] == "public" and s[4] == nil,
    "CREATE PARTY sends no launch mode")
check(queueSubmit.Text == "CREATING PARTY..." and not queueSubmit.Active, "the submit locks while creating the party")
queueSubmit.Activated:Fire()
check(#sent == 1, "a second submit while creating is ignored")
for _, fn in ipairs(delayed) do fn() end
table.clear(delayed)
check(queueSubmit.Text == "CREATE PARTY" and queueSubmit.Active, "the submit lock times out")

onStatus("queuehost", 117, 3, "friends", nil)
check(queueShade:GetAttribute("QueueLaunchModes") == nil and queueSubmit.Text == "CREATE PARTY", "a Level 5 host sees CREATE PARTY")
queueSubmit.Activated:Fire()
check(sent[2].n == 4 and sent[2][1] == 117 and sent[2][2] == 3 and sent[2][3] == "friends" and sent[2][4] == nil,
    "a Level 5 submit sends size and privacy, no mode")
for _, bogus in ipairs({"preview,trial", "TRIAL", 42, true}) do
    onStatus("queuehost", 113, 6, "public", bogus)
    check(queueShade:GetAttribute("QueueLaunchModes") == nil and queueSubmit.Text == "CREATE PARTY",
        "unknown mode lists are dropped: " .. tostring(bogus))
end
check(bound.QueueHostClose, "open panel binds the gamepad close")
queueShade.Visible = false
check(queueShade:GetAttribute("QueueLaunchModes") == nil and not bound.QueueHostClose, "hiding the panel unbinds the gamepad close")

onStatus("lobbycountdown", 9, 2, 113, 6, "public", nil)
check(messages[#messages] == "STATION 113  •  GAME BEGINS IN 9\n2/6 READY  •  PUBLIC", "a Level 4 countdown names no launch")
onStatus("lobbycountdown", 7, 1, 117, 4, "friends", nil)
check(messages[#messages] == "STATION 117  •  GAME BEGINS IN 7\n1/4 READY  •  FRIENDS ONLY", "plain friends-only countdown")
print("Level 4 ordinary bays (client): " .. checks .. " checks passed")
'''


def submit_rows():
    marker = "Control = queueSubmit, Apply = function(y, h)"
    rows, pos = [], 0
    while (start := CLIENT.find(marker, pos)) >= 0:
        stop = CLIENT.index("\n   end},", start)
        rows.append("function(y, h)" + CLIENT[start + len(marker):stop] + "\nend")
        pos = stop
    assert len(rows) == 2, "expected the touch and desktop submit rows"
    return "local submitRows = {" + ",\n".join(rows) + "}\n"


def branch(start, stop):
    return section(CLIENT, '\telseif ev == "' + start + '" then', '\telseif ev == "' + stop + '" then')


def main():
    artifact_binary = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau") or (
        str(artifact_binary) if artifact_binary.is_file() else None
    )
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no checks executed.")
    # Source contracts the harness cannot execute: the countdown carries the mode, and
    # launchStation still branches on previewQueue (true -> bridge preview, false -> round).
    assert ('fireGroup(ready, "lobbycountdown", t, #ready, station.index, station.maxPlayers, '
            'station.privacy, station.launchMode)') in SERVER
    assert "local function launchStation(station, participants)\n if station.previewQueue then" in SERVER
    new_host = section(SERVER, "  if not station.host then\n",
                       "  if not playerInsideZone(station.host, station) then")
    server = (SERVER_MOCK + ACCESS + AFTER_ACCESS + ROUTING + AFTER_ROUTING + BRIDGE + AFTER_BRIDGE
              + section(SERVER, "local LEVEL4_PUBLIC = true", "-- Always-on server authority")
              + section(SERVER, "local function setStationDisplay", "local function scatterAt")
              + section(SERVER, "local function queueRadius", "local function rawQueuedPlayers")
              + section(SERVER, "local function resetStation", "local function syncSetupFeedback")
              + section(SERVER, "local function privacyLabel", "local function connectElevator")
              + "local function hostStep(station, raw)\n repeat\n" + new_host + " until true\nend\n"
              + SERVER_CHECKS)
    client = (CLIENT_MOCK
              + section(CLIENT, 'do\n local preview, previewStroke = queueButton("MapPreview"', "\nend\n") + "\nend\n"
              + section(CLIENT, "local queueStation = nil\n", "queueMinus.Activated:Connect")
              + section(CLIENT, "do\n -- LEVEL4_QUEUE_CHOICE_20261002: both launch buttons share one submit",
                        "\n\n-- RoundUI is the sole cursor-policy owner") + "\n"
              + submit_rows()
              + "local function onStatus(ev, a, b, c, d, e, f)\n if false then\n"
              + branch("queuehost", "queueconfigured") + branch("lobbycountdown", "lobbycancel")
              + " end\nend\n" + CLIENT_CHECKS)
    with tempfile.TemporaryDirectory(prefix="level4-queue-choice-") as directory:
        for name, source in (("server.luau", server), ("client.luau", client)):
            path = Path(directory) / name
            path.write_text(source, encoding="utf-8")
            subprocess.run([binary, str(path)], check=True)
        compiler = Path(binary).with_name("luau-compile.exe")
        if compiler.exists():
            # RoundUI sits at the 200-register limit; the whole real files must still compile.
            for path in (SERVER_PATH, CLIENT_PATH, BRIDGE_PATH):
                subprocess.run([str(compiler), str(path)], stdout=subprocess.DEVNULL, check=True)


if __name__ == "__main__":
    main()
