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


CARD_SETUP = r'''
local DEV = DEV
local checks = 0
local function expect(actual, expected, message)
    checks += 1
    assert(actual == expected, message .. ': expected ' .. tostring(expected)
        .. ', got ' .. tostring(actual))
end
local function signal()
    local callbacks = {}
    return {
        Connect = function(_, callback)
            table.insert(callbacks, callback)
            return {Disconnect = function() end}
        end,
        Fire = function(_, ...)
            for _, callback in ipairs(callbacks) do callback(...) end
        end,
    }
end
local function attributed()
    local values, signals = {}, {}
    return {
        GetAttribute = function(_, key) return values[key] end,
        GetAttributeChangedSignal = function(_, key)
            signals[key] = signals[key] or signal()
            return signals[key]
        end,
        SetAttribute = function(_, key, value)
            if values[key] == value then return end
            values[key] = value
            if signals[key] then signals[key]:Fire() end
        end,
    }
end
local objects = {}
local function object(class)
    local obj = {ClassName = class, Activated = signal(), Visible = true, Active = true,
        Selectable = true, Text = ''}
    table.insert(objects, obj)
    return obj
end
local Instance = {new = object}
local UDim2 = {new = function(...) return {...} end,
    fromScale = function(...) return {...} end, fromOffset = function(...) return {...} end}
local UDim = {new = function(...) return {...} end}
local Vector2 = {new = function(...) return {...} end}
local Color3 = {fromRGB = function(...) return {...} end}
local Enum = {Font = {GothamBlack = 'GothamBlack', Code = 'Code', GothamBold = 'GothamBold', GothamMedium = 'GothamMedium'},
    TextXAlignment = {Left = 'Left'}, TextYAlignment = {Top = 'Top'}, TextTruncate = {AtEnd = 'AtEnd'},
    EasingStyle = {Quad = 'Quad'}}  -- the death-cause card now shares the extracted range
local GuiService = {}
local purchases = {}
local MarketplaceService = {PromptProductPurchase = function(_, _, id) table.insert(purchases, id) end}
local game = {GetService = function(_, name)
    if name == 'GuiService' then return GuiService end
    if name == 'MarketplaceService' then return MarketplaceService end
    error('Unexpected service: ' .. name)
end}
local now = 100
local os = {clock = function() return now end}
local player, workspace = attributed(), attributed()
player.Name = 'Tester'
local RS = {FindFirstChild = function(_, name)
    return name == 'DevAccess' and {IsAllowed = function() return DEV end} or nil
end}
local function require(module) assert(module, 'require(nil)') return module end
local UIDevice = {Layout = function() return {Height = 720} end, Changed = signal(),
    LastInput = function() return 'Keyboard' end}
local RunService = {RenderStepped = signal(), IsStudio = function() return false end}
local remote = {OnClientEvent = signal()}
local actions = {}
local dispatchAudio = {accent = 'accent', action = {FireServer = function(_, action)
    table.insert(actions, action)
end}}
local gui = object('ScreenGui')
local label = {Text = ''}
local messages = {}
local function setMsg(text) table.insert(messages, text) end
local commands = {}
local bindable = {IsA = function(_, class) return class == 'BindableEvent' end,
    Fire = function(_, command) table.insert(commands, command) end}
local script = {Parent = {FindFirstChild = function(_, name)
    return name == 'DevCheatCommand' and bindable or nil
end}}
'''

