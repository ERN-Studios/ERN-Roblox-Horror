"""Embed a small real-clip fixture and the player's exact sampling functions in a pure-Luau test."""
from pathlib import Path
import json
import re
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
player = (ROOT / "out/Level 1 Entity Motion.LocalScript.lua").read_text()
clip_bytes = (ROOT / "out/clips.json").read_bytes()
source = json.loads(clip_bytes)
fixtures = {}
for name in ("Walk", "Run", "Lunge_Flight"):
    clip = source[name]
    fixtures[name] = {key: value for key, value in clip.items() if key != "bones"}
    fixtures[name]["bones"] = {key: value for key, value in clip["bones"].items()
                                if key in ("Hips", "Head")}
    assert "Hips" in fixtures[name]["bones"]

def function(name):
    marker = "local function " + name + "("
    start = player.index(marker)
    following = player.find("\nlocal function ", start + len(marker))
    block = player[start:following if following >= 0 else len(player)]
    block = re.sub(r"\n--[^\n]*\n$", "\n", block)
    # atPhase is preceded by a comment, but ends before sampleBone.
    return block.strip()

prefix = r'''-- ENTITY_MOTION_20261010: standalone mock; actual clip excerpts, exact player sampling functions.
-- Rebuild this fixture with: python3 work/write_sample_test.py
local function jsonDecode(text)
	local p = 1
	local parse
	local function ws()
		while string.match(string.sub(text, p, p), "%s") do p += 1 end
	end
	local function stringValue()
		p += 1
		local start = p
		while string.sub(text, p, p) ~= '"' do
			assert(p <= #text, "unterminated JSON string")
			assert(string.sub(text, p, p) ~= "\\", "fixture uses only unescaped ASCII names")
			p += 1
		end
		local value = string.sub(text, start, p - 1)
		p += 1
		return value
	end
	parse = function()
		ws()
		local token = string.sub(text, p, p)
		if token == '"' then return stringValue() end
		if token == "{" or token == "[" then
			local object, close, result = token == "{", token == "{" and "}" or "]", {}
			p += 1; ws()
			if string.sub(text, p, p) == close then p += 1; return result end
			while true do
				local key
				if object then
					assert(string.sub(text, p, p) == '"', "expected JSON key")
					key = stringValue(); ws()
					assert(string.sub(text, p, p) == ":"); p += 1
				end
				local value = parse()
				if object then result[key] = value else table.insert(result, value) end
				ws()
				local separator = string.sub(text, p, p); p += 1
				if separator == close then break end
				assert(separator == ",", "expected JSON separator"); ws()
			end
			return result
		end
		for literal, value in pairs({["true"] = true, ["false"] = false}) do
			if string.sub(text, p, p + #literal - 1) == literal then p += #literal; return value end
		end
		local number = string.match(string.sub(text, p), "^%-?%d+%.?%d*[eE]?[%+%-]?%d*")
		assert(number and tonumber(number), "expected JSON value at " .. p)
		p += #number
		return tonumber(number)
	end
	local result = parse(); ws(); assert(p > #text, "trailing JSON")
	return result
end

local HttpService = {JSONDecode = function(_, raw) return jsonDecode(raw) end}
local Vector3 = {}
local VectorMT = {}
VectorMT.__index = VectorMT
function Vector3.new(x, y, z) return setmetatable({X = x, Y = y, Z = z}, VectorMT) end
function VectorMT:Lerp(other, t)
	return Vector3.new(self.X + (other.X - self.X) * t, self.Y + (other.Y - self.Y) * t, self.Z + (other.Z - self.Z) * t)
end
local CFrame = {}
local FrameMT = {}
FrameMT.__index = FrameMT
local function frame(x, y, z, qx, qy, qz, qw)
	return setmetatable({Position = Vector3.new(x, y, z), q = {qx, qy, qz, qw}}, FrameMT)
end
function CFrame.new(x, y, z, qx, qy, qz, qw)
	if type(x) == "table" then return frame(x.X, x.Y, x.Z, 0, 0, 0, 1) end
	return frame(x or 0, y or 0, z or 0, qx or 0, qy or 0, qz or 0, qw or 1)
end
function FrameMT:Lerp(other, t)
	local a, b, dot = self.q, other.q, 0
	for i = 1, 4 do dot += a[i] * b[i] end
	local sign = dot < 0 and -1 or 1
	dot = math.clamp(math.abs(dot), 0, 1)
	local w0, w1 = 1 - t, t
	if dot < 0.9995 then
		local angle = math.acos(dot)
		w0, w1 = math.sin((1 - t) * angle) / math.sin(angle), math.sin(t * angle) / math.sin(angle)
	end
	local q, norm = {}, 0
	for i = 1, 4 do q[i] = w0 * a[i] + w1 * sign * b[i]; norm += q[i] * q[i] end
	norm = math.sqrt(norm)
	for i = 1, 4 do q[i] /= norm end
	local v = self.Position:Lerp(other.Position, t)
	return frame(v.X, v.Y, v.Z, q[1], q[2], q[3], q[4])
end
function FrameMT.__mul(a, b)
	-- sampleBone multiplies a translation by a rotation, so no position rotation is needed here.
	assert(a.q[1] == 0 and a.q[2] == 0 and a.q[3] == 0 and a.q[4] == 1, "unexpected mock multiplication")
	return frame(a.Position.X + b.Position.X, a.Position.Y + b.Position.Y, a.Position.Z + b.Position.Z, b.q[1], b.q[2], b.q[3], b.q[4])
end
CFrame.identity = CFrame.new()
local IDENTITY = CFrame.identity
'''

