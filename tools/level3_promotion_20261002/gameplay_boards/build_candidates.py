"""Draft scoped public Level 3 and original R4 support-board Source candidates.

Reads the pinned live Source capture, never Studio/repository runtime mirrors.
No Studio write is performed here; root applies candidates after review/CAS.
"""
import difflib
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).parent
BASE = ROOT / "capture-baseline"
OUT = ROOT / "candidates"
OUT.mkdir(exist_ok=True)


def read(path):
    return (BASE / (path + ".luau")).read_text()


def function(source, marker):
    start = source.index(marker)
    end = source.index("\nend", start) + 4
    return source[start:end]


def substitute_function(source, donor, marker):
    old = function(source, marker)
    assert source.count(old) == 1
    return source.replace(old, function(donor, marker), 1)


def replace_once(source, old, new):
    assert source.count(old) == 1, old[:120]
    return source.replace(old, new, 1)


changes = []


def emit(path, candidate, reason):
    baseline = read(path)
    assert candidate != baseline
    dest = OUT / (path + ".candidate.luau")
    dest.write_text(candidate)
    (OUT / (path + ".diff")).write_text("".join(difflib.unified_diff(
        baseline.splitlines(True), candidate.splitlines(True),
        fromfile=path + " live baseline", tofile=path + " scoped candidate")))
    changes.append({
        "path": path,
        "class": "LocalScript" if path.startswith("StarterPlayer.") else "ModuleScript",
        "baselineFile": str(BASE / (path + ".luau")),
        "candidateFile": str(dest),
        "baselineSHA256": hashlib.sha256(baseline.encode()).hexdigest(),
        "candidateSHA256": hashlib.sha256(candidate.encode()).hexdigest(),
        "baselineSourceEditorMatch": True,
        "reason": reason,
    })


lighting_path = "StarterPlayer.StarterPlayerScripts.Level 3 Lighting Controller"
lighting = read(lighting_path)
donor = (BASE / "normalized6_Lighting Controller.luau").read_text()
start = donor.index("-- The Blender diffuser")
end = donor.index("-- enforceBlackout", start)
lighting = replace_once(lighting,
    "local blackoutPartSeen: {[BasePart]: boolean} = {}\n",
    "local blackoutPartSeen: {[BasePart]: boolean} = {}\n" + donor[start:end])
marker = "local function captureAuthoredRoomGlow"
lighting = replace_once(lighting, "local function captureWorldLightBaseline()",
    function(donor, marker) + "\n\nlocal function captureWorldLightBaseline()")
for marker in ["local function captureWorldLightBaseline", "local function bindWorld", "applyLevelGrade = function"]:
    lighting = substitute_function(lighting, donor, marker)
lighting = lighting.replace("-- client-owned grade keeps the exterior at night without changing the lobby\n\t-- or the original Level 3 for players outside this preview.",
    "-- client-owned grade keeps the exterior at night for public Level 3 rounds.")
lighting = replace_once(lighting, '\tif not instance:FindFirstChild("Level 3 Fluorescent Light") then return end',
    '\tif not instance:FindFirstChildWhichIsA("Light")\n\t\tand instance:GetAttribute("Level3_HiddenExitFrame") ~= true then return end')
lighting = replace_once(lighting, 'local function captureAuthoredRoomGlow(instance: Instance)\n',
    '''local function captureAuthoredRoomGlow(instance: Instance)
\t-- Every authored hidden-door frame participates, including the seven
\t-- frame carriers that do not own the portal's one spill light.
\tif instance:IsA("BasePart") and instance:GetAttribute("Level3_HiddenExitFrame") == true then
\t\tif not blackoutPartSeen[instance] then
\t\t\tblackoutPartSeen[instance] = true
\t\t\ttable.insert(blackoutParts, {Part=instance, Material=instance.Material, Color=instance.Color})
\t\tend
\t\treturn
\tend
''')
assert 'local LEVEL = 3' in lighting
assert 'workspace:GetAttribute("SelectedLevel") == LEVEL' in lighting
assert 'player:GetAttribute("InRound") == true' in lighting
assert "Level3SelectedLevel" not in lighting and "Level3InRound" not in lighting
emit(lighting_path, lighting, "Public client material-chunk diffuser synchronization, ceiling bounce, gateway glow blackout/fade and revised night grade; retain public lighting ownership and restoration.")