CARD_TESTS = r'''
local card, free, decline, reentry, frame
for _, obj in ipairs(objects) do
    if obj.Name == 'PartyDownCard' then card = obj end
    if obj.Name == 'PartyDownFreeRespawn' then free = obj end
    if obj.Name == 'PartyDownDecline' then decline = obj end
    if obj.Name == 'PartyDownReentry' then reentry = obj end
    if obj.Name == 'PartyDownOverlay' then frame = obj end
end
assert(card and decline and reentry and frame, 'production card parts exist')
local function step() RunService.RenderStepped:Fire() end
if not DEV then
    expect(free, nil, 'ordinary player gets no free respawn button')
    expect(card.Size[4], 268, 'ordinary card height unchanged')
    expect(decline.Position[2], 206, 'ordinary decline position unchanged')
else
    assert(free, 'developer gets the free respawn button')
    expect(card.Size[4], 316, 'developer card grows by one row')
    expect(free.Position[2], 200, 'free button sits between re-entry and decline')
    expect(free.Size[4], 44, 'free button height')
    expect(decline.Position[2], 254, 'decline moves below the free button')
    expect(free.Active, false, 'button starts inert')
end
player:SetAttribute('InRound', true)
workspace:SetAttribute('RoundActive', true)
player:SetAttribute('ZyntraReentryCredits', 1)
remote.OnClientEvent:Fire('partydown', 15, 'Someone')
expect(frame.Visible, true, 'party-down card opens')
expect(player:GetAttribute('PartyDownCardOpen'), true, 'card flag published')
step()
if DEV then expect(free.Active, false, 'still inert before the arming delay') end
now += 0.7
step()
expect(decline.Active, true, 'decline armed after the delay')
if DEV then
    expect(free.Active, true, 'free button armed after the delay')
    expect(free.Text, 'FREE RESPAWN  //  DEV', 'idle caption')
    free.Activated:Fire()
    expect(#commands, 1, 'free button dispatches exactly once')
    expect(commands[1], 'freeRespawn', 'dispatches the existing DEV command')
    expect(#actions, 0, 'free respawn spends no credit')
    expect(#purchases, 0, 'free respawn prompts no purchase')
    player:SetAttribute('DevRespawnBusy', true)
    expect(free.Active, false, 'busy button leaves the input stack')
    expect(free.Text, 'RESPAWNING...', 'busy caption')
    free.Activated:Fire()
    expect(#commands, 1, 'busy button does not re-dispatch')
    player:SetAttribute('DevRespawnBusy', nil)
    player:SetAttribute('DevRespawnStatus', 'MUST_BE_DEAD')
    player:SetAttribute('DevRespawnSerial', 1)
    expect(messages[#messages], 'FREE RESPAWN  //  MUST_BE_DEAD', 'refusal reaches the status line')
    expect(free.Active, true, 'button returns after a refusal')
    player:SetAttribute('ZyntraReentryUsed', true)
    expect(reentry.Visible, false, 'used paid re-entry hides the paid button')
    expect(free.Active, true, 'free path ignores the used paid re-entry')
    GuiService.SelectedObject = free
    remote.OnClientEvent:Fire('reentry', 'Tester')
    expect(frame.Visible, false, 'own re-entry closes the card')
    expect(GuiService.SelectedObject, nil, 'closing drops a selection on the free button')
end
reentry.Activated:Fire()
if not DEV then
    expect(#actions, 1, 'paid credit path still works')
    expect(actions[1], 'UseReentry', 'existing credit action preserved')
end
print('Free respawn offer (card, dev=' .. tostring(DEV) .. '): ' .. checks .. ' checks passed')
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
    roundui = ROUNDUI.read_text(encoding='utf-8')
    card = section(roundui, 'do\n\tlocal GuiService = game:GetService("GuiService")',
                   '-- ── DEATH CARD')  # PARTY DOWN only; the death-cause card (2026-09-21) follows it
    with tempfile.TemporaryDirectory(prefix='free-respawn-offer-') as directory:
        for dev in ('true', 'false'):
            run(binary, directory, f'modal_{dev}.luau',
                [f'local DEV = {dev}', MODAL_SETUP, modal_extra, state, modal, MODAL_TESTS])
            run(binary, directory, f'card_{dev}.luau',
                [f'local DEV = {dev}', CARD_SETUP, card, CARD_TESTS])


if __name__ == '__main__':
    main()
