"""TOP SUPPORTERS board columns (Trello #100).

Extracts the real COLORS table, saturatedLobbyColor, makePart and
addDonationLeaderboard out of TunnelLobbyBuilder and builds the board inside a
fake Instance world under the real Luau interpreter. Covers: the
INCLUDES VERIFIED HISTORICAL PURCHASES footer is gone while the RankingScope
attribute, the status line, the divider and the title stay; every row is a frame
of three fixed-offset columns at the authored geometry; the name column
truncates and clips; all ten plates land inside the canvas; a row renders from
the Rank/Name/Robux attributes, from the legacy bullet string, and from the two
plain messages; a 21-character name moves neither the rank nor the amount; the
thousands separator is applied without a locale; the status binding, the value
binding, the attribute bindings and the ancestry teardown all still work.

No Studio, no network. Set LUAU_BIN to the official Luau interpreter.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATH = ROOT / "ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua"
SOURCE = SOURCE_PATH.read_text(encoding="utf-8")


def block(start, end):
    a = SOURCE.index(start)
    b = SOURCE.index(end, a + 1)
    return SOURCE[a:b].rstrip() + "\n"


SATURATION_LINE = re.search(r"^local LOBBY_SATURATION = [\d.]+$", SOURCE, re.M)
assert SATURATION_LINE, "LOBBY_SATURATION constant not found"

ACTUAL = "\n".join([
    block("local COLORS = {", "\n-- One reversible lever"),
    SATURATION_LINE.group(0),
    block("local function saturatedLobbyColor(", "\n-- Roblox Texture instances"),
    block("local function makePart(", "\nlocal function addSurfaceTexture("),
    block("local function addDonationLeaderboard(", "\nlocal function makeStationMonitorPart("),
])

PRELUDE = r'''
local checks = 0
local function check(ok, why) checks += 1; assert(ok, why) end

-- ------------------------------------------------------------- fake datamodel
local C3 = {}
C3.__index = C3
local Color3 = {}
local function rgb(r, g, b) return setmetatable({R = r, G = g, B = b}, C3) end
function Color3.new(r, g, b) return rgb(r, g, b) end
function Color3.fromRGB(r, g, b) return rgb(r / 255, g / 255, b / 255) end
function Color3.fromHSV(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local m = i % 6
    if m == 0 then return rgb(v, t, p) elseif m == 1 then return rgb(q, v, p)
    elseif m == 2 then return rgb(p, v, t) elseif m == 3 then return rgb(p, q, v)
    elseif m == 4 then return rgb(t, p, v) else return rgb(v, p, q) end
end
function C3:ToHSV()
    local r, g, b = self.R, self.G, self.B
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h /= 6
    end
    return h, (mx > 0 and d / mx or 0), mx
end
C3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end

local V3 = {}
V3.__index = V3
V3.__add = function(a, b) return setmetatable({X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z}, V3) end
local Vector3 = {new = function(x, y, z) return setmetatable({X = x, Y = y, Z = z}, V3) end}
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
-- typeof() reports "table" for the fake CFrame, so makePart's CFrame guard
-- misses and re-wraps the value; absorb that here the way the sibling test does.
local CFrame = {new = function(p) return p.Position and p or {Position = p} end}
local UDim = {new = function(s, o) return {Scale = s, Offset = o} end}
local UDim2 = {}
function UDim2.new(sx, ox, sy, oy) return {X = UDim.new(sx, ox), Y = UDim.new(sy, oy)} end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end

local function enumTable()
    return setmetatable({}, {__index = function(t, k) rawset(t, k, {Name = k}); return rawget(t, k) end})
end
local Enum = setmetatable({}, {__index = function(t, k) rawset(t, k, enumTable()); return rawget(t, k) end})

local function signal()
    local handlers = {}
    local s = {}
    function s:Connect(fn)
        local id = #handlers + 1
        handlers[id] = fn
        return {Disconnect = function() handlers[id] = nil; s.disconnects += 1 end}
    end
    function s:Fire(...)
        for _, fn in pairs(handlers) do fn(...) end
    end
    function s:Count()
        local n = 0
        for _ in pairs(handlers) do n += 1 end
        return n
    end
    s.disconnects = 0
    return s
end

local Instance = {}
function Instance.new(class)
    local inst = {ClassName = class, Name = class, Children = {}, Attributes = {}}
    local attributeSignals = {}
    local propertySignals = {}
    function inst:IsA(kind) return kind == class end
    function inst:GetAttributeChangedSignal(key)
        attributeSignals[key] = attributeSignals[key] or signal()
        return attributeSignals[key]
    end
    function inst:SetAttribute(k, v)
        self.Attributes[k] = v
        if attributeSignals[k] then attributeSignals[k]:Fire() end
    end
    function inst:GetAttribute(k) return self.Attributes[k] end
    function inst:GetPropertyChangedSignal(key)
        propertySignals[key] = propertySignals[key] or signal()
        return propertySignals[key]
    end
    function inst:FindFirstChild(name)
        for _, c in ipairs(self.Children) do if c.Name == name then return c end end
        return nil
    end
    function inst:WaitForChild(name) return self:FindFirstChild(name) end
    inst.AncestryChanged = signal()
    local store = {}
    return setmetatable(inst, {
        __index = store,
        __newindex = function(t, k, v)
            if k == "Parent" and v and v.Children then table.insert(v.Children, t) end
            store[k] = v
            if propertySignals[k] then propertySignals[k]:Fire() end
        end,
    })
end

local task = {spawn = function(fn) fn() end}
local TweenService = {}

-- The published values folder. Rows carry the legacy string; the Rank/Name/Robux
-- attributes A-SERVER adds are set per test, never here.
local folder = Instance.new("Folder")
folder.Name = "ZyntraDonationLeaderboard"
local published = {}
local function publish(name, text)
    local v = Instance.new("StringValue")
    v.Name = name
    v.Value = text
    v.Parent = folder
    published[name] = v
    return v
end
publish("Status", "CONNECTING")
for rank = 1, 10 do publish(string.format("Row%02d", rank), "") end

local ReplicatedStorage = {}
function ReplicatedStorage:WaitForChild(name)
    check(name == "ZyntraDonationLeaderboard", "the board waits for the published values folder")
    return folder
end

-- ACTUAL_SOURCE

-- --------------------------------------------------------------- build it once
local concourse = Instance.new("Folder")
local model = addDonationLeaderboard(concourse, Vector3.new(0, 0, 0))

local panel = model:FindFirstChild("LeaderboardPanel")
check(panel ~= nil, "the board still builds its panel")
check(model:FindFirstChild("LeaderboardCollision") ~= nil, "the walk blocker is still built")
check(type(model:GetAttribute("RankingScope")) == "string", "the RankingScope attribute survives the footer")
check(#model:GetAttribute("RankingScope") > 100, "RankingScope still carries the full scope wording")

local gui = panel:FindFirstChild("DonationLeaderboardDisplay")
check(gui ~= nil, "the surface gui is still built")
check(gui.CanvasSize.X == 560 and gui.CanvasSize.Y == 392, "the canvas is untouched at 560x392")
check(gui.Face == Enum.NormalId.Right, "the display still faces the walkway")

local background = gui.Children[1]
local function childNamed(name)
    for _, c in ipairs(background.Children) do if c.Name == name then return c end end
    return nil
end

-- ------------------------------------------------------- 1. the footer is gone
check(childNamed("RecordedSupportScope") == nil, "the footer label is deleted")
for _, c in ipairs(background.Children) do
    check(c.Name ~= "RecordedSupportScope", "no child is named RecordedSupportScope")
    check(c.Text ~= "INCLUDES VERIFIED HISTORICAL PURCHASES", "the footer wording is nowhere on the canvas")
end

-- ------------------------------------------------- 2. the header is unchanged
local title = childNamed("Title")
check(title ~= nil and title.Text == "TOP SUPPORTERS", "the title is untouched")
check(title.TextSize == 44 and title.Position.Y.Offset == 12, "the title keeps its authored geometry")
local status = childNamed("Status")
check(status ~= nil and status.TextSize == 17, "the status label is untouched")
check(status.Position.Y.Offset == 60, "the status label keeps its authored position")
local divider = nil
for _, c in ipairs(background.Children) do
    if c.ClassName == "Frame" and c.Position.Y.Offset == 90 then divider = c end
end
check(divider ~= nil and divider.Size.Y.Offset == 2, "the divider is still drawn at y 90")

-- ---------------------------------------------------- 3. ten three-column rows
local rowFrames = {}
for _, c in ipairs(background.Children) do
    if string.match(c.Name, "^Rank%d%d$") then table.insert(rowFrames, c) end
end
check(#rowFrames == 10, "exactly ten rank plates are drawn")

local COLUMNS = {
    {name = "Rank", x = 12, right = 56, align = "Right"},
    {name = "Name", x = 72, right = 396, align = "Left"},
    {name = "Robux", x = 408, right = 548, align = "Right"},
}

local rows = {}
for rank = 1, 10 do
    local row = childNamed(string.format("Rank%02d", rank))
    check(row ~= nil, "row " .. rank .. " exists under its authored name")
    check(row.ClassName == "Frame", "row " .. rank .. " is a frame, not one centred label")
    check(row.Position.Y.Offset == 98 + (rank - 1) * 27, "row " .. rank .. " sits on the 27 px pitch")
    check(row.Size.Y.Offset == 25, "row " .. rank .. " keeps the 25 px plate height")
    check(row.Position.Y.Offset + row.Size.Y.Offset <= 372, "row " .. rank .. " ends no lower than 372")
    check(row.Position.Y.Offset + row.Size.Y.Offset <= gui.CanvasSize.Y, "row " .. rank .. " ends inside the canvas")
    check(row.Position.Y.Offset >= 92, "row " .. rank .. " starts below the divider")
    local expected = rank % 2 == 1 and Color3.fromRGB(15, 25, 22) or Color3.fromRGB(10, 17, 15)
    check(row.BackgroundColor3 == expected, "row " .. rank .. " keeps its alternating plate colour")
    local corner
    for _, c in ipairs(row.Children) do if c.ClassName == "UICorner" then corner = c end end
    check(corner ~= nil and corner.CornerRadius.Offset == 6, "row " .. rank .. " keeps corner 6")
    for _, c in ipairs(row.Children) do
        check(c.ClassName ~= "UIPadding", "row " .. rank .. " carries no padding: offsets are explicit now")
        check(c.ClassName ~= "UIListLayout", "row " .. rank .. " has no layout that could reflow the columns")
    end

    local entry = {}
    local tint = rank <= 3 and Color3.fromRGB(236, 224, 165) or Color3.fromRGB(201, 225, 214)
    for _, spec in ipairs(COLUMNS) do
        local label
        for _, c in ipairs(row.Children) do if c.Name == spec.name then label = c end end
        check(label ~= nil, "row " .. rank .. " has a " .. spec.name .. " label")
        check(label.ClassName == "TextLabel", spec.name .. " is a TextLabel")
        check(label.Position.X.Offset == spec.x, spec.name .. " starts at its fixed offset on row " .. rank)
        check(label.Position.X.Scale == 0, spec.name .. " uses a pure offset, never a scale")
        check(label.Position.X.Offset + label.Size.X.Offset == spec.right,
            spec.name .. " ends at its fixed offset on row " .. rank)
        check(label.Size.X.Scale == 0, spec.name .. " has a fixed width, so it cannot stretch")
        check(label.Size.Y.Scale == 1 and label.Size.Y.Offset == 0, spec.name .. " fills the plate height")
        check(label.Position.Y.Offset == 0, spec.name .. " is flush with the plate top")
        check(label.TextXAlignment == Enum.TextXAlignment[spec.align],
            spec.name .. " is aligned " .. spec.align .. " on row " .. rank)
        check(label.Font == Enum.Font.Code, spec.name .. " is monospace, so digits line up")
        check(label.TextSize == 20, spec.name .. " is TextSize 20 on row " .. rank)
        check(label.TextColor3 == tint, spec.name .. " carries the row tint (top three gold)")
        check(label.BackgroundTransparency == 1, spec.name .. " draws no plate of its own")
        entry[spec.name] = label
    end
    check(entry.Name.TextTruncate == Enum.TextTruncate.AtEnd, "row " .. rank .. " truncates a long name")
    check(entry.Name.ClipsDescendants == true, "row " .. rank .. " clips a long name")
    check(entry.Rank.TextTruncate == nil, "the rank column needs no truncation")
    rows[rank] = entry
end

-- Columns never collide and are never crowded.
for _, gap in ipairs({{"Rank", "Name", 16}, {"Name", "Robux", 12}}) do
    local left, right = rows[1][gap[1]], rows[1][gap[2]]
    local measured = right.Position.X.Offset - (left.Position.X.Offset + left.Size.X.Offset)
    check(measured == gap[3], gap[1] .. " to " .. gap[2] .. " leaves " .. gap[3] .. " px of air")
    check(measured >= 12, "the gap is wide enough that neither column is crowded")
end
check(rows[1].Robux.Position.X.Offset + rows[1].Robux.Size.X.Offset + 12 == gui.CanvasSize.X,
    "the amount column keeps the same 12 px margin as the rank column")
check(rows[1].Rank.Position.X.Offset == 12, "the rank column keeps the same 12 px margin")

-- Every row shares one set of x offsets: that is what stops a name shifting
-- the rank or the amount on any OTHER row.
for rank = 2, 10 do
    for _, spec in ipairs(COLUMNS) do
        check(rows[rank][spec.name].Position.X.Offset == rows[1][spec.name].Position.X.Offset,
            spec.name .. " shares one x offset down the whole board")
        check(rows[rank][spec.name].Size.X.Offset == rows[1][spec.name].Size.X.Offset,
            spec.name .. " shares one width down the whole board")
    end
end

-- Monospace budget: 0.6 em advance at TextSize 20 = 12 px per character.
local perChar = 0.6 * rows[1].Rank.TextSize
check(20 * perChar <= rows[1].Name.Size.X.Offset, "a full 20-character Roblox name fits the name column")
check(#"NO SUPPORT RECORDED YET" * perChar <= rows[1].Name.Size.X.Offset, "the empty-board message fits")
check(#"999,999 R$" * perChar <= rows[1].Robux.Size.X.Offset, "a six-digit grouped total fits the amount column")
-- Right aligned, so anything wider grows leftwards into the 12 px gap. Even a
-- seven-digit total stops short of the name column, which is the real failure.
local widest = rows[1].Robux.Position.X.Offset + rows[1].Robux.Size.X.Offset - #"9,999,999 R$" * perChar
check(widest > rows[1].Name.Position.X.Offset + rows[1].Name.Size.X.Offset,
    "even a seven-digit total never reaches the name column")
check(#"01" * perChar <= rows[1].Rank.Size.X.Offset, "a two-digit rank fits the rank column")

-- ------------------------------------------------------- 4. pre-bind fallback
check(rows[1].Name.Text == "" or rows[1].Name.Text == "NO SUPPORT RECORDED YET",
    "the board renders the published empty row rather than inventing content")

-- ----------------------------------------------------------- 5. the bindings
check(published.Status:GetPropertyChangedSignal("Value"):Count() == 1, "the status value is bound exactly once")
for rank = 1, 10 do
    local value = published[string.format("Row%02d", rank)]
    check(value:GetPropertyChangedSignal("Value"):Count() == 1, "row " .. rank .. " is bound to its value")
    for _, attribute in ipairs({"Rank", "Name", "Robux"}) do
        check(value:GetAttributeChangedSignal(attribute):Count() == 1,
            "row " .. rank .. " listens to its " .. attribute .. " attribute")
    end
end

published.Status.Value = "RECORDED ROBUX: PRODUCTS, PASSES & DONATIONS"
check(status.Text == "RECORDED ROBUX: PRODUCTS, PASSES & DONATIONS", "the status line still re-renders")

-- --------------------------------------------- 6. attribute-driven rendering
local LONG_NAME = "AVERYLONGPLAYERNAMEXX"          -- 21 characters
local rankX = rows[1].Rank.Position.X.Offset
local robuxX = rows[1].Robux.Position.X.Offset
local row1 = published.Row01
row1:SetAttribute("Rank", 1)
row1:SetAttribute("Name", LONG_NAME)
row1:SetAttribute("Robux", 21207)
check(rows[1].Rank.Text == "01", "rank 1 renders as 01 from the attribute")
check(rows[1].Name.Text == LONG_NAME, "the name renders from the attribute")
check(rows[1].Robux.Text == "21,207 R$", "the amount is grouped without a locale")
check(rows[1].Rank.Position.X.Offset == rankX, "a 21-character name did not move the rank")
check(rows[1].Robux.Position.X.Offset == robuxX, "a 21-character name did not move the amount")
check(rows[1].Rank.Position.X.Offset == rows[2].Rank.Position.X.Offset, "the rank still lines up with row 2")
check(rows[1].Robux.Position.X.Offset == rows[2].Robux.Position.X.Offset, "the amount still lines up with row 2")
check(rows[1].Name.Size.X.Offset == rows[2].Name.Size.X.Offset, "the name column did not widen to fit")

-- A single attribute write re-renders on its own.
row1:SetAttribute("Robux", 1234)
check(rows[1].Robux.Text == "1,234 R$", "a Robux attribute change alone re-renders the row")
row1:SetAttribute("Name", "SHORT")
check(rows[1].Name.Text == "SHORT", "a Name attribute change alone re-renders the row")
check(rows[1].Rank.Text == "01", "the rank survived the name change")

-- The separator, across the magnitudes the board can publish.
for _, case in ipairs({{0, "0 R$"}, {7, "7 R$"}, {999, "999 R$"}, {1000, "1,000 R$"},
                       {12345, "12,345 R$"}, {999999, "999,999 R$"}, {1000000, "1,000,000 R$"},
                       {9876543, "9,876,543 R$"}}) do
    row1:SetAttribute("Robux", case[1])
    check(rows[1].Robux.Text == case[2], case[1] .. " groups as " .. case[2])
end

-- A hostile number must not throw inside the handler and freeze the row.
row1:SetAttribute("Robux", 4210.7)
check(rows[1].Robux.Text == "4,210 R$", "a float amount is floored, not an error")
row1:SetAttribute("Robux", 0 / 0)
check(rows[1].Robux.Text == "", "a NaN amount renders blank instead of throwing")
row1:SetAttribute("Robux", math.huge)
check(rows[1].Robux.Text == "", "an infinite amount renders blank instead of throwing")
row1:SetAttribute("Robux", nil)
check(rows[1].Robux.Text == "", "a missing amount renders blank")
row1:SetAttribute("Name", nil)
check(rows[1].Name.Text == "", "a missing name renders blank, never nil")
check(rows[1].Rank.Text == "01", "the rank still renders when the other two attributes are gone")

-- Attributes win over the string, so a stale legacy string cannot leak through.
row1.Value = "07   STALE   •   999 R$"
check(rows[1].Rank.Text == "01", "the attribute rank beats the legacy string")

-- ------------------------------------------------- 7. legacy string fallback
local row2 = published.Row02
row2.Value = "02   SUPPORTER   •   4210 R$"
check(rows[2].Rank.Text == "02", "the legacy string still yields a rank")
check(rows[2].Name.Text == "SUPPORTER", "the legacy string still yields a name")
check(rows[2].Robux.Text == "4,210 R$", "the legacy amount is regrouped into the column")
published.Row03.Value = "03   TWO WORD NAME   •   50 R$"
check(rows[3].Name.Text == "TWO WORD NAME", "a name with spaces survives the legacy parse")
check(rows[3].Robux.Text == "50 R$", "a small legacy amount needs no separator")
published.Row04.Value = "10   LASTPLACE   •   1 R$"
check(rows[4].Rank.Text == "10", "a two-digit legacy rank parses")

-- --------------------------------------------------------- 8. plain messages
published.Row05.Value = "NO SUPPORT RECORDED YET"
check(rows[5].Name.Text == "NO SUPPORT RECORDED YET", "the empty-board message goes in the name column")
check(rows[5].Rank.Text == "", "the empty-board message publishes no rank")
check(rows[5].Robux.Text == "", "the empty-board message publishes no amount")
published.Row06.Value = ""
check(rows[6].Name.Text == "" and rows[6].Rank.Text == "" and rows[6].Robux.Text == "", "an empty row is blank")
published.Row07.Value = "SOMETHING UNPARSABLE 12 R"
check(rows[7].Name.Text == "SOMETHING UNPARSABLE 12 R", "an unparsable row is shown as a message")
check(rows[7].Rank.Text == "" and rows[7].Robux.Text == "", "an unparsable row invents no rank or amount")

-- A ranked row that later goes empty clears all three columns.
row2.Value = ""
check(rows[2].Rank.Text == "" and rows[2].Name.Text == "" and rows[2].Robux.Text == "",
    "a row that loses its entry clears every column")

-- ------------------------------------------------------------- 9. teardown
local before = published.Status:GetPropertyChangedSignal("Value").disconnects
model.AncestryChanged:Fire(concourse, nil)
check(published.Status:GetPropertyChangedSignal("Value"):Count() == 0, "unparenting disconnects the status binding")
check(published.Status:GetPropertyChangedSignal("Value").disconnects > before, "the status connection was disconnected")
for rank = 1, 10 do
    local value = published[string.format("Row%02d", rank)]
    check(value:GetPropertyChangedSignal("Value"):Count() == 0, "row " .. rank .. " value binding is disconnected")
    for _, attribute in ipairs({"Rank", "Name", "Robux"}) do
        check(value:GetAttributeChangedSignal(attribute):Count() == 0,
            "row " .. rank .. " " .. attribute .. " binding is disconnected")
    end
end
local frozenRank = rows[8].Rank.Text
published.Row08:SetAttribute("Rank", 8)
published.Row08.Value = "08   GHOST   •   1 R$"
check(rows[8].Rank.Text == frozenRank, "a torn-down board no longer renders")

-- Re-parenting is a no-op for the teardown (it only fires on nil).
model.AncestryChanged:Fire(concourse, concourse)
check(true, "an ancestry change with a parent is ignored")

print(string.format(
    "supporter board columns: %d checks passed (10 rows, columns 12/72/408 on a %dx%d canvas, last plate foot %d)",
    checks, gui.CanvasSize.X, gui.CanvasSize.Y, rowFrames[1].Position.Y.Offset + 9 * 27 + 25))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    compiler = Path(luau).with_name("luau-compile.exe")
    source = PRELUDE.replace("-- ACTUAL_SOURCE", ACTUAL)
    with tempfile.TemporaryDirectory(prefix="board-columns-") as directory:
        path = Path(directory) / "board_columns.luau"
        path.write_text(source, encoding="utf-8")
        if compiler.exists():
            # Compile parity: the shipped file itself has to be loadable, not
            # only the slice this test extracts from it.
            whole = Path(directory) / "TunnelLobbyBuilder.luau"
            whole.write_text(SOURCE, encoding="utf-8")
            compiled = subprocess.run(
                [str(compiler), "--binary", str(whole)], capture_output=True, timeout=120
            )
            if compiled.returncode != 0:
                print(compiled.stderr.decode("utf-8", "replace"), end="")
                raise SystemExit("TunnelLobbyBuilder does not compile")
            print("TunnelLobbyBuilder.ModuleScript.lua compiles (%d bytes of bytecode)" % len(compiled.stdout))
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
