"""Exercise production audio gates for escaped spectators in offline Luau."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'StarterPlayer/StarterPlayerScripts'


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def main():
    l1 = (SCRIPTS / 'SoundController.LocalScript.lua').read_text(encoding='utf-8')
    l2 = (SCRIPTS / 'Level 2 Sound Controller.LocalScript.lua').read_text(encoding='utf-8')
    l3 = (SCRIPTS / 'Level 3 Sound Controller.LocalScript.lua').read_text(encoding='utf-8')
    code = '''
local count = 0
local function check(actual, expected)
 count += 1
 assert(actual == expected, 'check '..count..': '..tostring(actual)..' != '..tostring(expected))
end
local own = {InRound=true, Escaped=true}
local world = {SelectedLevel=2, RoundActive=true, WorldGenerated=true}
local player = {GetAttribute=function(_, key) return own[key] end}
local workspace = {
 GetAttribute=function(_, key) return world[key] end,
 FindFirstChild=function() return {} end,
}
local target = {}
local function spectateSubject() return target end
local function rootPart() return {} end
local ambientWorld = {GetAttribute=function() return 1 end}
local groanRecord = {Owner={Parent=true}, Sound={Parent=true}, World=ambientWorld,
 Generation=1}
-- LEVEL2_GROAN_OWNERSHIP_20260921: the distant groan no longer has a body form;
-- it stands down wholesale when the entity audio client owns the voice.
local function entityAudioOwnsBody() return false end
local function stateFolder() return nil end
local LEVEL=3
local played=0
local function playPowerDown() played += 1 end
local function generationMatches() return false end
'''
    code += section(l1, 'local function chaseActive()', 'local lastSpotScreamAt')
    code += section(l2, 'local function participantActive()', 'local function active()')
    code += section(l2, 'local function active()', '\nend') + '\nend\n'
    code += section(l2, 'local function randomActive()', '\nend') + '\nend\n'
    code += section(l2, 'local function groanPlaybackStillValid(record)', 'local function playMonsterGroan')
    code += section(l3, 'local function isActive()', '-- The listener body')
    code += section(l3, 'local function handleClientEvent(', 'local function bindClientEvent')
    code += '''
check(active(), true)
check(randomActive(), true)
check(groanPlaybackStillValid(groanRecord), true)
target=nil
check(active(), false)
check(randomActive(), false)
check(groanPlaybackStillValid(groanRecord), false)
own.Level2_ExitTransition=true
world.RoundActive=false
check(active(), true) -- original exit-ride ambience survives round completion
check(randomActive(), false)
own.Level2_ExitTransition=nil
world.RoundActive=true
target={}
world.SelectedLevel=1
check(chaseActive(), true)
target=nil
check(chaseActive(), false)
own.Escaped=false
check(chaseActive(), true)
world.RoundActive=false
check(chaseActive(), false)
world.SelectedLevel=3
own.Escaped=true
target={}
check(isActive(), true)
handleClientEvent({Type='Sound', Cue='PowerDown'})
check(played, 1)
target=nil
check(isActive(), false)
handleClientEvent({Type='Sound', Cue='PowerDown'})
check(played, 1)
own.Escaped=false
handleClientEvent({Type='Sound', Cue='PowerDown'})
check(played, 2)
world.SelectedLevel=1
handleClientEvent({Type='Sound', Cue='PowerDown'})
check(played, 2)
print('Spectate audio gates: '..count..' checks passed (offline Luau)')
'''
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'gates.luau'
        path.write_text(code, encoding='utf-8')
        subprocess.run([os.environ['LUAU_BIN'], str(path)], check=True)


if __name__ == '__main__':
    main()
