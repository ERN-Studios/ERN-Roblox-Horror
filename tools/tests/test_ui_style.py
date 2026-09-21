"""Run the real ReplicatedStorage/UIStyle module, and two restyled UI blocks, offline.

UI_STYLE_20260915 (Trello card 98). Three things are checked, none of them
reimplemented:

  1. UIStyle loads and its tokens hold the values read off the two reference
     surfaces (Level 1's Objectives panel, the Mission Brief card).
  2. Every helper writes EXACTLY the documented properties and nothing else --
     the whole reason the restyle is safe is that it never touches Position,
     Size, Name, Visible or Text, which is what the UIRegression fit matrix
     measures. A helper that started writing one of those would pass a colour
     review and break the layout contracts.
  3. The production UI-building blocks out of Level 2 Objective UI and Round
     Exit Client -- extracted by marker, not retyped -- still build their panels
     and buttons, now carrying the shared tokens, with their authored geometry
     untouched.

What this CANNOT see: real font metrics, TextBounds, the engine's own
UICorner/UIStroke rendering, and anything about how it looks. Desktop and touch
captures are the proof for those. Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
UISTYLE = (ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua").read_text(encoding="utf-8")
LEVEL2 = (ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Objective UI.LocalScript.lua"
          ).read_text(encoding="utf-8")
EXIT = (ROOT / "StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua"
        ).read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted)
        .. ', got ' .. tostring(value))
end

-- ── the smallest Roblox these blocks need ────────────────────────────────
-- Value types are MEMOISED so `==` answers "same value", the way the engine's
-- own Color3/UDim do; without that every assertion below would compare two
-- fresh tables and pass for the wrong reason.
local function memo(kind)
    local cache = {}
    return function(...)
        local key = kind .. ':' .. table.concat({...}, ',')
        if not cache[key] then cache[key] = {Kind = kind, Key = key} end
        return cache[key]
    end
end
local Color3 = {fromRGB = memo('Color3'), new = memo('Color3n')}
local UDim = {new = memo('UDim')}
local UDim2 = {
    new = function(sx, ox, sy, oy) return {Kind = 'UDim2', SX = sx, OX = ox, SY = sy, OY = oy} end,
    fromOffset = function(x, y) return {Kind = 'UDim2', SX = 0, OX = x, SY = 0, OY = y} end,
    fromScale = function(x, y) return {Kind = 'UDim2', SX = x, OX = 0, SY = y, OY = 0} end,
}
local Vector2 = {new = function(x, y) return {Kind = 'Vector2', X = x, Y = y} end}
-- Enum members answer as their own name, so equality is string equality.
local Enum = setmetatable({}, {__index = function(_, group)
    return setmetatable({}, {__index = function(_, item) return group .. '.' .. item end})
end})

-- Instances record every property WRITTEN to them, which is what check (2) is.
local function newInstance(class)
    local fields = {ClassName = class, Name = class, Children = {}, Written = {}}
    local proxy = {}
    fields.FindFirstChildOfClass = function(_, want)
        for _, child in ipairs(fields.Children) do
            if child.ClassName == want then return child end
        end
        return nil
    end
    setmetatable(proxy, {
        __index = fields,
        __newindex = function(_, key, value)
            fields.Written[key] = true
            if key == 'Parent' and value ~= nil then table.insert(value.Children, proxy) end
            fields[key] = value
        end,
    })
    return proxy
end
local Instance = {new = newInstance}

local function clearWrites(object)
    table.clear(object.Written)
    return object
end

-- Exactly this set, no more and no less.
local function wroteExactly(object, wanted, label)
    local seen = {}
    for key in pairs(object.Written) do table.insert(seen, key) end
    table.sort(seen)
    local expected = table.clone(wanted)
    table.sort(expected)
    expect(table.concat(seen, ','), table.concat(expected, ','),
        label .. ' writes exactly its documented properties')
end

local function cornerOf(object) return object:FindFirstChildOfClass('UICorner') end
local function strokeOf(object) return object:FindFirstChildOfClass('UIStroke') end
'''


TESTS = r'''
-- ── (1) tokens ───────────────────────────────────────────────────────────
-- Spot-checks, not a copy of the table: these are the values the two reference
-- surfaces actually carry, so a token edited by accident fails here.
expect(UIStyle.Color.Panel, Color3.fromRGB(9, 13, 11), 'panel surface is Level1Objectives')
expect(UIStyle.Color.Card, Color3.fromRGB(8, 12, 10), 'card surface is ObjectivesPanel')
expect(UIStyle.Color.Caption, Color3.fromRGB(4, 8, 6), 'caption surface is CommandSubtitles')
expect(UIStyle.Color.Line, Color3.fromRGB(75, 94, 83), 'the one stroke colour')
expect(UIStyle.Color.Title, Color3.fromRGB(231, 238, 233), 'title face is objectiveTitle')
expect(UIStyle.Color.Body, Color3.fromRGB(201, 213, 205), 'body face is makeLabel')
expect(UIStyle.Color.Accent, Color3.fromRGB(83, 204, 145), 'accent is SignalAccent/Fill')
expect(UIStyle.Radius.Panel, 10, 'panel radius')
expect(UIStyle.Radius.Card, 12, 'card radius')
expect(UIStyle.Radius.Control, 9, 'control radius')
expect(UIStyle.Stroke.Thickness, 1, 'stroke weight')
expect(UIStyle.Stroke.Transparency, 0.28, 'stroke transparency')
expect(UIStyle.Transparency.Panel, 0.08, 'panel transparency')
expect(UIStyle.Font.Title, Enum.Font.GothamBold, 'title face')
expect(UIStyle.Font.Body, Enum.Font.GothamMedium, 'body face')
expect(UIStyle.Font.Readout, Enum.Font.Code, 'readout face')

-- ── (2) the helpers write exactly what they document ─────────────────────
local frame = Instance.new('Frame')
UIStyle.panel(frame)
wroteExactly(frame, {'BackgroundColor3', 'BackgroundTransparency', 'BorderSizePixel'},
    'UIStyle.panel')
expect(frame.BackgroundColor3, UIStyle.Color.Panel, 'panel takes the panel surface')
expect(frame.BackgroundTransparency, UIStyle.Transparency.Panel, 'panel takes .08')
expect(cornerOf(frame).CornerRadius, UDim.new(0, 10), 'panel is rounded 10')
wroteExactly(cornerOf(frame), {'CornerRadius', 'Parent'}, 'the adopted UICorner')
expect(strokeOf(frame).Color, UIStyle.Color.Line, 'panel stroke is the line colour')
expect(strokeOf(frame).Thickness, 1, 'panel stroke is 1px')
expect(strokeOf(frame).Transparency, 0.28, 'panel stroke is .28')
wroteExactly(strokeOf(frame), {'Color', 'Thickness', 'Transparency', 'ApplyStrokeMode', 'Parent'},
    'the adopted UIStroke')
-- The trap this restyle had to defuse: ApplyStrokeMode defaults to Contextual,
-- which on a TextLabel/TextButton outlines the TEXT instead of the border --
-- and draws nothing at all when that object's own Text is "".
expect(strokeOf(frame).ApplyStrokeMode, Enum.ApplyStrokeMode.Border,
    'every stroke is a BORDER, never a text outline')
local textPanel = Instance.new('TextButton')
textPanel.Text = ''
UIStyle.panel(textPanel)
expect(strokeOf(textPanel).ApplyStrokeMode, Enum.ApplyStrokeMode.Border,
    'a TextButton used as a panel still gets a real border')

-- Called twice -- which presentAlert and showToast both do after a fade -- it
-- ADOPTS. A second UICorner would leave two competing radii on one frame.
local corner, stroke = cornerOf(frame), strokeOf(frame)
UIStyle.panel(frame)
expect(#frame.Children, 2, 'restyling adopts rather than adding a second corner/stroke')
expect(cornerOf(frame), corner, 'the same UICorner is reused')
expect(strokeOf(frame), stroke, 'the same UIStroke is reused')

-- 0 is a real request, not "unset". `or` would have silently made it .08.
local opaque = Instance.new('Frame')
UIStyle.panel(opaque, {Transparency = 0, Radius = 0, StrokeTransparency = 0})
expect(opaque.BackgroundTransparency, 0, 'a transparency of 0 survives')
expect(cornerOf(opaque).CornerRadius, UDim.new(0, 0), 'a radius of 0 survives')
expect(strokeOf(opaque).Transparency, 0, 'a stroke transparency of 0 survives')

local control = Instance.new('TextButton')
control.TextScaled = false
clearWrites(control)
UIStyle.button(control)
wroteExactly(control, {'BackgroundColor3', 'BackgroundTransparency', 'BorderSizePixel',
    'Font', 'TextColor3', 'TextSize'}, 'UIStyle.button')
expect(control.BackgroundColor3, UIStyle.Color.Control, 'a button is the control surface')
expect(cornerOf(control).CornerRadius, UDim.new(0, 9), 'a button is rounded 9')
expect(control.Font, Enum.Font.GothamBold, 'a button prints in GothamBold')
expect(control.TextSize, 13, 'a button prints at 13')

-- TextScaled owns its own size: the helper must not overwrite it, or every
-- measured scale contract in the HUD would be replaced by a fixed face.
local scaled = Instance.new('TextLabel')
scaled.TextScaled = true
clearWrites(scaled)
UIStyle.title(scaled)
wroteExactly(scaled, {'Font', 'TextColor3'}, 'UIStyle.title on a TextScaled label')

local plain = Instance.new('TextLabel')
UIStyle.title(plain)
wroteExactly(plain, {'Font', 'TextColor3', 'TextSize'}, 'UIStyle.title')
expect(plain.Font, Enum.Font.GothamBold, 'title face')
expect(plain.TextColor3, UIStyle.Color.Title, 'title colour')
expect(plain.TextSize, 16, 'title size')

local prose = clearWrites(Instance.new('TextLabel'))
UIStyle.body(prose, {TextSize = 14})
wroteExactly(prose, {'Font', 'TextColor3', 'TextSize'}, 'UIStyle.body')
expect(prose.Font, Enum.Font.GothamMedium, 'body face')
expect(prose.TextSize, 14, 'body honours an explicit size')

local meterLabel = clearWrites(Instance.new('TextLabel'))
UIStyle.readout(meterLabel)
expect(meterLabel.Font, Enum.Font.Code, 'a readout stays monospaced')
expect(meterLabel.TextColor3, UIStyle.Color.AccentText, 'a readout is the eyebrow green')

local band = Instance.new('Frame')
UIStyle.caption(band)
expect(band.BackgroundColor3, UIStyle.Color.Caption, 'a caption is the subtitle surface')
expect(band.BackgroundTransparency, 0.18, 'a caption is .18')
expect(cornerOf(band).CornerRadius, UDim.new(0, 8), 'a caption is rounded 8')
expect(strokeOf(band).Color, UIStyle.Color.LiveStroke, 'a caption carries the live stroke')
expect(strokeOf(band).Thickness, 1.5, 'a caption stroke is 1.5px')

-- ── (3a) Level 2 Objective UI, the real block ────────────────────────────
expect(panel.BackgroundColor3, UIStyle.Color.Panel, 'L2 panel took the shared surface')
expect(panel.BackgroundTransparency, UIStyle.Transparency.Panel, 'L2 panel took .08')
expect(cornerOf(panel).CornerRadius, UDim.new(0, 10),
    'L2 panel is rounded 10 (was 6)')
expect(strokeOf(panel).Thickness, 1, 'L2 panel stroke is 1px (was 2)')
expect(strokeOf(panel).Transparency, 0.28, 'L2 panel stroke is .28')
expect(strokeOf(panel).Color, UIStyle.Color.Line,
    'L2 panel rests on the neutral line, not a cyan of its own')
expect(l2stroke, strokeOf(panel), 'refresh() writes the adopted stroke')

expect(title.Font, Enum.Font.Code, 'the "> PUMP NETWORK" line stays monospaced')
expect(title.TextColor3, Color3.fromRGB(126, 224, 235), "Level 2's cyan identity is kept")
expect(meter.TextColor3, UIStyle.Color.Body, 'the meter prints in the shared body face')
expect(hint.TextColor3, UIStyle.Color.Warning, 'the hint prints in the shared caution face')
-- The geometry the fit matrix measures is UNCHANGED by the restyle.
expect(title.Position.OX, 10, 'the title keeps its authored x')
expect(title.Position.OY, 4, 'the title keeps its authored y')
expect(hint.Position.OY, 51, 'the hint keeps its authored y')
expect(title.TextScaled, true, 'the title keeps its scale contract')
expect(title.Parent, panel, 'the rows are still the panel\'s children')

-- ── (3b) Round Exit Client, the real block ───────────────────────────────
local sample = makeButton(gui, 'LeaveChip', 'BACK TO LOBBY')
expect(sample.Name, 'LeaveChip', 'the button keeps the name UIRegression addresses it by')
expect(sample.Text, 'BACK TO LOBBY', 'the copy is untouched')
expect(sample.BackgroundColor3, UIStyle.Color.Control, 'the chip is the control surface')
expect(sample.TextColor3, UIStyle.Color.Title, 'the chip prints in the title face')
expect(sample.Font, Enum.Font.GothamBold, 'the chip prints in GothamBold')
expect(cornerOf(sample).CornerRadius, UDim.new(0, 9), 'the chip is rounded 9 (was 6)')
expect(strokeOf(sample).Color, UIStyle.Color.Line, 'the chip stroke is the shared line')
expect(strokeOf(sample).Thickness, 1, 'the chip stroke is 1px (was 1.2)')

expect(card.BackgroundColor3, UIStyle.Color.Card, 'the confirm card is the card surface')
expect(card.BackgroundTransparency, UIStyle.Transparency.Card, 'the confirm card is .035')
expect(cornerOf(card).CornerRadius, UDim.new(0, 12), 'the confirm card is rounded 12')
expect(strokeOf(card).Transparency, UIStyle.Stroke.CardTransparency,
    'the confirm card stroke is .25')
expect(card.Size.OX, 340, 'the card keeps its authored width')
expect(card.Name, 'RoundExitCard', 'the card keeps its name')

print('UI style: ' .. tostring(checks)
    .. ' checks passed (offline Luau; font metrics, rendering and look not exercised)')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "\n".join([
        PRELUDE,
        # the real module, run as a module
        "local UIStyle = (function()", UISTYLE, "end)()",
        # (3a) Level 2's real panel + row construction
        'local panel = Instance.new("Frame")',
        section(LEVEL2, "UIStyle.panel(panel)", "local POWERED_HINT")
        .replace("local stroke =", "l2stroke ="),
        # (3b) Round Exit Client's real button factory, shade and confirm card
        'local gui = Instance.new("ScreenGui")',
        section(EXIT, "local function makeButton", "\nlocal title = Instance.new"),
        TESTS,
    ])
    # `stroke` is a local inside the extracted L2 block; the assertions need it.
    source = "local l2stroke\n" + source
    with tempfile.TemporaryDirectory(prefix="ui-style-") as directory:
        fixture = Path(directory) / "ui_style.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
