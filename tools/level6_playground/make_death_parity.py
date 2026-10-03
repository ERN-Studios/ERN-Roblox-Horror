"""Level 6 deaths behave like a death in any round (owner, 2026-10-03): the body stays in the level, the
player spectates living teammates, the PARTY DOWN card offers Emergency Re-entry, and only a wipe (or the
player's own choice) sends them to the lobby.

    python3 tools/level6_playground/make_death_parity.py [--check]

Level 6 runs on the lobby server, so `workspace.RoundActive` must stay false there (Daily Rewards, the Lucky
Wheel, the Friend Boost chip and the Mimic all key on it for LOBBY players). Each gate below therefore
accepts the player attribute `Level6PlaygroundPreview` next to `RoundActive`. Exact, counted, re-runnable.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(Path(__file__).parent))
import import_to_studio as studio_io

L6 = 'player:GetAttribute("Level6PlaygroundPreview") == true'
SPS = 'StarterPlayer.StarterPlayerScripts.'
REENTRY = ('zyntraReentry.OnInvoke = function(player, free) local l6 = ServerStorage:FindFirstChild("Level6Reentry") '
           'if l6 and typeof(player) == "Instance" and player:GetAttribute("Level6PlaygroundPreview") == true '
           'then return l6:Invoke(player, free) end return false end')
# (studio path, repo path, [(old, new, expected count)])
EDITS = [
    ('ServerScriptService.GameManager', 'ServerScriptService/GameManager.Script.lua', [
        # outside its own rounds the re-entry function hands a Level 6 player to the level
        ('zyntraReentry.OnInvoke = function() return false end', REENTRY, 6),
        # a Level 6 body that dies stays dead in the level: the level owns what happens next
        ('''  if not inRound[player] then
   task.delay(3, function()
    if player.Parent and not inRound[player] then loadLobbyCharacter(player) end''',
         '''  if not inRound[player] and player:GetAttribute("Level6PlaygroundPreview") ~= true then
   task.delay(3, function()
    if player.Parent and not inRound[player] and player:GetAttribute("Level6PlaygroundPreview") ~= true then loadLobbyCharacter(player) end''', 1),
    ]),
    ('ServerScriptService.Level6PreviewAccess', 'ServerScriptService/Level6PreviewAccess.Script.lua', [
        ('''	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.Died:Once(function() Runtime.Leave(player, true) end) end
''', '', 1),
        ('''	humanoid.Died:Once(function() Runtime.Leave(player, true) end)
''', '', 1),
        ('''	Playground.RemovePlayer(player)
	if was and not died and player.Parent == Players then''',
         '''	Playground.RemovePlayer(player)
	if was and player.Parent == Players then
		-- the same word GameManager sends a player it stands back up in the lobby: RoundUI clears its round state on it
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local status = remotes and remotes:FindFirstChild("RoundStatus")
		if status then status:FireClient(player, "lobby") end
	end
	if was and not died and player.Parent == Players then''', 1),
        ('''-- A live level is played in the round body:''',
         '''-- Back to lobby from inside the level (the exit chip and the spectate band's button send this on the round
-- remote; GameManager only answers it inside its own rounds).
do
	local status = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
	status.OnServerEvent:Connect(function(player, message)
		if message == "leaveround" and player:GetAttribute(IN_PREVIEW) == true then
			status:FireClient(player, "leaveack")
			Runtime.Leave(player)
		end
	end)
end
-- A live level is played in the round body:''', 1),
    ]),
    ('ServerScriptService.ZyntraMonetization', 'ServerScriptService/ZyntraMonetization.Script.lua', [
        ('''	if player:GetAttribute("InRound") ~= true then return false end
	if workspace:GetAttribute("RoundActive") ~= true then return false end
	if player:GetAttribute("ZyntraReentryUsed") == true then return false end''',
         '''	if player:GetAttribute("InRound") ~= true then return false end
	if workspace:GetAttribute("RoundActive") ~= true
		and player:GetAttribute("Level6PlaygroundPreview") ~= true then return false end   -- Level 6 runs on the lobby server
	if player:GetAttribute("ZyntraReentryUsed") == true then return false end''', 1),
    ]),
    (SPS + 'SpectateController', 'StarterPlayer/StarterPlayerScripts/SpectateController.LocalScript.lua', [
        ('''	if spectating or not workspace:GetAttribute("RoundActive") then return end''',
         '''	if spectating or not (workspace:GetAttribute("RoundActive") or %s) then return end''' % L6, 1),
        ('''		if p ~= player and p:GetAttribute("Escaped") ~= true then''',
         '''		-- In Level 6 (lobby server) only the others in the level, never somebody standing in the lobby.
		if p ~= player and p:GetAttribute("Escaped") ~= true
			and (player:GetAttribute("Level6PlaygroundPreview") ~= true
				or p:GetAttribute("Level6PlaygroundPreview") == true) then''', 1),
    ]),
    (SPS + 'ZyntraStore', 'StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua', [
        ('''	local roundActive = workspace:GetAttribute("RoundActive") == true
	local used = player:GetAttribute("ZyntraReentryUsed") == true''',
         '''	local roundActive = workspace:GetAttribute("RoundActive") == true or %s
	local used = player:GetAttribute("ZyntraReentryUsed") == true''' % L6, 1),
    ]),
    (SPS + 'RoundUI', 'StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua', [
        ('''		local eligible = player:GetAttribute("InRound") == true
			and workspace:GetAttribute("RoundActive") == true
			and player:GetAttribute("ZyntraReentryUsed") ~= true''',
         '''		local eligible = player:GetAttribute("InRound") == true
			and (workspace:GetAttribute("RoundActive") == true or %s)
			and player:GetAttribute("ZyntraReentryUsed") ~= true''' % L6, 1),
        ('''				and player:GetAttribute("InRound") == true
				and workspace:GetAttribute("RoundActive") == true
			pd.free.Selectable = pd.free.Active''',
         '''				and player:GetAttribute("InRound") == true
				and (workspace:GetAttribute("RoundActive") == true or %s)
			pd.free.Selectable = pd.free.Active''' % L6, 1),
    ]),
    (SPS + 'Round Exit Client', 'StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua', [
        ('''	return player:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true
		and alive()''',
         '''	return player:GetAttribute("InRound") == true
		and (workspace:GetAttribute("RoundActive") == true or %s)
		and alive()''' % L6, 1),
        ('''	if shade.Visible or player:GetAttribute("InRound") ~= true
		or workspace:GetAttribute("RoundActive") ~= true then return end''',
         '''	if shade.Visible or player:GetAttribute("InRound") ~= true
		or not (workspace:GetAttribute("RoundActive") == true or %s) then return end''' % L6, 1),
    ]),
]

LUAU = '''
local path, edits, dry = %s, game:GetService("HttpService"):JSONDecode(%s), %s
local scr = game
for seg in string.gmatch(path, "[^.]+") do scr = scr[seg] end
local src = scr.Source
local function count(h, n) local k, i = 0, 1 while true do local s, e = string.find(h, n, i, true) if not s then break end k += 1 i = e + 1 end return k end
local function swap(h, n, r) local s, e = string.find(h, n, 1, true) return string.sub(h, 1, s - 1) .. r .. string.sub(h, e + 1) end
for i, edit in ipairs(edits) do
	local old, new, expected = edit[1], edit[2], edit[3]
	local have = count(src, old)
	if new ~= "" and count(src, new) >= 1 and (have == 0 or string.find(new, old, 1, true)) then continue end -- applied
	if new == "" and have == 0 then continue end
	if have ~= expected then error(path .. ": edit " .. i .. " found " .. have .. " times, expected " .. expected) end
	for _ = 1, expected do src = swap(src, old, new) end
end
if src ~= scr.Source then
	if dry then return "would change" end
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
        print(studio_path, '->', s.luau(LUAU % (json.dumps(studio_path), json.dumps(json.dumps(edits)), 'true' if dry else 'false')))
        if dry:
            continue
        f = ROOT / repo_path
        text = f.read_bytes().decode()
        for old, new, expected in edits:
            if (new != '' and new in text and (old not in text or old in new)) or (new == '' and old not in text):
                continue
            if text.count(old) != expected:
                print(f'   repo copy differs: {repo_path} (edit not mirrored)')
                continue
            text = text.replace(old, new)
        f.write_bytes(text.encode())


main()
