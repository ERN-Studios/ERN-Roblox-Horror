"""Make Level 6 play like a live round (2026-10-03, owner: "the normal stage when a level is live").

    python3 tools/level6_playground/make_live.py

Level 6 runs outside GameManager's rounds, on the lobby server. These exact, counted edits give its players
the round body and state: the hazmat StarterCharacter (through GameManager's own serialized loaders, exposed
as ServerStorage.LoadGameplayCharacter / LoadLobbyCharacter), InRound = true (first person with the C toggle,
flashlight, sprint, lobby HUD hidden), crouch and skin visuals without workspace.RoundActive, and keeps
Level 1's ambience and round footsteps out. Each edit is applied in Studio (UpdateSourceAsync) and to the
repo copy; an edit whose old text is not found exactly once stops the run.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(Path(__file__).parent))
import import_to_studio as studio_io

P = 'player:GetAttribute("Level6PlaygroundPreview")'
SPS = 'StarterPlayer.StarterPlayerScripts.'
EDITS = [
    # --- GameManager: loaders for a level that runs outside its rounds, and no lobby treatment for its body
    ('ServerScriptService.GameManager', 'ServerScriptService/GameManager.Script.lua', [
        (''' if not ok then warn("[GameManager] Gameplay character load failed:", err) end
 return ok
end
''', ''' if not ok then warn("[GameManager] Gameplay character load failed:", err) end
 return ok
end

do -- Level 6 runs outside this script's rounds but wears the round body: same two loads, same gate.
 local function expose(name, handler)
  local old = ServerStorage:FindFirstChild(name)
  if old then old:Destroy() end
  local bindable = Instance.new("BindableFunction")
  bindable.Name = name
  bindable.OnInvoke = handler
  bindable.Parent = ServerStorage
 end
 expose("LoadGameplayCharacter", function(player)
  if typeof(player) ~= "Instance" or not player:IsA("Player") or inRound[player] then return false end
  return loadGameplayCharacter(player, function() return player.Parent == Players and not inRound[player] end)
 end)
 expose("LoadLobbyCharacter", function(player)
  if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
  return loadLobbyCharacter(player)
 end)
end
'''),
        ('''local function onCharacter(player, char)
 if inRound[player] then
''', '''local function onCharacter(player, char)
 if inRound[player] or %s == true then
''' % P),
        ('''  else
   scatterAt(char, lobbySpawn, false)
  end
''', '''  elseif %s ~= true then -- Level 6 places its own round body
   scatterAt(char, lobbySpawn, false)
  end
''' % P),
    ]),
    # --- Level6PreviewAccess: round body and InRound on entry, lobby avatar on the way out
    ('ServerScriptService.Level6PreviewAccess', 'ServerScriptService/Level6PreviewAccess.Script.lua', [
        ('''local HttpService = game:GetService("HttpService")
''', '''local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
'''),
        ('''function Runtime.Leave(player)
	player:SetAttribute(IN_PREVIEW, nil)
	Playground.RemovePlayer(player)
end
function Runtime.Join(player)
	player:SetAttribute(IN_PREVIEW, true)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.Died:Once(function() Runtime.Leave(player) end) end
''', '''function Runtime.Leave(player, died)
	local was = player:GetAttribute(IN_PREVIEW) == true
	player:SetAttribute(IN_PREVIEW, nil)
	if was then player:SetAttribute("InRound", false) end
	Playground.RemovePlayer(player)
	if was and not died and player.Parent == Players then
		-- Back into the player's own avatar at the lobby spawn. A death is respawned by GameManager.
		task.spawn(function()
			local load = ServerStorage:FindFirstChild("LoadLobbyCharacter")
			if load then pcall(load.Invoke, load, player) end
		end)
	end
end
function Runtime.Join(player)
	player:SetAttribute(IN_PREVIEW, true)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.Died:Once(function() Runtime.Leave(player, true) end) end
'''),
        ('''assert(transport:IsA("RemoteEvent"), "Level6PreviewTransport has wrong class")
''', '''assert(transport:IsA("RemoteEvent"), "Level6PreviewTransport has wrong class")
-- A live level is played in the round body: the hazmat StarterCharacter with InRound set, which is what
-- the first-person camera and its C toggle, the flashlight, sprint and the hidden lobby HUD all key on.
function Runtime.Suit(player, frame)
	if player.Parent ~= Players or player:GetAttribute(IN_PREVIEW) ~= true then return end
	player:SetAttribute("InRound", true)
	local load = ServerStorage:FindFirstChild("LoadGameplayCharacter")
	local previous = player.Character
	local ok, loaded = pcall(function() return load ~= nil and load:Invoke(player) end)
	local character = player.Character
	if player.Parent ~= Players or player:GetAttribute(IN_PREVIEW) ~= true then return end
	if not ok or not loaded or not character or character == previous then
		warn("[Level6PreviewAccess] round character did not load for " .. player.Name .. ": " .. tostring(loaded))
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root or player:GetAttribute(IN_PREVIEW) ~= true then return end
	root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(frame)
	humanoid.Died:Once(function() Runtime.Leave(player, true) end)
	transport:FireClient(player, "ArrivalFacing", frame, MODEL_NAME)
end
'''),
        ('''		or player:GetAttribute("InRound") == true
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
''', '''		or (player:GetAttribute("InRound") == true and player:GetAttribute(IN_PREVIEW) ~= true)
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
'''),
        ('''		transport:FireClient(player, "ArrivalFacing", upright(exit.CFrame), MODEL_NAME)
	end)
''', '''		transport:FireClient(player, "ArrivalFacing", upright(exit.CFrame), MODEL_NAME)
		task.spawn(Runtime.Suit, player, upright(exit.CFrame))
	end)
'''),
        ('''    return bridge.CommitPreviewGroup(context, entries, function(entry)
     local joined, reason = Runtime.Join(entry.player)
     if joined then transport:FireClient(entry.player, "ArrivalFacing", entry.frame, MODEL_NAME) end
     return joined, reason
    end, function(entry) Runtime.Leave(entry.player) end)
''', '''    local committed, commitProblem = bridge.CommitPreviewGroup(context, entries, function(entry)
     local joined, reason = Runtime.Join(entry.player)
     if joined then transport:FireClient(entry.player, "ArrivalFacing", entry.frame, MODEL_NAME) end
     return joined, reason
    end, function(entry) Runtime.Leave(entry.player) end)
    -- The queue validates each member's lobby character through the commit, so the round body goes on after it.
    if committed then
     for _, entry in ipairs(entries) do task.spawn(Runtime.Suit, entry.player, entry.frame) end
    end
    return committed, commitProblem
'''),
    ]),
    ('ServerScriptService.HazmatSkinVisuals', 'ServerScriptService/HazmatSkinVisuals.Script.lua', [
        ('''	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or workspace:GetAttribute("RoundActive") ~= true
''', '''	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or (workspace:GetAttribute("RoundActive") ~= true and %s ~= true)
''' % P),
    ]),
    ('ServerScriptService.Crouch State Server', 'ServerScriptService/Crouch State Server.Script.lua', [
        ('''		else player:GetAttribute("InRound") == true and workspace:GetAttribute("RoundActive") == true
''', '''		else player:GetAttribute("InRound") == true
			and (workspace:GetAttribute("RoundActive") == true or %s == true)
''' % P),
    ]),
    (SPS + 'HazmatSkinDriver', 'StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua', [
        ('''		if player:GetAttribute("InRound") ~= true
			or workspace:GetAttribute("RoundActive") ~= true then
''', '''		if player:GetAttribute("InRound") ~= true
			or (workspace:GetAttribute("RoundActive") ~= true and %s ~= true) then
''' % P),
    ]),
    (SPS + 'NoiseReporter', 'StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua', [
        ('''	if not movementAvailable() or workspace:GetAttribute(if inPreview() then "Level6RoundActive" else "RoundActive") ~= true then return false end
''', '''	if not movementAvailable() or (%s ~= true
		and workspace:GetAttribute(if inPreview() then "Level6RoundActive" else "RoundActive") ~= true) then return false end
''' % P),
        ('''		if inPreview() or not inRound() or (level ~= 1 and level ~= 2 and level ~= 4) then continue end
''', '''		if inPreview() or not inRound() or (level ~= 1 and level ~= 2 and level ~= 4)
			or %s == true then continue end -- nothing in the playground listens
''' % P),
    ]),
    (SPS + 'SoundController', 'StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua', [
        ('''		or (inRound and workspace:GetAttribute("SelectedLevel") ~= 2)) then
''', '''		or (inRound and workspace:GetAttribute("SelectedLevel") ~= 2
			and %s ~= true)) then -- Level 6 has its own steps
''' % P),
    ]),
    (SPS + 'Level 1 Sound Controller', 'StarterPlayer/StarterPlayerScripts/Level 1 Sound Controller.LocalScript.lua', [
        ('''	return (level == 1 or level == nil)
		and player:GetAttribute("InRound") == true
end
''', '''	return (level == 1 or level == nil)
		and player:GetAttribute("InRound") == true
		and %s ~= true -- the lobby server's SelectedLevel stays 1
end
''' % P),
    ]),
    # --- crouch looks and feels the same without workspace.RoundActive
    (SPS + 'EntityShakeController', 'StarterPlayer/StarterPlayerScripts/EntityShakeController.LocalScript.lua', [
        ('''	local isCrouching = not isHidden and player:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true
''', '''	local isCrouching = not isHidden and player:GetAttribute("InRound") == true
		and (workspace:GetAttribute("RoundActive") == true or %s == true)
''' % P),
    ]),
    (SPS + 'Level 3 Table Hiding Client', 'StarterPlayer/StarterPlayerScripts/Level 3 Table Hiding Client.LocalScript.lua', [
        ('''	local ordinaryCrouch = targetPlayer:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true
''', '''	local ordinaryCrouch = targetPlayer:GetAttribute("InRound") == true
		and (workspace:GetAttribute("RoundActive") == true
			or targetPlayer:GetAttribute("Level6PlaygroundPreview") == true)
'''),
    ]),
    # --- the level is live: its exit prompt no longer says DEV PREVIEW
    ('ServerScriptService.Level6PreviewAccess', 'ServerScriptService/Level6PreviewAccess.Script.lua', [
        ('''	if prompt:IsA("ProximityPrompt") and not hooked[prompt] then
''', '''	if prompt:IsA("ProximityPrompt") then prompt.ObjectText = "LEVEL 6" end
	if prompt:IsA("ProximityPrompt") and not hooked[prompt] then
'''),
    ]),
]

LUAU = '''
local path, edits = %s, game:GetService("HttpService"):JSONDecode(%s)
local scr = game
for seg in string.gmatch(path, "[^.]+") do scr = scr[seg] end
local src = scr.Source
local function count(h, n) local k, i = 0, 1 while true do local s, e = string.find(h, n, i, true) if not s then break end k += 1 i = e + 1 end return k end
local function swap(h, n, r) local s, e = string.find(h, n, 1, true) return string.sub(h, 1, s - 1) .. r .. string.sub(h, e + 1) end
for i, edit in ipairs(edits) do
	-- an edit whose new text contains its old text was once applied twice: undo the doubling
	local os_, oe = string.find(edit[2], edit[1], 1, true)
	if os_ then
		local twice = string.sub(edit[2], 1, os_ - 1) .. edit[2] .. string.sub(edit[2], oe + 1)
		while count(src, twice) > 0 do src = swap(src, twice, edit[2]) end
	end
	if count(src, edit[2]) >= 1 then continue end -- already applied
	local n = count(src, edit[1])
	if n ~= 1 then error(path .. ": edit " .. i .. " found " .. n .. " times") end
	local s, e = string.find(src, edit[1], 1, true)
	src = string.sub(src, 1, s - 1) .. edit[2] .. string.sub(src, e + 1)
end
if src ~= scr.Source then
	game:GetService("ScriptEditorService"):UpdateSourceAsync(scr, function() return src end)
	assert(scr.Source == src, "readback mismatch")
	return "written"
end
return "unchanged"
'''


def main():
    s = studio_io.Studio()
    dry = '--check' in sys.argv
    for studio_path, repo_path, edits in EDITS:
        if dry:
            code = LUAU.replace('game:GetService("ScriptEditorService"):UpdateSourceAsync(scr, function() return src end)', '').replace('assert(scr.Source == src, "readback mismatch")', '')
        else:
            code = LUAU
        print(studio_path, '->', s.luau(code % (json.dumps(studio_path), json.dumps(json.dumps(edits)))))
        if dry:
            continue
        f = ROOT / repo_path
        text = f.read_bytes().decode()
        nl = '\r\n' if '\r\n' in text else '\n'
        for old, new in edits:
            old, new = old.replace('\n', nl), new.replace('\n', nl)
            if old in new:
                twice = new.replace(old, new, 1)
                while twice in text:
                    text = text.replace(twice, new, 1)
            if text.count(new) >= 1:
                continue
            if text.count(old) != 1:
                print(f'   repo copy differs from Studio: {repo_path} (edit not mirrored)')
                continue
            text = text.replace(old, new)
        f.write_bytes(text.encode())


main()
