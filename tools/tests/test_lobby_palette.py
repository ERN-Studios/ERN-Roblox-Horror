"""Lobby saturation lever (Trello #90) and the TOP SUPPORTERS board (#78).

Extracts the real LOBBY_SATURATION constant, saturatedLobbyColor, makePart and
addDonationLeaderboard out of TunnelLobbyBuilder and runs them against a fake
Instance/Color3/UDim2 surface. Covers: the helper raises HSV saturation and
preserves value, clamps at 1, leaves greys and blacks untouched, and reproduces
the authored palette byte for byte at 1.0; every authored lobby colour survives
the round trip; the board's canvas matches its panel face aspect exactly, all
ten rank rows fit between the divider and the footer, every element is centred,
the widest row the server can publish still fits, the text is physically larger
than the layout it replaces, and the value binding still reaches all ten rows.
No Studio, no network. Set LUAU_BIN to the official Luau interpreter.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua").read_text(encoding="utf-8")


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
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

-- Real HSV maths, so the helper is exercised rather than mimicked.
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
function C3:Lerp(other, a)
    return rgb(self.R + (other.R - self.R) * a, self.G + (other.G - self.G) * a, self.B + (other.B - self.B) * a)
end
C3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
local function bytes(c) return math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5) end

local V3 = {}
V3.__index = V3
V3.__add = function(a, b) return setmetatable({X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z}, V3) end
local Vector3 = {new = function(x, y, z) return setmetatable({X = x, Y = y, Z = z}, V3) end}
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
-- Luau's typeof() reports "table" for the fakes, so makePart's
-- `typeof(cf) == "CFrame"` guard misses and re-wraps: absorb that here.
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

local Instance = {}
function Instance.new(class)
    local inst = {ClassName = class, Name = class, Children = {}, Attributes = {}}
    function inst:IsA(kind) return kind == class end
    function inst:SetAttribute(k, v) self.Attributes[k] = v end
    function inst:GetAttribute(k) return self.Attributes[k] end
    function inst:FindFirstChild(name)
        for _, c in ipairs(self.Children) do if c.Name == name then return c end end
        return nil
    end
    inst.AncestryChanged = {Connect = function() return {Disconnect = function() end} end}
    local store = {}
    return setmetatable(inst, {
        __index = store,
        __newindex = function(t, k, v)
            if k == "Parent" and v and v.Children then table.insert(v.Children, t) end
            store[k] = v
        end,
    })
end

local task = {spawn = function(fn) fn() end}
local TweenService = {}
local bound = {}
local ReplicatedStorage = {}
function ReplicatedStorage:WaitForChild(name)
    local folder = Instance.new("Folder")
    folder.Name = name
    local function value(vname, text)
        local v = Instance.new("StringValue")
        v.Name = vname
        v.Value = text
        function v:IsA(kind) return kind == "StringValue" end
        function v:GetPropertyChangedSignal()
            return {Connect = function() bound[vname] = true; return {Disconnect = function() end} end}
        end
        v.Parent = folder
    end
    value("Status", "DONATIONS + RECORDED TOKEN / RE-ENTRY PURCHASES")
    for rank = 1, 10 do
        value(string.format("Row%02d", rank), string.format("%02d   %s   . %d R$", rank, "SUPPORTER", rank * 100))
    end
    return folder
end

-- ACTUAL_SOURCE

-- ---------------------------------------------------------------- #90 palette
check(LOBBY_SATURATION >= 1, "the lever only ever adds saturation")

local sample = Color3.fromRGB(116, 105, 82)          -- COLORS.concrete
local h0, s0, v0 = sample:ToHSV()
local boosted = saturatedLobbyColor(sample)
local h1, s1, v1 = boosted:ToHSV()
check(near(h1, h0, 1e-4), "hue is preserved: the art direction keeps its colours")
check(near(v1, v0, 1e-4), "value is preserved: nothing in the lobby darkens")
check(near(s1, s0 * LOBBY_SATURATION, 1e-4), "saturation is raised by exactly the lever")
check(s1 > s0, "the authored lobby colour actually got more saturated")

local hot = Color3.fromRGB(255, 76, 60)              -- COLORS.red, already near the edge
local _, hotS = saturatedLobbyColor(hot):ToHSV()
check(hotS <= 1 + 1e-9, "saturation clamps at 1 instead of running past the gamut")
check(near(hotS, 1, 1e-6), "an already-vivid colour saturates fully rather than wrapping")

for _, grey in ipairs({Color3.fromRGB(0, 0, 0), Color3.fromRGB(27, 27, 27), Color3.new(1, 1, 1)}) do
    local out = saturatedLobbyColor(grey)
    local r, g, b = bytes(out)
    check(r == g and g == b, "a grey has no hue to raise and stays grey")
    check(out == grey, "a grey passes through untouched, so darkness stays neutral")
end

-- Every authored colour in the module survives the round trip in gamut.
local authored = 0
for _, line in ipairs(AUTHORED_COLORS) do
    local c = Color3.fromRGB(line[1], line[2], line[3])
    local before = select(2, c:ToHSV())
    local out = saturatedLobbyColor(c)
    local hh, ss, vv = out:ToHSV()
    local r, g, b = bytes(out)
    check(r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255, "boosted colour stays inside 0-255")
    check(ss <= 1 + 1e-9 and ss >= before - 1e-9, "no authored colour loses saturation")
    check(near(vv, select(3, c:ToHSV()), 1e-4), "no authored colour changes brightness")
    check(hh == hh, "no authored colour produces NaN hue")
    authored += 1
end
check(authored > 100, "the authored palette sweep covered the module's colours")

-- 1.0 is a true off switch: identical Color3 values, not merely close ones.
LOBBY_SATURATION = 1
for _, line in ipairs(AUTHORED_COLORS) do
    local c = Color3.fromRGB(line[1], line[2], line[3])
    check(saturatedLobbyColor(c) == c, "LOBBY_SATURATION = 1.0 reproduces the authored palette exactly")
end
LOBBY_SATURATION = SHIPPED_SATURATION

-- makePart is the single funnel: a part is born with the boosted colour.
local bin = Instance.new("Folder")
local part = makePart(bin, "Probe", CFrame.new(Vector3.new(0, 0, 0)), Vector3.new(1, 1, 1), sample, Enum.Material.Metal)
check(part.Color == boosted, "makePart applies the lever to every lobby part")
check(part.Material == Enum.Material.Metal, "makePart still honours the requested material")

-- ------------------------------------------------------------ #78 leaderboard
local concourse = Instance.new("Folder")
local model = addDonationLeaderboard(concourse, Vector3.new(0, 0, 0))
local panel = model:FindFirstChild("LeaderboardPanel")
check(panel ~= nil, "the board still builds its panel")
check(panel.Size.X == 0.62 and panel.Size.Y == 12.6 and panel.Size.Z == 18, "the panel part keeps its authored size")
check(panel.CFrame.Position.X == -30 and panel.CFrame.Position.Y == 7.15 and panel.CFrame.Position.Z == -35,
    "the panel part keeps its authored position")
check(model:FindFirstChild("LeaderboardCollision") ~= nil, "the invisible walk blocker is still built")

local gui = panel:FindFirstChild("DonationLeaderboardDisplay")
check(gui ~= nil and gui.Face == Enum.NormalId.Right, "the display still faces the walkway")

-- Face = Right, so the canvas is stretched over Size.Z wide by Size.Y tall.
local faceW, faceH = panel.Size.Z, panel.Size.Y
local pxU = gui.CanvasSize.X / faceW
local pxV = gui.CanvasSize.Y / faceH
check(near(pxU, pxV, 1e-6), "canvas aspect matches the face, so glyphs are not stretched sideways")
check(pxV < 52.38, "fewer pixels per stud than the 900x660 canvas, which is what enlarges the text")

local background = gui.Children[1]
local function childNamed(name)
    for _, c in ipairs(background.Children) do if c.Name == name then return c end end
    return nil
end

local title = childNamed("Title")
check(title.Text == "TOP SUPPORTERS", "the title text is unchanged")
check(title.TextXAlignment == Enum.TextXAlignment.Center, "the title is centred")
check(title.Position.X.Offset == 0 and title.Size.X.Scale == 1 and title.Size.X.Offset == 0,
    "the title spans the full canvas, so centring is exact")
check(title.TextSize / pxV > 43 / (660 / faceH) * 1.5, "the title is at least 1.5x its old physical height")

local status = childNamed("Status")
check(status.TextXAlignment == Enum.TextXAlignment.Center, "the status line is centred")
check(status.TextSize / pxV > 19 / (660 / faceH), "the status line is physically larger than before")

local scope = childNamed("RecordedSupportScope")
check(scope.TextXAlignment == Enum.TextXAlignment.Center, "the footer is centred")
check(scope.TextSize / pxV > 17 / (660 / faceH), "the footer is physically larger than before")

local rows = {}
for rank = 1, 10 do
    local row = childNamed(string.format("Rank%02d", rank))
    check(row ~= nil, "rank row " .. rank .. " exists")
    rows[rank] = row
end
check(#rows == 10, "all ten published ranks still have a row")
local drawn = {}
for _, c in ipairs(background.Children) do
    if string.match(c.Name, "^Rank%d%d$") then table.insert(drawn, c) end
end
check(#drawn == 10, "exactly ten rank plates are drawn -- an extra one would not fit the budget")

local rowH = rows[1].Size.Y.Offset
local pitch = rows[2].Position.Y.Offset - rows[1].Position.Y.Offset
for rank, row in ipairs(rows) do
    check(row.TextXAlignment == Enum.TextXAlignment.Center, "rank row " .. rank .. " is centred")
    check(row.Size.Y.Offset == rowH and row.TextSize == rows[1].TextSize, "every rank row is the same height and size")
    check(row.Position.X.Offset == rows[1].Position.X.Offset, "every rank row shares one left margin")
    if rank > 1 then
        check(row.Position.Y.Offset - rows[rank - 1].Position.Y.Offset == pitch, "rank rows are evenly pitched")
    end
    check(row.Position.Y.Offset >= 92, "rank row " .. rank .. " starts below the divider")
    check(row.Position.Y.Offset + rowH <= scope.Position.Y.Offset, "rank row " .. rank .. " ends above the footer")
end
check(pitch >= rowH, "rank plates do not overlap")
check(scope.Position.Y.Offset + scope.Size.Y.Offset <= gui.CanvasSize.Y, "the footer fits inside the canvas")
check(rows[1].TextSize / pxV > 24 / (660 / faceH), "rank text is physically larger than before")

-- The widest row ZyntraMonetization can publish is "00" + a 20-character name
-- + the separators + a six-digit amount: 41 monospace characters.
local pad = rows[1].Children[1]
check(pad.ClassName == "UIPadding", "rank rows still carry their padding")
local inner = gui.CanvasSize.X + rows[1].Size.X.Offset - pad.PaddingLeft.Offset - pad.PaddingRight.Offset
check(41 * 0.6 * rows[1].TextSize <= inner, "the longest publishable row still fits without clipping a name")

check(bound.Status == true, "the status value is still bound")
for rank = 1, 10 do
    check(bound[string.format("Row%02d", rank)] == true, "row " .. rank .. " is still bound to its value")
    check(rows[rank].Text:find("SUPPORTER") ~= nil, "row " .. rank .. " renders what the server published")
end

print(string.format(
    "lobby palette + supporter board: %d checks passed (LOBBY_SATURATION=%.2f, canvas %dx%d = %.2f px/stud)",
    checks, SHIPPED_SATURATION, gui.CanvasSize.X, gui.CanvasSize.Y, pxV))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    colors = re.findall(r"Color3\.fromRGB\((\d+), (\d+), (\d+)\)", SOURCE)
    table = "local AUTHORED_COLORS = {%s}\n" % ",".join(
        "{%s,%s,%s}" % rgb for rgb in sorted(set(colors))
    )
    shipped = "local SHIPPED_SATURATION = %s\n" % SATURATION_LINE.group(0).split("=")[1].strip()
    source = PRELUDE.replace("-- ACTUAL_SOURCE", ACTUAL + "\n" + table + shipped)
    with tempfile.TemporaryDirectory(prefix="lobby-palette-") as directory:
        path = Path(directory) / "lobby_palette.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
