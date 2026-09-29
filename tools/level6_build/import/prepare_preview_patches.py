"""Produce reviewable narrow shared-client changes from the fresh native snapshot.

No Studio writes. Installer must recheck live Source and editorSource against
each exact baseline SHA before applying these candidates.
"""
import hashlib
import json
import pathlib

base = pathlib.Path(__file__).resolve().parents[3]
snapshot = base / 'artifacts/level6-build-20260930/native-backup/scripts.json'
records = {x['path']: x for x in json.loads(snapshot.read_text())}
out = pathlib.Path(__file__).parent / 'shared-candidates'
out.mkdir(exist_ok=True)
patches = []

def replace_once(source, before, after):
    assert source.count(before) == 1, (before, source.count(before))
    return source.replace(before, after)

def save(path, source):
    original = records[path]
    assert original['editorMatch']
    filename = path.replace('.', '__') + '.' + original['class'] + '.luau'
    (out / filename).write_text(source)
    patches.append({'path': path, 'class': original['class'], 'candidate': filename,
        'beforeSha256': hashlib.sha256(original['source'].encode()).hexdigest(),
        'afterSha256': hashlib.sha256(source.encode()).hexdigest(),
        'baseline': str(snapshot.relative_to(base))})

path = 'StarterPlayer.StarterPlayerScripts.NoiseReporter'
s = records[path]['source']
s = s.replace('player:GetAttribute("Level3_Hiding") == true', 'isHiding()')
s = s.replace('player:GetAttribute("Level3_Hiding") ~= true', 'not isHiding()')
s = s.replace('player:GetAttribute("Escaped") == true', 'isEscaped()')
s = s.replace('player:GetAttribute("Escaped") ~= true', 'not isEscaped()')
s = replace_once(s, 'local function inRound() return player:GetAttribute("InRound") == true end', '''-- Level6 preview participates in local movement only; public progression attributes stay untouched.
local function inPreview() return devAllowed and player:GetAttribute("Level6InRound") == true end
local function inRound() return player:GetAttribute("InRound") == true or inPreview() end
local function isHiding()
\treturn player:GetAttribute(if inPreview() then "Level6_Hiding" else "Level3_Hiding") == true
end
local function isEscaped()
\treturn player:GetAttribute(if inPreview() then "Level6Escaped" else "Escaped") == true
end''')
s = replace_once(s, 'if not inRound() or isHiding()\n\t\tor os.clock() - lastGlowstickDrop', 'if inPreview() or not inRound() or isHiding()\n\t\tor os.clock() - lastGlowstickDrop')
s = replace_once(s, 'local function staminaMax()\n', 'local function staminaMax()\n\tif inPreview() then return STAMINA_BASE end\n')
s = replace_once(s, 'local function chaseActive()\n', 'local function chaseActive()\n\tif inPreview() then return player:GetAttribute("Level6BeingChased") == true end\n')
s = replace_once(s, 'player:GetAttributeChangedSignal("BeingChased"):Connect(updateChaseAdrenaline)', 'player:GetAttributeChangedSignal("BeingChased"):Connect(updateChaseAdrenaline)\nplayer:GetAttributeChangedSignal("Level6BeingChased"):Connect(updateChaseAdrenaline)\nplayer:GetAttributeChangedSignal("Level6InRound"):Connect(updateChaseAdrenaline)')
s = replace_once(s, 'if not movementAvailable() or workspace:GetAttribute("RoundActive") ~= true then return false end', 'if not movementAvailable() or workspace:GetAttribute(if inPreview() then "Level6RoundActive" else "RoundActive") ~= true then return false end')
s = replace_once(s, 'function speedBoost()\n\tif not inRound() then return 1 end', 'function speedBoost()\n\tif inPreview() or not inRound() then return 1 end')
s = replace_once(s, 'if not inRound() or (level ~= 1 and level ~= 2) then continue end', 'if inPreview() or not inRound() or (level ~= 1 and level ~= 2) then continue end')
s = replace_once(s, 'if os.clock() - lastVitalReport >= .25 then', 'if not inPreview() and os.clock() - lastVitalReport >= .25 then')
s = replace_once(s, 'UIDevice.SetInteractive(touchGlowButton, usable)', 'UIDevice.SetInteractive(touchGlowButton, usable and not inPreview())')
s = replace_once(s, 'player:GetAttributeChangedSignal("InRound"):Connect(updateRoundState)', 'player:GetAttributeChangedSignal("InRound"):Connect(updateRoundState)\nplayer:GetAttributeChangedSignal("Level6InRound"):Connect(updateRoundState)')
s = replace_once(s, '{"Escaped", "Level3_Hiding", "Spectating",', '{"Escaped", "Level3_Hiding", "Level6Escaped", "Level6_Hiding", "Spectating",')
save(path, s)

