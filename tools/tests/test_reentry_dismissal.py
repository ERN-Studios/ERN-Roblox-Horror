"""Exercise the production re-entry modal and death lifecycle in offline Luau.

Extracts the actual UI, update function, button callbacks and character hooks.
Roblox hit testing, rendering and physical controller navigation need Studio.
Set LUAU_BIN or put the official luau executable on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


SETUP = r'''
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
    local obj = {ClassName = class, Activated = signal(), Enabled = true,
        Visible = true, Active = true, Selectable = true}
    function obj:IsDescendantOf(parent)
        local ancestor = self.Parent
        while ancestor do
            if ancestor == parent then return true end
            ancestor = ancestor.Parent
        end
        return false
    end
    table.insert(objects, obj)
    return obj
end
local Instance = {new = object}
local UDim2 = {new = function(...) return {...} end,
    fromScale = function(...) return {...} end, fromOffset = function(...) return {...} end}
local Vector2 = {new = function(...) return {...} end}
local Color3 = {fromRGB = function(...) return {...} end}
local Enum = {ZIndexBehavior = {Sibling = 'Sibling'},
    Font = {GothamBold = 'GothamBold'}, TextYAlignment = {Top = 'Top'}}
local COLORS = {bg = 'bg', error = 'error', text = 'text', muted = 'muted'}
local function corner() end
local function outline() end
local function label(parent, text, size, position)
    local obj = object('TextLabel')
    obj.Parent, obj.Text, obj.Size, obj.Position = parent, text, size, position
    return obj
end
local function button(parent, text, size, position)
    local obj = label(parent, text, size, position)
    obj.ClassName = 'TextButton'
    return obj
end
local GuiService = {MenuIsOpen = false}
local game = {GetService = function(_, name)
    assert(name == 'GuiService', 'Unexpected service: ' .. name)
    return GuiService
end}
local task = {spawn = function(fn) fn() end, defer = function(fn) fn() end}
local player, workspace = attributed(), attributed()
player.CharacterAdded = signal()
local playerGui = object('PlayerGui')
function player:WaitForChild(name)
    assert(name == 'PlayerGui')
    return playerGui
end
local profile = {ReentryCredits = 2}
local displayedProductPrices = {}
local Config = {Products = {EmergencyReentry = {Id = 77, Price = 49}}}
local actions, purchases, statuses = {}, {}, {}
local actionRemote = {FireServer = function(_, action) table.insert(actions, action) end}
local MarketplaceService = {PromptProductPurchase = function(_, buyer, id)
    expect(buyer, player, 'purchase targets local player')
    table.insert(purchases, id)
end}
local function showStatus(message, tone) table.insert(statuses, {message, tone}) end
'''


TESTS = r'''
local reentryDecline
for _, obj in ipairs(objects) do
    if obj.Name == 'ReentryDecline' then reentryDecline = obj end
end
assert(reentryDecline, 'Production re-entry modal needs a dismiss control')
local function spawnCharacter()
    local humanoid = {Health = 100, Died = signal()}
    local character = {WaitForChild = function(_, name)
        assert(name == 'Humanoid')
        return humanoid
    end}
    player.Character = character
    player.CharacterAdded:Fire(character)
    return humanoid
end
local function die(humanoid)
    humanoid.Health = 0
    humanoid.Died:Fire()
end
local function setRound(active)
    workspace:SetAttribute('RoundActive', active)
    updateReentry()
end
local function setInRound(active)
    player:SetAttribute('InRound', active)
    updateReentry()
end
expect(reentryGui.Enabled, false, 'modal initially hidden')
setInRound(true)
setRound(true)
local humanoid = spawnCharacter()
expect(reentryGui.Enabled, false, 'living player has no re-entry modal')
die(humanoid)
expect(reentryGui.Enabled, true, 'death during live round opens re-entry')
expect(player:GetAttribute('ZyntraReentryOpen'), true, 'visible modal owns input')
expect(reentryDecline.Name, 'ReentryDecline', 'dismiss control has stable UI name')
GuiService.SelectedObject = reentryDecline
reentryDecline.Activated:Fire()
expect(reentryGui.Enabled, false, 'spectate button closes re-entry')
expect(player:GetAttribute('ZyntraReentryOpen'), nil, 'dismissal releases modal input')
expect(GuiService.SelectedObject, nil, 'dismissal clears its gamepad selection')
expect(#actions, 0, 'dismissal spends no credits')
expect(#purchases, 0, 'dismissal prompts no purchase')
updateReentry()
profile.ReentryCredits = 3
displayedProductPrices.EmergencyReentry = 60
updateReentry()
expect(reentryGui.Enabled, false, 'profile and price refresh preserve dismissal')
expect(player:GetAttribute('ZyntraReentryCredits'), 3, 'dismissed modal still publishes credits')
expect(player:GetAttribute('ZyntraReentryPrice'), 60, 'dismissed modal still publishes price')
player:SetAttribute('PartyDownWindowOpen', true)
player:SetAttribute('PartyDownCardOpen', true)
expect(reentryGui.Enabled, false, 'party-down purchase surface remains exclusive')
expect(player:GetAttribute('ZyntraReentryOpen'), true, 'party-down card still owns input')
player:SetAttribute('PartyDownCardOpen', nil)
expect(player:GetAttribute('ZyntraReentryOpen'), nil, 'declined party-down card releases input')
expect(reentryGui.Enabled, false, 'declined party-down card does not open re-entry')
player:SetAttribute('PartyDownWindowOpen', nil)
expect(reentryGui.Enabled, false, 'teammate re-entry keeps original dismissal')
humanoid = spawnCharacter()
expect(reentryGui.Enabled, false, 'fresh living character hides modal')
die(humanoid)
expect(reentryGui.Enabled, true, 'new death permits re-entry again')
player:SetAttribute('PartyDownWindowOpen', true)
expect(reentryGui.Enabled, false, 'party-down hides an undismissed modal')
player:SetAttribute('PartyDownWindowOpen', nil)
expect(reentryGui.Enabled, true, 'undismissed modal returns after party-down clears')
local foreignSelection = object('TextButton')
GuiService.SelectedObject = foreignSelection
reentryDecline.Activated:Fire()
expect(GuiService.SelectedObject, foreignSelection, 'closing preserves other UI selection')
GuiService.SelectedObject = nil
setRound(false)
expect(reentryGui.Enabled, false, 'round end hides modal')
setRound(true)
expect(reentryGui.Enabled, true, 'round reset clears old dismissal')
reentryDecline.Activated:Fire()
setInRound(false)
expect(reentryGui.Enabled, false, 'leaving round hides modal')
setInRound(true)
expect(reentryGui.Enabled, true, 'leaving round resets old dismissal')
reentryButton.Activated:Fire()
expect(#actions, 1, 'credit button dispatches exactly once')
expect(actions[1], 'UseReentry', 'existing credit action preserved')
expect(#purchases, 0, 'owned credit does not prompt purchase')
profile.ReentryCredits = 0
updateReentry()
reentryButton.Activated:Fire()
expect(#purchases, 1, 'empty credits open product purchase')
expect(purchases[1], 77, 'configured re-entry product preserved')
Config.Products.EmergencyReentry.Id = 0
reentryButton.Activated:Fire()
expect(#purchases, 1, 'unconfigured product cannot prompt purchase')
expect(#statuses, 1, 'unconfigured product reports status')
player:SetAttribute('ZyntraReentryUsed', true)
updateReentry()
expect(reentryGui.Enabled, false, 'used re-entry hides modal')
expect(player:GetAttribute('ZyntraReentryOpen'), nil, 'used re-entry releases input')
print('Re-entry dismissal: ' .. checks .. ' checks passed (offline Luau; engine hit testing not exercised)')
'''


def main():
    binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary:
        raise SystemExit('Set LUAU_BIN or install luau; no tests were executed.')
    source = SOURCE.read_text(encoding='utf-8')
    state = section(source, 'local reentryDead = false', 'local COLORS =')
    modal = section(source, 'player:SetAttribute("ZyntraReentryOpen", nil)',
                    'local function refreshUI()')
    with tempfile.TemporaryDirectory(prefix='reentry-dismissal-') as directory:
        fixture = Path(directory) / 'reentry_dismissal_test.luau'
        fixture.write_text('\n'.join([SETUP, state, modal, TESTS]), encoding='utf-8')
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == '__main__':
    main()