tests = r'''
local raw = {Walk = jsonDecode(RAW_WALK), Run = jsonDecode(RAW_RUN), Flight = jsonDecode(RAW_FLIGHT)}
local walk = decodeClip(RAW_WALK)
local run = decodeClip(RAW_RUN)
local flight = decodeClip(RAW_FLIGHT)
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end
local function equivalent(a, b)
	local dot = 0
	for i = 1, 4 do dot += a.q[i] * b.q[i] end
	return near(math.abs(dot), 1, 1e-8) and near(a.Position.X, b.Position.X) and near(a.Position.Y, b.Position.Y) and near(a.Position.Z, b.Position.Z)
end
local function pose(c, name, phase)
	local i0, i1, a = atPhase(c, phase)
	return sampleBone(c, name, i0, i1, a)
end
for _, c in ipairs({walk, run, flight}) do
	check(near(c.duration, c.frames / c.fps), "advertised duration")
	for _, track in pairs(c.tracks) do
		for _, transform in ipairs(track) do
			local norm = 0
			for _, q in ipairs(transform.q) do norm += q * q end
			check(near(norm, 1, 1e-10), "decode normalizes quantized quaternion")
		end
	end
end
local i0, i1, a = atPhase(walk, 0)
check(i0 == 1 and i1 == 2 and a == 0, "loop phase zero")
i0, i1, a = atPhase(walk, 1)
check(i0 == 1 and i1 == 2 and a == 0, "loop one wraps exactly")
i0, i1, a = atPhase(walk, (walk.frames - 0.5) / walk.frames)
check(i0 == walk.frames and i1 == 1 and near(a, 0.5), "last frame interpolates to first")
i0, i1, a = atPhase(flight, 1)
check(i0 == flight.frames and i1 == flight.frames and a == 0, "nonloop endpoint holds")
check(equivalent(pose(walk, "Hips", 0), pose(walk, "Hips", 1)), "whole pose wraps")
check(pose(walk, "MissingBone", 0.25) == nil, "absent bone passes through")
local hips = pose(walk, "Hips", 0)
check(near(hips.Position.X, raw.Walk.hips[1] / 1000) and near(hips.Position.Y, raw.Walk.hips[2] / 1000), "hips translation uses local studs")
local left, right = pose(walk, "Hips", 0.37), pose(run, "Hips", 0.37)
local mockBone = {Transform = CFrame.identity}
mockBone.Transform = left:Lerp(right, 0.35)
local blend = mockBone.Transform
check(near(blend.Position.X, left.Position.X * 0.65 + right.Position.X * 0.35), "blend position")
check(equivalent(left:Lerp(right, 0), left) and equivalent(left:Lerp(right, 1), right), "blend endpoints")
local norm = 0
for _, q in ipairs(blend.q) do norm += q * q end
check(near(norm, 1, 1e-10), "blend normalized")
check(equivalent(left:Lerp(frame(left.Position.X, left.Position.Y, left.Position.Z, -left.q[1], -left.q[2], -left.q[3], -left.q[4]), 0.5), left), "shortest quaternion hemisphere")
check(crossedContacts(walk, 0.49, 0.51) == 1, "right contact")
check(crossedContacts(walk, 0.99, 1.01) == 1, "left contact across wrap")
check(crossedContacts(walk, 0.1, 2.1) == 4, "large update keeps all contacts")
local phase = 0
for _ = 1, 120 do phase += walk.speed / 120 / walk.stride end
check(near(phase, walk.speed / walk.stride), "distance matched phase")
check(near(raw.Walk.stride, walk.stride) and near(raw.Run.stride, run.stride), "actual authored clip metadata")
print("PASS " .. checks .. " checks; real Walk/Run/Flight excerpts decode, wrap, sample, blend and contact-count on a pure-Luau mock")
'''