objective_path = "ServerScriptService.Level 3 Systems.Level 3 Objective Controller"
objective = read(objective_path)
donor = (BASE / "normalized6_Objective Controller.luau").read_text()
for marker in ["local function updateFinalHallChase", "local function configureRuntimeDiscPart", "local function refreshPlayerCarryVisuals"]:
    objective = substitute_function(objective, donor, marker)
objective = replace_once(objective, "local function refreshPlayerCarryVisuals",
    function(donor, "local function setDiscVisualCFrame") + "\n\nlocal function refreshPlayerCarryVisuals")
objective = replace_once(objective, "\tdisc.CFrame = dropCF\n\thub.CFrame = dropCF",
    '\tsetDiscVisualCFrame(disc, dropCF * (if disc:GetAttribute("Level3_CDBasis") == "Y" then CFrame.Angles(0,0,-math.pi*.5) else CFrame.identity))\n'
    '\tsetDiscVisualCFrame(hub, dropCF * (if hub:GetAttribute("Level3_CDBasis") == "Y" then CFrame.Angles(0,0,-math.pi*.5) else CFrame.identity))')
objective = objective.replace("ZYNTRA TV/VCR RELAY", "BIRTHDAY CD PLAYER").replace("INSERT CDS INTO VCR", "INSERT CARRIED CDS")
objective = replace_once(objective, '\t\tportal.Wall.CanQuery = true\n\tend\n\tfor _, framePart in ipairs(portal.FrameParts) do',
    '''\t\tportal.Wall.CanQuery = true
\tend
\t-- The revised Blender skin is separate from the full-size collision wall.
\t-- Its reactive carrier forwards this fade to every authored material chunk.
\tlocal visualWall = portal.VisualWall
\tif visualWall and visualWall.Parent then
\t\tplayTween(session, visualWall, TweenInfo.new(0.60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
\t\t\tTransparency = 1,
\t\t})
\tend
\tfor _, framePart in ipairs(portal.FrameParts) do''')
assert function(objective, "local function fireEscapeStatus") == function(read(objective_path), "local function fireEscapeStatus")
assert 'local TeamObjectives = require(game:GetService("ServerScriptService"):WaitForChild("TeamObjectives"))' in objective
assert 'player:SetAttribute("Escaped", true)' in objective
assert "Level3SelectedLevel" not in objective and "Level3InRound" not in objective
emit(objective_path, objective, "First living survivor strictly beyond hall midpoint; CD material chunks restore and move with Y-basis carry/drop clones; revised CD player wording. Preserve public team notices/escape/rewards.")


ai_path = "ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller"
ai = read(ai_path)
donor = (BASE / "normalized6_Mall Manager AI Controller.luau").read_text()
for marker in ["local function currentSpeed", "local function nearestLivingPlayer", "local function chooseFinalHallSpawn"]:
    ai = substitute_function(ai, donor, marker)
ai = replace_once(ai,
    "\t\t-- Finish the fast approach promptly, including braking at the hall mouth.",
    "\t\t-- Reach the fixed fast-walk pace promptly and brake within the attack range.")
noise = function(donor, "function Controller.ReportNoise")
ai = replace_once(ai, "\nreturn Controller\n", "\n-- Server-only arcade/mechanical noise hook; caller cannot target non-participants.\n" + noise + "\n\nreturn Controller\n")
assert 'DeathAdvice.Mark(player, "L3Manager")' in ai
assert 'DeathAdvice.Mark(player, "L6Manager")' not in ai
assert "Level3SelectedLevel" not in ai and "Level3InRound" not in ai and "Level3BeingChased" not in ai
emit(ai_path, ai, "Far-end finale spawn .90-.98 with existing all-living-player minimum distance/volume gate, face/target hall runners, fixed configured pace, bounded existing retries; public arcade noise hook. Keep L3Manager death advice and public flags.")


