"""The teammate death scream plays in Level 1 rounds only (owner, 2026-10-05).

Runs SoundController's real "death" handler in offline Luau with a fake engine.
Needs LUAU_BIN.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua'


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def main():
    sound = SOURCE.read_text(encoding='utf-8')
    code = '''
local world = {SelectedLevel=1}
local own = {}
local workspace = {GetAttribute=function(_, key) return world[key] end}
local player = {Name='Listener', GetAttribute=function(_, key) return own[key] end}
local sounds = {}
local Instance = {new=function(class)
 local object = {ClassName=class, Ended={Connect=function() end}}
 function object:Play() table.insert(sounds, self) end
 function object:Destroy() end
 return object
end}
local Vector3 = {new=function() return {} end}
local CFrame = {new=function() return {} end}
local Enum = {RollOffMode={InverseTapered='InverseTapered', Linear='Linear'}}
local task = {delay=function() end}
local function typeof() return 'Vector3' end
local handler
local remote = {OnClientEvent={Connect=function(_, fn) handler = fn end}}
local RS = {WaitForChild=function() return {WaitForChild=function() return remote end} end}
local DEATH_SOUND = 'rbxassetid://113822157484898'
local DEATH_VOLUME = .5
local alive = true
local function audioSubject() return alive end
'''
    code += section(sound, '-- death audio:', '-- the elevator sound')
    code += '''
local function heard(level, marker)
 table.clear(sounds)
 world.SelectedLevel = level
 own.Level6PlaygroundPreview = marker
 handler('death', 'Other', {})
 return #sounds
end
assert(heard(1) == 1, 'Level 1 death must scream')
assert(sounds[1].RollOffMaxDistance == 96, 'Level 1 scream stays local to the kill')
assert(heard(2) == 0, 'Level 2 death must be silent')
assert(heard(3) == 0, 'Level 3 death must be silent')
assert(heard(4) == 0, 'Level 4 death must be silent')
assert(heard(nil) == 0, 'no level must be silent')
assert(heard(1, true) == 0, 'Level 5/6 on the lobby server (SelectedLevel 1) must be silent')
table.clear(sounds); world.SelectedLevel = 1; own.Level6PlaygroundPreview = nil
handler('death', 'Listener', {})
assert(#sounds == 0, 'own death is on the Jumpscare remote')
alive = false
assert(heard(1) == 0, 'dead listeners hear nothing')
print('death scream level gate: ok')
'''
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'death_scream.luau'
        path.write_text(code, encoding='utf-8')
        subprocess.run([os.environ['LUAU_BIN'], str(path)], check=True)


if __name__ == '__main__':
    main()