data = prefix + "\n" + "\n\n".join(function(name) for name in ("finite", "decodeClip", "atPhase", "sampleBone", "crossedContacts"))
data += "\n"
for name, variable in (("Walk", "RAW_WALK"), ("Run", "RAW_RUN"), ("Lunge_Flight", "RAW_FLIGHT")):
    data += "local " + variable + " = [==[" + json.dumps(fixtures[name], separators=(",", ":")) + "]==]\n"
data += tests
(ROOT / "out/sample_test.luau").write_text(data)
luau = Path('/private/tmp/stayquiet-luau-validation/luau')
compiler = luau.with_name('luau-compile')
results = []
for path in (ROOT / 'out/Level 1 Entity Motion.LocalScript.lua', ROOT / 'out/sample_test.luau'):
    result = subprocess.run([str(compiler), '--null', str(path)], capture_output=True, text=True)
    results.append({'file': str(path.relative_to(ROOT)), 'exit_code': result.returncode})
    assert result.returncode == 0, result.stderr + result.stdout
result = subprocess.run([str(luau), str(ROOT / 'out/sample_test.luau')], capture_output=True, text=True)
assert result.returncode == 0, result.stderr + result.stdout
match = re.search(r'PASS (\d+) checks', result.stdout)
assert match, result.stdout
checks = int(match.group(1))
contract_path = ROOT / "work/player_contract.json"
if contract_path.exists():
    contract = json.loads(contract_path.read_text())
    evidence = contract["offline_validation"]["sample_test"]
    evidence["fixture_source_sha256"] = hashlib.sha256(clip_bytes).hexdigest()
    evidence["fixture_frames"] = {name: clip["frames"] for name, clip in fixtures.items()}
    evidence["fixture"] = "actual Hips/Head tracks for " + ",".join(name + str(clip["frames"]) for name, clip in fixtures.items()) + " from generated clips.json"
    evidence['passed'], evidence['checks'] = True, checks
    evidence['player_source_sha256'] = hashlib.sha256(player.encode()).hexdigest()
    contract_path.write_text(json.dumps(contract, indent=2) + "\n")
(ROOT / 'work/sample_validation.json').write_text(json.dumps({
    'passed': True, 'checks': checks, 'output': result.stdout.strip(), 'compile': results,
    'payload_sha256': hashlib.sha256(clip_bytes).hexdigest(),
    'player_sha256': hashlib.sha256(player.encode()).hexdigest(),
    'sample_sha256': hashlib.sha256((ROOT / 'out/sample_test.luau').read_bytes()).hexdigest(),
    'scope': 'Pure-Luau mocks exercise actual exported Hips/Head tracks and exact player decode/sample/contact functions; Roblox engine behavior is unverified.',
}, indent=2))
print("wrote out/sample_test.luau", len(data), "bytes")
print(result.stdout.strip())