builder_path = "ServerScriptService.LobbyReimaginedPreview.Builder"
builder = read(builder_path)
helper = '''-- Move the original live renderer; its existing Value/attribute connections
-- are closure-held and would not survive cloning just the display model.
local function supportBoardTransfer(destination, center)
    local installed = destination:FindFirstChild("ZyntraDonationLeaderboardBoard", true)
    if installed then
        assert(installed:IsA("Model"), "Inspect conflicting R4 support board")
        return nil
    end
    local lobby = assert(workspace:FindFirstChild("ServerLobby"), "Original server lobby must precede R4")
    local board
    for _, descendant in ipairs(lobby:GetDescendants()) do
        if descendant.Name == "ZyntraDonationLeaderboardBoard" then
            assert(descendant:IsA("Model") and board == nil, "Inspect conflicting original support boards")
            board = descendant
        end
    end
    assert(board, "Original support board is not ready")
    local panel = board:FindFirstChild("LeaderboardPanel")
    assert(panel and panel:IsA("BasePart") and panel:FindFirstChild("DonationLeaderboardDisplay"),
        "Inspect original support-board renderer before relocation")
    return {
        Board = board,
        Parent = board.Parent,
        Pivot = board:GetPivot(),
        TargetPivot = CFrame.new(center + Vector3.new(-30, 7.15, -35) - panel.Position) * board:GetPivot(),
    }
end
local function applySupportBoardTransfer(transfer, destination)
    if not transfer then return end
    transfer.Board:PivotTo(transfer.TargetPivot)
    -- Never assign a nil direct Parent: the original renderer tears down on nil.
    transfer.Board.Parent = destination
end
local function restoreSupportBoardTransfer(transfer)
    if not transfer then return end
    transfer.Board.Parent = transfer.Parent
    transfer.Board:PivotTo(transfer.Pivot)
end
'''
builder = replace_once(builder, "function Module.Build()", helper + "function Module.Build()")
builder = replace_once(builder,
    '\t\trequire(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)\n\t\treturn existing',
    '''\t\tlocal center = existing:GetAttribute("PreviewCenter")
\t\tassert(typeof(center) == "Vector3", "Inspect R4 lobby center before relocating support board")
\t\tlocal transfer = supportBoardTransfer(existing, center)
\t\tlocal ok, failure = pcall(function()
\t\t\tapplySupportBoardTransfer(transfer, existing)
\t\t\trequire(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
\t\tend)
\t\tif not ok then restoreSupportBoardTransfer(transfer); error(failure) end
\t\treturn existing''')
builder = replace_once(builder,
    '\tlocal model = Instance.new("Model"); model.Name = NAME; model.WorldPivot = CFrame.new(center)\n\tlocal ok, built = pcall(function()',
    '\tlocal model = Instance.new("Model"); model.Name = NAME; model.WorldPivot = CFrame.new(center)\n\tlocal transfer\n\tlocal ok, built = pcall(function()')
notice = '''\tlocal notice=manifest.notice
\tif notice then
\t\tlocal host=part(signs,"Mounted Revision Notice",vec(notice.size),CFrame.new(center+vec(notice.position))*CFrame.Angles(0,notice.yaw,0),false)
\t\ttext(host,Enum.NormalId.Back,"LOBBY REVISION · DEV",Color3.fromRGB(192,244,223),Vector2.new(440,100))
\tend
'''
builder = replace_once(builder, notice, "")
builder = replace_once(builder,
    '\trequire(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)\n',
    '\trequire(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)\n\ttransfer = supportBoardTransfer(model, center)\n\tapplySupportBoardTransfer(transfer, model)\n')
builder = replace_once(builder,
    '\tif not ok then model:Destroy(); error(built) end',
    '\tif not ok then restoreSupportBoardTransfer(transfer); model:Destroy(); error(built) end')
assert "LOBBY REVISION · DEV" not in builder
assert builder.count('require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(') == 2
emit(builder_path, builder, "Relocate original combined donation/purchase TOP SUPPORTERS renderer into R4 after cosmetic polish, preserving subscriptions with non-nil reparent and restoring original parent/pivot before failed-build teardown. Remove only exact requested mounted revision plaque creation.")

(ROOT / "candidate-manifest.json").write_text(json.dumps({
    "studioId": "c1e8b040-e549-408a-8a5b-7fe6905c2d55",
    "placeId": 131311258779917,
    "universeId": 10559217407,
    "status": "Drafted locally; no Studio write",
    "requiredCAS": "Root must resolve exact instance/class and compare current Source plus ScriptEditorService:GetEditorSource against exact baseline file inside scoped UpdateSourceAsync before write; changed baselines require fresh reconciliation.",
    "changes": changes,
}, indent=2) + "\n")
print("Drafted", len(changes), "scoped candidates")