path = 'StarterPlayer.StarterPlayerScripts.LobbyMusicController'
s = records[path]['source']
s = replace_once(s, 'and player:GetAttribute("InRound") ~= true', 'and player:GetAttribute("InRound") ~= true\n\t\tand player:GetAttribute("Level6InRound") ~= true')
s = replace_once(s, 'player:GetAttributeChangedSignal("InRound"):Connect(beginMusicIfReady)', 'player:GetAttributeChangedSignal("InRound"):Connect(beginMusicIfReady)\nplayer:GetAttributeChangedSignal("Level6InRound"):Connect(beginMusicIfReady)')
save(path, s)

path = 'ServerScriptService.Crouch State Server'
s = records[path]['source']
s = replace_once(s, 'local ReplicatedStorage = game:GetService("ReplicatedStorage")', 'local ReplicatedStorage = game:GetService("ReplicatedStorage")\nlocal DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))')
s = replace_once(s, 'local function characterAllowsCrouch(player: Player): boolean\n', '''local function characterAllowsCrouch(player: Player): boolean
\tlocal preview = player:GetAttribute("Level6InRound") == true and DevAccess.IsAllowed(player)
\tlocal participating = if preview then workspace:GetAttribute("Level6RoundActive") == true
\t\telse player:GetAttribute("InRound") == true and workspace:GetAttribute("RoundActive") == true
''')
s = replace_once(s, 'or player:GetAttribute("InRound") ~= true\n\t\tor workspace:GetAttribute("RoundActive") ~= true', 'or not participating')
s = replace_once(s, 'or player:GetAttribute("Escaped") == true', 'or player:GetAttribute(if preview then "Level6Escaped" else "Escaped") == true')
s = replace_once(s, 'or player:GetAttribute("Level3_Hiding") == true then', 'or player:GetAttribute(if preview then "Level6_Hiding" else "Level3_Hiding") == true then')
s = replace_once(s, '{"InRound", "Escaped", "Spectating", "Level3_Hiding"}', '{"InRound", "Escaped", "Spectating", "Level3_Hiding", "Level6InRound", "Level6Escaped", "Level6_Hiding"}')
s = replace_once(s, '''workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
\tif workspace:GetAttribute("RoundActive") == true then return end
\tfor _, player in ipairs(Players:GetPlayers()) do setCrouching(player, false) end
end)''', '''local function clearUnavailableCrouches()
\tfor _, player in ipairs(Players:GetPlayers()) do
\t\tif not characterAllowsCrouch(player) then setCrouching(player, false) end
\tend
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(clearUnavailableCrouches)
workspace:GetAttributeChangedSignal("Level6RoundActive"):Connect(clearUnavailableCrouches)''')
save(path, s)

path = 'StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt'
s = records[path]['source']
s = replace_once(s, '\tLevel5DeveloperPreviewReturnPrompt = true,', '\tLevel5DeveloperPreviewReturnPrompt = true,\n\tLevel6DeveloperPreviewPrompt = true,\n\tLevel6DeveloperPreviewReturnPrompt = true,')
s = s.replace('Level 4 and Level 5 developer preview prompts', 'Level 4, Level 5 and Level 6 developer preview prompts', 1)
save(path, s)
(out / 'patch-manifest.json').write_text(json.dumps(patches, indent=2) + '\n')
print(json.dumps(patches, indent=2))
