"""Card 81: the dev-only FREE RESPAWN action inside both respawn offers.

Runs the production PARTY DOWN card block (RoundUI) and the production
EMERGENCY RE-ENTRY modal (ZyntraStore) in offline Luau, once as a whitelisted
developer and once as an ordinary player. Rendering, hit testing and the server
gate (GameManager/DevAccess) need Studio. Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_reentry_dismissal import SETUP as MODAL_SETUP, section  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
STORE = ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua"
ROUNDUI = ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"


MODAL_EXTRA = r'''
local devAllowed = DEV
local UIDevice = {SetEnabled = function(element, enabled) element.Active = enabled end}
local commands = {}
local bindable = {IsA = function(_, class) return class == 'BindableEvent' end,
    Fire = function(_, command) table.insert(commands, command) end}
local playerScripts = {FindFirstChild = function(_, name)
    return name == 'DevCheatCommand' and bindable or nil
end}
function player:FindFirstChild(name) return name == 'PlayerScripts' and playerScripts or nil end
'''

MODAL_TESTS = r'''
local free, decline
for _, obj in ipairs(objects) do
    if obj.Name == 'ReentryFreeRespawn' then free = obj end
    if obj.Name == 'ReentryDecline' then decline = obj end
end
assert(decline, 'SPECTATE control still exists')
if not DEV then
    expect(free, nil, 'ordinary player gets no free respawn control')
    expect(decline.Position[2], 156, 'ordinary layout unchanged')
    expect(reentry.Size[4], 216, 'ordinary modal height unchanged')
else
    assert(free, 'developer gets the free respawn control')
    expect(free.Position[2], 156, 'free control sits where SPECTATE used to')
    expect(decline.Position[2], 208, 'SPECTATE moves below the free control')
    expect(reentry.Size[4], 268, 'developer modal grows by one row')
    expect(reentryConstraint.MinSize[2], 268, 'size floor follows the modal')
    expect(free.Text, 'FREE RESPAWN  //  DEV', 'idle caption')
    expect(free.Active, true, 'idle control is pressable')
    free.Activated:Fire()
    expect(#commands, 0, 'hidden modal ignores the free control')
    player:SetAttribute('InRound', true)
    workspace:SetAttribute('RoundActive', true)
    local humanoid = {Health = 100, Died = signal()}
    local character = {WaitForChild = function(_, name) return humanoid end}
    player.Character = character
    player.CharacterAdded:Fire(character)
    humanoid.Health = 0
    humanoid.Died:Fire()
    expect(reentryGui.Enabled, true, 'death opens the offer')
    free.Activated:Fire()
    expect(#commands, 1, 'free control dispatches exactly once')
    expect(commands[1], 'freeRespawn', 'dispatches the existing DEV command')
    expect(#actions, 0, 'free respawn spends no credit')
    expect(#purchases, 0, 'free respawn prompts no purchase')
    player:SetAttribute('DevRespawnBusy', true)
    expect(free.Text, 'RESPAWNING...', 'busy caption while the server works')
    expect(free.Active, false, 'busy control leaves the input stack')
    free.Activated:Fire()
    expect(#commands, 1, 'busy control does not re-dispatch')
    player:SetAttribute('DevRespawnBusy', nil)
    expect(free.Active, true, 'control returns when the server answers')
    player:SetAttribute('ZyntraReentryUsed', true)
    updateReentry()
    expect(reentryGui.Enabled, false, 'used paid re-entry still hides the whole offer')
end
print('Free respawn offer (modal, dev=' .. tostring(DEV) .. '): ' .. checks .. ' checks passed')
'''


def run(binary, directory, name, chunks):
    fixture = Path(directory) / name
    fixture.write_text('\n'.join(chunks), encoding='utf-8')
    subprocess.run([binary, str(fixture)], check=True, timeout=30)


def main():
    binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary:
        raise SystemExit('Set LUAU_BIN or install luau; no tests were executed.')
    store = STORE.read_text(encoding='utf-8')
    state = section(store, 'local reentryDead = false', 'local COLORS =')
    modal = section(store, 'player:SetAttribute("ZyntraReentryOpen", nil)',
                    'local function refreshUI()')
    modal_extra = MODAL_EXTRA.replace("local UIDevice", "COLORS.accent = 'accent'\nlocal UIDevice")
    with tempfile.TemporaryDirectory(prefix='free-respawn-offer-') as directory:
        for dev in ('true', 'false'):
            run(binary, directory, f'modal_{dev}.luau',
                [f'local DEV = {dev}', MODAL_SETUP, modal_extra, state, modal, MODAL_TESTS])
    from test_hud_b8 import main as verify_b8
    verify_b8()


if __name__ == '__main__':
    main()
